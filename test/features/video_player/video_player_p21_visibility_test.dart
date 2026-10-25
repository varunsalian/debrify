import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/widgets/debrify_tv_banner.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _tick = Duration(seconds: 1);

Finder get _floatingZap =>
    find.byWidgetPredicate((w) => w is IptvZapBanner && !w.flush);
Finder get _dockZap =>
    find.byWidgetPredicate((w) => w is IptvZapBanner && w.flush);
Finder get _floatingDebrify =>
    find.byWidgetPredicate((w) => w is DebrifyTvBanner && !w.flush);

PlaybackUiClockController _clock(P21Driver d) =>
    (d.tv ? d.bar.clock : d.controls.clock) as PlaybackUiClockController;

/// The visibility listener (`_onControlsVisibilityChanged`), pinned through
/// every observable it drives: the playback clock, both floating banners,
/// the IPTV banner ticker and the television focus hand-back.
void main() {
  p21Timeouts();

  for (final tv in [false, true]) {
    testWidgets(
      'P21 ${tv ? 'TV' : 'desktop'} the playback clock runs exactly while the controls are up',
      (t) async {
        final d = P21Driver(t, tv: tv);
        await d.initialize();
        try {
          await d.mount(screen: P21Driver.screen());
          expect(_clock(d).visible, isTrue);
          await d.wait(4000);
          expect(d.barUp, isFalse);
          expect(_clock(d).visible, isFalse);
          await d.at(const Duration(seconds: 500));
          expect(_clock(d).value.position, isNot(const Duration(seconds: 500)));
          if (tv) {
            await d.key(LogicalKeyboardKey.arrowDown);
          } else {
            await d.hover();
          }
          expect(_clock(d).visible, isTrue);
          // Raising publishes the current position at once.
          expect(_clock(d).value.position, const Duration(seconds: 500));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 raising the controls drops a floating Debrify TV banner at once',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://p21.test/a.mp4',
            title: 'Film A',
            showChannelName: true,
            channelName: 'Alpha',
            channelNumber: 7,
            requestNextChannel: () async => {
              'url': 'https://p21.test/b.mp4',
              'title': 'Film B',
              'channelName': 'Beta',
              'channelNumber': 9,
            },
          ),
        );
        await d.wait(4000);
        await d.f.finish(t, d.beginNextChannel());
        await d.wait(500);
        expect(_floatingDebrify, findsOneWidget);
        expect(d.barUp, isFalse);
        await d.hover();
        // Same frame: no fade-out of a second copy of the panel.
        expect(_floatingDebrify, findsNothing);
        expect(_clock(d).visible, isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 raising the controls drops a floating IPTV zap banner at once and runs the dock ticker',
    (t) async {
      final channels = [P21Driver.channel(0), P21Driver.channel(1)];
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: P21Driver.iptv(channels),
          settleInitialization: false,
        );
        // The launch banner floats for its own window, then fades out.
        for (var i = 0; i < 5; i++) {
          await d.wait(1000);
        }
        expect(_floatingZap, findsNothing);
        expect(d.activePeriodic(_tick), 0);
        d.observe(d.controls.onNext!);
        await d.wait(500);
        expect(_floatingZap, findsOneWidget);
        expect(d.activePeriodic(_tick), 1, reason: 'the floating banner ticks');
        await d.hover();
        expect(_floatingZap, findsNothing);
        expect(_dockZap, findsOneWidget);
        expect(d.activePeriodic(_tick), 1, reason: 'the dock banner ticks');
        // Lowered with no floating banner left: the ticker stops.
        await d.wait(3100);
        expect(d.barUp, isFalse);
        expect(d.activePeriodic(_tick), 0);
        await d.hover();
        expect(d.activePeriodic(_tick), 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a bar lowered by a tap hands its focus back to the root',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(d.focused, 'tvPlayPause');
        await d.observe(() => t.tapAt(const Offset(150, 400)));
        await d.wait(320);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a bar lowered while focus is outside it leaves focus where it is',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        // Focus leaves the bar's scope for the route's.
        d.bar.scopeNode.unfocus();
        await d.wait(0);
        final elsewhere = d.focused;
        expect(elsewhere, isNot('tvPlayPause'));
        expect(elsewhere, isNot('tvPlayerRoot'));
        await d.observe(() => t.tapAt(const Offset(150, 400)));
        await d.wait(320);
        expect(d.barUp, isFalse);
        expect(d.focused, elsewhere);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV an inactivity hide reclaims the root even when focus had left the bar',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        d.bar.scopeNode.unfocus();
        await d.wait(0);
        expect(d.focused, isNot('tvPlayerRoot'));
        await d.wait(3100);
        expect(d.barUp, isFalse);
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
