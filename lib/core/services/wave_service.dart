import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/player_controller.dart';
import '../models/track.dart';
import 'auth_service.dart';
import 'music_service.dart';

// ══════════════════════════════════════════════════════════════
//                     CANONICAL NORMALIZATION
// ══════════════════════════════════════════════════════════════

String canonicalArtist(String? raw) {
  var s = (raw ?? '').toLowerCase().trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('ё', 'е');

  const splitters = [
    ' feat. ',
    ' feat ',
    ' ft. ',
    ' ft ',
    ' featuring ',
    ' при участии ',
    ' & ',
    ' x ',
    ', '
  ];
  for (final sp in splitters) {
    final idx = s.indexOf(sp);
    if (idx > 0) {
      s = s.substring(0, idx);
      break;
    }
  }

  return s
      .replaceAll(RegExp(r'[^a-z0-9а-я\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String canonicalTitle(String? raw) {
  var s = (raw ?? '').toLowerCase().trim();
  if (s.isEmpty) return '';
  s = s.replaceAll('ё', 'е');

  s = s.replaceAll(RegExp(r'\b(feat\.?|ft\.?|featuring)\b.*$'), ' ').trim();

  s = s.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
    final inside = m.group(1) ?? '';
    return _containsVersionWords(inside) ? ' ' : (m.group(0) ?? '');
  });

  s = s.replaceAllMapped(RegExp(r'\[([^\]]*)\]'), (m) {
    final inside = m.group(1) ?? '';
    return _containsVersionWords(inside) ? ' ' : (m.group(0) ?? '');
  });

  s = s.replaceAllMapped(RegExp(r'\s-\s(.+)$'), (m) {
    final tail = m.group(1) ?? '';
    return _containsVersionWords(tail) ? ' ' : (m.group(0) ?? '');
  });

  s = s.replaceAll(
    RegExp(
      r'\b(remaster(ed)?|live|edit|radio edit|extended|mix|version|deluxe|bonus|demo|instrumental|acoustic|karaoke)\b.*$',
    ),
    ' ',
  );

  s = s.replaceAll(RegExp(r'\b(19\d{2}|20\d{2})\b'), ' ');

  return s
      .replaceAll(RegExp(r'[^a-z0-9а-я\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _containsVersionWords(String x) {
  final l = x.toLowerCase();
  const words = [
    'remix',
    'mix',
    'edit',
    'radio',
    'extended',
    'version',
    'live',
    'remaster',
    'remastered',
    'acoustic',
    'demo',
    'instrumental',
    'karaoke'
  ];
  return words.any((w) => l.contains(w));
}

// ══════════════════════════════════════════════════════════════
//                     WAVE MODE
// ══════════════════════════════════════════════════════════════

enum WaveMode {
  flow,        // Моя Волна (персональный поток)
  exploration, // Открытия
  favorites,   // Любимое
  energy,      // Драйв
  calm,        // Спокойное
  coldStart,   // Популярное
}

// ══════════════════════════════════════════════════════════════
//                     WAVE PROFILE STORE
// ══════════════════════════════════════════════════════════════

class WaveProfileStore {
  static const _keyArtists = 'wave_profile_artists';
  static const _keyGenres = 'wave_profile_genres';
  static const _keyHistory = 'wave_profile_history';
  static const _keyDislikes = 'wave_profile_dislikes';
  static const _keySkips = 'wave_profile_skips';

  static const int _historyMax = 500;
  static const int _dislikesMax = 200;

  String makeTrackKey(String? artist, String? title) {
    final a = canonicalArtist(artist);
    final t = canonicalTitle(title);
    if (a.isEmpty && t.isEmpty) return '';
    return '$a—$t';
  }

  Future<List<String>> topArtists(int n) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyArtists);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final now = DateTime.now().millisecondsSinceEpoch;

      final scored = <MapEntry<String, int>>[];
      for (final entry in map.entries) {
        final artist = entry.key;
        final data = Map<String, dynamic>.from(entry.value as Map);
        final score = (data['score'] as num?)?.toInt() ?? 0;
        final lastPlayed = (data['lastPlayed'] as num?)?.toInt() ?? 0;

        // Decay: -1 point every 7 days without listening
        final daysSince = (now - lastPlayed) ~/ (1000 * 60 * 60 * 24);
        final decay = daysSince ~/ 7;
        final finalScore = max(0, score - decay);

        if (finalScore > 0) {
          scored.add(MapEntry(artist, finalScore));
        }
      }

      scored.sort((a, b) => b.value.compareTo(a.value));
      return scored.take(n).map((e) => e.key).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> adjustArtist(String? artistRaw, int delta) async {
    final artist = canonicalArtist(artistRaw);
    if (artist.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyArtists);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }

    final data = Map<String, dynamic>.from((map[artist] as Map?) ?? {});
    final currentScore = (data['score'] as num?)?.toInt() ?? 0;
    final newScore = (currentScore + delta).clamp(-50, 999);

    data['score'] = newScore;
    data['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;

    if (newScore <= 0) {
      map.remove(artist);
    } else {
      map[artist] = data;
    }

    await prefs.setString(_keyArtists, jsonEncode(map));
  }

  Future<void> onLikeTrack(String? artist) => adjustArtist(artist, 3);
  Future<void> onPlayTrack(String? artist) => adjustArtist(artist, 1);
  Future<void> onDislikeTrack(String? artist) => adjustArtist(artist, -5);
  Future<void> onSkipTrack(String? artist) => adjustArtist(artist, -1);

  Future<List<String>> topGenres(int n) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyGenres);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final entries = map.entries
          .map((e) => MapEntry(e.key, (e.value as num?)?.toInt() ?? 0))
          .toList();
      entries.sort((a, b) => b.value.compareTo(a.value));
      return entries.take(n).map((e) => e.key).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Set<String>> historyKeysLast(int n) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHistory);
    if (raw == null || raw.isEmpty) return const {};

    try {
      final list = (jsonDecode(raw) as List).cast<String>();
      final last = list.length > n ? list.sublist(list.length - n) : list;
      return last.where((k) => k.isNotEmpty).toSet();
    } catch (_) {
      return const {};
    }
  }

  Future<void> markPlayed(String trackKey) async {
    if (trackKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHistory);
    var list = <String>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {}
    }

    list.add(trackKey);
    final dedup = list.reversed.toSet().toList().reversed.toList();
    if (dedup.length > _historyMax) {
      list = dedup.sublist(dedup.length - _historyMax);
    } else {
      list = dedup;
    }

    await prefs.setString(_keyHistory, jsonEncode(list));
  }

  Future<bool> isDisliked(String trackKey) async {
    if (trackKey.isEmpty) return false;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDislikes);
    if (raw == null || raw.isEmpty) return false;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return map.containsKey(trackKey);
    } catch (_) {
      return false;
    }
  }

  Future<void> markDisliked(String trackKey) async {
    if (trackKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyDislikes);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }

    map[trackKey] = DateTime.now().millisecondsSinceEpoch;
    if (map.length > _dislikesMax) {
      final sortedKeys = map.keys.toList()
        ..sort((a, b) => (map[a] as num).compareTo(map[b] as num));
      for (var i = 0; i < sortedKeys.length - _dislikesMax; i++) {
        map.remove(sortedKeys[i]);
      }
    }

    await prefs.setString(_keyDislikes, jsonEncode(map));
  }

  Future<int> skipCount(String trackKey) async {
    if (trackKey.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySkips);
    if (raw == null || raw.isEmpty) return 0;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return (map[trackKey] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markSkipped(String trackKey) async {
    if (trackKey.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keySkips);
    final map = <String, dynamic>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        map.addAll(Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }

    final cur = (map[trackKey] as num?)?.toInt() ?? 0;
    map[trackKey] = cur + 1;
    await prefs.setString(_keySkips, jsonEncode(map));
  }
}

// ══════════════════════════════════════════════════════════════
//                     WAVE GENERATOR
// ══════════════════════════════════════════════════════════════

class WaveGenerator {
  WaveGenerator({
    required this.musicService,
    required this.store,
    this.authService,
  });

  final MusicService musicService;
  final WaveProfileStore store;
  final AuthService? authService;
  final Random _random = Random();

  final Set<String> _sessionPlayedKeys = {};

  Future<List<Track>> generate({
    String? seedArtistRaw,
    String? seedTitleRaw,
    int amount = 30,
    WaveMode mode = WaveMode.flow,
  }) async {
    final seedArtist = canonicalArtist(seedArtistRaw);

    final topArtists = await store.topArtists(10);
    final historySet = await store.historyKeysLast(150);

    // 1. Fetch user's saved favorites
    List<Track> userFavorites = const [];
    if (authService != null) {
      try {
        final token = await authService!.getSavedToken();
        if (token != null && token.isNotEmpty) {
          userFavorites = await authService!.listFavorites(token);
        }
      } catch (_) {}
    }

    // 2. Mode: FAVORITES - play directly from user's liked tracks
    if (mode == WaveMode.favorites && userFavorites.isNotEmpty) {
      final validFavs = <Track>[];
      for (final t in userFavorites) {
        if (!t.hasPlayableUrl) continue;
        final k = store.makeTrackKey(t.artist, t.title);
        if (await store.isDisliked(k)) continue;
        validFavs.add(t);
      }
      if (validFavs.isNotEmpty) {
        validFavs.shuffle(_random);
        return validFavs.take(amount).toList();
      }
    }

    // 3. Extract user's favorite artists ranked by frequency
    final artistFrequency = <String, int>{};
    for (final t in userFavorites) {
      final a = canonicalArtist(t.artist);
      if (a.isNotEmpty) {
        artistFrequency[a] = (artistFrequency[a] ?? 0) + 1;
      }
    }
    // Add top artists from listening history
    for (var i = 0; i < topArtists.length; i++) {
      final a = canonicalArtist(topArtists[i]);
      if (a.isNotEmpty) {
        artistFrequency[a] = (artistFrequency[a] ?? 0) + (topArtists.length - i);
      }
    }

    final rankedArtists = artistFrequency.keys.toList()
      ..sort((a, b) => (artistFrequency[b] ?? 0).compareTo(artistFrequency[a] ?? 0));

    // Fallback if user has no favorites and no seed
    if (rankedArtists.isEmpty && seedArtist.isEmpty) {
      return generateColdStart(amount);
    }

    // 4. Select top artists to search for
    final searchQueries = <String>[];
    if (seedArtist.isNotEmpty) {
      searchQueries.add(seedArtist);
    }

    // Pick top favorite artists
    final availableArtists = rankedArtists.where((a) => a != seedArtist).toList();
    if (availableArtists.isNotEmpty) {
      availableArtists.shuffle(_random);
      searchQueries.addAll(availableArtists.take(3));
    }

    // Mood query additions
    switch (mode) {
      case WaveMode.exploration:
        const explorationQueries = [
          'свежий инди рок',
          'новая русская музыка',
          'indie pop new',
          'открытия музыка',
        ];
        searchQueries.add(explorationQueries[_random.nextInt(explorationQueries.length)]);
        break;
      case WaveMode.energy:
        const energyQueries = [
          'танцевальные хиты',
          'драйв рок',
          'клубная музыка',
        ];
        searchQueries.add(energyQueries[_random.nextInt(energyQueries.length)]);
        break;
      case WaveMode.calm:
        const calmQueries = [
          'спокойная музыка chill',
          'lo-fi relax',
          'акустика вечер',
        ];
        searchQueries.add(calmQueries[_random.nextInt(calmQueries.length)]);
        break;
      case WaveMode.coldStart:
        searchQueries.add('топ чарт хиты');
        break;
      case WaveMode.flow:
      case WaveMode.favorites:
        break;
    }

    // Dedup and take at most 3 queries for maximum parallel speed
    final finalQueries = searchQueries.toSet().take(3).toList();

    // 5. PARALLEL FETCHING: Dispatch all queries at once
    final searchFutures = finalQueries.map((q) => _safeSearch(q, 'yandex'));
    final results = await Future.wait(searchFutures).timeout(
      const Duration(milliseconds: 3200),
      onTimeout: () => <List<Track>>[],
    );

    final candidates = <Track>[];
    for (final list in results) {
      candidates.addAll(list);
    }

    // 6. In FLOW mode: Mix in familiar favorite tracks directly (~30-40%)
    final pickedFamiliar = <Track>[];
    if (userFavorites.isNotEmpty && mode == WaveMode.flow) {
      final eligibleFavs = userFavorites.where((t) {
        if (!t.hasPlayableUrl) return false;
        final k = store.makeTrackKey(t.artist, t.title);
        return !_sessionPlayedKeys.contains(k);
      }).toList()..shuffle(_random);
      pickedFamiliar.addAll(eligibleFavs.take((amount * 0.35).round()));
    }

    // 7. Filter candidate tracks
    final candidateSet = <Track>[];
    final seenKeys = <String>{};

    for (final tr in candidates) {
      if (!tr.hasPlayableUrl) continue;
      final k = store.makeTrackKey(tr.artist, tr.title);
      if (k.isEmpty || seenKeys.contains(k)) continue;
      if (historySet.contains(k)) continue;
      if (_sessionPlayedKeys.contains(k)) continue;
      if (await store.isDisliked(k)) continue;
      if (await store.skipCount(k) >= 3) continue;

      seenKeys.add(k);
      candidateSet.add(tr);
    }

    // If candidates are scarce, try fallback or cold start
    if (candidateSet.isEmpty && pickedFamiliar.isEmpty) {
      return generateColdStart(amount);
    }

    // 8. Score candidates based on ARTIST AFFINITY & PREFERENCES (NOT title words!)
    final topArtistsSet = rankedArtists.take(10).toSet();
    final scored = <MapEntry<Track, double>>[];
    for (final track in candidateSet) {
      var score = 0.0;
      final a = canonicalArtist(track.artist);
      if (a.isNotEmpty && topArtistsSet.contains(a)) {
        score += 5.0;
      }
      if (seedArtist.isNotEmpty && a == seedArtist) {
        score += 3.0;
      }
      final k = store.makeTrackKey(track.artist, track.title);
      final skips = await store.skipCount(k);
      score -= skips * 2.0;

      // Subtle jitter to keep stream varied
      score += _random.nextDouble() * 2.0;
      scored.add(MapEntry(track, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    // 9. Mix familiar + recommended tracks with consecutive artist limiting
    final resultList = <Track>[];
    final artistCount = <String, int>{};

    bool canAdd(Track tr) {
      final a = canonicalArtist(tr.artist);
      final count = artistCount[a] ?? 0;
      if (a.isNotEmpty && count >= 2) return false;
      resultList.add(tr);
      artistCount[a] = count + 1;
      final k = store.makeTrackKey(tr.artist, tr.title);
      _sessionPlayedKeys.add(k);
      return true;
    }

    // Interleave familiar and recommendations
    var favIndex = 0;
    var recIndex = 0;
    while (resultList.length < amount && (favIndex < pickedFamiliar.length || recIndex < scored.length)) {
      if (favIndex < pickedFamiliar.length && (resultList.length % 3 == 0 || recIndex >= scored.length)) {
        canAdd(pickedFamiliar[favIndex++]);
      } else if (recIndex < scored.length) {
        canAdd(scored[recIndex++].key);
      } else {
        break;
      }
    }

    // Fill remaining if needed
    for (final e in scored) {
      if (resultList.length >= amount) break;
      final k = store.makeTrackKey(e.key.artist, e.key.title);
      if (!_sessionPlayedKeys.contains(k)) {
        resultList.add(e.key);
        _sessionPlayedKeys.add(k);
      }
    }

    if (resultList.isNotEmpty) {
      return resultList;
    }
    return generateColdStart(amount);
  }

  Future<List<Track>> generateColdStart(int amount) async {
    const popularQueries = [
      'топ чарт хиты',
      'популярная музыка',
      'новинки недели',
    ];

    // Fetch popular in parallel
    final results = await Future.wait(
      popularQueries.map((q) => _safeSearch(q, 'yandex')),
    ).timeout(
      const Duration(milliseconds: 3000),
      onTimeout: () => <List<Track>>[],
    );

    final candidates = <Track>[];
    for (final list in results) {
      candidates.addAll(list);
    }

    final valid = candidates.where((t) => t.hasPlayableUrl).toList();
    valid.shuffle(_random);
    return valid.take(amount).toList();
  }

  Future<List<Track>> _safeSearch(String query, String service) async {
    try {
      final res = await musicService.search(
        service: service,
        query: query,
        limit: 20,
      );
      return res.tracks;
    } catch (_) {
      return const [];
    }
  }
}

// ══════════════════════════════════════════════════════════════
//                     WAVE CONTROLLER
// ══════════════════════════════════════════════════════════════

class WaveController extends ChangeNotifier {
  WaveController({
    required this.generator,
    required this.store,
    this.authService,
  });

  final WaveGenerator generator;
  final WaveProfileStore store;
  final AuthService? authService;

  bool isRunning = false;
  bool isLoading = false;
  String statusMessage = 'Моя Волна готова';
  WaveMode mode = WaveMode.flow;
  Track? lastPlayedTrack;
  DateTime? _currentTrackStartTime;

  Future<void> startWave({
    Track? seedTrack,
    required PlayerController playerController,
  }) async {
    if (isLoading) return;

    isRunning = true;
    isLoading = true;
    statusMessage = 'Собираем персональный поток...';
    notifyListeners();

    try {
      final tracks = await generator.generate(
        seedArtistRaw: seedTrack?.artist,
        seedTitleRaw: seedTrack?.title,
        amount: 30,
        mode: mode,
      );

      if (tracks.isEmpty) {
        statusMessage = 'Не удалось найти треки для волны';
        isRunning = false;
        isLoading = false;
        notifyListeners();
        return;
      }

      statusMessage = 'Волна активна';
      isLoading = false;
      notifyListeners();

      await playerController.playTracks(tracks, startIndex: 0);
      _onTrackStarted(playerController.currentTrack);
    } catch (e) {
      statusMessage = 'Ошибка запуска: $e';
      isRunning = false;
      isLoading = false;
      notifyListeners();
    }
  }

  void onPlayerTick(PlayerController playerController) {
    if (!isRunning) return;

    // Check track transitions
    final current = playerController.currentTrack;
    if (current != null && current.id != lastPlayedTrack?.id) {
      _handleTrackChanged(lastPlayedTrack, current);
    }

    // Auto-load next batch if queue remaining count <= 4
    if (!isLoading && playerController.remainingTracksCount <= 4) {
      loadMore(playerController);
    }
  }

  Future<void> loadMore(PlayerController playerController) async {
    if (isLoading || !isRunning) return;

    isLoading = true;
    notifyListeners();

    try {
      final lastTrack = playerController.queue.isNotEmpty
          ? playerController.queue.last
          : null;

      final moreTracks = await generator.generate(
        seedArtistRaw: lastTrack?.artist,
        seedTitleRaw: lastTrack?.title,
        amount: 20,
        mode: mode,
      );

      if (moreTracks.isNotEmpty) {
        playerController.appendTracks(moreTracks);
      }
    } catch (_) {}

    isLoading = false;
    notifyListeners();
  }

  void _onTrackStarted(Track? track) {
    lastPlayedTrack = track;
    _currentTrackStartTime = DateTime.now();
    if (track != null) {
      final key = store.makeTrackKey(track.artist, track.title);
      store.markPlayed(key);
      store.onPlayTrack(track.artist);
    }
  }

  void _handleTrackChanged(Track? previous, Track? current) {
    if (previous != null && _currentTrackStartTime != null) {
      final elapsed = DateTime.now().difference(_currentTrackStartTime!);
      // If skipped within 15 seconds, penalize
      if (elapsed.inSeconds < 15) {
        final key = store.makeTrackKey(previous.artist, previous.title);
        store.markSkipped(key);
        store.onSkipTrack(previous.artist);
      }
    }
    _onTrackStarted(current);
  }

  Future<void> dislikeTrack(
    Track track, {
    required PlayerController playerController,
  }) async {
    final key = store.makeTrackKey(track.artist, track.title);
    await store.markDisliked(key);
    await store.onDislikeTrack(track.artist);

    // Skip and remove from current playlist
    await playerController.removeTrackAndSkip(track.id);

    // Trigger load more if queue dropped low
    if (playerController.remainingTracksCount <= 4) {
      await loadMore(playerController);
    }
  }

  Future<void> likeTrack(
    Track track, {
    required AuthService authService,
    required String? token,
  }) async {
    await store.onLikeTrack(track.artist);
    if (token != null && token.isNotEmpty) {
      try {
        await authService.likeTrack(token: token, track: track);
      } catch (_) {}
    }
  }

  void stopWave() {
    isRunning = false;
    statusMessage = 'Моя Волна остановлена';
    notifyListeners();
  }

  Future<void> setMode(WaveMode newMode, {PlayerController? playerController}) async {
    if (mode == newMode && isRunning) return;
    mode = newMode;
    notifyListeners();

    if (isRunning && playerController != null) {
      isLoading = true;
      statusMessage = 'Переключаем волну...';
      notifyListeners();

      try {
        final current = playerController.currentTrack;
        final tracks = await generator.generate(
          seedArtistRaw: current?.artist,
          seedTitleRaw: current?.title,
          amount: 25,
          mode: mode,
        );

        if (tracks.isNotEmpty) {
          await playerController.playTracks(tracks, startIndex: 0);
          _onTrackStarted(playerController.currentTrack);
          statusMessage = 'Волна активна';
        }
      } catch (_) {}

      isLoading = false;
      notifyListeners();
    }
  }
}
