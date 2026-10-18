import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  // ВСТАВЬ СВОИ URL
  static const String searchBaseUrl = 'https://functions.yandexcloud.net/d4e09khm9p5t3cu2oq22';
  static const String authBaseUrl = 'https://functions.yandexcloud.net/d4e55oqrims414ecgmtd';
}

class TrackResponse {
  final String? id;
  final String? title;
  final String? artist;
  final String? image;
  final String? preview;
  final String? source;
  final String? externalId;
  final String? artistId;
  final String? albumId;
  final String? ownerId;
  final String? accessKey;
  final int? audioId;
  final int? albumYear;
  final String? albumTitle;
  final String? error;

  const TrackResponse({
    this.id,
    this.title,
    this.artist,
    this.image,
    this.preview,
    this.source,
    this.externalId,
    this.artistId,
    this.albumId,
    this.ownerId,
    this.accessKey,
    this.audioId,
    this.albumYear,
    this.albumTitle,
    this.error,
  });

  factory TrackResponse.fromJson(Map<String, dynamic> json) {
    int? tryInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

    return TrackResponse(
      id: json['id']?.toString(),
      title: json['title']?.toString(),
      artist: json['artist']?.toString(),
      image: _normalizeImageUrl(json['image']?.toString()),
      preview: json['preview']?.toString(),
      source: json['source']?.toString(),
      externalId: json['externalId']?.toString() ?? json['external_id']?.toString(),
      artistId: json['artist_id']?.toString(),
      albumId: json['album_id']?.toString(),
      ownerId: json['owner_id']?.toString(),
      accessKey: json['access_key']?.toString(),
      audioId: tryInt(json['audio_id']),
      albumYear: tryInt(json['album_year']),
      albumTitle: json['album_title']?.toString(),
      error: json['error']?.toString(),
    );
  }

  Map<String, dynamic> toBackendJson() {
    return {
      'id': externalId ?? id ?? '',
      'title': title ?? '',
      'artist': artist ?? '',
      'image': image ?? '',
      'preview': preview ?? '',
      'source': source ?? '',
      'artist_id': artistId ?? '',
      'album_id': albumId ?? '',
      'album_title': albumTitle ?? '',
      'album_year': albumYear,
      'owner_id': ownerId ?? '',
      'audio_id': audioId?.toString() ?? '',
      'access_key': accessKey ?? '',
    };
  }
}

class ArtistSearchHit {
  final String? artistId;
  final String? artistName;
  final String? source;
  final String? image;

  const ArtistSearchHit({
    this.artistId,
    this.artistName,
    this.source,
    this.image,
  });

  factory ArtistSearchHit.fromJson(Map<String, dynamic> json) {
    return ArtistSearchHit(
      artistId: json['artist_id']?.toString(),
      artistName: json['artist_name']?.toString(),
      source: json['source']?.toString(),
      image: json['image']?.toString(),
    );
  }
}

class SearchPageData {
  final List<TrackResponse> tracks;
  final List<ArtistSearchHit> artists;
  final bool hasMore;
  final int? nextOffset;

  const SearchPageData({
    required this.tracks,
    required this.artists,
    required this.hasMore,
    required this.nextOffset,
  });
}

abstract class SearchApi {
  Future<SearchPageData> searchTracksPage({
    required String service,
    required String query,
    required int limit,
    required int offset,
  });
}

class HttpSearchApi implements SearchApi {
  @override
  Future<SearchPageData> searchTracksPage({
    required String service,
    required String query,
    required int limit,
    required int offset,
  }) async {
    final uri = Uri.parse(AppConfig.searchBaseUrl).replace(
      queryParameters: {
        'type': 'search_v2',
        'service': service,
        'q': query,
        'limit': '$limit',
        'offset': '$offset',
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    final tracks = ((data['tracks'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => TrackResponse.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final artists = ((data['artists'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => ArtistSearchHit.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    return SearchPageData(
      tracks: tracks,
      artists: artists,
      hasMore: data['has_more'] == true,
      nextOffset: data['next_offset'] is int
          ? data['next_offset'] as int
          : int.tryParse('${data['next_offset']}'),
    );
  }
}

class AuthApi {
  static const _tokenKey = 'auth_token';

  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<String> login({
    required String nickname,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.authBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'login',
        'nickname': nickname,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Login error');
    }

    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception('Токен не пришёл');
    }

    await saveToken(token);
    return token;
  }

  Future<void> register({
    required String nickname,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.authBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'register',
        'nickname': nickname,
        'password': password,
        'avatar_url': '',
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Register error');
    }
  }

  Future<List<TrackResponse>> listFavorites(String token) async {
    final response = await http.post(
      Uri.parse(AppConfig.authBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'list_favorites',
        'token': token,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Favorites error');
    }

    return (data as List)
        .whereType<Map>()
        .map((e) => TrackResponse.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> likeTrack({
    required String token,
    required TrackResponse track,
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.authBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'like_track',
        'token': token,
        'track': track.toBackendJson(),
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Like error');
    }
  }

  Future<void> removeLike({
    required String token,
    required String trackId,
  }) async {
    final response = await http.post(
      Uri.parse(AppConfig.authBaseUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'remove_like',
        'token': token,
        'track_id': trackId,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? 'Remove like error');
    }
  }
}

String? _normalizeImageUrl(String? url) {
  if (url == null) return null;
  final value = url.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('//')) {
    return 'https:$value';
  }

  if (value.startsWith('http://')) {
    return 'https://${value.substring(7)}';
  }

  return value;
}