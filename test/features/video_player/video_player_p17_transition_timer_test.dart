import 'dart:async';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'support/player_actions.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['next', 'by id', 'Stremio']) {
    testWidgets(
      'P17 $route channel transition hides the outgoing texture before held pause and restores it after open',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final pause = Completer<void>();
        var entered = false;
        Future<dynamic>? task;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: route == 'by id' ? tvDirectory : null,
              requestChannelById: route == 'by id'
                  ? (id) async => {'url': 'https://player.test/b.mp4'}
                  : null,
              requestNextChannel: route == 'next'
                  ? () async => {'url': 'https://player.test/b.mp4'}
                  : null,
              stremioTvChannels: route == 'Stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: route == 'Stremio'
                  ? (id) async => null
                  : null,
            ),
          );
          expect(find.byType(mkv.Video), findsOneWidget);
          final dynamic guide = route == 'by id'
              ? await d.debrifyGuide()
              : route == 'Stremio'
              ? await d.stremioGuide()
              : null;
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
                      final dynamic action = playerControls(t).onNextChannel!;
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
          await d.f.advance(
            t,
          ); // Render queued setState while native pause stays held.
          expect(find.byType(mkv.Video), findsNothing);
          expect(find.byType(TransitionOverlay), findsOneWidget);
          expect(d.opens, hasLength(1));
          pause.complete();
          await d.f.finish(t, task);
          await d.f.advance(t);
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          expect(find.byType(mkv.Video), findsOneWidget);
          expect(d.errors, isEmpty);
        } finally {
          if (!pause.isCompleted) pause.complete();
          if (task != null) await d.f.finish(t, task);
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P17 Stremio switch replaces playback timers with its full 1500ms stop and retires the running flag',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        final guide = await d.stremioGuide();
        final before = d.timers.length;
        await d.stremioPick(guide, 'b');
        expect(find.byType(TransitionOverlay), findsOneWidget);
        final animation = t
            .widget<TransitionOverlay>(find.byType(TransitionOverlay))
            .rainbowController;
        expect(animation.isAnimating, isTrue);
        expect(find.byType(mkv.Video), findsOneWidget);
        final created = d.timers.skip(before).toList();
        final phase = created.where(
          (v) =>
              v.stack.contains('bindPlayerInstanceSubscriptions') &&
              v.duration == const Duration(milliseconds: 1500),
        );
        final playbackStop = created.where(
          (v) =>
              v.stack.contains('bindPlayerInstanceSubscriptions') &&
              v.duration == const Duration(seconds: 3),
        );
        expect(phase, hasLength(1));
        expect(playbackStop, hasLength(1));
        expect(phase.single.timer.isActive, isFalse);
        expect(playbackStop.single.timer.isActive, isFalse);
        final stop = created
            .where(
              (v) =>
                  v.stack.contains('switchToStremioTvChannel') &&
                  v.duration == const Duration(milliseconds: 1500) &&
                  v.timer.isActive,
            )
            .toList();
        expect(stop, hasLength(1));
        final remaining = stop.single.at
            .add(stop.single.duration)
            .difference(t.binding.clock.now());
        await d.f.advance(t, remaining - const Duration(milliseconds: 1));
        expect(find.byType(TransitionOverlay), findsOneWidget);
        expect(animation.isAnimating, isTrue);
        await d.f.advance(t, const Duration(milliseconds: 1));
        expect(find.byType(TransitionOverlay), findsNothing);
        expect(animation.isAnimating, isFalse);
        final settled = d.timers.length;
        d.player.emit('playing', true);
        await d.f.advance(t);
        expect(
          d.timers
              .skip(settled)
              .where(
                (v) =>
                    v.stack.contains('bindPlayerInstanceSubscriptions') &&
                    (v.duration == const Duration(milliseconds: 1500) ||
                        v.duration == const Duration(seconds: 3)),
              ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
