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

  Future<List<Track>> generate({
    String? seedArtistRaw,
    String? seedTitleRaw,
    int amount = 30,
    WaveMode mode = WaveMode.flow,
  }) async {
    final seedArtist = canonicalArtist(seedArtistRaw);
    final seedTitle = canonicalTitle(seedTitleRaw);

    final topArtists = await store.topArtists(10);
    final topGenres = await store.topGenres(5);
    final historySet = await store.historyKeysLast(200);

    // 1. Fetch user's saved favorites if available
    List<Track> userFavorites = const [];
    if (authService != null) {
      try {
        final token = await authService!.getSavedToken();
        if (token != null && token.isNotEmpty) {
          userFavorites = await authService!.listFavorites(token);
        }
      } catch (_) {}
    }

    // 2. Mode: FAVORITES - play directly from user's favorite library
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

    // Extract favorite artists to seed personalization if history is empty
    final effectiveTopArtists = <String>[...topArtists];
    if (effectiveTopArtists.isEmpty && userFavorites.isNotEmpty) {
      for (final t in userFavorites) {
        final a = canonicalArtist(t.artist);
        if (a.isNotEmpty && !effectiveTopArtists.contains(a)) {
          effectiveTopArtists.add(a);
        }
      }
    }

    // COLD START — if no history, no favorites, and no seed
    if (effectiveTopArtists.isEmpty && seedArtist.isEmpty) {
      return generateColdStart(amount);
    }

    // FORM QUERIES
    final queries = <String>[];
    if (seedArtist.isNotEmpty) {
      queries.add(seedArtist);
      if (seedTitle.isNotEmpty) queries.add('$seedArtist $seedTitle');
    }

    for (final a in effectiveTopArtists.take(5)) {
      if (a.isNotEmpty && a != seedArtist) queries.add(a);
    }

    for (final g in topGenres.take(2)) {
      if (g.isNotEmpty) queries.add(g);
    }

    if (seedTitle.isNotEmpty) {
      final strong = _extractStrongWord(seedTitle);
      if (strong != null) queries.add(strong);
    }

    // Mood-specific query injection
    switch (mode) {
      case WaveMode.exploration:
        const explorationSeeds = [
          'новые треки',
          'свежая музыка',
          'инди музыка',
          'открытия музыка',
          'indie new',
        ];
        queries.add(explorationSeeds[_random.nextInt(explorationSeeds.length)]);
        break;
      case WaveMode.energy:
        const energySeeds = [
          'хиты драйв',
          'танцевальные хиты',
          'клубная музыка',
          'энергичные песни',
          'рок драйв',
        ];
        queries.add(energySeeds[_random.nextInt(energySeeds.length)]);
        break;
      case WaveMode.calm:
        const calmSeeds = [
          'спокойная музыка',
          'chillout lo-fi',
          'акустика релакс',
          'вечерний чилл',
          'расслабляющая музыка',
        ];
        queries.add(calmSeeds[_random.nextInt(calmSeeds.length)]);
        break;
      case WaveMode.coldStart:
        const popularSeeds = [
          'топ чарт',
          'главные хиты',
          'популярные песни',
          'лучшие треки',
        ];
        queries.add(popularSeeds[_random.nextInt(popularSeeds.length)]);
        break;
      case WaveMode.flow:
      case WaveMode.favorites:
        break;
    }

    final distinctQueries = queries
        .map((q) => q.trim())
        .where((q) => q.isNotEmpty)
        .toSet()
        .take(8)
        .toList();

    if (distinctQueries.isEmpty) return generateColdStart(amount);

    // FETCH CANDIDATES (Primary Yandex Music for high stream reliability)
    final candidates = <Track>[];
    for (final q in distinctQueries) {
      candidates.addAll(await _safeSearch(q, 'yandex'));
      if (candidates.length < 15) {
        candidates.addAll(await _safeSearch(q, 'vkmusic'));
      }
    }

    // CO-ARTISTS
    final coArtists = _extractCoArtists(candidates, seedArtist, effectiveTopArtists.toSet());
    for (final a in coArtists.take(3)) {
      candidates.addAll(await _safeSearch(a, 'yandex'));
    }

    // FILTER CANDIDATES
    final filtered = <Track>[];
    final seenKeys = <String>{};

    for (final track in candidates) {
      if (!track.hasPlayableUrl) continue;

      final key = store.makeTrackKey(track.artist, track.title);
      if (key.isEmpty || seenKeys.contains(key)) continue;
      if (historySet.contains(key)) continue;
      if (await store.isDisliked(key)) continue;
      if (await store.skipCount(key) >= 3) continue;

      seenKeys.add(key);
      filtered.add(track);
    }

    if (filtered.isEmpty) return generateColdStart(amount);

    // SCORE CANDIDATES
    final topSet = effectiveTopArtists.toSet();
    final scored = <MapEntry<Track, double>>[];
    for (final track in filtered) {
      final score = await _scoreTrack(track, seedArtist, topSet, seedTitle);
      scored.add(MapEntry(track, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));

    // DIVERSITY MIX: familiar + discoveries
    final familiar = scored.where((e) {
      final a = canonicalArtist(e.key.artist);
      return a.isNotEmpty && topSet.contains(a);
    }).toList();

    final discoveries = scored.where((e) {
      final a = canonicalArtist(e.key.artist);
      return a.isNotEmpty && !topSet.contains(a);
    }).toList();

    final discoveryRatio = switch (mode) {
      WaveMode.coldStart => 0.5,
      WaveMode.exploration => 0.6,
      WaveMode.flow => 0.3,
      WaveMode.favorites => 0.05,
      WaveMode.energy => 0.25,
      WaveMode.calm => 0.25,
    };

    final targetDiscoveries =
        (amount * discoveryRatio).toInt().clamp(3, max(4, amount - 5));

    final byArtistCount = <String, int>{};
    final picked = <Track>[];

    bool tryAdd(Track tr) {
      final artist = canonicalArtist(tr.artist);
      final count = byArtistCount[artist] ?? 0;
      if (artist.isNotEmpty && count >= 2) return false;
      picked.add(tr);
      byArtistCount[artist] = count + 1;
      return true;
    }

    var discCount = 0;
    for (final e in discoveries) {
      if (picked.length >= amount) break;
      if (discCount >= targetDiscoveries) break;
      if (tryAdd(e.key)) discCount++;
    }

    for (final e in [...familiar, ...discoveries]) {
      if (picked.length >= amount) break;
      tryAdd(e.key);
    }

    if (picked.isNotEmpty) return picked;
    return await generateColdStart(amount);
  }

  Future<List<Track>> generateColdStart(int amount) async {
    const popularQueries = [
      'топ чарт 2025',
      'популярные треки',
      'главные хиты',
      'новинки недели',
      'лучшая музыка',
    ];

    final candidates = <Track>[];
    for (final q in popularQueries.take(3)) {
      candidates.addAll(await _safeSearch(q, 'yandex'));
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
        limit: 15,
      );
      return res.tracks;
    } catch (_) {
      return const [];
    }
  }

  Future<double> _scoreTrack(
    Track track,
    String seedArtist,
    Set<String> topArtists,
    String seedTitle,
  ) async {
    var score = 0.0;
    final a = canonicalArtist(track.artist);
    final t = canonicalTitle(track.title);

    if (a.isNotEmpty && topArtists.contains(a)) score += 5.0;
    if (seedArtist.isNotEmpty && a == seedArtist) score += 3.0;

    if (seedTitle.isNotEmpty && t.isNotEmpty) {
      final seedWords = seedTitle.split(' ').where((w) => w.length >= 3).toSet();
      final trackWords = t.split(' ').where((w) => w.length >= 3).toSet();
      final overlap = trackWords.intersection(seedWords).length;
      score += overlap * 0.5;
    }

    final key = store.makeTrackKey(track.artist, track.title);
    final skips = await store.skipCount(key);
    score -= skips * 1.5;

    score += _random.nextDouble();
    return score;
  }

  List<String> _extractCoArtists(
    List<Track> candidates,
    String seedArtist,
    Set<String> topArtists,
  ) {
    final counts = <String, int>{};
    for (final tr in candidates) {
      final raw = tr.artist.toLowerCase();
      if (raw.isEmpty) continue;
      const splitters = [' feat. ', ' ft. ', ' & ', ', ', ' x '];
      for (final sp in splitters) {
        if (raw.contains(sp)) {
          final parts = raw.split(sp);
          for (final p in parts.skip(1)) {
            final ca = canonicalArtist(p);
            if (ca.isNotEmpty && ca != seedArtist && !topArtists.contains(ca)) {
              counts[ca] = (counts[ca] ?? 0) + 1;
            }
          }
        }
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(5).map((e) => e.key).toList();
  }

  String? _extractStrongWord(String title) {
    const stopWords = {
      'the', 'a', 'an', 'and', 'or', 'to', 'of', 'in', 'on', 'for', 'with', 'at', 'by',
      'love', 'night', 'day', 'remix', 'mix', 'edit', 'radio', 'version', 'live', 'remastered',
      'feat', 'ft', 'featuring', 'и', 'а', 'но', 'на', 'в', 'во', 'к', 'ко', 'у', 'от',
      'за', 'про', 'без', 'для', 'по', 'ты', 'я', 'мы', 'вы', 'он', 'она', 'они', 'ремикс'
    };

    final words = title
        .replaceAll(RegExp(r'[^a-z0-9а-я\s]'), ' ')
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 5 && !stopWords.contains(w));

    return words.isEmpty ? null : words.first;
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
