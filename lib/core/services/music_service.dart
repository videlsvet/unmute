import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/artist.dart';
import '../models/track.dart';
import '../network/app_config.dart';

class SearchPageResult {
  const SearchPageResult({
    required this.tracks,
    required this.artists,
    required this.hasMore,
    required this.nextOffset,
  });

  final List<Track> tracks;
  final List<ArtistSummary> artists;
  final bool hasMore;
  final int nextOffset;

  factory SearchPageResult.fromJson(Map<String, dynamic> json) {
    final tracksRaw = (json['tracks'] as List?) ?? const [];
    final artistsRaw = (json['artists'] as List?) ?? const [];
    final fallbackSource = (json['source'] ?? json['service'] ?? '').toString();

    final tracks = tracksRaw
        .whereType<Map>()
        .map((e) {
          final trackJson = Map<String, dynamic>.from(e);
          if ((trackJson['source'] ?? '').toString().trim().isEmpty &&
              fallbackSource.trim().isNotEmpty) {
            trackJson['source'] = fallbackSource;
          }
          return Track.fromJson(trackJson);
        })
        .where((t) => (t.error ?? '').isEmpty)
        .toList();

    final artists = artistsRaw
        .whereType<Map>()
        .map((e) {
          final artistJson = Map<String, dynamic>.from(e);
          if ((artistJson['source'] ?? '').toString().trim().isEmpty &&
              fallbackSource.trim().isNotEmpty) {
            artistJson['source'] = fallbackSource;
          }
          return ArtistSummary.fromJson(artistJson);
        })
        .toList();

    final nextOffsetRaw = json['next_offset'];
    final nextOffset = nextOffsetRaw is int
        ? nextOffsetRaw
        : int.tryParse('$nextOffsetRaw') ?? tracks.length;

    return SearchPageResult(
      tracks: tracks,
      artists: artists,
      hasMore: json['has_more'] == true,
      nextOffset: nextOffset,
    );
  }
}

class ArtistResult {
  const ArtistResult({
    required this.name,
    required this.source,
    required this.tracks,
    this.artistId,
    this.image,
  });

  final String name;
  final String source;
  final String? artistId;
  final String? image;
  final List<Track> tracks;

  factory ArtistResult.fromJson(Map<String, dynamic> json) {
    final artist = Map<String, dynamic>.from((json['artist'] as Map?) ?? {});
    final tracksRaw = (json['tracks'] as List?) ?? const [];
    final fallbackSource = (json['source'] ?? json['service'] ?? '').toString();

    return ArtistResult(
      artistId: artist['artist_id']?.toString(),
      name: (artist['artist_name'] ?? 'Без имени').toString(),
      image: artist['image']?.toString(),
      source: fallbackSource,
      tracks: tracksRaw
          .whereType<Map>()
          .map((e) {
            final trackJson = Map<String, dynamic>.from(e);
            if ((trackJson['source'] ?? '').toString().trim().isEmpty &&
                fallbackSource.trim().isNotEmpty) {
              trackJson['source'] = fallbackSource;
            }
            return Track.fromJson(trackJson);
          })
          .where((t) => (t.error ?? '').isEmpty)
          .toList(),
    );
  }
}

class AlbumResult {
  const AlbumResult({
    required this.title,
    required this.source,
    required this.tracks,
    this.albumId,
    this.image,
    this.year,
  });

  final String title;
  final String source;
  final String? albumId;
  final String? image;
  final int? year;
  final List<Track> tracks;

  factory AlbumResult.fromJson(Map<String, dynamic> json) {
    final album = Map<String, dynamic>.from((json['album'] as Map?) ?? {});
    final tracksRaw = (json['tracks'] as List?) ?? const [];
    final fallbackSource = (json['source'] ?? json['service'] ?? '').toString();

    return AlbumResult(
      albumId: album['album_id']?.toString(),
      title: (album['album_title'] ?? 'Альбом').toString(),
      image: album['image']?.toString(),
      year: int.tryParse('${album['album_year']}'),
      source: fallbackSource,
      tracks: tracksRaw
          .whereType<Map>()
          .map((e) {
            final trackJson = Map<String, dynamic>.from(e);
            if ((trackJson['source'] ?? '').toString().trim().isEmpty &&
                fallbackSource.trim().isNotEmpty) {
              trackJson['source'] = fallbackSource;
            }
            return Track.fromJson(trackJson);
          })
          .where((t) => (t.error ?? '').isEmpty)
          .toList(),
    );
  }
}

class MusicService {
  Future<dynamic> _fetchWithFallback(Map<String, String> params) async {
    final endpoints = [
      AppConfig.apiGatewayUrl,
      AppConfig.searchBaseUrl,
    ];

    Object? lastError;
    for (final base in endpoints) {
      try {
        final uri = Uri.parse(base).replace(queryParameters: params);
        final response = await http.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        lastError = e;
      }
    }
    throw Exception(lastError?.toString() ?? 'Ошибка обращения к музыкальному сервису');
  }

  Future<SearchPageResult> search({
    required String service,
    required String query,
    int limit = 40,
    int offset = 0,
  }) async {
    final params = {
      'type': 'search_v2',
      'service': service,
      'q': query,
      'limit': '$limit',
      'offset': '$offset',
    };

    final data = await _fetchWithFallback(params);
    if (data is Map) {
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return SearchPageResult.fromJson(Map<String, dynamic>.from(data));
    } else if (data is List) {
      final tracks = data
          .whereType<Map>()
          .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
          .where((t) => (t.error ?? '').isEmpty)
          .toList();
      return SearchPageResult(
        tracks: tracks,
        artists: const [],
        hasMore: false,
        nextOffset: tracks.length,
      );
    }
    throw Exception('Некорректный формат ответа поиска');
  }

  Future<ArtistResult> loadArtist({
    required String service,
    String? artistId,
    String? artistName,
  }) async {
    final params = <String, String>{
      'type': 'artist',
      'service': service,
    };

    if ((artistId ?? '').trim().isNotEmpty) {
      params['artist_id'] = artistId!.trim();
    }
    if ((artistName ?? '').trim().isNotEmpty) {
      params['artist_name'] = artistName!.trim();
    }

    final data = await _fetchWithFallback(params);
    if (data is Map) {
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return ArtistResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('Некорректный формат ответа артиста');
  }

  Future<AlbumResult> loadAlbum({
    required String service,
    required String albumId,
    String? ownerId,
    String? accessKey,
  }) async {
    final params = <String, String>{
      'type': 'album',
      'service': service,
      'album_id': albumId,
    };

    if ((ownerId ?? '').trim().isNotEmpty) {
      params['owner_id'] = ownerId!.trim();
    }
    if ((accessKey ?? '').trim().isNotEmpty) {
      params['access_key'] = accessKey!.trim();
    }

    final data = await _fetchWithFallback(params);
    if (data is Map) {
      if (data.containsKey('error') && data['error'] != null) {
        throw Exception(data['error'].toString());
      }
      return AlbumResult.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('Некорректный формат ответа альбома');
  }

  Future<List<Track>> loadSimilarTracks({
    required String service,
    required String trackId,
  }) async {
    final params = <String, String>{
      'type': 'similar',
      'service': service,
      'track_id': trackId,
    };

    try {
      final data = await _fetchWithFallback(params);
      if (data is List) {
        return data
            .whereType<Map>()
            .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
            .where((t) => (t.error ?? '').isEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
