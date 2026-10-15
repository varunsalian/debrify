import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'support/iptv_workflow_driver.dart';
import 'video_player_iptv_memory_test.dart' show iptvEpisode;

void main() {
  for (final tv in [false, true]) {
    for (final style in ['classic', 'ott']) {
      testWidgets(
        'P15 controls TV=$tv style=$style preserve zap guide Back callbacks and focus',
        (t) async {
          final d = IptvWorkflowDriver(t);
          await d.initialize();
          PlatformUtil.debugSetAndroidTvCached(tv);
          final channels = [iptvChannel(0), iptvChannel(1)];
          try {
            await d.f.finish(
              t,
              tv
                  ? PlayerAppearanceStorage.setTvPlayerControlsStyle(style)
                  : PlayerAppearanceStorage.setPlayerDockStyle(
                      style == 'ott' ? 'auto' : style,
                    ),
            );
            await d.mount(channels);
            if (tv) {
              final bar = t.widget<TvControls>(find.byType(TvControls));
              expect(bar.isLive, true);
              expect(bar.progressFocusable, false);
              expect(bar.onNext, isNotNull);
              expect(bar.onPrevious, isNotNull);
              bar.onNext!();
              await d.settle();
              expect(d.playingUrl, channels[1].url);
            } else {
              expect(playerControls(t).onNext, isNotNull);
              await d.zap(1);
            }
            // Both transport directions are independently callable.
            if (tv) {
              t.widget<TvControls>(find.byType(TvControls)).onPrevious!();
            } else {
              expect(playerControls(t).onPrevious, isNotNull);
              playerControls(t).onPrevious!();
            }
            await d.settle();
            expect(d.playingUrl, channels[0].url);
            if (tv) {
              t.widget<TvControls>(find.byType(TvControls)).onNext!();
            } else {
              playerControls(t).onNext!();
              expect(playerControls(t).hasNext, true);
              expect(playerControls(t).hasPrevious, true);
            }
            await d.settle();
            await d.f.key(t, LogicalKeyboardKey.keyG);
            expect(find.byType(IptvChannelSheet), findsOneWidget);
            final s = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
            expect(s.currentIndex, 1);
            await d.f.key(t, LogicalKeyboardKey.escape);
            await d.settle();
            expect(find.byType(IptvChannelSheet), findsNothing);
            await d.f.key(t, LogicalKeyboardKey.channelDown);
            await d.settle();
            expect(d.playingUrl, channels[0].url);
            for (final key in [
              LogicalKeyboardKey.channelUp,
              LogicalKeyboardKey.pageDown,
              LogicalKeyboardKey.pageUp,
              LogicalKeyboardKey.channelDown,
            ]) {
              final previous = d.playingUrl;
              await d.f.key(t, key);
              await d.settle();
              expect(d.playingUrl, isNot(previous));
            }
            await d.advance(const Duration(seconds: 3));
            for (final key in [
              LogicalKeyboardKey.arrowRight,
              LogicalKeyboardKey.arrowLeft,
            ]) {
              final previous = d.playingUrl;
              await d.f.key(t, key);
              await d.settle();
              expect(d.playingUrl, isNot(previous));
              await d.advance(const Duration(seconds: 3));
            }
            if (tv) {
              await d.f.key(t, LogicalKeyboardKey.arrowUp);
            } else {
              await d.f.key(t, LogicalKeyboardKey.keyC);
            }
            expect(find.byType(IptvChannelSheet), findsOneWidget);
            await d.f.key(t, LogicalKeyboardKey.escape);
            if (tv) {
              t
                  .widget<TvControls>(find.byType(TvControls))
                  .onShowIptvChannels!();
            } else {
              playerControls(t).onShowIptvChannels!();
            }
            await d.settle();
            expect(find.byType(IptvChannelSheet), findsOneWidget);
            final finalSheet = t.widget<IptvChannelSheet>(
              find.byType(IptvChannelSheet),
            );
            finalSheet.onClose();
            await d.settle();
            expect(find.byType(IptvChannelSheet), findsNothing);
            expect(d.calls('seek'), isEmpty);
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
            PlatformUtil.debugSetAndroidTvCached(false);
          }
        },
      );
    }
  }
  testWidgets(
    'P15 TV Start Over timeline focuses the progress row and Back dismisses guide first',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      final live = iptvChannel(
        0,
        url: 'https://p15-tv-start.test/live/u/p/123.ts',
        attributes: {'tv_archive': '1'},
      );
      d.response = iptvPanelReply;
      try {
        await d.mount([live]);
        await d.f.until(
          t,
          () =>
              t.widget<TvControls>(find.byType(TvControls)).onLiveEdgeAction !=
              null,
        );
        t.widget<TvControls>(find.byType(TvControls)).onLiveEdgeAction!();
        await d.f.until(
          t,
          () => t
              .widget<TvControls>(find.byType(TvControls))
              .liveEdgeActionActive,
        );
        await d.f.key(t, LogicalKeyboardKey.arrowDown);
        t
            .widget<TvControls>(find.byType(TvControls))
            .onToggleStartOverTimeline!();
        await d.settle();
        final bar = t.widget<TvControls>(find.byType(TvControls));
        expect(bar.startOverTimelineVisible, true);
        expect(bar.progressFocusable, true);
        expect(bar.progressFocusNode.hasFocus, true);
        bar.onShowIptvChannels!();
        await d.settle();
        await d.f.key(t, LogicalKeyboardKey.escape);
        expect(find.byType(IptvChannelSheet), findsNothing);
        expect(find.byType(VideoPlayerScreen), findsOneWidget);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  for (final tv in [false, true]) {
    testWidgets('P15 series Next Previous and EOF use the owner on TV=$tv', (
      t,
    ) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(tv);
      final a = [iptvEpisode(1), iptvEpisode(2), iptvEpisode(3)];
      try {
        await d.mount(a);
        if (tv) {
          t.widget<TvControls>(find.byType(TvControls)).onNext!();
        } else {
          playerControls(t).onNext!();
        }
        await d.settle();
        expect(d.playingUrl, a[1].url);
        if (tv) {
          t.widget<TvControls>(find.byType(TvControls)).onPrevious!();
        } else {
          playerControls(t).onPrevious!();
        }
        await d.settle();
        expect(d.playingUrl, a[0].url);
        d.player.emit('completed', true);
        await d.settle();
        expect(d.playingUrl, a[1].url);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    });
  }
  testWidgets(
    'P15 TV transition arrows supersede a held pause while the older direct open still wins later',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      final gate = Completer<void>();
      var entered = false;
      final a = [iptvChannel(0), iptvChannel(1)];
      try {
        await d.mount(a);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        final sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        d.player.heldOperation = (n, v) => n == 'pause' && !entered;
        d.player.beforeOperation = (n, v) async {
          if (n == 'pause' && !entered) {
            entered = true;
            await gate.future;
          }
        };
        final pending = d.observe(() => sheet.onChannelSelected(a, 1));
        await d.f.until(t, () => entered);
        await d.f.key(t, LogicalKeyboardKey.arrowRight);
        await d.settle();
        expect(d.playingUrl, a[0].url);
        expect(d.opened.length, 2);
        gate.complete();
        await d.f.finish(t, pending);
        await d.settle();
        expect(d.playingUrl, a[1].url);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        final after = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        expect(after.currentIndex, 0);
        expect(d.calls('seek'), isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'P15 non-live TV arrows retain held-key scrub ownership outside the live zap branch',
    (t) async {
      final d = IptvWorkflowDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      try {
        await d.mount([iptvEpisode(1)]);
        await d.advance(const Duration(seconds: 6));
        for (var i = 0; i < 3; i++) {
          await d.f.key(t, LogicalKeyboardKey.arrowRight);
        }
        expect(
          t.widget<TvControls>(find.byType(TvControls)).scrubPreview,
          isNotNull,
        );
        expect(d.calls('seek').length, 2);
        await d.f.key(t, LogicalKeyboardKey.select);
        expect(
          t.widget<TvControls>(find.byType(TvControls)).scrubPreview,
          isNull,
        );
        expect(d.calls('seek').length, 3);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
