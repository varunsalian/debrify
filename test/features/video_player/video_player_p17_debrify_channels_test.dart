import 'dart:async';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final directory in [null, <Map<String, dynamic>>[], tvDirectory]) {
    testWidgets('P17 directory ${directory?.length} and guide close callers', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            channelDirectory: directory,
            requestChannelById: (id) async => null,
          ),
        );
        if (directory == null || directory.isEmpty) {
          expect(playerControls(t).onShowGuide, isNull);
        } else {
          final g = await d.debrifyGuide();
          expect(
            g.channels.map((v) => (v.id, v.number, v.order, v.isCurrent)),
            [('a', 7, 0, true), ('b', 9, 1, false)],
          );
          expect(g.currentChannelId, 'a');
          expect(g.currentChannelNumber, 7);
          g.onClose();
          await d.f.advance(t);
          expect(find.byType(ChannelGuide), findsNothing);
          await d.debrifyGuide();
          await d.f.key(t, LogicalKeyboardKey.escape);
          expect(find.byType(ChannelGuide), findsNothing);
        }
      } finally {
        await d.close();
      }
    });
  }
  for (final next in [false, true]) {
    for (final payload in [
      'null',
      'throw',
      'empty',
      'primary',
      'fallback',
      'blank metadata',
      'invalid types',
      'open failure',
      'pause failure',
    ]) {
      testWidgets('P17 Debrify ${next ? 'next' : 'by id'} $payload', (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        var requests = 0;
        Future<Map<String, dynamic>?> request() async {
          requests++;
          if (payload == 'throw') {
            throw StateError(
              'provider rejected https://player.test/rejected?token=p17-fake',
            );
          }
          if (payload == 'null') {
            return null;
          }
          if (payload == 'empty') {
            return {
              'firstUrl': '',
              'channelId': 'c',
              'channelName': 'Cinema',
              'channelNumber': '12',
            };
          }
          if (payload == 'invalid types') {
            return {'firstUrl': 4, 'firstTitle': false};
          }
          return {
            if (payload == 'fallback')
              'url': 'https://player.test/b.mp4'
            else
              'firstUrl': 'https://player.test/b.mp4',
            if (payload != 'fallback') 'url': 'https://player.test/ignored.mp4',
            if (payload == 'fallback')
              'title': 'Film B'
            else
              'firstTitle': 'Film B',
            'channelId': 'c',
            'channelName': payload == 'blank metadata' ? '  ' : 'Cinema',
            'channelNumber': payload == 'fallback' ? 12 : '12',
          };
        }

        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Film A',
              channelDirectory: tvDirectory,
              showChannelName: true,
              channelName: 'Alpha',
              channelNumber: 7,
              httpHeaders: const {'Referer': 'p17'},
              requestChannelById: (id) {
                expect(id, 'b');
                return request();
              },
              requestNextChannel: request,
            ),
          );
          final g = await d.debrifyGuide();
          if (payload == 'open failure') {
            d.player.failures['open'] = StateError('open failed');
          }
          if (payload == 'pause failure') {
            d.player.failures['pause'] = StateError('pause failed');
          }
          final callStart = d.player.calls.length;
          if (next) {
            g.onClose();
            await d.f.advance(t);
            await d.nextChannel();
          } else {
            await d.byId(g, g.channels.last);
          }
          expect(requests, 1);
          expect(d.openAutoplay, everyElement(isTrue));
          expect(find.byType(ChannelGuide), findsNothing);
          final succeeds = [
            'primary',
            'fallback',
            'blank metadata',
            'pause failure',
          ].contains(payload);
          expect(
            d.player.state.playlist.medias.single.uri,
            succeeds
                ? 'https://player.test/b.mp4'
                : 'https://player.test/a.mp4',
          );
          if (succeeds) {
            expect(d.opens.last.httpHeaders, {'Referer': 'p17'});
            expect(d.player.state.track.subtitle.id, 'no');
            expect(
              d.player.calls.skip(callStart).map((c) => c.$1),
              containsAllInOrder(['pause', 'open', 'subtitle']),
            );
            final plate = t
                .widgetList<DebrifyTvBanner>(find.byType(DebrifyTvBanner))
                .first;
            expect(
              plate.channelName,
              payload == 'blank metadata'
                  ? (next ? 'Alpha' : 'Beta')
                  : 'Cinema',
            );
            expect(plate.channelNumber, 12);
          } else {
            expect(d.player.state.playing, isFalse);
            expect(d.player.calls.where((c) => c.$1 == 'play'), isEmpty);
            if (payload == 'empty' || payload == 'invalid types') {
              expect(
                t
                    .widget<TransitionOverlay>(find.byType(TransitionOverlay))
                    .tvStaticMessage,
                '⚠ CHANNEL HAS NO STREAMS',
              );
            } else {
              expect(
                t
                    .widget<TransitionOverlay>(find.byType(TransitionOverlay))
                    .tvStaticMessage,
                '⚠ CHANNEL SWITCH FAILED',
              );
            }
          }
          if (payload == 'throw') {
            expect(
              d.logs.any(
                (v) =>
                    v.contains('https://player.test/rejected?token=p17-fake'),
              ),
              isTrue,
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      });
    }
  }
  testWidgets('P17 missing by-id provider hides guide without pause', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'A',
          channelDirectory: tvDirectory,
          requestChannelById: (id) async => null,
        ),
      );
      final g = await d.debrifyGuide();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: d.f.navigator,
          theme: ThemeData.dark(),
          home: const VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            channelDirectory: tvDirectory,
          ),
        ),
      );
      await d.f.advance(t);
      final before = d.player.calls.length;
      await d.byId(g, g.channels.last);
      expect(
        d.player.calls.skip(before).where((c) => c.$1 == 'pause'),
        isEmpty,
      );
      expect(d.logs, contains('Player: requestChannelById not provided'));
      expect(find.byType(ChannelGuide), findsNothing);
    } finally {
      await d.close();
    }
  });
  for (final pair in ['next/next', 'next/by-id']) {
    testWidgets('P17 overlapping $pair older provider opens last', (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final held = Completer<Map<String, dynamic>?>();
      var calls = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            channelDirectory: tvDirectory,
            requestNextChannel: () => ++calls == 1
                ? held.future
                : Future.value({
                    'url': 'https://player.test/new.mp4',
                    'title': 'New',
                  }),
            requestChannelById: (id) async => {
              'url': 'https://player.test/new.mp4',
              'title': 'New',
            },
          ),
        );
        final g = await d.debrifyGuide();
        g.onClose();
        await d.f.advance(t);
        final old = d.beginNextChannel();
        await d.f.until(t, () => calls == 1);
        if (pair == 'next/next') {
          await d.nextChannel();
        } else {
          await d.byId(g, g.channels.last);
        }
        expect(d.opens.last.uri, 'https://player.test/new.mp4');
        held.complete({'url': 'https://player.test/old.mp4', 'title': 'Old'});
        await d.f.finish(t, old);
        expect(d.opens.map((m) => m.uri), [
          'https://player.test/a.mp4',
          'https://player.test/new.mp4',
          'https://player.test/old.mp4',
        ]);
      } finally {
        if (!held.isCompleted) {
          held.complete(null);
        }
        await d.close();
      }
    });
  }
  for (final random in [false, true]) {
    for (final byId in [false, true]) {
      testWidgets(
        'P17 start offset random=$random byId=$byId preserves next-only asymmetry',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'A',
                channelDirectory: tvDirectory,
                startFromRandom: random,
                randomStartMaxPercent: 50,
                startAtPercent: 0.25,
                requestNextChannel: () async => {
                  'url': 'https://player.test/b.mp4',
                },
                requestChannelById: (id) async => {
                  'url': 'https://player.test/b.mp4',
                },
              ),
            );
            final guide = await d.debrifyGuide();
            final before = d.seeks.length;
            if (byId) {
              await d.byId(guide, guide.channels.last);
            } else {
              guide.onClose();
              await d.f.advance(t);
              await d.nextChannel();
            }
            final seeks = d.seeks.skip(before).toList();
            if (byId) {
              expect(seeks, isEmpty);
            } else if (random) {
              expect(seeks, hasLength(1));
              expect(seeks.single.inMilliseconds, inInclusiveRange(1, 599999));
            } else {
              expect(seeks, [const Duration(minutes: 5)]);
            }
          } finally {
            await d.close();
          }
        },
      );
    }
  }

  testWidgets('P17 captured guide opener refuses an emptied public directory', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'A',
          channelDirectory: tvDirectory,
          requestChannelById: (id) async => null,
        ),
      );
      final opener = playerControls(t).onShowGuide!;
      final g = await d.debrifyGuide();
      g.channels.clear();
      g.onClose();
      await d.f.advance(t);
      opener();
      await d.f.advance(t);
      expect(find.byType(ChannelGuide), findsNothing);
      expect(d.logs, contains('Player: No channels available for guide'));
    } finally {
      await d.close();
    }
  });
  testWidgets(
    'P17 older Debrify failure paints failed static while a newer provider is still held',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final gates = [
        Completer<Map<String, dynamic>?>(),
        Completer<Map<String, dynamic>?>(),
      ];
      var calls = 0;
      Future<dynamic>? first;
      Future<dynamic>? second;
      var secondDone = false;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            requestNextChannel: () => gates[calls++].future,
          ),
        );
        first = d.beginNextChannel();
        await d.f.until(t, () => calls == 1);
        second = d.beginNextChannel();
        second.then<void>((_) => secondDone = true);
        await d.f.until(t, () => calls == 2);
        gates.first.complete(null);
        await d.f.finish(t, first);
        first = null;
        await d.f.advance(t);
        expect(secondDone, isFalse);
        expect(
          t
              .widget<TransitionOverlay>(find.byType(TransitionOverlay))
              .tvStaticMessage,
          '⚠ CHANNEL SWITCH FAILED',
        );
        gates.last.complete({
          'url': 'https://player.test/new.mp4',
          'title': 'New',
        });
        await d.f.finish(t, second);
        second = null;
        expect(d.opens.last.uri, 'https://player.test/new.mp4');
        expect(d.errors, isEmpty);
      } finally {
        for (final gate in gates) {
          if (!gate.isCompleted) {
            gate.complete(null);
          }
        }
        if (first != null) {
          await d.f.finish(t, first);
        }
        if (second != null) {
          await d.f.finish(t, second);
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'P17 captured next-channel callback silently returns after its provider is removed',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var requests = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            requestNextChannel: () async {
              requests++;
              return null;
            },
          ),
        );
        final dynamic next = playerControls(t).onNextChannel!;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: const VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'A',
              ),
            ),
          ),
        );
        final pauses = d.player.calls.where((c) => c.$1 == 'pause').length;
        final logs = d.logs.length;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        expect(d.f.players, hasLength(1));
        expect(requests, 0);
        expect(d.player.calls.where((c) => c.$1 == 'pause'), hasLength(pauses));
        expect(d.opens, hasLength(1));
        expect(
          d.logs.skip(logs).where((v) => v.contains('Player: Next channel')),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
