import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/playlist.dart';
import '../models/track.dart';
import '../network/app_config.dart';
import '../network/backend_client.dart';

class PlaylistService {
  Future<List<PlaylistSummary>> listPlaylists(String token) async {
    final response = await _post({
      'action': 'list_playlists',
      'token': token,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'List playlists error').toString());
    }
    if (data is! List) {
      throw Exception('Некорректный ответ list_playlists');
    }

    return data
        .whereType<Map>()
        .map((e) => PlaylistSummary.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<String> createPlaylist({
    required String token,
    required String title,
  }) async {
    final response = await _post({
      'action': 'create_playlist',
      'token': token,
      'title': title,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Create playlist error').toString());
    }

    return (data['playlist_id'] ?? '').toString();
  }

  Future<String> addPlaylist({
    required String token,
    required String title,
    required String link,
  }) async {
    final response = await _post({
      'action': 'add_playlist',
      'token': token,
      'title': title,
      'link': link,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Add playlist error').toString());
    }

    return (data['playlist_id'] ?? '').toString();
  }

  Future<void> updatePlaylist({
    required String token,
    required String playlistId,
    required String title,
  }) async {
    final response = await _post({
      'action': 'update_playlist',
      'token': token,
      'playlist_id': playlistId,
      'title': title,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Update playlist error').toString());
    }
  }

  Future<void> deletePlaylist({
    required String token,
    required String playlistId,
  }) async {
    final response = await _post({
      'action': 'delete_playlist',
      'token': token,
      'playlist_id': playlistId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Delete playlist error').toString());
    }
  }

  Future<void> addTrackToPlaylist({
    required String token,
    required String playlistId,
    required Track track,
  }) async {
    final response = await _post({
      'action': 'add_track_to_playlist',
      'token': token,
      'playlist_id': playlistId,
      'track': track.toBackendJson(),
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Add track error').toString());
    }
  }

  Future<List<Track>> listPlaylistTracks({
    required String token,
    required String playlistId,
  }) async {
    final response = await _post({
      'action': 'list_playlist_tracks',
      'token': token,
      'playlist_id': playlistId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'List playlist tracks error').toString());
    }

    final tracks = (data['tracks'] as List?) ?? const [];
    return tracks
        .whereType<Map>()
        .map((e) => Track.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> removeTrackFromPlaylist({
    required String token,
    required String playlistId,
    required String trackId,
  }) async {
    final response = await _post({
      'action': 'remove_track_from_playlist',
      'token': token,
      'playlist_id': playlistId,
      'track_id': trackId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Remove track error').toString());
    }
  }

  Future<void> importPlaylistText({
    required String token,
    required String playlistId,
    required String text,
    required String service,
  }) async {
    final response = await _post({
      'action': 'import_playlist_text',
      'token': token,
      'playlist_id': playlistId,
      'text': text,
      'service': service,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Import playlist text error').toString());
    }
  }

  Future<FavoriteImportResult> importTextToFavorites({
    required String token,
    required String text,
    required String service,
    int offset = 0,
    int batchSize = 2,
  }) async {
    final response = await _post({
      'action': 'import_text_to_favorites',
      'token': token,
      'text': text,
      'service': service,
      'offset': offset,
      'batch_size': batchSize,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Import favorites error').toString());
    }

    return FavoriteImportResult.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ImportProgress> getPlaylistImportProgress({
    required String token,
    required String playlistId,
  }) async {
    final response = await _post({
      'action': 'playlist_import_progress',
      'token': token,
      'playlist_id': playlistId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Import progress error').toString());
    }

    return ImportProgress.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<PlaylistTrackItem>> getRealPlaylist({
    required String token,
    required String playlistId,
  }) async {
    final response = await _post({
      'action': 'get_real_playlist',
      'token': token,
      'playlist_id': playlistId,
    });

    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception((data['error'] ?? 'Get real playlist error').toString());
    }

    final tracks = (data['tracks'] as List?) ?? const [];
    return tracks
        .whereType<Map>()
        .map((e) => PlaylistTrackItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<http.Response> _post(Map<String, dynamic> body) {
    return postJson(Uri.parse(AppConfig.authBaseUrl), body);
  }
}
