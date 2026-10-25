import 'dart:async';

import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

/// The retro static lines a transition may draw (`_tvStaticMessages`).
const _messages = [
  '📺 BUFFERING... JUST KIDDING',
  '📺 RETICULATING SPLINES...',
  '📺 SUMMONING VIDEO GODS...',
  '📺 ENGAGING HYPERDRIVE...',
  '📺 CALIBRATING FLUX CAPACITOR',
  '📺 CONSULTING THE ALGORITHMS',
  '📺 WARMING UP THE PIXELS',
  '📺 BRIBING THE SERVERS...',
];

TransitionOverlay? _overlay(WidgetTester t) {
  final f = find.byType(TransitionOverlay);
  return f.evaluate().isEmpty ? null : t.widget<TransitionOverlay>(f);
}

double _buffering(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byType(BufferingIndicator),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

/// A Debrify TV channel session whose next-channel request is held.
class _Channels {
  final requests = <Completer<Map<String, dynamic>?>>[];
  VideoPlayerScreen screen() => VideoPlayerScreen(
    videoUrl: 'https://p21-transition.test/a.mp4',
    title: 'Film A',
    showChannelName: true,
    channelName: 'Alpha',
    channelNumber: 7,
    requestNextChannel: () {
      final request = Completer<Map<String, dynamic>?>();
      requests.add(request);
      return request.future;
    },
  );
  void release(int index, String name) => requests[index].complete({
    'url': 'https://p21-transition.test/$name.mp4',
    'title': 'Film $name',
    'channelName': 'Channel $name',
    'channelNumber': 9,
  });
}

void main() {
  p21Timeouts();

  testWidgets(
    'P21 a transition shows the static overlay with a listed line and no subtitle, animating every 50 ms',
    (t) async {
      final d = P21Driver(t);
      final channels = _Channels();
      await d.initialize();
      try {
        await d.mount(screen: channels.screen());
        expect(_overlay(t), isNull);
        final work = d.beginNextChannel();
        await d.wait(0);
        expect(_overlay(t), isNotNull);
        final overlay = _overlay(t)!;
        expect(_messages, contains(overlay.tvStaticMessage));
        expect(overlay.tvStaticSubtext, '');
        final controller = overlay.rainbowController;
        expect(controller.isAnimating, isTrue);
        final start = controller.value;
        await d.wait(25);
        expect((controller.value - start).abs(), closeTo(0.5, 0.05));
        channels.release(0, 'B');
        await d.f.finish(t, work);
        await d.wait(100);
        expect(_overlay(t)?.tvStaticSubtext, '▶ FILM B');
        await d.wait(4000);
        expect(_overlay(t), isNull);
        expect(d.errors, isEmpty);
      } finally {
        for (final r in channels.requests) {
          if (!r.isCompleted) r.complete(null);
        }
        await d.close();
      }
    },
  );

  testWidgets('P21 transitions draw exactly the eight listed lines', (t) async {
    final d = P21Driver(t);
    final channels = _Channels();
    await d.initialize();
    final seen = <String>{};
    try {
      await d.mount(screen: channels.screen());
      // 100 draws: each line is missed with probability (7/8)^100 < 2e-6.
      for (var i = 0; i < 100; i++) {
        final work = d.beginNextChannel();
        await d.wait(0);
        seen.add(_overlay(t)!.tvStaticMessage);
        channels.release(i, 'N$i');
        await d.f.finish(t, work);
        await d.wait(4000);
      }
      expect(seen, _messages.toSet());
      expect(d.errors, isEmpty);
    } finally {
      for (final r in channels.requests) {
        if (!r.isCompleted) r.complete(null);
      }
      await d.close();
    }
  });

  testWidgets(
    'P21 a new transition clears the previous subtitle and outlives the previous stop timer',
    (t) async {
      final d = P21Driver(t);
      final channels = _Channels();
      await d.initialize();
      try {
        await d.mount(screen: channels.screen());
        final first = d.beginNextChannel();
        await d.wait(0);
        channels.release(0, 'B');
        await d.f.finish(t, first);
        await d.wait(100);
        expect(_overlay(t)?.tvStaticSubtext, '▶ FILM B');
        // The incoming play edge armed a three-second stop; a second switch
        // starts before it fires and is still resolving when it would.
        await d.wait(1000);
        final second = d.beginNextChannel();
        await d.wait(0);
        expect(_overlay(t), isNotNull);
        expect(_overlay(t)!.tvStaticSubtext, '');
        await d.wait(2500);
        expect(
          _overlay(t),
          isNotNull,
          reason: 'the old stop timer was cancelled',
        );
        channels.release(1, 'C');
        await d.f.finish(t, second);
        await d.wait(4000);
        expect(_overlay(t), isNull);
        expect(d.errors, isEmpty);
      } finally {
        for (final r in channels.requests) {
          if (!r.isCompleted) r.complete(null);
        }
        await d.close();
      }
    },
  );

  testWidgets('P21 a transition lowers a raised buffering indicator at once', (
    t,
  ) async {
    final d = P21Driver(t);
    final channels = _Channels();
    await d.initialize();
    try {
      await d.mount(screen: channels.screen());
      d.player.state = d.player.state.copyWith(buffering: true);
      d.player.emit('buffering', true);
      await d.wait(1500);
      expect(_buffering(t), 1);
      final work = d.beginNextChannel();
      await d.wait(0);
      expect(_buffering(t), 0);
      channels.release(0, 'B');
      await d.f.finish(t, work);
      await d.wait(4000);
      expect(d.errors, isEmpty);
    } finally {
      for (final r in channels.requests) {
        if (!r.isCompleted) r.complete(null);
      }
      await d.close();
    }
  });
}
