import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../network/app_config.dart';
import '../network/backend_client.dart';

class ProfileService {
  Future<Profile> getProfile(String token) async {
    final response = await _post({
      'action': 'get_profile',
      'token': token,
    });
    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Profile error').toString());
    }

    return Profile.fromJson(Map<String, dynamic>.from(data));
  }

  Future<String> updateAvatar({
    required String token,
    required String avatarUrl,
  }) async {
    final response = await _post({
      'action': 'update_avatar',
      'token': token,
      'avatar_url': avatarUrl,
    });
    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Update avatar error').toString());
    }

    return (data['avatar_url'] ?? '').toString();
  }

  Future<ServiceKeys> getKeys(String token) async {
    final response = await _post({
      'action': 'get_keys',
      'token': token,
    });
    final data = jsonDecode(response.body);

    if (response.statusCode == 404) {
      return const ServiceKeys();
    }

    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Get keys error').toString());
    }

    return ServiceKeys.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> saveKeys({
    required String token,
    required ServiceKeys keys,
  }) async {
    final response = await _post({
      'action': 'save_keys',
      'token': token,
      ...keys.toJson(),
    });
    final data = jsonDecode(response.body);

    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Save keys error').toString());
    }
  }

  Future<http.Response> _post(Map<String, dynamic> body) {
    return postJson(Uri.parse(AppConfig.authBaseUrl), body);
  }
}
