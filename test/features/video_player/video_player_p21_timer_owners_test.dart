import 'dart:async';

import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

const _hide = Duration(seconds: 3);

int _armed(P21Driver d) => d.timers.where((v) => v.duration == _hide).length;

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

bool _seekHudShown() => find.byType(SeekHud).evaluate().isNotEmpty;

Future<void> _start(P21Driver d, Offset at) async {
  d.observe(() => d.gestures.onPanStart!(DragStartDetails(localPosition: at)));
  await d.wait(0);
  await d.wait(0);
}

void _update(P21Driver d, Offset at) => d.observe(
  () => d.gestures.onPanUpdate!(
    DragUpdateDetails(globalPosition: at, localPosition: at),
  ),
);

Future<void> _end(P21Driver d) async {
  d.observe(() => d.gestures.onPanEnd!(DragEndDetails()));
  await d.wait(0);
}

/// Phase 21a Step 0c, class 5: which timer each moved path arms, cancels or
/// leaves pending: the auto-hide on a press before ready and on a scrub
/// abandoned by a switch, the buffering debounce on a clear, and the pan
/// HUD clear across consecutive pans.
void main() {
  p21Timeouts();

  for (final (key, label) in [
    (LogicalKeyboardKey.space, 'space'),
    (LogicalKeyboardKey.mediaPlayPause, 'media play-pause'),
  ]) {
    testWidgets(
      'P21 desktop $label before the first ready arms no countdown, and after it arms one',
      (t) async {
        final d = P21Driver(t);
        await d.initialize();
        try {
          await d.mountUnready(P21Driver.screen());
          final before = _armed(d);
          await d.key(key);
          await d.wait(100);
          expect(_armed(d), before, reason: 'the press did nothing');
          expect(d.activeTimers(_hide), 0);
          await d.ready();
          await d.wait(4000);
          final ready = _armed(d);
          await d.key(key);
          expect(_armed(d), ready + 1);
          expect(d.activeTimers(_hide), 1);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P21 TV a channel switch that drops a scrub arms no countdown of its own and leaves the scrub one pending',
    (t) async {
      final requests = <Completer<Map<String, dynamic>?>>[];
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://p21-timers.test/a.mp4',
            title: 'Film A',
            showChannelName: true,
            channelName: 'Alpha',
            channelNumber: 7,
            requestNextChannel: () {
              final request = Completer<Map<String, dynamic>?>();
              requests.add(request);
              return request.future;
            },
          ),
        );
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        for (var i = 0; i < 3; i++) {
          await d.key(LogicalKeyboardKey.arrowRight);
        }
        expect(d.bar.scrubPreview, isNotNull);
        final armed = _armed(d);
        expect(d.activeTimers(_hide), 1);
        final work = d.startNextChannel();
        await d.wait(0);
        expect(d.bar.scrubPreview, isNull);
        expect(_armed(d), armed, reason: 'the abandon re-arms nothing');
        expect(d.activeTimers(_hide), 1);
        requests.last.complete(null);
        await d.f.finish(t, work);
        await d.wait(100);
        expect(d.errors, isEmpty);
      } finally {
        for (final r in requests) {
          if (!r.isCompleted) r.complete(null);
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a buffering stall cleared by a playlist switch never shows its spinner on the incoming item',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://p21-timers.test/e1.mp4',
            title: 'Episode 1',
            playlist: [
              PlaylistEntry(url: 'https://p21-timers.test/e1.mp4', title: 'E1'),
              PlaylistEntry(url: 'https://p21-timers.test/e2.mp4', title: 'E2'),
            ],
          ),
        );
        await d.wait(4000);
        final opens = d.opens.length;
        d.player.state = d.player.state.copyWith(buffering: true);
        d.observe(() => d.player.emit('buffering', true));
        await d.wait(100);
        expect(_buffering(t), 0, reason: 'still inside the debounce');
        await d.key(LogicalKeyboardKey.keyN);
        await d.f.until(t, () => d.opens.length > opens);
        for (var i = 0; i < 20; i++) {
          await d.wait(100);
        }
        expect(_buffering(t), 0);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a pan end HUD clear is not cancelled by the next pan: it blanks the live pan at 250 ms and the next move shows it again',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        await _start(d, const Offset(300, 400));
        _update(d, const Offset(500, 400));
        await _end(d);
        await d.wait(100);
        await _start(d, const Offset(300, 400));
        _update(d, const Offset(400, 400));
        await d.wait(0);
        expect(_seekHudShown(), isTrue);
        await d.wait(160);
        expect(_seekHudShown(), isFalse, reason: 'the first end cleared it');
        _update(d, const Offset(420, 400));
        await d.wait(0);
        expect(_seekHudShown(), isTrue);
        await _end(d);
        await d.wait(249);
        expect(_seekHudShown(), isTrue);
        await d.wait(1);
        expect(_seekHudShown(), isFalse);
        expect(d.seeks, hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
