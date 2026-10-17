import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'by id', 'Stremio']) {
    testWidgets(
      'P17 $route prelude clears live buffering and TV scrub preview before its held pause',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final pause = Completer<void>();
        var entered = false;
        var requests = 0;
        Future<dynamic>? task;
        TvControls controls() => t.widget<TvControls>(find.byType(TvControls));
        double opacity() => t
            .widget<AnimatedOpacity>(
              find
                  .ancestor(
                    of: find.byType(BufferingIndicator),
                    matching: find.byType(AnimatedOpacity),
                  )
                  .first,
            )
            .opacity;
        try {
          PlatformUtil.debugSetAndroidTvCached(true);
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              requestNextChannel: route == 'next'
                  ? () async {
                      requests++;
                      return {'url': 'https://player.test/b.mp4'};
                    }
                  : null,
              channelDirectory: route == 'by id' ? tvDirectory : null,
              requestChannelById: route == 'by id'
                  ? (id) async {
                      requests++;
                      return {'url': 'https://player.test/b.mp4'};
                    }
                  : null,
              stremioTvChannels: route == 'Stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: route == 'Stremio'
                  ? (id) async => null
                  : null,
            ),
          );
          dynamic guide;
          if (route != 'next') {
            controls().onShowGuide!();
            await d.f.advance(t);
            guide = route == 'by id'
                ? t.widget<ChannelGuide>(find.byType(ChannelGuide))
                : t.widget<StremioTvGuideSheet>(
                    find.byType(StremioTvGuideSheet),
                  );
            guide.onClose();
            await d.f.advance(t);
          }
          await d.f.advance(t, const Duration(seconds: 4));
          t
              .widget<Focus>(
                find.byWidgetPredicate(
                  (w) =>
                      w is Focus && w.focusNode?.debugLabel == 'tvPlayerRoot',
                ),
              )
              .focusNode!
              .requestFocus();
          await d.f.advance(t);
          await t.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          await d.f.advance(t, const Duration(milliseconds: 50));
          await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          await d.f.advance(t, const Duration(milliseconds: 50));
          await t.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
          await d.f.advance(t, const Duration(milliseconds: 50));
          await t.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
          await d.f.advance(t);
          expect(controls().scrubPreview, isNotNull);
          d.player.state = d.player.state.copyWith(buffering: true);
          d.player.emit('buffering', true);
          await d.f.advance(
            t,
            VideoPlayerTimingConstants.bufferingDebounceDelay +
                const Duration(milliseconds: 1),
          );
          expect(opacity(), 1);
          d.player.beforeOperation = (name, value) async {
            if (name == 'pause' && !entered) {
              entered = true;
              await pause.future;
            }
          };
          d.player.heldOperation = (name, value) =>
              name == 'pause' && !pause.isCompleted;
          task =
              d.observe<dynamic>(() {
                    if (route == 'next') {
                      final dynamic action = controls().onNextChannel!;
                      return action();
                    }
                    if (route == 'by id') {
                      final dynamic action = guide.onChannelSelected;
                      return action(guide.channels.last);
                    }
                    final dynamic action = guide.onChannelSwitched;
                    return action('b', 'https://player.test/b.mp4', 'B');
                  })
                  as Future<dynamic>;
          await d.f.until(t, () => entered);
          await d.f.advance(t);
          expect(controls().scrubPreview, isNull);
          expect(controls().isTransitioning, isTrue);
          expect(opacity(), 0);
          expect(find.byType(TransitionOverlay), findsOneWidget);
          expect(
            t
                .widget<TransitionOverlay>(find.byType(TransitionOverlay))
                .rainbowController
                .isAnimating,
            isTrue,
          );
          if (route == 'Stremio')
            expect(find.byType(StremioTvGuideSheet), findsNothing);
          expect(requests, 0);
          expect(d.opens, hasLength(1));
          pause.complete();
          await d.f.finish(t, task);
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          expect(d.errors, isEmpty);
        } finally {
          if (!pause.isCompleted) pause.complete();
          if (task != null) await d.f.finish(t, task);
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
