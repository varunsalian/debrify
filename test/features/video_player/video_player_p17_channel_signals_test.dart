import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';
import 'support/player_actions.dart';

void main() {
  for (final route in ['next', 'by id']) {
    testWidgets(
      'P17 $route publishes acquired signal and uppercase subtext before held open',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final open = Completer<void>();
        var entered = false;
        Future<dynamic>? task;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: tvDirectory,
              requestChannelById: (id) async => {
                'url': 'https://player.test/b.mp4',
                'title': 'Film B',
              },
              requestNextChannel: () async => {
                'url': 'https://player.test/b.mp4',
                'title': 'Film B',
              },
            ),
          );
          final guide = await d.debrifyGuide();
          d.player.beforeOperation = (name, value) async {
            if (name == 'open' && !entered) {
              entered = true;
              await open.future;
            }
          };
          d.player.heldOperation = (name, value) =>
              name == 'open' && !open.isCompleted;
          if (route == 'next') {
            guide.onClose();
            await d.f.advance(t);
            task = d.beginNextChannel();
          } else {
            final dynamic select = guide.onChannelSelected;
            task =
                d.observe<dynamic>(() => select(guide.channels.last))
                    as Future<dynamic>;
          }
          await d.f.until(t, () => entered);
          await d.f.advance(t);
          final overlay = t.widget<TransitionOverlay>(
            find.byType(TransitionOverlay),
          );
          expect(overlay.tvStaticMessage, '📺 SIGNAL ACQUIRED');
          expect(overlay.tvStaticSubtext, '▶ FILM B');
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/a.mp4',
          );
          open.complete();
          await d.f.finish(t, task);
          expect(
            d.player.state.playlist.medias.single.uri,
            'https://player.test/b.mp4',
          );
          expect(d.errors, isEmpty);
        } finally {
          if (!open.isCompleted) open.complete();
          if (task != null) await d.f.finish(t, task);
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 removed by-id provider closes the guide and retains its exact diagnostic',
    (t) async {
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
        final guide = await d.debrifyGuide();
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
        await d.byId(guide, guide.channels.last);
        expect(find.byType(ChannelGuide), findsNothing);
        expect(
          d.player.calls
              .skip(before)
              .where((c) => c.$1 == 'pause' || c.$1 == 'open'),
          isEmpty,
        );
        expect(d.logs, contains('Player: requestChannelById not provided'));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 Stremio next publishes distinct now and next guide maps with shallow values',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final nested = <Object>['shared'];
      final now = <String, dynamic>{'title': 'Now', 'nested': nested};
      final next = <String, dynamic>{'title': 'Next', 'nested': nested};
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvCurrentChannelId: 'a',
            stremioTvChannelSwitchProvider: (id) async => null,
            stremioTvNextProvider: (id) async => {
              'channelId': 'b',
              'url': 'https://player.test/b.mp4',
              'title': 'B',
              'nowPlaying': now,
              'nextUp': next,
            },
          ),
        );
        final dynamic action = playerControls(t).onNext!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => action()));
        final guide = await d.stremioGuide();
        expect(guide.currentChannelId, 'b');
        expect(guide.channels.last['nowPlaying'], now);
        expect(guide.channels.last['nextUp'], next);
        final copiedNow = guide.channels.last['nowPlaying'] as Map;
        final copiedNext = guide.channels.last['nextUp'] as Map;
        expect(identical(copiedNow, now), isFalse);
        expect(identical(copiedNext, next), isFalse);
        expect(identical(copiedNow['nested'], nested), isTrue);
        expect(identical(copiedNext['nested'], nested), isTrue);
        expect(
          d.player.state.playlist.medias.single.uri,
          'https://player.test/b.mp4',
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
