import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../network/app_config.dart';
import '../network/backend_client.dart';

class ProfileDto {
  const ProfileDto({
    required this.nickname,
    this.avatarUrl,
  });

  final String nickname;
  final String? avatarUrl;

  factory ProfileDto.fromJson(Map<String, dynamic> json) {
    final avatar = (json['avatar_url'] ?? '').toString().trim();
    return ProfileDto(
      nickname: (json['nickname'] ?? '').toString(),
      avatarUrl: avatar.isEmpty ? null : avatar,
    );
  }
}

class AuthService {
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
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'login',
      'nickname': nickname,
      'password': password,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Login error').toString());
    }

    final token = (data['token'] ?? '').toString();
    if (token.isEmpty) {
      throw Exception('Токен не пришёл');
    }

    await saveToken(token);
    return token;
  }

  Future<String> register({
    required String nickname,
    required String password,
  }) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'register',
      'nickname': nickname,
      'password': password,
      'avatar_url': '',
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Register error').toString());
    }

    final token = (data['token'] ?? '').toString();
    if (token.isNotEmpty) {
      await saveToken(token);
    }
    return token;
  }

  Future<ProfileDto> getProfile(String token) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'get_profile',
      'token': token,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Profile error').toString());
    }

    return ProfileDto.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Track>> listFavorites(String token) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'list_favorites',
      'token': token,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Favorites error').toString());
    }

    if (data is! List) {
      throw Exception('Некорректный ответ list_favorites');
    }

    return data
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> likeTrack({
    required String token,
    required Track track,
  }) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'like_track',
      'token': token,
      'track': track.toBackendJson(),
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Like error').toString());
    }
  }

  Future<void> removeLike({
    required String token,
    required String trackId,
  }) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'remove_like',
      'token': token,
      'track_id': trackId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Remove like error').toString());
    }
  }

  Future<String> getFreshFavoriteStream({
    required String token,
    required String trackId,
  }) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'get_stream',
      'token': token,
      'track_id': trackId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Get stream error').toString());
    }

    final preview = (data['preview'] ?? '').toString().trim();
    if (preview.isEmpty) {
      throw Exception('Сервер не вернул ссылку на поток');
    }

    return preview;
  }

  Future<List<Track>> getMyWave({
    required String token,
    String service = 'yandex',
    String mode = 'flow',
    int limit = 36,
  }) async {
    final response = await postJson(Uri.parse(AppConfig.authBaseUrl), {
      'action': 'my_wave',
      'token': token,
      'service': service,
      'mode': mode,
      'limit': limit,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Wave error').toString());
    }

    final tracksRaw = data is Map
        ? (data['tracks'] as List? ?? const [])
        : (data is List ? data : const []);

    return tracksRaw
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .where((t) => (t.error ?? '').isEmpty && t.hasPlayableUrl)
        .toList();
  }
}
