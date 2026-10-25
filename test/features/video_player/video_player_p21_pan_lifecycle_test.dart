import 'dart:async';

import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'support/display_mode_driver.dart' show displayGesture;
import 'support/p21_controls_driver.dart';
import 'support/trakt_player_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

bool _seekHud() => find.byType(SeekHud).evaluate().isNotEmpty;
bool _verticalHud() => find.byType(VerticalHud).evaluate().isNotEmpty;

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

/// Brightness reads that stay pending until the case completes them.
class _HeldBrightness extends VideoPlayerBrightness {
  final reads = <Completer<double>>[];
  @override
  Future<double> get application {
    final read = Completer<double>();
    reads.add(read);
    return read.future;
  }
}

Future<P21Driver> _raised(WidgetTester t) async {
  final d = P21Driver(t);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  await d.at(const Duration(seconds: 300));
  await d.hover();
  expect(d.barUp, isTrue);
  return d;
}

/// Phase 21a Step 0c, class 9: pan lifecycle edges: a pan that never ends
/// (no cancel callback reaches the screen), a volume pan inside the HUD tail
/// of a seek pan, a pan without movement, and the remembered auto-hide block
/// across a tap raise.
void main() {
  p21Timeouts();
  TraktTestTransport.install();

  testWidgets(
    'P21 an ignored band pan that never ends does not swallow the next pan',
    (t) async {
      final d = await _raised(t);
      try {
        await _start(d, const Offset(640, 760));
        _update(d, const Offset(900, 760));
        await d.wait(0);
        expect(_seekHud(), isFalse);
        // No end: the next pan starts in the open area.
        await d.hover();
        await _start(d, const Offset(640, 400));
        _update(d, const Offset(700, 400));
        await d.wait(0);
        expect(_seekHud(), isTrue);
        await _end(d);
        expect(d.seeks, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 an ignored band pan that never ends does not swallow a pan made after the controls lowered',
    (t) async {
      final d = await _raised(t);
      try {
        await _start(d, const Offset(640, 760));
        _update(d, const Offset(900, 760));
        await d.wait(0);
        expect(_seekHud(), isFalse);
        // No end; the controls time out, then a pan starts on bare video.
        await d.wait(3100);
        expect(d.barUp, isFalse);
        await _start(d, const Offset(640, 400));
        _update(d, const Offset(700, 400));
        await d.wait(0);
        expect(_seekHud(), isTrue);
        await _end(d);
        expect(d.seeks, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a live pan that never ends leaves the next band pan ignored and the one after it live',
    (t) async {
      final d = await _raised(t);
      try {
        await _start(d, const Offset(640, 400));
        _update(d, const Offset(700, 400));
        await d.wait(0);
        expect(_seekHud(), isTrue);
        // Abandoned without an end; a pan now starts in the dock band.
        await d.hover();
        await _start(d, const Offset(640, 760));
        _update(d, const Offset(900, 760));
        _update(d, const Offset(900, 500));
        await d.wait(0);
        await _end(d);
        expect(d.seeks, isEmpty, reason: 'the band pan was ignored');
        expect(
          d.player.calls.where((c) => c.$1 == 'volume'),
          isEmpty,
          reason: 'and drove nothing',
        );
        await d.hover();
        await _start(d, const Offset(900, 300));
        _update(d, const Offset(900, 400));
        await d.wait(0);
        expect(_verticalHud(), isTrue);
        await _end(d);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P21 a pan that never moves seeks and reports nothing', (
    t,
  ) async {
    final d = await _raised(t);
    try {
      await _start(d, const Offset(640, 400));
      _update(d, const Offset(646, 404));
      await _end(d);
      await d.wait(300);
      expect(d.seeks, isEmpty);
      expect(_seekHud(), isFalse);
      expect(_verticalHud(), isFalse);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P21 TV a tap raise keeps a block remembered from before, so the bar stays one extra interval',
    (t) async {
      final d = P21Driver(t, tv: true);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.key(LogicalKeyboardKey.arrowDown);
        await d.f.finish(t, d.player.pause());
        // The 3 s poll finds it paused: the block is remembered.
        await d.wait(3500);
        expect(d.barUp, isTrue);
        await d.observe(() => t.tapAt(const Offset(150, 400)));
        await d.wait(320);
        expect(d.barUp, isFalse);
        await d.f.finish(t, d.player.play());
        await d.wait(500);
        // A tap raise, not the remote's: the countdown starts at the tap's
        // 300 ms double-tap timeout and its first poll spends the block.
        await d.observe(() => t.tapAt(const Offset(150, 400)));
        await d.wait(320);
        expect(d.barUp, isTrue);
        await d.wait(3100);
        expect(d.barUp, isTrue, reason: 'the remembered block re-armed it');
        await d.wait(2800);
        expect(d.barUp, isTrue);
        await d.wait(200);
        expect(d.barUp, isFalse);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a volume pan inside a seek pan HUD tail reports nothing to Trakt and seeks nothing',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = TraktPlayerDriver(t, f);
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      await d.initialize();
      try {
        await d.mount(traktScreen());
        await d.position(300000);
        final gesture = displayGesture(t);
        gesture.onPanStart!(
          DragStartDetails(localPosition: const Offset(640, 400)),
        );
        await d.drain();
        gesture.onPanUpdate!(
          DragUpdateDetails(
            globalPosition: const Offset(512, 400),
            localPosition: const Offset(512, 400),
          ),
        );
        gesture.onPanEnd!(DragEndDetails());
        await f.advance(t);
        expect(d.seeks, [const Duration(seconds: 288)]);
        // Let the seek pan's own report land before counting.
        await f.advance(t);
        await f.advance(t);
        final reported = d.requests.length;
        expect(reported, greaterThan(0));
        // A volume pan starts at once; its brightness read is held, so the
        // seek HUD from the pan before is still on screen when it ends.
        ScreenBrightnessPlatform.instance = held;
        gesture.onPanStart!(
          DragStartDetails(localPosition: const Offset(900, 300)),
        );
        await f.advance(t);
        gesture.onPanUpdate!(
          DragUpdateDetails(
            globalPosition: const Offset(900, 400),
            localPosition: const Offset(900, 400),
          ),
        );
        await f.advance(t);
        expect(find.byType(SeekHud), findsOneWidget);
        gesture.onPanEnd!(DragEndDetails());
        await f.advance(t);
        expect(d.seeks, [const Duration(seconds: 288)]);
        held.reads.single.complete(0.5);
        await d.drain();
        expect(d.requests, hasLength(reported));
      } finally {
        for (final read in held.reads) {
          if (!read.isCompleted) read.complete(0.5);
        }
        ScreenBrightnessPlatform.instance = previous;
        await d.close();
      }
    },
  );
}
