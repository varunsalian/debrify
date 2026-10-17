import 'dart:async';
import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  testWidgets(
    'P17 guide before first ready exposes launch banner with hidden controls and disposes its timer',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      Timer? hide;
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'A',
                showChannelName: true,
                channelName: 'Alpha',
                channelDirectory: tvDirectory,
                requestChannelById: (id) async => null,
              ),
            ),
          ),
        );
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        await d.f.key(t, LogicalKeyboardKey.keyG);
        final guide = t.widget<ChannelGuide>(find.byType(ChannelGuide));
        expect(d.player.readyDelivered, isFalse);
        guide.onClose();
        await d.f.advance(t);
        d.observe(d.player.deliverReady);
        await d.f.advance(t);
        expect(
          find.byWidgetPredicate((w) => w is DebrifyTvBanner && !w.flush),
          findsOneWidget,
        );
        hide = d.timers
            .lastWhere((v) => v.stack.contains('armDebrifyBannerTimer'))
            .timer;
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        expect(hide.isActive, isTrue);
      } finally {
        await d.close();
        expect(hide?.isActive, isFalse);
        expect(d.errors, isEmpty);
      }
    },
  );
}
