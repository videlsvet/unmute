import 'dart:io';

import 'package:flutter/services.dart';

import '../controllers/player_controller.dart';

class IosNowPlayingService {
  static const MethodChannel _channel = MethodChannel('unmute/now_playing');
  static bool _initialized = false;

  static String? _lastTrackId;
  static bool? _lastIsPlaying;
  static double? _lastDurationSeconds;
  static double? _lastPositionSeconds;
  static DateTime? _lastSyncTime;

  static void initialize(PlayerController controller) {
    if (_initialized) return;
    if (!Platform.isIOS) return;
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'play':
          if (!controller.isPlaying) {
            controller.togglePlayPause();
          }
          break;
        case 'pause':
          if (controller.isPlaying) {
            controller.togglePlayPause();
          }
          break;
        case 'togglePlayPause':
          controller.togglePlayPause();
          break;
        case 'next':
          if (controller.canPlayNext) {
            controller.playNext();
          }
          break;
        case 'previous':
          if (controller.canPlayPrevious) {
            controller.playPrevious();
          }
          break;
        case 'seek':
          final args = call.arguments;
          if (args is Map && args['position'] != null) {
            final seconds = (args['position'] as num).toDouble();
            controller.seek(Duration(milliseconds: (seconds * 1000).toInt()));
          }
          break;
      }
    });

    controller.addListener(() {
      _syncNowPlaying(controller);
    });
  }

  static void _syncNowPlaying(PlayerController controller) {
    if (!Platform.isIOS) return;
    final track = controller.currentTrack;
    if (track == null) return;

    final currentPositionSec = controller.position.inMilliseconds / 1000.0;
    final currentDurationSec = controller.duration.inSeconds.toDouble();
    final isPlaying = controller.isPlaying;
    final now = DateTime.now();

    final isTrackChanged = track.id != _lastTrackId;
    final isPlayingChanged = isPlaying != _lastIsPlaying;
    final isDurationChanged = _lastDurationSeconds == null ||
        (currentDurationSec - _lastDurationSeconds!).abs() > 1.0;

    // Check for seek / position jump (> 2.0s unexpected gap)
    bool isPositionJump = false;
    if (_lastPositionSeconds != null && _lastSyncTime != null) {
      final elapsedSinceLastSync =
          now.difference(_lastSyncTime!).inMilliseconds / 1000.0;
      final expectedPosition = isPlaying
          ? (_lastPositionSeconds! + elapsedSinceLastSync)
          : _lastPositionSeconds!;
      if ((currentPositionSec - expectedPosition).abs() > 2.0) {
        isPositionJump = true;
      }
    }

    // Periodic sync at most every 4 seconds to maintain accuracy without spamming
    final isPeriodicSync = _lastSyncTime == null ||
        now.difference(_lastSyncTime!) > const Duration(seconds: 4);

    if (!isTrackChanged &&
        !isPlayingChanged &&
        !isDurationChanged &&
        !isPositionJump &&
        !isPeriodicSync) {
      return;
    }

    _lastTrackId = track.id;
    _lastIsPlaying = isPlaying;
    _lastDurationSeconds = currentDurationSec;
    _lastPositionSeconds = currentPositionSec;
    _lastSyncTime = now;

    try {
      _channel.invokeMethod('updateNowPlaying', {
        'title': track.title,
        'artist': track.artist,
        'album': track.albumTitle ?? '',
        'duration': currentDurationSec,
        'position': currentPositionSec,
        'isPlaying': isPlaying,
        'artworkUrl': track.image ?? '',
      });
    } catch (_) {}
  }
}
