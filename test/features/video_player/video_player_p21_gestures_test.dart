import 'dart:async';

import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/painters/double_tap_ripple_painter.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'support/p21_controls_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';

const _at = Duration(seconds: 300);

Future<P21Driver> _mount(WidgetTester t, {bool hidden = true}) async {
  final d = P21Driver(t);
  await d.initialize();
  await d.mount(screen: P21Driver.screen());
  if (hidden) await d.wait(4000);
  await d.at(_at);
  return d;
}

DoubleTapRipple? _ripple(WidgetTester t) {
  final paint = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is DoubleTapRipplePainter,
  );
  if (paint.evaluate().isEmpty) return null;
  return (t.widget<CustomPaint>(paint).painter! as DoubleTapRipplePainter)
      .ripple;
}

SeekHudState? _seekHud(WidgetTester t) {
  final hud = find.byType(SeekHud);
  return hud.evaluate().isEmpty ? null : t.widget<SeekHud>(hud).hud;
}

/// The seek HUD, which must be on screen.
SeekHudState _seekNow(WidgetTester t) {
  expect(find.byType(SeekHud), findsOneWidget);
  return _seekHud(t)!;
}

/// The vertical HUD, which must be on screen.
VerticalHudState _verticalNow(WidgetTester t) {
  expect(find.byType(VerticalHud), findsOneWidget);
  return _verticalHud(t)!;
}

VerticalHudState? _verticalHud(WidgetTester t) {
  final hud = find.byType(VerticalHud);
  return hud.evaluate().isEmpty ? null : t.widget<VerticalHud>(hud).hud;
}

Future<void> _doubleTap(P21Driver d, Offset at) async {
  d.observe(
    () => d.gestures.onDoubleTapDown!(TapDownDetails(localPosition: at)),
  );
  await d.wait(0);
  await d.wait(0);
}

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

double _lastVolume(P21Driver d) {
  final last = d.player.calls.last;
  expect(last.$1, 'volume');
  return last.$2! as double;
}

class _HeldBrightness extends VideoPlayerBrightness {
  final reads = <Completer<double>>[];
  @override
  Future<double> get application {
    final read = Completer<double>();
    reads.add(read);
    return read.future;
  }
}

void main() {
  p21Timeouts();
  TraktTestTransport.install();
  group('double tap', () {
    for (final forward in [true, false]) {
      testWidgets(
        'P21 a double tap on the ${forward ? 'right' : 'left'} half seeks ten seconds and ripples for 450 ms',
        (t) async {
          final d = await _mount(t);
          try {
            final at = Offset(forward ? 640 : 639.9, 400);
            await _doubleTap(d, at);
            expect(d.seeks, [
              forward
                  ? const Duration(seconds: 310)
                  : const Duration(seconds: 290),
            ]);
            expect(_ripple(t), isNotNull);
            final ripple = _ripple(t)!;
            expect(ripple.center, at);
            expect(
              ripple.icon,
              forward ? Icons.forward_10_rounded : Icons.replay_10_rounded,
            );
            await d.wait(449);
            expect(_ripple(t), isNotNull);
            await d.wait(1);
            expect(_ripple(t), isNull, reason: 'cleared at 450 ms');
            expect(d.barUp, isFalse, reason: 'a double tap raises nothing');
            expect(d.errors, isEmpty);
          } finally {
            await d.close();
          }
        },
      );
    }

    testWidgets('P21 a double tap keeps a 24-pixel guard at both side edges', (
      t,
    ) async {
      final d = await _mount(t);
      try {
        for (final sample in <(double, bool)>[
          (23.9, false),
          (24, true),
          (1256, true),
          (1256.1, false),
        ]) {
          final before = d.seeks.length;
          await _doubleTap(d, Offset(sample.$1, 400));
          expect(
            d.seeks.length,
            before + (sample.$2 ? 1 : 0),
            reason: 'x=${sample.$1}',
          );
          await d.wait(500);
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });

    testWidgets(
      'P21 a double tap over raised controls skips the 72-pixel top and dock bands',
      (t) async {
        final d = await _mount(t, hidden: false);
        try {
          expect(d.barUp, isTrue);
          for (final sample in <(double, bool)>[
            (71.9, false),
            (72, true),
            (728, true),
            (728.1, false),
          ]) {
            final before = d.seeks.length;
            await _doubleTap(d, Offset(300, sample.$1));
            expect(
              d.seeks.length,
              before + (sample.$2 ? 1 : 0),
              reason: 'y=${sample.$1}',
            );
            await d.wait(500);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 with the controls hidden a double tap seeks in the bands',
      (t) async {
        final d = await _mount(t);
        try {
          await _doubleTap(d, const Offset(300, 10));
          await d.wait(500);
          await _doubleTap(d, const Offset(1000, 790));
          // The second tap seeks from where the first one landed.
          expect(d.seeks, [
            const Duration(seconds: 290),
            const Duration(seconds: 300),
          ]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets('P21 a double tap clamps its seek to the start and the end', (
      t,
    ) async {
      final d = await _mount(t);
      try {
        await d.at(const Duration(seconds: 4));
        await _doubleTap(d, const Offset(200, 400));
        await d.wait(500);
        await d.at(const Duration(minutes: 19, seconds: 55));
        await _doubleTap(d, const Offset(1000, 400));
        expect(d.seeks, [Duration.zero, const Duration(minutes: 20)]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });

    testWidgets(
      'P21 a double tap shows its ripple only once the seek has completed',
      (t) async {
        final d = await _mount(t);
        final seek = Completer<void>();
        try {
          d.player.delays['seek'] = seek;
          await _doubleTap(d, const Offset(900, 400));
          await d.wait(600);
          expect(d.seeks, [const Duration(seconds: 310)]);
          expect(_ripple(t), isNull);
          seek.complete();
          await d.wait(0);
          await d.wait(0);
          expect(_ripple(t), isNotNull);
          await d.wait(460);
          expect(_ripple(t), isNull);
          expect(d.errors, isEmpty);
        } finally {
          if (!seek.isCompleted) seek.complete();
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a screen closed during a double-tap seek still repaints after it and reports the error',
      (t) async {
        final d = await _mount(t);
        final seek = Completer<void>();
        try {
          d.player.delays['seek'] = seek;
          await _doubleTap(d, const Offset(900, 400));
          await t.pumpWidget(const SizedBox.shrink());
          seek.complete();
          await d.wait(0);
          await d.wait(0);
          // Pinned (hazard 11): the post-seek setState has no mounted guard.
          expect(d.errors.map((e) => e.runtimeType.toString()), [
            'FlutterError',
          ]);
          expect(
            d.errors.single.toString(),
            contains('setState() called after dispose()'),
          );
          d.errors.clear();
        } finally {
          if (!seek.isCompleted) seek.complete();
          await d.close();
        }
      },
    );
  });

  group('pan', () {
    testWidgets(
      'P21 a horizontal pan maps its width to two minutes and seeks once at the end',
      (t) async {
        final d = await _mount(t);
        try {
          await _start(d, const Offset(640, 400));
          _update(d, const Offset(700, 405));
          _update(d, const Offset(768, 410));
          await d.wait(0);
          final hud = _seekNow(t);
          expect(hud.target, const Duration(seconds: 312));
          expect(hud.base, _at);
          expect(hud.isForward, isTrue);
          expect(d.seeks, isEmpty, reason: 'nothing seeks mid-pan');
          await _end(d);
          expect(d.seeks, [const Duration(seconds: 312)]);
          await d.wait(249);
          expect(_seekHud(t), isNotNull);
          await d.wait(1);
          expect(_seekHud(t), isNull, reason: 'cleared at 250 ms');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a backward pan reports a backward target and clamps at the start',
      (t) async {
        final d = await _mount(t);
        try {
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(836, 400));
          await d.wait(0);
          expect(_seekNow(t).target, const Duration(seconds: 294));
          expect(_seekNow(t).isForward, isFalse);
          _update(d, const Offset(-4000, 400));
          await d.wait(0);
          expect(_seekNow(t).target, Duration.zero);
          await _end(d);
          expect(d.seeks, [Duration.zero]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a forward pan clamps at the end and a short item maps its own length',
      (t) async {
        final d = await _mount(t);
        try {
          await d.at(const Duration(minutes: 19, seconds: 30));
          await _start(d, const Offset(100, 400));
          _update(d, const Offset(1200, 400));
          await d.wait(0);
          expect(_seekNow(t).target, const Duration(minutes: 20));
          await _end(d);
          await d.wait(300);
          await d.length(const Duration(seconds: 60));
          await d.at(const Duration(seconds: 10));
          await _start(d, const Offset(100, 400));
          _update(d, const Offset(740, 400));
          await d.wait(0);
          // Half the width of a 60 s item is 30 s.
          expect(_seekNow(t).target, const Duration(seconds: 40));
          // Equal position is reported as forward.
          _update(d, const Offset(100, 400));
          await d.wait(0);
          expect(_seekNow(t).target, const Duration(seconds: 10));
          expect(_seekNow(t).isForward, isTrue);
          await _end(d);
          expect(d.seeks, [
            const Duration(minutes: 20),
            const Duration(seconds: 10),
          ]);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a pan picks its mode after more than twelve pixels on the dominant axis',
      (t) async {
        final d = await _mount(t);
        try {
          await _start(d, const Offset(640, 400));
          _update(d, const Offset(652, 400));
          await d.wait(0);
          expect(_seekHud(t), isNull, reason: 'exactly 12 px is not a move');
          expect(_verticalHud(t), isNull);
          _update(d, const Offset(653, 400));
          await d.wait(0);
          expect(_seekHud(t), isNotNull);
          // Once seeking, vertical travel does not switch the mode.
          _update(d, const Offset(653, 700));
          await d.wait(0);
          expect(_verticalHud(t), isNull);
          await _end(d);
          await d.wait(300);
          // A tie goes vertical, and 12 px vertically is not yet a move.
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(912, 412));
          await d.wait(0);
          expect(_seekHud(t), isNull);
          expect(_verticalHud(t), isNull);
          _update(d, const Offset(913, 420));
          await d.wait(0);
          expect(_seekHud(t), isNull);
          expect(_verticalHud(t)?.kind, VerticalKind.volume);
          await _end(d);
          expect(d.seeks, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a vertical pan on the right half sets the volume from where it started',
      (t) async {
        final d = await _mount(t);
        try {
          await d.f.finish(t, d.player.setVolume(80));
          await _start(d, const Offset(900, 300));
          _update(d, const Offset(900, 460));
          await d.wait(0);
          // 0.8 - 160 / 800 = 0.6
          expect(_lastVolume(d), closeTo(60, 1e-9));
          expect(_verticalNow(t).kind, VerticalKind.volume);
          expect(_verticalNow(t).value, closeTo(0.6, 1e-9));
          _update(d, const Offset(900, -900));
          await d.wait(0);
          expect(_lastVolume(d), 100.0);
          expect(_verticalNow(t).value, 1.0);
          _update(d, const Offset(900, 2000));
          await d.wait(0);
          expect(_lastVolume(d), 0.0);
          await _end(d);
          expect(d.seeks, isEmpty);
          await d.wait(260);
          expect(_verticalHud(t), isNull);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a vertical pan on the left half sets the screen brightness',
      (t) async {
        final d = await _mount(t);
        try {
          d.f.brightness.value = 0.5;
          await _start(d, const Offset(300, 400));
          expect(d.f.brightness.calls, contains('read'));
          _update(d, const Offset(300, 240));
          await d.wait(0);
          // 0.5 + 160 / 800 = 0.7
          expect(d.f.brightness.calls.last, closeTo(0.7, 1e-9));
          expect(_verticalNow(t).kind, VerticalKind.brightness);
          expect(_verticalNow(t).value, closeTo(0.7, 1e-9));
          _update(d, const Offset(300, 2000));
          await d.wait(0);
          expect(d.f.brightness.calls.last, 0.0);
          expect(
            d.player.calls.where((c) => c.$1 == 'volume'),
            isEmpty,
            reason: 'the left half never touches volume',
          );
          await _end(d);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 without brightness support a left-half vertical pan does nothing and may still become a seek',
      (t) async {
        final d = await _mount(t);
        try {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(300, 200));
          await d.wait(0);
          expect(_verticalHud(t), isNull);
          expect(d.f.brightness.calls.whereType<double>(), isEmpty);
          // The mode is still undecided, so a later horizontal move seeks.
          _update(d, const Offset(600, 200));
          await d.wait(0);
          expect(_seekHud(t), isNotNull);
          await _end(d);
          expect(d.seeks, hasLength(1));
          debugDefaultTargetPlatformOverride = null;
          expect(d.errors, isEmpty);
        } finally {
          debugDefaultTargetPlatformOverride = null;
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 with raised controls a pan starting in the top or dock band is ignored to its end',
      (t) async {
        final d = await _mount(t, hidden: false);
        try {
          for (final y in [71.9, 728.1]) {
            await _start(d, Offset(640, y));
            _update(d, Offset(900, y));
            _update(d, Offset(900, y + 300));
            await d.wait(0);
            expect(_seekHud(t), isNull, reason: 'y=$y');
            expect(_verticalHud(t), isNull);
            await _end(d);
          }
          expect(d.seeks, isEmpty);
          expect(d.player.calls.where((c) => c.$1 == 'volume'), isEmpty);
          // Just inside the bands the pan is live, and the ignore flag is
          // cleared by the next start.
          for (final y in [72.0, 728.0]) {
            await _start(d, Offset(640, y));
            _update(d, Offset(900, y));
            await d.wait(0);
            expect(_seekHud(t), isNotNull, reason: 'y=$y');
            await _end(d);
            await d.wait(300);
          }
          expect(d.seeks, hasLength(2));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a volume pan end does not seek and the next pan chooses its mode afresh',
      (t) async {
        final d = await _mount(t);
        try {
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(900, 500));
          await _end(d);
          expect(d.seeks, isEmpty);
          await _start(d, const Offset(900, 400));
          // A new start clears the previous pan's HUDs at once.
          expect(_verticalHud(t), isNull);
          _update(d, const Offset(1000, 400));
          await d.wait(0);
          expect(_seekHud(t), isNotNull);
          expect(_verticalHud(t), isNull);
          await _end(d);
          expect(d.seeks, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a horizontal pan over an unknown duration shows no seek and seeks nothing',
      (t) async {
        final d = await _mount(t);
        try {
          await d.length(Duration.zero);
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(700, 400));
          await d.wait(0);
          expect(_seekHud(t), isNull);
          await _end(d);
          expect(d.seeks, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a pan start reads the volume and brightness it measures from before resetting',
      (t) async {
        final d = await _mount(t);
        final held = _HeldBrightness();
        final previous = ScreenBrightnessPlatform.instance;
        try {
          await d.f.finish(t, d.player.setVolume(50));
          ScreenBrightnessPlatform.instance = held;
          await _start(d, const Offset(900, 400));
          // The start is still waiting on brightness: the previous mode and
          // HUDs are untouched until it returns.
          expect(held.reads, hasLength(1));
          held.reads.single.complete(0.3);
          await d.wait(0);
          await d.wait(0);
          _update(d, const Offset(900, 480));
          await d.wait(0);
          expect(_lastVolume(d), closeTo(40, 1e-9));
          await _end(d);
          ScreenBrightnessPlatform.instance = previous;
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(300, 320));
          await d.wait(0);
          expect(d.f.brightness.calls.last, closeTo(0.6, 1e-9));
          await _end(d);
          expect(d.errors, isEmpty);
        } finally {
          for (final read in held.reads) {
            if (!read.isCompleted) read.complete(0.5);
          }
          ScreenBrightnessPlatform.instance = previous;
          await d.close();
        }
      },
    );
  });

  group('pan edges', () {
    testWidgets(
      'P21 a pan picks volume on a diagonal tie, 13 vertical pixels, and at the exact centre',
      (t) async {
        final d = await _mount(t);
        try {
          // A tie is not horizontal.
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(920, 420));
          await d.wait(0);
          expect(_seekHud(t), isNull);
          expect(_verticalNow(t).kind, VerticalKind.volume);
          await _end(d);
          await d.wait(300);
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(900, 413));
          await d.wait(0);
          expect(_verticalNow(t).kind, VerticalKind.volume);
          await _end(d);
          await d.wait(300);
          // x = 640 is the right half.
          await _start(d, const Offset(640, 400));
          _update(d, const Offset(640, 450));
          await d.wait(0);
          expect(_verticalNow(t).kind, VerticalKind.volume);
          await _end(d);
          await d.wait(300);
          // x = 600 is still the left half.
          await _start(d, const Offset(600, 400));
          _update(d, const Offset(600, 450));
          await d.wait(0);
          expect(_verticalNow(t).kind, VerticalKind.brightness);
          await _end(d);
          expect(d.seeks, isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a pan measures from a volume above 100 and a brightness near full, clamping both at full',
      (t) async {
        final d = await _mount(t);
        try {
          await d.f.finish(t, d.player.setVolume(150));
          await _start(d, const Offset(900, 400));
          _update(d, const Offset(900, 600));
          await d.wait(0);
          // Starts from 1.0, not 1.5: 1.0 - 200 / 800 = 0.75.
          expect(_lastVolume(d), closeTo(75, 1e-9));
          await _end(d);
          await d.wait(300);
          d.f.brightness.value = 0.9;
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(300, 0));
          await d.wait(0);
          expect(d.f.brightness.calls.last, 1.0);
          expect(_verticalNow(t).value, 1.0);
          await _end(d);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a new pan clears a still-showing seek HUD and an abandoned pan\'s mode',
      (t) async {
        final d = await _mount(t);
        try {
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(500, 400));
          await _end(d);
          expect(_seekHud(t), isNotNull);
          await _start(d, const Offset(300, 400));
          expect(_seekHud(t), isNull, reason: 'the start cleared it');
          // That pan is abandoned (no end): the next start resets its mode.
          _update(d, const Offset(500, 400));
          await d.wait(0);
          expect(_seekHud(t), isNotNull);
          await _start(d, const Offset(900, 300));
          _update(d, const Offset(900, 400));
          await d.wait(0);
          expect(_verticalNow(t).kind, VerticalKind.volume);
          expect(_seekHud(t), isNull);
          await _end(d);
          expect(d.seeks, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a pan update arriving before the start finishes reading brightness uses no mode yet',
      (t) async {
        final d = await _mount(t);
        final held = _HeldBrightness();
        final previous = ScreenBrightnessPlatform.instance;
        try {
          await _start(d, const Offset(300, 400));
          _update(d, const Offset(500, 400));
          await _end(d);
          await d.wait(300);
          ScreenBrightnessPlatform.instance = held;
          await _start(d, const Offset(900, 300));
          _update(d, const Offset(900, 400));
          await d.wait(0);
          // The finished pan left no seek mode behind.
          expect(_seekHud(t), isNull);
          expect(_verticalNow(t).kind, VerticalKind.volume);
          held.reads.single.complete(0.5);
          await d.wait(0);
          await _end(d);
          expect(d.seeks, hasLength(1));
          expect(d.errors, isEmpty);
        } finally {
          for (final read in held.reads) {
            if (!read.isCompleted) read.complete(0.5);
          }
          ScreenBrightnessPlatform.instance = previous;
          await d.close();
        }
      },
    );

    testWidgets(
      'P21 a pan starting in the dock band leaves the previous HUD alone',
      (t) async {
        final d = await _mount(t, hidden: false);
        try {
          await _start(d, const Offset(900, 300));
          _update(d, const Offset(900, 400));
          await _end(d);
          expect(_verticalHud(t), isNotNull);
          await _start(d, const Offset(900, 760));
          expect(
            _verticalHud(t),
            isNotNull,
            reason: 'an ignored start resets nothing',
          );
          await _end(d);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  });
}
