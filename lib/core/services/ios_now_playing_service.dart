import 'dart:io';

import 'package:flutter/services.dart';

import '../controllers/player_controller.dart';

class IosNowPlayingService {
  static const MethodChannel _channel = MethodChannel('unmute/now_playing');
  static bool _initialized = false;

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

    try {
      _channel.invokeMethod('updateNowPlaying', {
        'title': track.title,
        'artist': track.artist,
        'album': track.albumTitle ?? '',
        'duration': controller.duration.inSeconds.toDouble(),
        'position': controller.position.inSeconds.toDouble(),
        'isPlaying': controller.isPlaying,
        'artworkUrl': track.image ?? '',
      });
    } catch (_) {}
  }
}
