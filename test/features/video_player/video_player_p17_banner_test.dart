import 'dart:async';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

Finder floating() =>
    find.byWidgetPredicate((w) => w is DebrifyTvBanner && !w.flush);
double opacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .ancestor(of: floating(), matching: find.byType(AnimatedOpacity))
          .first,
    )
    .opacity;

void main() {
  for (final hideSeekbar in [false, true]) {
    testWidgets(
      'P17 banner resolve polling full window and clock hideSeekbar=$hideSeekbar',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final held = Completer<void>();
        var entered = false;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Film A',
              showChannelName: true,
              channelName: 'Alpha',
              channelNumber: 7,
              hideSeekbar: hideSeekbar,
              requestNextChannel: () async => {
                'url': 'https://player.test/b.mp4',
                'title': 'Film B',
                'channelName': 'Beta',
                'channelNumber': 9,
              },
            ),
          );
          await d.f.advance(t, const Duration(seconds: 4));
          d.player.beforeOperation = (name, value) async {
            if (name == 'open' && !entered) {
              entered = true;
              await held.future;
            }
          };
          d.player.heldOperation = (name, value) =>
              name == 'open' && !held.isCompleted;
          final work = d.beginNextChannel();
          await d.f.until(t, () => entered);
          expect(floating(), findsOneWidget);
          expect(opacity(t), 1);
          final poll = d.timers
              .where(
                (v) =>
                    v.stack.contains('armDebrifyBannerTimer') &&
                    v.timer.isActive,
              )
              .toList();
          expect(poll, hasLength(1));
          expect(poll.single.duration, const Duration(milliseconds: 400));
          final b = t.widget<DebrifyTvBanner>(floating());
          expect(b.showProgress, !hideSeekbar);
          expect((b.clock as PlaybackUiClockController).visible, !hideSeekbar);
          await d.f.advance(t, const Duration(seconds: 5));
          expect(opacity(t), 1);
          held.complete();
          await d.f.finish(t, work);
          await d.f.advance(t, const Duration(milliseconds: 401));
          expect(opacity(t), 1);
          expect(
            d.timers.where(
              (v) =>
                  v.stack.contains('armDebrifyBannerTimer') &&
                  v.duration == const Duration(seconds: 4) &&
                  v.timer.isActive,
            ),
            hasLength(1),
          );
          final full = d.timers.lastWhere(
            (v) =>
                v.stack.contains('armDebrifyBannerTimer') &&
                v.duration == const Duration(seconds: 4) &&
                v.timer.isActive,
          );
          final remaining = full.at
              .add(full.duration)
              .difference(t.binding.clock.now());
          await d.f.advance(t, remaining - const Duration(milliseconds: 1));
          expect(opacity(t), 1);
          await d.f.advance(t, const Duration(milliseconds: 2));
          expect(opacity(t), 0);
          expect((b.clock as PlaybackUiClockController).visible, isFalse);
          await d.f.advance(t, const Duration(milliseconds: 351));
          expect(floating(), findsNothing);
        } finally {
          if (!held.isCompleted) {
            held.complete();
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 controls hide floating banner immediately and clock follows controls',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            showChannelName: true,
            channelName: 'Alpha',
            requestNextChannel: () async => {
              'url': 'https://player.test/b.mp4',
              'channelName': 'Beta',
            },
          ),
        );
        await d.f.advance(t, const Duration(seconds: 4));
        await d.nextChannel();
        expect(floating(), findsOneWidget);
        final b = t.widget<DebrifyTvBanner>(floating());
        await d.f.key(t, LogicalKeyboardKey.arrowUp);
        expect(floating(), findsNothing);
        expect((b.clock as PlaybackUiClockController).visible, isTrue);
      } finally {
        await d.close();
      }
    },
  );
  for (final owned in [true, false]) {
    testWidgets('P17 banner ownership gate showChannelName=$owned', (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            showChannelName: owned,
            channelName: 'Alpha',
            requestNextChannel: () async => {
              'url': 'https://player.test/b.mp4',
              'channelName': 'Beta',
            },
          ),
        );
        await d.f.advance(t, const Duration(seconds: 4));
        await d.nextChannel();
        expect(floating(), owned ? findsOneWidget : findsNothing);
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('armDebrifyBannerTimer') && v.timer.isActive,
          ),
          hasLength(owned ? 1 : 0),
        );
      } finally {
        await d.close();
      }
    });
  }
  testWidgets(
    'P17 banner full-window timer notices a newer transition without a second raise',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var calls = 0;
      final held = Completer<Map<String, dynamic>?>();
      Future<dynamic>? second;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            showChannelName: true,
            channelName: 'Alpha',
            requestNextChannel: () => ++calls == 1
                ? Future.value({
                    'url': 'https://player.test/first.mp4',
                    'channelName': 'Beta',
                  })
                : held.future,
          ),
        );
        await d.f.advance(t, const Duration(seconds: 4));
        await d.nextChannel();
        await d.f.advance(t, const Duration(milliseconds: 401));
        final full = d.timers.lastWhere(
          (v) =>
              v.stack.contains('armDebrifyBannerTimer') &&
              v.duration == const Duration(seconds: 4) &&
              v.timer.isActive,
        );
        await d.f.advance(t, const Duration(seconds: 2));
        second = d.beginNextChannel();
        await d.f.until(t, () => calls == 2);
        await d.f.advance(
          t,
          full.at.add(full.duration).difference(t.binding.clock.now()) +
              const Duration(milliseconds: 1),
        );
        expect(opacity(t), 1);
        expect(full.timer.isActive, isFalse);
        expect(
          d.timers
              .where(
                (v) =>
                    v.stack.contains('armDebrifyBannerTimer') &&
                    v.timer.isActive,
              )
              .single
              .duration,
          const Duration(milliseconds: 400),
        );
        held.complete({'url': 'https://player.test/second.mp4'});
        await d.f.finish(t, second);
        second = null;
        await d.f.advance(t, const Duration(milliseconds: 401));
        expect(opacity(t), 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!held.isCompleted) {
          held.complete(null);
        }
        if (second != null) {
          await d.f.finish(t, second);
        }
        await d.close();
      }
    },
  );
}
