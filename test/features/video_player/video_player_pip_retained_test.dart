import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'PiP iOS starting entry hides Flutter subtitles and keeps native subtitles during a playlist open',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final gate = Completer<void>();
      Future<dynamic>? pending;
      try {
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/pa.mp4',
            title: 'PiP A',
            playlist: [
              PlaylistEntry(url: 'https://player.test/pa.mp4', title: 'PiP A'),
              PlaylistEntry(url: 'https://player.test/pb.mp4', title: 'PiP B'),
            ],
            startIndex: 0,
          ),
        );
        final n = f.player.platform! as FakeNativePlayer;
        final marker = n.calls.length;
        final openingVisibility = <String>[];
        f.player.beforeOperation = (name, value) {
          if (name == 'open') {
            openingVisibility.addAll(
              n.calls
                  .skip(marker)
                  .where(
                    (c) =>
                        c.$1 == 'setProperty' &&
                        (c.$2 as (String, String)).$1 == 'sub-visibility',
                  )
                  .map((c) => (c.$2 as (String, String)).$2),
            );
          }
          return null;
        };
        f.player.delays['handle'] = gate;
        final dynamic callback = playerControls(t).onPip!;
        pending = d.observe<Future<dynamic>>(() => callback());
        await f.until(t, () => d.operations('handle').isNotEmpty);
        await d.settle();
        expect(
          t
              .widget<mkv.Video>(find.byType(mkv.Video))
              .subtitleViewConfiguration
              .visible,
          isFalse,
        );
        playerControls(t).onNext!();
        await d.settle();
        await f.until(t, () => d.operations('open').length == 2);
        expect(openingVisibility, ['yes']);
        expect(
          n.calls
              .skip(marker)
              .where(
                (c) =>
                    c.$1 == 'setProperty' && c.$2 == ('sub-visibility', 'yes'),
              ),
          isNotEmpty,
        );
        expect(
          f.player.state.playlist.medias.single.uri,
          'https://player.test/pb.mp4',
        );
        gate.complete();
        f.player.delays.remove('handle');
        await f.finish<dynamic>(t, pending);
        await d.settle();
        expect(
          t
              .widget<mkv.Video>(find.byType(mkv.Video))
              .subtitleViewConfiguration
              .visible,
          isTrue,
        );
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (f.players.isNotEmpty) {
          f.player.delays.remove('handle');
        }
        if (pending != null) {
          await f.finish<dynamic>(t, pending);
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP parked next episode completes its original route result without reopening or returning fullscreen',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      TraktTestTransport.instance.attach(f);
      try {
        f.network.handler = (r) => r.url.path.contains('/tv/episodes/86420001')
            ? http.Response(
                jsonEncode([
                  {'season': 1, 'episode': 1, 'title': 'First'},
                  {'season': 1, 'episode': 2, 'title': 'Second'},
                ]),
                200,
              )
            : http.Response('{}', 404);
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/park-next.mp4',
            title: 'Parked series',
            contentImdbId: 'simkl:86420001',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
          ),
        );
        await d.enter();
        await d.deliver('onPipModeChanged', true);
        f.player.emit('completed', true);
        await d.settle();
        final result = await f.finish(t, d.route!.popped);
        expect(result, {
          'quickPlayNext': true,
          'imdbId': 'simkl:86420001',
          'season': 1,
          'episode': 2,
          'title': 'Parked series',
          'contentType': 'series',
        });
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(find.text('PiP browser'), findsOneWidget);
        expect(f.players, hasLength(1));
        expect(d.operations('open'), hasLength(1));
      } finally {
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );
  testWidgets(
    'PiP scoped State disposal completes its session while the hosting route remains present',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final show = ValueNotifier(true);
      final route = IosPipPlayerRoute<Object?>(
        builder: (_) => ValueListenableBuilder<bool>(
          valueListenable: show,
          builder: (_, visible, __) =>
              visible ? pipScreen : const Text('No player'),
        ),
      );
      try {
        await d.observe(() async {
          await t.pumpWidget(
            MaterialApp(navigatorKey: f.navigator, home: const Text('Browser')),
          );
          f.navigator.currentState!.push(route);
          await f.until(t, () => f.controllers.isNotEmpty);
          f.player.deliverReady();
          await f.until(t, () => d.operations('open').isNotEmpty);
          await f.until(
            t,
            () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
          );
        });
        var completed = false;
        Object? result = 'pending';
        route.popped.then((v) {
          completed = true;
          result = v;
        });
        expect(completed, isFalse);
        show.value = false;
        await d.settle();
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(completed, isTrue);
        expect(result, isNull);
        expect(route.isCurrent, isTrue);
        expect(find.text('No player'), findsOneWidget);
      } finally {
        await d.close();
        show.dispose();
      }
    },
  );
}
