import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final action in [
    'tune with controls',
    'hide then timeout',
    'second raise',
  ]) {
    testWidgets(
      'P17 banner reentry $action retains one timer and the visible clock owner',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        var calls = 0;
        final floating = find.byWidgetPredicate(
          (w) => w is DebrifyTvBanner && !w.flush,
        );
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              showChannelName: true,
              channelName: 'Alpha',
              requestNextChannel: () async => {
                'url': 'https://player.test/b${++calls}.mp4',
                'channelName': 'Beta $calls',
              },
            ),
          );
          await d.f.advance(t, const Duration(seconds: 4));
          if (action == 'tune with controls') {
            await d.f.key(t, LogicalKeyboardKey.arrowUp);
            await d.nextChannel();
            expect(floating, findsNothing);
            expect(
              d.timers.where(
                (v) =>
                    v.stack.contains('armDebrifyBannerTimer') &&
                    v.timer.isActive,
              ),
              isEmpty,
            );
          } else {
            await d.nextChannel();
            expect(floating, findsOneWidget);
            final before = d.timers.lastWhere(
              (v) =>
                  v.stack.contains('armDebrifyBannerTimer') && v.timer.isActive,
            );
            if (action == 'second raise') {
              await d.nextChannel();
              expect(before.timer.isActive, isFalse);
              expect(
                d.timers.where(
                  (v) =>
                      v.stack.contains('armDebrifyBannerTimer') &&
                      v.timer.isActive,
                ),
                hasLength(1),
              );
            } else {
              await d.f.key(t, LogicalKeyboardKey.arrowUp);
              expect(floating, findsNothing);
              final clock =
                  playerControls(t).clock as PlaybackUiClockController;
              expect(clock.visible, isTrue);
              await d.f.advance(t, const Duration(seconds: 5));
              expect(clock.visible, isFalse);
              expect(floating, findsNothing);
            }
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
