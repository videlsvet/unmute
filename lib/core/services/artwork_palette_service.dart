import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ArtworkPaletteService {
  ArtworkPaletteService._();

  static final ArtworkPaletteService instance = ArtworkPaletteService._();

  final Map<String, Color> _cache = {};
  final Map<String, Future<Color>> _inflight = {};

  Future<Color> preload(String? artworkUrl, {Color fallback = AppTheme.accent}) {
    return colorFor(artworkUrl, fallback: fallback);
  }

  Future<Color> colorFor(String? artworkUrl, {Color fallback = AppTheme.accent}) {
    final normalized = (artworkUrl ?? '').trim();
    if (normalized.isEmpty) return Future<Color>.value(fallback);
    if (_cache.containsKey(normalized)) {
      return Future<Color>.value(_cache[normalized]!);
    }

    final existing = _inflight[normalized];
    if (existing != null) return existing;

    final future = _resolveColor(normalized, fallback);
    _inflight[normalized] = future;
    return future;
  }

  Future<Color> _resolveColor(String artworkUrl, Color fallback) async {
    try {
      final provider = ResizeImage.resizeIfNeeded(
        40,
        40,
        NetworkImage(artworkUrl),
      );
      final image = await _loadImage(provider);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return fallback;
      final color = _extractAccent(byteData, fallback);
      _cache[artworkUrl] = color;
      return color;
    } catch (_) {
      return fallback;
    } finally {
      _inflight.remove(artworkUrl);
    }
  }

  Future<ui.Image> _loadImage(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        completer.complete(info.image);
        stream.removeListener(listener);
      },
      onError: (Object _, StackTrace? __) {
        completer.completeError(Exception('Artwork decode error'));
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Color _extractAccent(ByteData byteData, Color fallback) {
    final bytes = byteData.buffer.asUint8List();
    if (bytes.isEmpty) return fallback;

    var totalWeight = 0.0;
    var red = 0.0;
    var green = 0.0;
    var blue = 0.0;

    for (var i = 0; i <= bytes.length - 4; i += 4) {
      final r = bytes[i].toDouble();
      final g = bytes[i + 1].toDouble();
      final b = bytes[i + 2].toDouble();
      final a = bytes[i + 3].toDouble() / 255.0;
      if (a < 0.35) continue;

      final color = Color.fromARGB(
        255,
        r.round(),
        g.round(),
        b.round(),
      );
      final hsl = HSLColor.fromColor(color);
      final lightnessWeight = 1.0 - (hsl.lightness - 0.55).abs();
      final saturationWeight = 0.35 + hsl.saturation;
      final normalizedLightnessWeight =
          lightnessWeight.clamp(0.1, 1.0).toDouble();
      final weight = a * saturationWeight * normalizedLightnessWeight;

      red += r * weight;
      green += g * weight;
      blue += b * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) return fallback;

    final base = Color.fromARGB(
      255,
      (red / totalWeight).round().clamp(0, 255).toInt(),
      (green / totalWeight).round().clamp(0, 255).toInt(),
      (blue / totalWeight).round().clamp(0, 255).toInt(),
    );
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.38, 0.82).toDouble())
        .withLightness(hsl.lightness.clamp(0.34, 0.62).toDouble())
        .toColor();
  }
}
