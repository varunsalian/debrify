import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';
import 'support/player_actions.dart';

void main() {
  for (final kind in ['unnumbered', 'numbered', 'payload override']) {
    final numbered = kind != 'unnumbered';
    final overridden = kind == 'payload override';
    testWidgets(
      'P17 failed by-id selection retains selected identity kind=$kind while old media stays paused',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final directory = <Map<String, dynamic>>[
          {'id': 'a', 'name': 'Alpha', 'channelNumber': 7, 'isCurrent': true},
          {'id': 'b', 'name': 'Beta', if (numbered) 'channelNumber': 9},
        ];
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: directory,
              requestChannelById: (id) async => overridden
                  ? {
                      'url': '',
                      'channelId': 'reported',
                      'channelName': 'Reported',
                      'channelNumber': '12',
                    }
                  : null,
              showChannelName: true,
              channelName: 'Alpha',
              channelNumber: 7,
            ),
          );
          final guide = await d.debrifyGuide();
          await d.byId(guide, guide.channels.last);
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/a.mp4',
          );
          expect(d.player.state.playing, isFalse);
          expect(find.byType(mkv.Video), findsOneWidget);
          final again = await d.debrifyGuide();
          expect(again.currentChannelId, overridden ? 'reported' : 'b');
          expect(
            again.currentChannelNumber,
            overridden
                ? 12
                : numbered
                ? 9
                : 7,
          );
          again.onClose();
          await d.f.advance(t);
          expect(find.byType(DebrifyTvBanner), findsWidgets);
          final plates = t.widgetList<DebrifyTvBanner>(
            find.byType(DebrifyTvBanner),
          );
          expect(
            plates.map((p) => p.channelName),
            everyElement(overridden ? 'Reported' : 'Beta'),
          );
          expect(
            plates.map((p) => p.channelNumber),
            everyElement(
              overridden
                  ? 12
                  : numbered
                  ? 9
                  : 7,
            ),
          );
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  for (final route in ['next', 'by id']) {
    for (final failure in ['null', 'empty', 'open']) {
      testWidgets(
        'P17 older $route $failure failure clears newer acquired subtext while its open is held',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          final oldPayload = Completer<Map<String, dynamic>?>();
          final newOpen = Completer<void>();
          var oldEntered = false;
          var openEntered = false;
          var nextCalls = 0;
          Future<dynamic>? oldTask;
          Future<dynamic>? newTask;
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'A',
                requestMagicNext: () async => null,
                channelDirectory: tvDirectory,
                requestChannelById: (id) {
                  oldEntered = true;
                  return oldPayload.future;
                },
                requestNextChannel: () {
                  if (route == 'next' && nextCalls++ == 0) {
                    oldEntered = true;
                    return oldPayload.future;
                  }
                  return Future.value({
                    'url': 'https://player.test/new.mp4',
                    'title': 'Newer',
                  });
                },
              ),
            );
            final guide = await d.debrifyGuide();
            if (route == 'next') {
              guide.onClose();
              await d.f.advance(t);
              oldTask = d.beginNextChannel();
            } else {
              final dynamic pick = guide.onChannelSelected;
              oldTask =
                  d.observe<dynamic>(() => pick(guide.channels.last))
                      as Future<dynamic>;
            }
            await d.f.until(t, () => oldEntered);
            d.player.beforeOperation = (name, value) async {
              if (name == 'open' && !openEntered) {
                openEntered = true;
                await newOpen.future;
              }
            };
            d.player.heldOperation = (name, value) =>
                name == 'open' && !newOpen.isCompleted;
            newTask = d.beginNextChannel();
            await d.f.until(t, () => openEntered);
            await d.f.advance(t);
            expect(
              t
                  .widget<TransitionOverlay>(find.byType(TransitionOverlay))
                  .tvStaticSubtext,
              '▶ NEWER',
            );
            if (failure == 'open') {
              d.player.failures['open'] = StateError(
                'older channel open failed',
              );
            }
            oldPayload.complete(
              failure == 'null'
                  ? null
                  : failure == 'open'
                  ? {'url': 'https://player.test/old.mp4', 'title': 'Older'}
                  : {'url': ''},
            );
            await d.f.finish(t, oldTask);
            await d.f.advance(t);
            final overlay = t.widget<TransitionOverlay>(
              find.byType(TransitionOverlay),
            );
            expect(
              overlay.tvStaticMessage,
              failure != 'empty'
                  ? '⚠ CHANNEL SWITCH FAILED'
                  : '⚠ CHANNEL HAS NO STREAMS',
            );
            expect(overlay.tvStaticSubtext, '');
            expect(playerControls(t).title, 'A');
            expect(
              d.player.state.playlist.medias.single.uri,
              'https://player.test/a.mp4',
            );
            newOpen.complete();
            await d.f.finish(t, newTask);
            expect(
              d.player.state.playlist.medias.single.uri,
              'https://player.test/new.mp4',
            );
            expect(d.errors, isEmpty);
          } finally {
            if (!oldPayload.isCompleted) oldPayload.complete(null);
            if (!newOpen.isCompleted) newOpen.complete();
            if (oldTask != null) await d.f.finish(t, oldTask);
            if (newTask != null) await d.f.finish(t, newTask);
            await d.close();
          }
        },
      );
    }
  }
  testWidgets(
    'P17 by-id no-stream payload raises a fresh floating identity after the launch banner expired',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final floating = find.byWidgetPredicate(
        (w) => w is DebrifyTvBanner && !w.flush,
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            channelDirectory: tvDirectory,
            showChannelName: true,
            channelName: 'Alpha',
            requestChannelById: (id) async => {
              'url': '',
              'channelName': 'Beta',
              'channelNumber': 9,
            },
          ),
        );
        await d.f.advance(t, const Duration(seconds: 5));
        expect(floating, findsNothing);
        final guide = await d.debrifyGuide();
        await d.byId(guide, guide.channels.last);
        expect(floating, findsOneWidget);
        expect(t.widget<DebrifyTvBanner>(floating).channelName, 'Beta');
        expect(t.widget<DebrifyTvBanner>(floating).channelNumber, 9);
        expect(d.player.state.playing, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
