import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

void main() {
  for (final paused in [false, true]) {
    testWidgets(
      'PiP background cancels held Start Over probe while user-paused=$paused without hiding its feedback',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        final gate = Completer<http.Response>();
        Future<void>? pending;
        final live = IptvChannel(
          name: 'Live',
          url:
              'https://background-catchup-${paused ? 'paused' : 'playing'}.test/live/user/pass/123.ts',
          contentType: 'live',
        );
        try {
          f.network.handler = (r) => r.url.path.contains('/timeshift/')
              ? gate.future
              : http.Response('{}', 404);
          await d.mount(
            VideoPlayerScreen(
              videoUrl: live.url,
              title: live.name,
              iptvChannels: [live],
            ),
          );
          if (paused) {
            playerControls(t).onPlayPause();
            await d.settle();
          }
          playerControls(t).onShowIptvChannels!();
          await f.until(
            t,
            () => find.byType(IptvChannelSheet).evaluate().isNotEmpty,
          );
          final sheet = t.widget<IptvChannelSheet>(
            find.byType(IptvChannelSheet),
          );
          pending = sheet.onPlayProgramme!(
            live,
            EpgProgramme(
              title: 'Held start over',
              description: '',
              start: DateTime(2020, 1, 1, 1),
              stop: DateTime(2020, 1, 1, 2),
              hasArchive: true,
              rawStart: '2020-01-01 01:00:00',
            ),
          );
          await f.until(
            t,
            () => f.network.requests.any(
              (r) => r.url.path.contains('/timeshift/'),
            ),
          );
          // Keep the guide open: closing it is itself a catchup cancellation.
          await d.settle();
          expect(gate.isCompleted, isFalse);
          await background(d);
          await foreground(d);
          await f.advance(t, const Duration(milliseconds: 300));
          expect(
            find.text('Preparing replay of "Held start over"…'),
            findsOneWidget,
          );
          gate.complete(http.Response('', 200));
          await f.finish<void>(t, pending);
          await d.settle();
          sheet.onClose();
          await d.settle();
          expect(d.operations('open'), hasLength(1));
          expect(f.player.state.playlist.medias.single.uri, live.url);
          expect(f.player.state.playing, !paused);
        } finally {
          if (!gate.isCompleted) {
            gate.complete(http.Response('', 404));
          }
          if (pending != null) {
            await f.finish<void>(t, pending);
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP background during held playlist opening latches playing intent and pauses its late playing event',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final gate = Completer<void>();
      try {
        await d.mount(
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            playlist: [
              PlaylistEntry(url: 'https://player.test/a.mp4', title: 'A'),
              PlaylistEntry(url: 'https://player.test/b.mp4', title: 'B'),
            ],
            startIndex: 0,
          ),
        );
        expect(
          (d.named('updatePlaybackState').last.arguments as Map)['hasNext'],
          isTrue,
        );
        f.player.delays['open'] = gate;
        final enter = playerControls(t).onPip!;
        await d.deliver('onPipAction', 'next');
        await f.until(t, () => d.operations('open').length == 2);
        expect(gate.isCompleted, isFalse);
        expect(f.player.state.playing, isFalse);
        final dynamic invoke = enter;
        await f.finish<dynamic>(t, invoke());
        expect(d.named('enterPip'), isEmpty);
        final before = d.operations('seek').length;
        await d.deliver('onPipAction', 'seek:5');
        expect(d.operations('seek').length, before);
        await background(d);
        gate.complete();
        f.player.delays.remove('open');
        await d.settle();
        expect(
          f.player.state.playlist.medias.single.uri,
          'https://player.test/b.mp4',
        );
        expect(f.player.state.playing, isFalse);
        await foreground(d);
        await d.settle();
        expect(f.player.state.playing, isTrue);
        expect(d.operations('play'), hasLength(1));
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        if (f.players.isNotEmpty) {
          f.player.delays.remove('open');
        }
        await d.close();
      }
    },
  );
  for (final paused in [false, true]) {
    testWidgets(
      'PiP Start Over held open arms background intent even with user-paused=$paused before the new playing event',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        final gate = Completer<void>();
        final live = IptvChannel(
          name: 'Start Over',
          url:
              'https://start-over-${paused ? 'paused' : 'playing'}.test/live/user/pass/123.ts',
          contentType: 'live',
        );
        try {
          final now = DateTime.now();
          f.network.handler = (r) {
            if (r.url.path.contains('/timeshift/')) {
              return http.Response('', 200);
            }
            if (r.url.path.endsWith('/player_api.php')) {
              return http.Response(
                jsonEncode({
                  'epg_listings': [
                    {
                      'title': 'Current broadcast',
                      'description': '',
                      'start_timestamp':
                          '${now.subtract(const Duration(minutes: 15)).millisecondsSinceEpoch ~/ 1000}',
                      'stop_timestamp':
                          '${now.add(const Duration(minutes: 45)).millisecondsSinceEpoch ~/ 1000}',
                      'start':
                          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} 01:00:00',
                      'has_archive': 1,
                    },
                  ],
                }),
                200,
              );
            }
            return http.Response('{}', 404);
          };
          await d.mount(
            VideoPlayerScreen(
              videoUrl: live.url,
              title: live.name,
              iptvChannels: [live],
            ),
          );
          await f.until(t, () => playerControls(t).onLiveEdgeAction != null);
          if (paused) {
            playerControls(t).onPlayPause();
            await d.settle();
          }
          f.player.delays['open'] = gate;
          playerControls(t).onLiveEdgeAction!();
          await f.until(t, () => d.operations('open').length == 2);
          expect(gate.isCompleted, isFalse);
          expect(playerControls(t).liveEdgeActionActive, isTrue);
          await background(d);
          gate.complete();
          f.player.delays.remove('open');
          await d.settle();
          expect(f.player.state.playing, isFalse);
          await foreground(d);
          await d.settle();
          expect(f.player.state.playing, isTrue);
          expect(d.operations('play'), hasLength(1));
          expect(d.operations('open'), hasLength(2));
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          if (f.players.isNotEmpty) {
            f.player.delays.remove('open');
          }
          await d.close();
        }
      },
    );
  }
}
