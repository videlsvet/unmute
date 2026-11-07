import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:unmute/core/controllers/player_controller.dart';
import 'package:unmute/core/models/track.dart';
import 'package:unmute/widgets/premium_components.dart';
import 'package:unmute/theme/app_theme.dart';

class FakeStreams implements mk.PlayerStream {
  final end = StreamController<bool>.broadcast(sync: true);
  @override
  Stream<bool> get completed => end.stream;
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<String> get error => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayer implements mk.Player {
  @override
  final FakeStreams streams = FakeStreams();
  final opened = <mk.Playable>[];
  @override
  mk.PlayerStream get stream => streams;
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> open(mk.Playable playable, {bool play = true}) async {
    opened.add(playable);
  }

  @override
  Future<void> dispose() async {
    await streams.end.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Track song(String id) => Track(
    id: id,
    title: '',
    artist: '',
    image: null,
    preview: 'https://example.com/$id',
    source: 'yandex');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completion advances queue once and resolves each next track', () async {
    final player = FakePlayer();
    final controller = PlayerController(player: player);
    final resolved = <String>[];
    controller.prepareTrackForPlayback = (track) async {
      resolved.add(track.id);
      return track;
    };
    await controller
        .playTracks([song('1'), song('2'), song('3')], startIndex: 0);
    player.streams.end.add(true);
    player.streams.end.add(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentIndex, 1);
    expect(resolved, ['1', '2']);
    controller.dispose();
  });
  test('wave resumes when tracks arrive after queue exhaustion', () async {
    final player = FakePlayer();
    final controller = PlayerController(player: player);
    await controller.playTracks([song('1')], startIndex: 0, isWave: true);
    player.streams.end.add(true);
    await Future<void>.delayed(Duration.zero);
    controller.appendTracks([song('2')]);
    await Future<void>.delayed(Duration.zero);
    expect(controller.currentIndex, 1);
    expect(player.opened.length, 2);
    controller.dispose();
  });
  testWidgets('compact search row leaves room for title at 320px',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
            body: PremiumTrackRow(
                track: const Track(
                    id: '1',
                    title: 'Название любимой песни',
                    artist: 'Исполнитель',
                    image: null,
                    preview: 'url',
                    source: 'yandex'),
                onPlay: () {},
                onFavorite: () {},
                onAlbum: () {},
                onPlaylist: () {},
                onArtist: (_) {}))));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Название любимой песни')).width,
        greaterThan(160));
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('В избранное'), findsOneWidget);
  });
}
