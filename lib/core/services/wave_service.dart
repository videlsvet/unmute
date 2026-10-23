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
  flow,        // Моя Волна (персональный сбалансированный поток)
  exploration, // Открытия (незнакомое, свежие находки)
  favorites,   // Любимое (золотая коллекция пользователя)
  energy,      // Драйв (бодрое, танцевальное, рок/хип-хоп)
  calm,        // Спокойное (чилл, релакс, акустика, lo-fi)
  coldStart,   // Популярное (хиты и топ чарты)
}

extension WaveModeX on WaveMode {
  String get displayName {
    switch (this) {
      case WaveMode.flow:
        return 'Моя Волна';
      case WaveMode.exploration:
        return 'Открытия';
      case WaveMode.favorites:
        return 'Любимое';
      case WaveMode.energy:
        return 'Драйв';
      case WaveMode.calm:
        return 'Спокойное';
      case WaveMode.coldStart:
        return 'Популярное';
    }
  }

  String get description {
    switch (this) {
      case WaveMode.flow:
        return 'Персональный поток рекомендаций под ваш вкус';
      case WaveMode.exploration:
        return 'Свежие треки и новые имена, похожие на ваших любимых артистов';
      case WaveMode.favorites:
        return 'Только любимые и проверенные треки из вашей коллекции';
      case WaveMode.energy:
        return 'Энергичные, ритмичные и драйвовые треки для движения';
      case WaveMode.calm:
        return 'Спокойная, атмосферная музыка для отдыха и концентрации';
      case WaveMode.coldStart:
        return 'Самые популярные треки и хиты чартов';
    }
  }
}

// ══════════════════════════════════════════════════════════════
//          ARTIST SIMILARITY GRAPH (COLLABORATIVE MAP)
// ══════════════════════════════════════════════════════════════

/// Knowledge graph mapping artists to closely related artists across genres.
/// Simulates Yandex Music's collaborative filtering embeddings.
class ArtistSimilarityGraph {
  static final Map<String, List<String>> _similarityMap = {
    // Russian Hip-Hop / Trap
    'скриптонит': ['104', 'truwer', 'niman', 'saluki', 'масло черного тмина', 't fest', 'баста'],
    'saluki': ['boulevard depo', 'сеня полоз', 'thomas mraz', 'og buda', '104', 'скриптонит'],
    'pharaoh': ['лсп', 'boulevard depo', 'mnogoznaal', 'jeembo', 'tveth', 'saluki', 'dead dynasty'],
    'oxxxymiron': ['markul', 'loqiemean', 'porchy', 'thomas mraz', 'horus', 'schokk', 'atl'],
    'boulevard depo': ['saluki', 'pharaoh', 'jeembo', 'basic boy', 'glebasta spal', 'rocket'],
    'big baby tape': ['kizaru', 'aarne', 'alblak 52', 'friendly thug 52 ngg', r'toxi$', 'og buda'],
    'kizaru': ['big baby tape', 'alblak 52', 'friendly thug 52 ngg', 'obratno', 'hoodrich pablo juan'],
    'friendly thug 52 ngg': ['alblak 52', 'glocki52', 'saintprince 52', 'big baby tape', 'kizaru'],
    'alblak 52': ['friendly thug 52 ngg', 'glocki52', 'big baby tape', 'kizaru'],
    'macan': ['navai', 'hammali navai', 'xcho', 'jakone', 'kiliana', 'ramil'],
    'miyagi эндшпиль': ['andy panda', 'miyagi', 'tumaniyo', 'castle', 'mav d', 'krec', 'hloy'],
    'miyagi': ['andy panda', 'miyagi эндшпиль', 'tumaniyo', 'castle', 'hloy', 'rem digga'],
    'andy panda': ['miyagi', 'miyagi эндшпиль', 'tumaniyo', 'castle', 'hloy'],
    'atl': ['горизонт', 'loqiemean', 'егор натс', 'oxxxymiron', 'пика', 'зараза'],
    'markul': ['oxxxymiron', 'thomas mraz', 'obladaet', 'платина', 'feduk'],
    'og buda': ['mayot', 'seventeen', r'toxi$', 'scally milano', '163onmyneck', 'saluki'],
    'mayot': ['og buda', 'seventeen', 'scally milano', '163onmyneck', r'toxi$'],
    r'toxi$': ['og buda', 'mayot', 'big baby tape', 'aarne', 'heronwater'],

    // Russian Indie / Post-Punk / Alternative
    'дайте танк': ['ssshhhiiittt', 'папин олимпос', 'перемотка', 'комсомольск', 'валентин стрыкало', 'петля пристрастия'],
    'молчат дома': ['ploho', 'буерак', 'дурной вкус', 'chernikovskaya hata', 'электрофорез', 'союз'],
    'буерак': ['молчат дома', 'ploho', 'дурной вкус', 'пасош', 'увула', 'электрофорез'],
    'ssshhhiiittt': ['дайте танк', 'папин олимпос', 'перемотка', 'пасош', 'пошлая молли'],
    'папин олимпос': ['дайте танк', 'ssshhhiiittt', 'три дня дождя', 'валентин стрыкало'],
    'три дня дождя': ['zivert', 'папин олимпос', 'мукка', 'кис кис', 'тринадцать карат'],
    'сироткин': ['polnalyubvi', 'мы', 'свидание', 'the retuses', 'обе две', 'тима ищет свет'],
    'polnalyubvi': ['сироткин', 'мы', 'свидание', 'обе две', 'маяковский', 'алена швец'],
    'перемотка': ['дайте танк', 'молчат дома', 'буерак', 'ssshhhiiittt', 'дурной вкус'],
    'электрофорез': ['молчат дома', 'буерак', 'ploho', 'shortparis', 'ic3peak'],
    'shortparis': ['электрофорез', 'ic3peak', 'аигел', 'хадн дадн', 'глупый белый'],
    'валентин стрыкало': ['дайте танк', 'папин олимпос', 'ssshhhiiittt', 'пошлая молли', 'нервы'],
    'нервы': ['валентин стрыкало', 'пошлая молли', 'три дня дождя', 'папин олимпос'],

    // Russian Rock & Classic
    'король и шут': ['княzz', 'сектор газа', 'порнофильмы', 'кукрыниксы', 'эпидемия', 'кипелов'],
    'княzz': ['король и шут', 'сектор газа', 'кукрыниксы', 'ария'],
    'сектор газа': ['король и шут', 'княzz', 'гражданская оборона', 'ленинград'],
    'кино': ['наутилус помпилиус', 'аквариум', 'ддт', 'алиса', 'би 2', 'сплин', 'виктор цой'],
    'наутилус помпилиус': ['кино', 'сплин', 'агата кристи', 'пикник', 'ддт', 'би 2'],
    'би 2': ['сплин', 'земфира', 'мумий тролль', 'агата кристи', 'кино', 'ночные снайперы'],
    'сплин': ['би 2', 'земфира', 'мумий тролль', 'кино', 'наутилус помпилиус', 'animal джаz'],
    'земфира': ['мумий тролль', 'ночные снайперы', 'сплин', 'би 2', 'моя мишель'],
    'агата кристи': ['наутилус помпилиус', 'пикник', 'сплин', 'король и шут'],
    'порнофильмы': ['король и шут', 'йорш', 'тараканы', 'люмен', 'lumen', 'план ломоносова'],

    // Russian Pop / Electronic
    'anna asti': ['zivert', 'мари краймбрери', 'jony', 'seville', 'люся чеботина', 'artik asti'],
    'zivert': ['anna asti', 'мари краймбрери', 'cream soda', 'jony', 'моя мишель'],
    'cream soda': ['антоха мс', 'tesla boy', 'иван дорн', 'kedr livanskiy', 'лауд'],
    'jony': ['hammali navai', 'navai', 'motto', 'andry', 'elmin', 'xcho', 'rauf faik'],

    // International Rock / Metal / Alternative
    'linkin park': ['bring me the horizon', 'three days grace', 'evanescence', 'papa roach', 'breaking benjamin', 'skillet'],
    'bring me the horizon': ['linkin park', 'bad omens', 'architects', 'falling in reverse', 'i prevail'],
    'three days grace': ['linkin park', 'skillet', 'breaking benjamin', 'saint asonia', 'shinedown'],
    'deftones': ['korn', 'slipknot', 'system of a down', 'alice in chains', 'tool', 'chevelle'],
    'system of a down': ['deftones', 'korn', 'slipknot', 'rage against the machine', 'serj tankian'],
    'radiohead': ['the smile', 'thom yorke', 'muse', 'coldplay', 'massive attack', 'portishead'],
    'arctic monkeys': ['the neighbourhood', 'the strokes', 'gorillaz', 'franz ferdinand', 'foals'],
    'the neighbourhood': ['arctic monkeys', 'chase atlantic', 'cigarettes after sex', 'lana del rey', 'joji'],
    'cigarettes after sex': ['the neighbourhood', 'beach house', 'mazzy star', 'lana del rey'],
    'nirvana': ['foo fighters', 'soundgarden', 'pearl jam', 'alice in chains', 'the smashing pumpkins'],
    'rammstein': ['lindemann', 'oomph', 'eisbrecher', 'megaherz', 'pain'],

    // International Hip-Hop & R&B
    'the weeknd': ['travis scott', 'drake', 'post malone', 'frank ocean', 'joji', 'kendrick lamar'],
    'travis scott': ['metro boomin', 'playboi carti', '21 savage', 'don toliver', 'asap rocky'],
    'kanye west': ['kid cudi', 'asap rocky', 'tyler the creator', 'pusha t', 'kendrick lamar', 'jay z'],
    'drake': ['the weeknd', 'travis scott', 'future', '21 savage', 'partynextdoor'],
    'kendrick lamar': ['j cole', 'kanye west', 'baby keem', 'asap rocky', 'schoolboy q'],
    'joji': ['the neighbourhood', 'chase atlantic', 'the weeknd', 'frank ocean', 'keshi'],
    'post malone': ['the weeknd', 'juice wrld', 'xxxtentacion', 'lil peep', 'iann dior'],
    'eminem': ['50 cent', 'dr dre', '2pac', 'snoop dogg', 'royce da 5 9'],

    // International Electronic & Synthwave
    'daft punk': ['justice', 'kavinsky', 'the chemical brothers', 'gesaffelstein', 'carpenter brut', 'moderat'],
    'gesaffelstein': ['daft punk', 'kavinsky', 'boyz noize', 'carpenter brut', 'perturbator'],
    'kavinsky': ['daft punk', 'gesaffelstein', 'carpenter brut', 'perturbator', 'lorn'],
    'burial': ['four tet', 'bonobo', 'tycho', 'boards of canada', 'aphex twin', 'jon hopkins'],
    'bonobo': ['tycho', 'four tet', 'maribou state', 'burial', 'emancipator', 'olafor arnalds'],
    'massive attack': ['portishead', 'tricky', 'morcheeba', 'radiohead', 'sneaker pimps'],

    // International Pop & Indie
    'billie eilish': ['lana del rey', 'lorde', 'finneas', 'olivia rodrigo', 'girl in red', 'clairo'],
    'lana del rey': ['billie eilish', 'the neighbourhood', 'marina', 'arctic monkeys', 'florence the machine'],
    'dua lipa': ['the weeknd', 'miley cyrus', 'doja cat', 'charli xcx', 'ava max'],
  };

  /// Returns known similar artists for [rawArtist].
  static List<String> getKindredArtists(String? rawArtist) {
    final key = canonicalArtist(rawArtist);
    if (key.isEmpty) return const [];

    // Exact key lookup
    if (_similarityMap.containsKey(key)) {
      return List<String>.from(_similarityMap[key]!);
    }

    // Substring or prefix lookup
    for (final entry in _similarityMap.entries) {
      if (entry.key.contains(key) || key.contains(entry.key)) {
        return List<String>.from(entry.value);
      }
    }

    return const [];
  }
}

// ══════════════════════════════════════════════════════════════
//                     WAVE PROFILE STORE
// ══════════════════════════════════════════════════════════════

class WaveProfileStore {
  static const _keyArtists = 'wave_profile_artists_v2';
  static const _keyHistory = 'wave_profile_history_v2';
  static const _keyDislikes = 'wave_profile_dislikes_v2';
  static const _keySkips = 'wave_profile_skips_v2';

  static const int _historyMax = 500;
  static const int _dislikesMax = 300;

  /// In-memory session set of artists that were quickly skipped to steer away in this session.
  final Set<String> sessionSkippedArtists = {};

  String makeTrackKey(String? artist, String? title) {
    final a = canonicalArtist(artist);
    final t = canonicalTitle(title);
    if (a.isEmpty && t.isEmpty) return '';
    return '$a—$t';
  }

  /// Returns top artists weighted by listen affinity and recency decay.
  Future<List<String>> topArtists(int n) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyArtists);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final now = DateTime.now().millisecondsSinceEpoch;

      final scored = <MapEntry<String, double>>[];
      for (final entry in map.entries) {
        final artist = entry.key;
        final data = Map<String, dynamic>.from(entry.value as Map);
        final score = (data['score'] as num?)?.toDouble() ?? 0.0;
        final lastPlayed = (data['lastPlayed'] as num?)?.toInt() ?? 0;

        // Exponential decay: half-life ~14 days without listening
        final daysSince = max(0, (now - lastPlayed) / (1000 * 60 * 60 * 24));
        final decayFactor = pow(0.95, daysSince).toDouble();
        final finalScore = score * decayFactor;

        if (finalScore > 0.5) {
          scored.add(MapEntry(artist, finalScore));
        }
      }

      scored.sort((a, b) => b.value.compareTo(a.value));
      return scored.take(n).map((e) => e.key).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> adjustArtist(String? artistRaw, double delta) async {
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
    final currentScore = (data['score'] as num?)?.toDouble() ?? 0.0;
    final newScore = (currentScore + delta).clamp(-50.0, 999.0);

    data['score'] = newScore;
    data['lastPlayed'] = DateTime.now().millisecondsSinceEpoch;

    if (newScore <= 0.0) {
      map.remove(artist);
    } else {
      map[artist] = data;
    }

    await prefs.setString(_keyArtists, jsonEncode(map));
  }

  /// Full listen through (>30s or >70% duration): high interest reward.
  Future<void> onCompletedListen(String? artist) => adjustArtist(artist, 2.5);

  /// User explicitly liked the track.
  Future<void> onLikeTrack(String? artist) => adjustArtist(artist, 5.0);

  /// Normal start of track.
  Future<void> onPlayTrack(String? artist) => adjustArtist(artist, 0.5);

  /// User explicitly disliked track: severe penalty.
  Future<void> onDislikeTrack(String? artist) => adjustArtist(artist, -15.0);

  /// Quick skip (<15s): negative feedback.
  Future<void> onSkipTrack(String? artist) {
    final a = canonicalArtist(artist);
    if (a.isNotEmpty) {
      sessionSkippedArtists.add(a);
    }
    return adjustArtist(artist, -2.5);
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

  /// Generates a fresh, cohesive queue of recommended tracks.
  ///
  /// CRITICAL: This is strictly independent of whatever playlist was playing before!
  /// It builds recommendations from the user's taste profile, similar artists graph,
  /// and selected [mode].
  Future<List<Track>> generate({
    int amount = 30,
    WaveMode mode = WaveMode.flow,
  }) async {
    if (_sessionPlayedKeys.length > 60) {
      final keep = _sessionPlayedKeys.skip(_sessionPlayedKeys.length - 20).toList();
      _sessionPlayedKeys
        ..clear()
        ..addAll(keep);
    }

    final topStoredArtists = await store.topArtists(12);
    final historySet = await store.historyKeysLast(150);

    // 1. Fetch user's saved favorites
    List<Track> userFavorites = const [];
    String? token;
    if (authService != null) {
      try {
        token = await authService!.getSavedToken();
        if (token != null && token.isNotEmpty) {
          userFavorites = await authService!.listFavorites(token);
        }
      } catch (_) {}
    }

    // 2. Mode: FAVORITES - play purely from user's liked collection + top artists
    if (mode == WaveMode.favorites && userFavorites.isNotEmpty) {
      final validFavs = <Track>[];
      for (final t in userFavorites) {
        if (!t.hasPlayableUrl) continue;
        final k = store.makeTrackKey(t.artist, t.title);
        if (await store.isDisliked(k)) continue;
        if (_sessionPlayedKeys.contains(k)) continue;
        validFavs.add(t);
      }
      if (validFavs.isNotEmpty) {
        validFavs.shuffle(_random);
        final formatted = _enforceAntiFatigue(validFavs, amount);
        for (final t in formatted) {
          _sessionPlayedKeys.add(store.makeTrackKey(t.artist, t.title));
        }
        return formatted;
      }
    }

    // 3. Extract user's core taste artists (combining favorites + history)
    final artistFrequency = <String, double>{};
    for (final t in userFavorites) {
      final a = canonicalArtist(t.artist);
      if (a.isNotEmpty) {
        artistFrequency[a] = (artistFrequency[a] ?? 0.0) + 2.0;
      }
    }
    for (var i = 0; i < topStoredArtists.length; i++) {
      final a = canonicalArtist(topStoredArtists[i]);
      if (a.isNotEmpty) {
        final weight = (topStoredArtists.length - i).toDouble();
        artistFrequency[a] = (artistFrequency[a] ?? 0.0) + weight;
      }
    }

    final rankedArtists = artistFrequency.keys.toList()
      ..sort((a, b) => (artistFrequency[b] ?? 0.0).compareTo(artistFrequency[a] ?? 0.0));

    // Fallback if brand new user without any history or likes
    if (rankedArtists.isEmpty) {
      return generateColdStart(amount);
    }

    // 4. Expand seeds using the Similarity Graph (Collaborative Filtering)
    final coreArtists = rankedArtists.take(8).toList();
    final kindredArtists = <String>{};
    for (final artist in coreArtists) {
      final similar = ArtistSimilarityGraph.getKindredArtists(artist);
      for (final s in similar) {
        final can = canonicalArtist(s);
        if (can.isNotEmpty && !rankedArtists.contains(can)) {
          kindredArtists.add(s);
        }
      }
    }

    // 5. Build dynamic search queries based on mode & taste
    final searchQueries = <String>[];

    // Mode-specific query synthesis
    switch (mode) {
      case WaveMode.flow:
        // Personal Flow: Focus on kindred artists and collaborative discovery
        final shuffledKindred = kindredArtists.toList()..shuffle(_random);
        searchQueries.addAll(shuffledKindred.take(4));
        if (searchQueries.isEmpty && coreArtists.isNotEmpty) {
          searchQueries.addAll(coreArtists.take(2));
        }
        break;

      case WaveMode.exploration:
        // Discovery: Heavy on kindred artists and fresh genre discovery
        final shuffledKindred = kindredArtists.toList()..shuffle(_random);
        searchQueries.addAll(shuffledKindred.take(3));
        const discoveryQueries = [
          'свежий инди рок',
          'новая русская музыка',
          'indie alternative new',
          'свежий хип хоп новинки',
          'открытия музыка',
        ];
        searchQueries.add(discoveryQueries[_random.nextInt(discoveryQueries.length)]);
        break;

      case WaveMode.energy:
        final shuffledCore = List<String>.from(coreArtists)..shuffle(_random);
        if (shuffledCore.isNotEmpty) {
          searchQueries.add('${shuffledCore.first} remix');
        }
        const energyQueries = [
          'танцевальные хиты',
          'драйв рок',
          'клубная музыка energy',
          'бодрый хип хоп',
        ];
        searchQueries.add(energyQueries[_random.nextInt(energyQueries.length)]);
        break;

      case WaveMode.calm:
        final shuffledCore = List<String>.from(coreArtists)..shuffle(_random);
        if (shuffledCore.isNotEmpty) {
          searchQueries.add('${shuffledCore.first} acoustic');
        }
        const calmQueries = [
          'lo-fi relax chill',
          'спокойная музыка акустика',
          'вечерний чилл инди',
          'ambient chillout',
        ];
        searchQueries.add(calmQueries[_random.nextInt(calmQueries.length)]);
        break;

      case WaveMode.coldStart:
        searchQueries.add('топ чарт хиты');
        break;

      case WaveMode.favorites:
        break;
    }

    // Dedup and select top 3-4 queries for fast parallel search
    final finalQueries = searchQueries.toSet().take(4).toList();

    // 6. PARALLEL FETCH: Gather candidates from search, similar tracks, and server Wave endpoint
    final rawCandidates = <Track>[];

    // A) Server Wave endpoint (if authenticated)
    Future<List<Track>>? serverWaveFuture;
    if (token != null && token.isNotEmpty && authService != null) {
      serverWaveFuture = authService!
          .getMyWave(
            token: token,
            service: 'yandex',
            mode: mode.name,
            limit: 30,
          )
          .catchError((_) => <Track>[]);
    }

    // B) Parallel search queries
    final searchFutures = finalQueries.map((q) => _safeSearch(q, 'yandex'));

    // C) Yandex Music native collaborative filtering: fetch similar tracks using favorite seeds
    final similarFutures = <Future<List<Track>>>[];
    final sampledSeeds = (List<Track>.from(userFavorites)..shuffle(_random)).take(4);
    for (final seedTrack in sampledSeeds) {
      final cleanId = (seedTrack.externalId ?? seedTrack.id)
          .replaceAll(RegExp(r'^[a-zA-Z]+:'), '')
          .trim();
      if (cleanId.isNotEmpty) {
        similarFutures.add(
          musicService
              .loadSimilarTracks(service: 'yandex', trackId: cleanId)
              .catchError((_) => <Track>[]),
        );
      }
    }

    final searchResults = await Future.wait(
      searchFutures.map(
        (f) => f.timeout(
          const Duration(seconds: 8),
          onTimeout: () => <Track>[],
        ),
      ),
    );
    for (final list in searchResults) {
      rawCandidates.addAll(list);
    }

    final similarResults = await Future.wait(
      similarFutures.map(
        (f) => f.timeout(
          const Duration(seconds: 8),
          onTimeout: () => <Track>[],
        ),
      ),
    );
    for (final list in similarResults) {
      rawCandidates.addAll(list);
    }

    if (serverWaveFuture != null) {
      try {
        final serverTracks = await serverWaveFuture.timeout(
          const Duration(seconds: 6),
          onTimeout: () => <Track>[],
        );
        rawCandidates.addAll(serverTracks);
      } catch (_) {}
    }

    // 7. Filter candidate tracks
    final candidateSet = <Track>[];
    final seenKeys = <String>{};
    final favoriteKeys = userFavorites
        .map((fav) => store.makeTrackKey(fav.artist, fav.title))
        .where((k) => k.isNotEmpty)
        .toSet();

    for (final tr in rawCandidates) {
      if (!tr.hasPlayableUrl) continue;
      final k = store.makeTrackKey(tr.artist, tr.title);
      if (k.isEmpty || seenKeys.contains(k)) continue;
      if (historySet.contains(k)) continue;
      if (_sessionPlayedKeys.contains(k)) continue;
      if (await store.isDisliked(k)) continue;
      if (await store.skipCount(k) >= 3) continue;

      // In recommendation modes, strictly exclude tracks already in user's favorites!
      // My Wave is purely for discovering new music and similar recommendations.
      if (mode != WaveMode.favorites && favoriteKeys.contains(k)) {
        continue;
      }

      seenKeys.add(k);
      candidateSet.add(tr);
    }

    // Relaxed pass: if candidateSet is empty, backfill from rawCandidates ignoring history/session exclusions
    if (candidateSet.isEmpty) {
      for (final tr in rawCandidates) {
        if (!tr.hasPlayableUrl) continue;
        final k = store.makeTrackKey(tr.artist, tr.title);
        if (k.isEmpty || seenKeys.contains(k)) continue;
        if (await store.isDisliked(k)) continue;
        seenKeys.add(k);
        candidateSet.add(tr);
      }
    }

    // Still empty: fallback to user favorites if available
    if (candidateSet.isEmpty && userFavorites.isNotEmpty) {
      for (final tr in userFavorites) {
        if (!tr.hasPlayableUrl) continue;
        final k = store.makeTrackKey(tr.artist, tr.title);
        if (k.isEmpty || seenKeys.contains(k)) continue;
        seenKeys.add(k);
        candidateSet.add(tr);
      }
    }

    if (candidateSet.isEmpty) {
      return generateColdStart(amount);
    }

    // 8. Multi-factor scoring formula:
    // Affinity + Similarity + Mode Novelty - Skips - Session Skips + Jitter
    final topArtistsSet = rankedArtists.take(10).toSet();
    final kindredSet = kindredArtists.map(canonicalArtist).toSet();
    final scored = <MapEntry<Track, double>>[];

    for (final track in candidateSet) {
      var score = 0.0;
      final a = canonicalArtist(track.artist);

      // Core artist affinity
      if (a.isNotEmpty && topArtistsSet.contains(a)) {
        score += 4.0;
      }

      // Kindred / similar artist bonus (strong discovery reward)
      if (a.isNotEmpty && kindredSet.contains(a)) {
        score += 6.0;
      }

      // Session steering penalty: if artist was skipped in current session, heavily penalize
      if (store.sessionSkippedArtists.contains(a)) {
        score -= 8.0;
      }

      // Lifetime skips penalty
      final k = store.makeTrackKey(track.artist, track.title);
      final skips = await store.skipCount(k);
      score -= skips * 2.5;

      // Subtle jitter to prevent deterministic repeats
      score += _random.nextDouble() * 2.0;

      scored.add(MapEntry(track, score));
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    final rankedCandidates = scored.map((e) => e.key).toList();

    // 9. Sequence formatting with anti-fatigue (no repeating artists)
    final finalResult = _enforceAntiFatigue(rankedCandidates, amount);
    for (final t in finalResult) {
      _sessionPlayedKeys.add(store.makeTrackKey(t.artist, t.title));
    }

    if (finalResult.isNotEmpty) {
      return finalResult;
    }
    return generateColdStart(amount);
  }

  /// Enforces anti-fatigue rules:
  /// 1. No consecutive tracks by the same artist (minimum gap >= 3).
  /// 2. Max 2 tracks per artist in the batch.
  List<Track> _enforceAntiFatigue(List<Track> tracks, int amount) {
    final result = <Track>[];
    final artistCount = <String, int>{};
    final artistLastIndex = <String, int>{};

    for (final tr in tracks) {
      if (result.length >= amount) break;
      final a = canonicalArtist(tr.artist);
      final count = artistCount[a] ?? 0;
      if (a.isNotEmpty && count >= 2) continue;

      final lastIdx = artistLastIndex[a];
      if (lastIdx != null && (result.length - lastIdx) < 3) {
        continue; // Too close to previous track by this artist
      }

      result.add(tr);
      artistCount[a] = count + 1;
      artistLastIndex[a] = result.length - 1;
    }

    // Fill remaining if needed
    if (result.length < amount) {
      for (final tr in tracks) {
        if (result.length >= amount) break;
        if (!result.contains(tr)) {
          final a = canonicalArtist(tr.artist);
          if (result.isNotEmpty && canonicalArtist(result.last.artist) == a) {
            continue;
          }
          result.add(tr);
        }
      }
    }

    return result;
  }

  Future<List<Track>> generateColdStart(int amount) async {
    const popularQueries = [
      'топ чарт хиты',
      'популярная музыка новинки',
      'русские хиты недели',
      'топ треки',
    ];

    final results = await Future.wait(
      popularQueries.map(
        (q) => _safeSearch(q, 'yandex').timeout(
          const Duration(seconds: 8),
          onTimeout: () => <Track>[],
        ),
      ),
    );

    final candidates = <Track>[];
    for (final list in results) {
      candidates.addAll(list);
    }

    final valid = candidates.where((t) => t.hasPlayableUrl).toList();
    if (valid.isNotEmpty) {
      valid.shuffle(_random);
      final result = _enforceAntiFatigue(valid, amount);
      for (final t in result) {
        _sessionPlayedKeys.add(store.makeTrackKey(t.artist, t.title));
      }
      return result;
    }

    // Safety net: if online cold start is empty, fallback to favorites if user has any
    if (authService != null) {
      try {
        final token = await authService!.getSavedToken();
        if (token != null && token.isNotEmpty) {
          final favs = await authService!.listFavorites(token);
          final validFavs = favs.where((t) => t.hasPlayableUrl).toList();
          if (validFavs.isNotEmpty) {
            validFavs.shuffle(_random);
            final result = _enforceAntiFatigue(validFavs, amount);
            for (final t in result) {
              _sessionPlayedKeys.add(store.makeTrackKey(t.artist, t.title));
            }
            return result;
          }
        }
      } catch (_) {}
    }

    return const [];
  }

  Future<List<Track>> _safeSearch(String query, String service) async {
    try {
      final res = await musicService.search(
        service: service,
        query: query,
        limit: 25,
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
  String statusMessage = 'Моя Волна готова к запуску';
  WaveMode mode = WaveMode.flow;
  Track? lastPlayedTrack;
  DateTime? _currentTrackStartTime;

  /// Starts Моя Волна.
  ///
  /// CRITICAL: Independent of whatever playlist was playing before!
  /// Recommendations are generated purely from the user's taste profile.
  Future<void> startWave({
    required PlayerController playerController,
  }) async {
    if (isLoading) return;

    isRunning = true;
    isLoading = true;
    statusMessage = 'Собираем персональный поток...';
    notifyListeners();

    try {
      var tracks = await generator.generate(
        amount: 30,
        mode: mode,
      );

      if (tracks.isEmpty) {
        // Direct fallback attempt: popular tracks
        tracks = await generator.generateColdStart(20);
      }

      if (tracks.isEmpty) {
        statusMessage = 'Не удалось найти треки для волны';
        isRunning = false;
        isLoading = false;
        notifyListeners();
        return;
      }

      statusMessage = 'Волна в эфире';
      isLoading = false;
      notifyListeners();

      // Launch playback strictly as Wave (isWave: true)
      await playerController.playTracks(tracks, startIndex: 0, isWave: true);
      _onTrackStarted(playerController.currentTrack);
    } catch (e) {
      statusMessage = 'Ошибка запуска: $e';
      isRunning = false;
      isLoading = false;
      notifyListeners();
    }
  }

  void onPlayerTick(PlayerController playerController) {
    if (!isRunning || !playerController.isWavePlayback) return;

    // Monitor track transitions
    final current = playerController.currentTrack;
    if (current != null && current.id != lastPlayedTrack?.id) {
      _handleTrackChanged(lastPlayedTrack, current);
    }

    // Auto-load next batch when queue remaining count <= 4
    if (!isLoading && playerController.remainingTracksCount <= 4) {
      loadMore(playerController);
    }
  }

  Future<void> loadMore(PlayerController playerController) async {
    if (isLoading || !isRunning || !playerController.isWavePlayback) return;

    isLoading = true;
    notifyListeners();

    try {
      final moreTracks = await generator.generate(
        amount: 20,
        mode: mode,
      );

      if (moreTracks.isNotEmpty && isRunning && playerController.isWavePlayback) {
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

      // If skipped within 15 seconds, penalize artist and track
      if (elapsed.inSeconds < 15) {
        final key = store.makeTrackKey(previous.artist, previous.title);
        store.markSkipped(key);
        store.onSkipTrack(previous.artist);
      } else if (elapsed.inSeconds >= 30) {
        // High engagement: listened through
        store.onCompletedListen(previous.artist);
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

    // Skip and remove from current queue
    await playerController.removeTrackAndSkip(track.id);

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
    if (!isRunning) return;
    isRunning = false;
    statusMessage = 'Моя Волна остановлена';
    notifyListeners();
  }

  Future<void> setMode(WaveMode newMode, {PlayerController? playerController}) async {
    if (mode == newMode && isRunning) return;
    mode = newMode;
    notifyListeners();

    if (isRunning && playerController != null && playerController.isWavePlayback) {
      isLoading = true;
      statusMessage = 'Переключаем волну...';
      notifyListeners();

      try {
        final tracks = await generator.generate(
          amount: 25,
          mode: mode,
        );

        if (tracks.isNotEmpty) {
          await playerController.playTracks(tracks, startIndex: 0, isWave: true);
          _onTrackStarted(playerController.currentTrack);
          statusMessage = 'Волна в эфире';
        }
      } catch (_) {}

      isLoading = false;
      notifyListeners();
    }
  }
}
