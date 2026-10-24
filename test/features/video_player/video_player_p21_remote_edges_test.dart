import 'dart:async';

import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';
import 'support/tv_episode_driver.dart' show tvDirectory;

const _right = LogicalKeyboardKey.arrowRight;

/// Phase 21 Step 0b: remote edges: the hold window between quick and slow
/// presses, the remote before the first ready, and a scrub confirm whose
/// seek has not completed yet.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 TV presses about 300 ms apart are a hold, so the third enters the scrub',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        // Each gap is measured from the previous press, not the first one.
        await d.key(_right);
        await d.realWait(const Duration(milliseconds: 300));
        await d.key(_right);
        await d.realWait(const Duration(milliseconds: 300));
        await d.key(_right);
        expect(d.seeks, [
          const Duration(seconds: 310),
          const Duration(seconds: 320),
        ]);
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        expect(d.count('pause'), 1);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV before the first ready a lowered bar is neither raised nor replaced by the guide',
    (t) async {
      p21IgnoreGuideRowOverflow();
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mountUnready(
          P21Driver.screen(
            channelDirectory: tvDirectory,
            requestChannelById: (id) async => null,
          ),
        );
        // A tap lowers the (not yet built) controls layer.
        await d.observe(() => t.tapAt(const Offset(150, 400)));
        await d.wait(320);
        final calls = d.player.calls.length;
        await d.key(LogicalKeyboardKey.arrowUp);
        await d.wait(300);
        expect(find.byType(ChannelGuide), findsNothing);
        await d.key(LogicalKeyboardKey.select);
        await d.key(LogicalKeyboardKey.arrowDown);
        expect(find.byType(ChannelGuide), findsNothing);
        expect(d.player.calls.length, calls);
        await d.ready();
        expect(d.barUp, isFalse, reason: 'no key raised it before ready');
        expect(d.focused, 'tvPlayerRoot');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV BACK before the first ready leaves the player even with the controls flagged up',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mountUnready(P21Driver.screen(), over: true);
        expect(d.playerRouteOpen, isTrue);
        await d.key(LogicalKeyboardKey.escape);
        await d.wait(500);
        expect(d.playerRouteOpen, isFalse, reason: 'BACK always gets out');
        for (var i = 0; i < 12; i++) {
          await d.wait(1000);
        }
        // Pinned (P21 Step 0b Follow-up): the startup abandoned before its
        // first ready still arms the 6 s resume autosave about ten seconds
        // after the dispose, and nothing cancels it.
        expect(d.activePeriodic(const Duration(seconds: 6)), 1);
        for (final v in d.periodicTimers) {
          v.$2.cancel();
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 TV a scrub confirm clears its preview at once, before the seek completes',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      final seek = Completer<void>();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        await d.f.finish(t, d.player.pause());
        await d.wait(50);
        for (var i = 0; i < 3; i++) {
          await d.key(_right);
        }
        expect(d.bar.scrubPreview, const Duration(seconds: 330));
        d.player.delays['seek'] = seek;
        await d.key(LogicalKeyboardKey.select);
        expect(d.seeks.last, const Duration(seconds: 330));
        expect(d.bar.scrubPreview, isNull, reason: 'the bar shows no preview');
        expect(d.focused, 'tvPlayPause');
        seek.complete();
        await d.wait(50);
        expect(d.bar.scrubPreview, isNull);
        expect(d.errors, isEmpty);
      } finally {
        if (!seek.isCompleted) seek.complete();
        await d.close();
      }
    },
  );
}
