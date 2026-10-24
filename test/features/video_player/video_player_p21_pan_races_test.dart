import 'dart:async';

import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player/widgets/vertical_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved plugin interface for test doubles; app dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

import 'support/p21_controls_driver.dart';
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

int _volumeCalls(P21Driver d) =>
    d.player.calls.where((c) => c.$1 == 'volume').length;

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

/// Phase 21 Step 0b: pan races: a start whose brightness read is still
/// pending, a playhead that moves during the pan, and an ignored pan in the
/// dock band followed at once by a live one.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 a pan start leaves the previous HUD on screen while its brightness read is held',
    (t) async {
      final d = await _mount(t);
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      try {
        await _start(d, const Offset(300, 400));
        _update(d, const Offset(500, 400));
        await _end(d);
        expect(_seekHud(t), isNotNull);
        ScreenBrightnessPlatform.instance = held;
        await _start(d, const Offset(900, 400));
        expect(held.reads, hasLength(1));
        await d.wait(100);
        // Held at 100 ms of the previous HUD's 250: nothing reset yet.
        expect(_seekHud(t), isNotNull, reason: 'reset waits for the read');
        held.reads.single.complete(0.4);
        await d.wait(0);
        await d.wait(0);
        expect(_seekHud(t), isNull, reason: 'the returned start resets it');
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
    'P21 a seek pan measures its HUD base and direction from the live playhead',
    (t) async {
      final d = await _mount(t);
      try {
        await _start(d, const Offset(640, 400));
        // Playback moves on while the finger is down.
        await d.at(const Duration(seconds: 305));
        _update(d, const Offset(661.4, 400));
        await d.wait(0);
        final hud = _seekHud(t)!;
        // 21.4 / 1280 * 120 = 2.0 s from the start position 300.
        expect(hud.target, const Duration(seconds: 302));
        expect(hud.base, const Duration(seconds: 305));
        expect(hud.isForward, isFalse, reason: 'behind the live playhead');
        await _end(d);
        expect(d.seeks, [const Duration(seconds: 302)]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a volume pan end clears its mode, so an update before the next start returns can seek',
    (t) async {
      final d = await _mount(t);
      final held = _HeldBrightness();
      final previous = ScreenBrightnessPlatform.instance;
      try {
        await _start(d, const Offset(900, 300));
        _update(d, const Offset(900, 400));
        await _end(d);
        expect(_verticalHud(t)?.kind, VerticalKind.volume);
        final volumes = _volumeCalls(d);
        ScreenBrightnessPlatform.instance = held;
        await _start(d, const Offset(640, 400));
        _update(d, const Offset(700, 400));
        await d.wait(0);
        // No mode is left over from the volume pan: this move seeks.
        expect(_seekHud(t), isNotNull);
        expect(_volumeCalls(d), volumes);
        held.reads.single.complete(0.5);
        await d.wait(0);
        await d.wait(0);
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
    'P21 an ignored pan in the dock band schedules no HUD clear over the next live pan',
    (t) async {
      final d = await _mount(t, hidden: false);
      try {
        expect(d.barUp, isTrue);
        await _start(d, const Offset(640, 760));
        _update(d, const Offset(900, 760));
        await _end(d);
        await d.wait(50);
        await _start(d, const Offset(640, 400));
        _update(d, const Offset(700, 400));
        await d.wait(0);
        expect(_seekHud(t), isNotNull);
        // Past 250 ms from the ignored end, the live pan is still held.
        await d.wait(300);
        expect(_seekHud(t), isNotNull, reason: 'still panning');
        await _end(d);
        await d.wait(260);
        expect(_seekHud(t), isNull);
        expect(d.seeks, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
