import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import '../models/track.dart';
import '../services/artwork_palette_service.dart';
import '../services/lyrics_service.dart';

enum RepeatMode { off, all, one }

class PlayerController extends ChangeNotifier {
  static const Duration _completionGraceWindow = Duration(seconds: 3);
  static const Duration _completionTolerance = Duration(seconds: 2);

  final mk.Player _player = mk.Player();
  final Random _random = Random();
  final LyricsService _lyricsService = LyricsService();
  Future<Track> Function(Track track)? prepareTrackForPlayback;

  List<Track> _queue = const [];
  int _currentIndex = -1;

  Track? currentTrack;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool isPlaying = false;
  double volume = 85;
  String? error;
  bool shuffleEnabled = false;
  RepeatMode repeatMode = RepeatMode.off;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<bool>? _completedSub;
  DateTime? _lastPlaybackErrorAt;

  PlayerController() {
    unawaited(_player.setVolume(volume));

    _playingSub = _player.stream.playing.listen((value) {
      isPlaying = value;
      notifyListeners();
    });

    _positionSub = _player.stream.position.listen((value) {
      position = value;
      notifyListeners();
    });

    _durationSub = _player.stream.duration.listen((value) {
      duration = value;
      notifyListeners();
    });

    _errorSub = _player.stream.error.listen((value) {
      _lastPlaybackErrorAt = DateTime.now();
      error = 'Ошибка воспроизведения: $value';
      isPlaying = false;
      notifyListeners();
    });

    _completedSub = _player.stream.completed.listen((completed) {
      if (!completed) return;
      unawaited(_handleTrackCompleted());
    });
  }

  mk.Player get rawPlayer => _player;

  bool get hasTrack => currentTrack != null;
  bool get canPlayPrevious => _findPreviousPlayableIndex() != -1;
  bool get canPlayNext => _findNextPlayableIndex() != -1;
  List<Track> get queue => _queue;
  int get currentIndex => _currentIndex;

  Future<void> playTrack(Track track) async {
    _queue = [track];
    _currentIndex = 0;
    await _playTrackInternal(track);
  }

  Future<void> playTracks(List<Track> tracks, {required int startIndex}) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;

    _queue = List<Track>.unmodifiable(tracks);
    _currentIndex = startIndex;
    await _playTrackInternal(_queue[startIndex]);
  }

  Future<void> playPrevious() async {
    final previousIndex = _findPreviousPlayableIndex();
    if (previousIndex == -1) return;

    _currentIndex = previousIndex;
    await _playTrackInternal(_queue[previousIndex]);
  }

  Future<void> playNext() async {
    final nextIndex = _findNextPlayableIndex();
    if (nextIndex == -1) return;

    _currentIndex = nextIndex;
    await _playTrackInternal(_queue[nextIndex]);
  }

  int get remainingTracksCount {
    if (_currentIndex < 0 || _queue.isEmpty) return 0;
    return _queue.length - _currentIndex - 1;
  }

  void appendTracks(List<Track> tracks) {
    if (tracks.isEmpty) return;
    final updated = List<Track>.from(_queue)..addAll(tracks);
    _queue = List<Track>.unmodifiable(updated);
    notifyListeners();
  }

  Future<void> removeTrackAndSkip(String trackId) async {
    final index = _queue.indexWhere((t) => t.id == trackId);
    if (index == -1) return;

    final wasCurrent = index == _currentIndex;
    final updated = List<Track>.from(_queue)..removeAt(index);
    _queue = List<Track>.unmodifiable(updated);

    if (wasCurrent) {
      if (_currentIndex < _queue.length) {
        await _playTrackInternal(_queue[_currentIndex]);
      } else if (_queue.isNotEmpty) {
        _currentIndex = 0;
        await _playTrackInternal(_queue[0]);
      } else {
        await stop();
      }
    } else if (index < _currentIndex) {
      _currentIndex--;
    }
    notifyListeners();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _playTrackInternal(_queue[index]);
  }

  void toggleShuffle() {
    shuffleEnabled = !shuffleEnabled;
    notifyListeners();
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      RepeatMode.off => RepeatMode.all,
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
    };
    notifyListeners();
  }

  Future<void> setVolume(double value) async {
    final nextVolume = value.clamp(0, 100).toDouble();

    try {
      await _player.setVolume(nextVolume);
      volume = nextVolume;
      error = null;
      notifyListeners();
    } catch (e) {
      error = 'Ошибка изменения громкости: $e';
      notifyListeners();
    }
  }

  Future<void> _playTrackInternal(Track track) async {
    final preparedTrack = await _prepareTrack(track);
    final url = (preparedTrack.preview ?? '').trim();

    if (url.isEmpty) {
      _lastPlaybackErrorAt = null;
      _replaceTrackInQueue(preparedTrack);
      currentTrack = preparedTrack;
      position = Duration.zero;
      duration = Duration.zero;
      isPlaying = false;
      error = 'У трека нет ссылки на воспроизведение';
      notifyListeners();
      return;
    }

    try {
      _lastPlaybackErrorAt = null;
      error = null;
      _replaceTrackInQueue(preparedTrack);
      currentTrack = preparedTrack;
      position = Duration.zero;
      duration = Duration.zero;
      unawaited(_lyricsService.preloadLyrics(track: preparedTrack));
      unawaited(ArtworkPaletteService.instance.preload(preparedTrack.image));
      notifyListeners();

      await _player.open(
        mk.Media(url),
        play: true,
      );
    } catch (e) {
      _lastPlaybackErrorAt = DateTime.now();
      error = 'Ошибка воспроизведения: $e';
      isPlaying = false;
      notifyListeners();
    }
  }

  Future<Track> _prepareTrack(Track track) async {
    final resolver = prepareTrackForPlayback;
    if (resolver == null) return track;

    try {
      return await resolver(track);
    } catch (_) {
      return track;
    }
  }

  void _replaceTrackInQueue(Track track) {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
    if (_queue[_currentIndex].id != track.id) return;

    final updatedQueue = List<Track>.from(_queue);
    updatedQueue[_currentIndex] = track;
    _queue = List<Track>.unmodifiable(updatedQueue);
  }

  Future<void> _handleTrackCompleted() async {
    if (_shouldIgnoreCompletedEvent()) {
      isPlaying = false;
      notifyListeners();
      return;
    }

    _lastPlaybackErrorAt = null;

    final nextIndex = _findNextPlayableIndex();
    if (nextIndex == -1) {
      isPlaying = false;
      notifyListeners();
      return;
    }
    await playNext();
  }

  bool _shouldIgnoreCompletedEvent() {
    final lastErrorAt = _lastPlaybackErrorAt;
    if (lastErrorAt == null) return false;

    final elapsedSinceError = DateTime.now().difference(lastErrorAt);
    if (elapsedSinceError > _completionGraceWindow) return false;

    if (duration <= Duration.zero) {
      return true;
    }

    final remaining = duration - position;
    return remaining > _completionTolerance;
  }

  int _findPreviousPlayableIndex() {
    if (_queue.isEmpty || _currentIndex < 0) return -1;

    if (shuffleEnabled && _queue.where((track) => track.hasPlayableUrl).length > 1) {
      final candidates = <int>[];
      for (var i = 0; i < _queue.length; i++) {
        if (i != _currentIndex && _queue[i].hasPlayableUrl) {
          candidates.add(i);
        }
      }
      return candidates.isEmpty ? -1 : candidates[_random.nextInt(candidates.length)];
    }

    for (var i = _currentIndex - 1; i >= 0; i--) {
      if (_queue[i].hasPlayableUrl) return i;
    }
    return -1;
  }

  int _findNextPlayableIndex() {
    if (_queue.isEmpty || _currentIndex < 0) return -1;

    if (repeatMode == RepeatMode.one && _queue[_currentIndex].hasPlayableUrl) {
      return _currentIndex;
    }

    if (shuffleEnabled && _queue.where((track) => track.hasPlayableUrl).length > 1) {
      final candidates = <int>[];
      for (var i = 0; i < _queue.length; i++) {
        if (i != _currentIndex && _queue[i].hasPlayableUrl) {
          candidates.add(i);
        }
      }
      return candidates.isEmpty ? -1 : candidates[_random.nextInt(candidates.length)];
    }

    for (var i = _currentIndex + 1; i < _queue.length; i++) {
      if (_queue[i].hasPlayableUrl) return i;
    }

    if (repeatMode == RepeatMode.all) {
      for (var i = 0; i < _currentIndex; i++) {
        if (_queue[i].hasPlayableUrl) return i;
      }
    }
    return -1;
  }

  Future<void> togglePlayPause() async {
    try {
      error = null;
      if (isPlaying) {
        await _player.pause();
      } else {
        await _player.play();
      }
    } catch (e) {
      error = 'Ошибка play/pause: $e';
      notifyListeners();
    }
  }

  Future<void> seek(Duration newPosition) async {
    try {
      error = null;
      await _player.seek(newPosition);
    } catch (e) {
      error = 'Ошибка перемотки: $e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try {
      await _player.stop();
      _lastPlaybackErrorAt = null;
      isPlaying = false;
      position = Duration.zero;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _playingSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _errorSub?.cancel();
    _completedSub?.cancel();
    _player.dispose();
    super.dispose();
  }
}
