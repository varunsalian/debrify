import 'dart:async';

import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/painters/double_tap_ripple_painter.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'support/p21_controls_driver.dart';
import 'support/video_player_environment.dart';

SeekHudState? _seekHud(WidgetTester t) {
  final hud = find.byType(SeekHud);
  return hud.evaluate().isEmpty ? null : t.widget<SeekHud>(hud).hud;
}

VerticalHudState? _verticalHud(WidgetTester t) {
  final hud = find.byType(VerticalHud);
  return hud.evaluate().isEmpty ? null : t.widget<VerticalHud>(hud).hud;
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

double _lastVolume(P21Driver d) =>
    d.player.calls.lastWhere((c) => c.$1 == 'volume').$2! as double;

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

/// Phase 21a Step 0c, class 4: inputs that change while a moved member is
/// suspended in an await. A pan start captures the playhead and the volume
/// before its brightness read and checks `mounted` after it; a double tap
/// computes its target and its band before its seek (the report of that
/// target after a moving playhead is in the tracker paths suite).
void main() {
  p21Timeouts();

  testWidgets(
    'P21 a pan start measures from the playhead and volume of the moment it began, not those when its brightness read returns',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        await d.f.finish(t, d.player.setVolume(50));
        ScreenBrightnessPlatform.instance = held;
        // A volume pan on the right half.
        await _start(d, const Offset(900, 400));
        expect(held.reads, hasLength(1));
        await d.f.finish(t, d.player.setVolume(90));
        held.reads.last.complete(0.4);
        await d.wait(0);
        await d.wait(0);
        _update(d, const Offset(900, 480));
        await d.wait(0);
        // 0.5 (at the start) - 80 / 800 = 0.4.
        expect(_lastVolume(d), closeTo(40, 1e-9));
        await _end(d);
        await d.wait(300);
        // A seek pan; the playhead moves while the read is held.
        await _start(d, const Offset(640, 400));
        expect(held.reads, hasLength(2));
        await d.at(const Duration(seconds: 360));
        held.reads.last.complete(0.4);
        await d.wait(0);
        await d.wait(0);
        _update(d, const Offset(661.4, 400));
        await d.wait(0);
        // 2 s on from the 300 s it began at; the HUD base is the live 360 s.
        expect(_seekHud(t)!.target, const Duration(seconds: 302));
        expect(_seekHud(t)!.base, const Duration(seconds: 360));
        await _end(d);
        expect(d.seeks, [const Duration(seconds: 302)]);
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
    'P21 a brightness pan measures from the value its held read returns, not one read later',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        ScreenBrightnessPlatform.instance = held;
        await _start(d, const Offset(300, 400));
        held.reads.single.complete(0.2);
        await d.wait(0);
        await d.wait(0);
        ScreenBrightnessPlatform.instance = previous;
        d.f.brightness.value = 0.9;
        _update(d, const Offset(300, 320));
        await d.wait(0);
        // 0.2 + 80 / 800 = 0.3.
        expect(_verticalHud(t)!.value, closeTo(0.3, 1e-9));
        expect(d.f.brightness.calls.last, closeTo(0.3, 1e-9));
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

  testWidgets(
    'P21 a pan start whose screen closes during its brightness read touches nothing when the read returns',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        await _start(d, const Offset(300, 400));
        _update(d, const Offset(500, 400));
        await _end(d);
        expect(_seekHud(t), isNotNull);
        ScreenBrightnessPlatform.instance = held;
        await _start(d, const Offset(900, 400));
        await t.pumpWidget(const SizedBox.shrink());
        held.reads.single.complete(0.4);
        await d.wait(0);
        await d.wait(300);
        // The returned start found the screen gone and wrote no HUD.
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
    'P21 a double tap decides its band and side at the tap, before its seek',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      final seek = Completer<void>();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.wait(4000);
        await d.at(const Duration(seconds: 300));
        d.player.delays['seek'] = seek;
        d.observe(
          () => d.gestures.onDoubleTapDown!(
            TapDownDetails(localPosition: const Offset(300, 760)),
          ),
        );
        await d.wait(0);
        // The controls rise while the seek is held: the tap already counted.
        await d.hover();
        expect(d.barUp, isTrue);
        seek.complete();
        await d.wait(0);
        await d.wait(0);
        expect(d.seeks, [const Duration(seconds: 290)]);
        final paint = find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is DoubleTapRipplePainter,
        );
        final ripple =
            (t.widget<CustomPaint>(paint).painter! as DoubleTapRipplePainter)
                .ripple;
        expect(ripple.center, const Offset(300, 760));
        expect(ripple.icon, Icons.replay_10_rounded);
        await d.wait(500);
        expect(d.errors, isEmpty);
      } finally {
        if (!seek.isCompleted) seek.complete();
        await d.close();
      }
    },
  );
}
