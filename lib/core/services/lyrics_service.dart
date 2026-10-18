import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

class LyricsResult {
  const LyricsResult({
    required this.lines,
    this.plainLyrics,
    this.instrumental = false,
  });

  final List<LyricLine> lines;
  final String? plainLyrics;
  final bool instrumental;

  bool get hasSyncedLyrics => lines.isNotEmpty;
}

class LyricLine {
  const LyricLine({
    required this.time,
    required this.text,
  });

  final Duration time;
  final String text;
}

class LyricsService {
  LyricsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static final Map<String, LyricsResult?> _cache = {};
  static final Map<String, Future<LyricsResult?>> _inflight = {};

  Future<LyricsResult?> preloadLyrics({
    required Track track,
    Duration? duration,
  }) {
    return loadLyrics(track: track, duration: duration);
  }

  Future<LyricsResult?> loadLyrics({
    required Track track,
    Duration? duration,
  }) {
    final title = _cleanTitle(track.title);
    final artist = _primaryArtist(track.artist);
    if (title.isEmpty || artist.isEmpty) {
      return Future<LyricsResult?>.value(null);
    }

    final cacheKey = _cacheKey(track: track, title: title, artist: artist);
    if (_cache.containsKey(cacheKey)) {
      return Future<LyricsResult?>.value(_cache[cacheKey]);
    }

    final existing = _inflight[cacheKey];
    if (existing != null) return existing;

    final future = _loadLyricsImpl(
      track: track,
      title: title,
      artist: artist,
      duration: duration,
      cacheKey: cacheKey,
    );
    _inflight[cacheKey] = future;
    return future;
  }

  Future<LyricsResult?> _loadLyricsImpl({
    required Track track,
    required String title,
    required String artist,
    required Duration? duration,
    required String cacheKey,
  }) async {
    try {
      final params = <String, String>{
        'track_name': title,
        'artist_name': artist,
      };
      final album = (track.albumTitle ?? '').trim();
      if (album.isNotEmpty) {
        params['album_name'] = album;
      }
      final seconds = duration?.inSeconds ?? 0;
      if (seconds > 0) {
        params['duration'] = '$seconds';
      }

      final uri = Uri.https('lrclib.net', '/api/get', params);
      final response = await _client.get(
        uri,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'UNMUTE/1.0 (https://lrclib.net)',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 404) {
        final fallback = await _searchLyrics(
          title: title,
          artist: artist,
          duration: duration,
        );
        _cache[cacheKey] = fallback;
        return fallback;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('LRCLIB ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final synced = (data['syncedLyrics'] ?? '').toString();
      final plain = (data['plainLyrics'] ?? '').toString().trim();
      final instrumental = data['instrumental'] == true;
      final result = LyricsResult(
        lines: _parseLrc(synced),
        plainLyrics: plain.isEmpty ? null : plain,
        instrumental: instrumental,
      );
      _cache[cacheKey] = result;
      return result;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  List<LyricLine> _parseLrc(String raw) {
    final lines = <LyricLine>[];
    final timestamp = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');

    for (final rawLine in raw.split('\n')) {
      final matches = timestamp.allMatches(rawLine).toList(growable: false);
      if (matches.isEmpty) continue;

      final text = rawLine.replaceAll(timestamp, '').trim();
      for (final match in matches) {
        final minutes = int.tryParse(match.group(1) ?? '') ?? 0;
        final seconds = int.tryParse(match.group(2) ?? '') ?? 0;
        final fraction = match.group(3) ?? '0';
        final millis = switch (fraction.length) {
          1 => int.parse(fraction) * 100,
          2 => int.parse(fraction) * 10,
          _ => int.parse(fraction.padRight(3, '0').substring(0, 3)),
        };
        lines.add(
          LyricLine(
            time: Duration(
              minutes: minutes,
              seconds: seconds,
              milliseconds: millis,
            ),
            text: text,
          ),
        );
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  Future<LyricsResult?> _searchLyrics({
    required String title,
    required String artist,
    Duration? duration,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      'artist_name': artist,
    });
    final response = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'UNMUTE/1.0 (https://lrclib.net)',
      },
    ).timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final data = jsonDecode(response.body) as List<dynamic>;
    if (data.isEmpty) return null;

    final normalizedTitle = _normalizeForMatch(title);
    final normalizedArtist = _normalizeForMatch(artist);
    final durationSeconds = duration?.inSeconds ?? 0;

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final item in data.whereType<Map>()) {
      final candidate = Map<String, dynamic>.from(item);
      final trackName =
          _normalizeForMatch(candidate['trackName']?.toString() ?? '');
      final artistName =
          _normalizeForMatch(candidate['artistName']?.toString() ?? '');
      var score = 0;
      if (trackName == normalizedTitle) score += 8;
      if (trackName.contains(normalizedTitle) ||
          normalizedTitle.contains(trackName)) {
        score += 4;
      }
      if (artistName == normalizedArtist) score += 5;
      if (artistName.contains(normalizedArtist) ||
          normalizedArtist.contains(artistName)) {
        score += 2;
      }
      final candidateDuration = int.tryParse('${candidate['duration']}') ?? 0;
      if (durationSeconds > 0 && candidateDuration > 0) {
        final diff = (candidateDuration - durationSeconds).abs();
        if (diff <= 2) {
          score += 4;
        } else if (diff <= 8) {
          score += 2;
        }
      }
      if (candidate['syncedLyrics'] != null &&
          candidate['syncedLyrics'].toString().trim().isNotEmpty) {
        score += 3;
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null || bestScore <= 0) return null;
    final synced = (best['syncedLyrics'] ?? '').toString();
    final plain = (best['plainLyrics'] ?? '').toString().trim();
    return LyricsResult(
      lines: _parseLrc(synced),
      plainLyrics: plain.isEmpty ? null : plain,
      instrumental: best['instrumental'] == true,
    );
  }

  String _cacheKey({
    required Track track,
    required String title,
    required String artist,
  }) {
    return [
      track.id.trim().toLowerCase(),
      title.toLowerCase(),
      artist.toLowerCase(),
      (track.albumTitle ?? '').trim().toLowerCase(),
    ].join('|');
  }

  String _primaryArtist(String value) {
    return value
        .split(RegExp(
          r'\s*(?:,|;|&|\s+feat\.?\s+|\s+ft\.?\s+|\s+и\s+)\s*',
          caseSensitive: false,
        ))
        .map((item) => item.trim())
        .firstWhere((item) => item.isNotEmpty, orElse: () => '');
  }

  String _cleanTitle(String value) {
    return value
        .replaceAll(
          RegExp(
            r'\s*\([^)]*(?:remix|live|edit|version)[^)]*\)',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  String _normalizeForMatch(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
