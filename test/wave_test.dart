import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:unmute/core/models/track.dart';
import 'package:unmute/core/services/music_service.dart';
import 'package:unmute/core/services/wave_service.dart';

class TestMusic extends MusicService {
  final queries = <String>[];
  @override
  Future<SearchPageResult> search(
      {required String service,
      required String query,
      int limit = 40,
      int offset = 0,
      String? token}) async {
    queries.add(query);
    if (query == 'slow artist') return Completer<SearchPageResult>().future;
    return SearchPageResult(
        tracks: List.generate(
            12,
            (i) => Track(
                id: '$i',
                title: 'Track $i',
                artist: query,
                image: null,
                preview: 'https://example.com/$i.mp3',
                source: 'yandex')),
        artists: [],
        hasMore: false,
        nextOffset: 12);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('favorite artists survive a new store instance and can be cleared',
      () async {
    await WaveProfileStore().saveFavoriteArtists(['Radiohead', 'Кино']);
    expect(await WaveProfileStore().favoriteArtists(), ['Radiohead', 'Кино']);
    await WaveProfileStore().saveFavoriteArtists([]);
    expect(await WaveProfileStore().favoriteArtists(), isEmpty);
  });
  test('personal seeds produce tracks without waiting for a stalled search',
      () async {
    final store = WaveProfileStore();
    await store.saveFavoriteArtists(['Test artist', 'Slow artist']);
    final music = TestMusic();
    final tracks = await WaveGenerator(musicService: music, store: store)
        .generate(amount: 8)
        .timeout(const Duration(seconds: 2));
    expect(music.queries, contains('test artist'));
    expect(tracks, isNotEmpty);
    expect(tracks.every((t) => t.artist == 'test artist'), isTrue);
  });
}
