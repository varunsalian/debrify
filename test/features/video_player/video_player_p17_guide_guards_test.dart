import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final kind in ['Debrify', 'Stremio']) {
    testWidgets(
      'P17 $kind guide hides the clock and closes without revealing controls',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: kind == 'Debrify' ? tvDirectory : null,
              requestChannelById: kind == 'Debrify' ? (id) async => null : null,
              stremioTvChannels: kind == 'Stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: kind == 'Stremio'
                  ? (id) async => null
                  : null,
            ),
          );
          await d.f.key(t, LogicalKeyboardKey.arrowDown);
          final clock = playerControls(t).clock as PlaybackUiClockController;
          expect(clock.visible, isTrue);
          final dynamic guide = kind == 'Debrify'
              ? await d.debrifyGuide()
              : await d.stremioGuide();
          expect(clock.visible, isFalse);
          guide.onClose();
          await d.f.advance(t);
          expect(clock.visible, isFalse);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 an emptied published guide refuses reopening without hiding controls or their clock',
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
        final opener = playerControls(t).onShowGuide!;
        final guide = await d.debrifyGuide();
        // ChannelGuide receives this same mutable legacy list. The retained
        // callback must still apply its empty-list guard when invoked again.
        guide.channels.clear();
        guide.onClose();
        await d.f.advance(t);
        await d.f.key(t, LogicalKeyboardKey.arrowDown);
        final clock = playerControls(t).clock as PlaybackUiClockController;
        expect(clock.visible, isTrue);
        opener();
        await d.f.advance(t);
        expect(find.byType(ChannelGuide), findsNothing);
        expect(clock.visible, isTrue);
        expect(d.logs, contains('Player: No channels available for guide'));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
