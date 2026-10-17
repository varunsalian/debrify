import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 controls cancel the owned banner timer before automatic hiding can reveal it again',
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
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('armDebrifyBannerTimer') && v.timer.isActive,
          ),
          hasLength(1),
        );
        await d.f.key(t, LogicalKeyboardKey.arrowUp);
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('armDebrifyBannerTimer') && v.timer.isActive,
          ),
          isEmpty,
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 controls alone drive the shared clock visibility without a channel banner',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
          ),
        );
        await d.f.advance(t, const Duration(seconds: 4));
        final clock = playerControls(t).clock as PlaybackUiClockController;
        await d.f.key(t, LogicalKeyboardKey.arrowUp);
        expect(clock.visible, isTrue);
        await d.f.advance(t, const Duration(seconds: 4));
        expect(clock.visible, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 Debrify guide hides the live IPTV banner and cannot raise an owned Debrify timer',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/live.ts',
            title: 'Live',
            iptvChannels: [
              IptvChannel(
                name: 'Live',
                url: 'https://player.test/live.ts',
                contentType: 'live',
              ),
            ],
            showChannelName: true,
            channelName: 'Alpha',
            channelDirectory: tvDirectory,
            requestChannelById: (id) async => {
              'url': 'https://player.test/b.mp4',
              'channelName': 'Beta',
            },
          ),
        );
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('raiseIptvZapBanner') &&
                v.duration == const Duration(milliseconds: 4500) &&
                v.timer.isActive,
          ),
          hasLength(1),
        );
        final guide = await d.debrifyGuide();
        expect(
          d.timers.where(
            (v) => v.stack.contains('raiseIptvZapBanner') && v.timer.isActive,
          ),
          isEmpty,
        );
        await d.byId(guide, guide.channels.last);
        expect(find.byType(DebrifyTvBanner), findsNothing);
        expect(
          d.timers.where(
            (v) =>
                v.stack.contains('armDebrifyBannerTimer') && v.timer.isActive,
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
