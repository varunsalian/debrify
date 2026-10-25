import 'dart:math' as math;

import 'package:debrify/screens/video_player/widgets/dock_widgets.dart';
import 'package:debrify/screens/video_player/widgets/seek_hud.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

/// The styled dock's measured bottom unit, or null when the classic dock is
/// on screen (no reporter mounted).
double? _styledExtent(P21Driver d) {
  final reporter = find.byType(DockExtentReporter);
  if (reporter.evaluate().isEmpty) return null;
  return d.t.getSize(reporter.first).height;
}

Future<P21Driver> _styled(WidgetTester t, {VideoPlayerScreen? screen}) async {
  final d = P21Driver(t);
  await d.initialize();
  await d.t.runAsync(
    () => PlayerAppearanceStorage.setPlayerDockStyle('cinema'),
  );
  await d.mount(screen: screen ?? P21Driver.screen());
  await d.at(const Duration(seconds: 300));
  return d;
}

/// Whether a double tap at height [y] (x = 300) seeks; the controls are
/// raised first so the bands apply.
Future<bool> _doubleTapSeeks(P21Driver d, double y) async {
  await d.hover();
  final before = d.seeks.length;
  d.observe(
    () => d.gestures.onDoubleTapDown!(
      TapDownDetails(localPosition: Offset(300, y)),
    ),
  );
  await d.wait(0);
  await d.wait(0);
  final seeked = d.seeks.length > before;
  await d.wait(500);
  return seeked;
}

/// Whether a pan starting at height [y] (x = 640) is live: a horizontal move
/// shows the seek HUD. The pan is ended and its HUD left to clear.
Future<bool> _panLive(P21Driver d, double y) async {
  await d.hover();
  d.observe(
    () =>
        d.gestures.onPanStart!(DragStartDetails(localPosition: Offset(640, y))),
  );
  await d.wait(0);
  await d.wait(0);
  d.observe(
    () => d.gestures.onPanUpdate!(
      DragUpdateDetails(
        globalPosition: Offset(700, y),
        localPosition: Offset(700, y),
      ),
    ),
  );
  await d.wait(0);
  final live = find.byType(SeekHud).evaluate().isNotEmpty;
  d.observe(() => d.gestures.onPanEnd!(DragEndDetails()));
  await d.wait(300);
  return live;
}

/// Samples both gestures just above and just below the band edge at
/// `height - band`, plus a point inside the band but outside the legacy
/// 72-pixel one.
Future<void> _expectBand(P21Driver d, double height, double band) async {
  final edge = height - band;
  for (final sample in <(double, bool)>[
    (edge - 0.5, true),
    (edge + 0.5, false),
    if (band > 73) (height - 72.5, false),
  ]) {
    expect(
      await _doubleTapSeeks(d, sample.$1),
      sample.$2,
      reason: 'double tap y=${sample.$1} band=$band',
    );
    expect(
      await _panLive(d, sample.$1),
      sample.$2,
      reason: 'pan y=${sample.$1} band=$band',
    );
  }
}

/// Phase 21 Step 0b: the double-tap and pan bands against a styled dock.
/// While the controls are up, both gestures ignore the dock's measured band
/// (at least the legacy 72 pixels); a viewport the styled dock cannot seat
/// falls back to the classic dock, whose band is the legacy 72 again rather
/// than the stale styled measurement.
void main() {
  p21Timeouts();

  testWidgets(
    'P21 a styled dock band follows its measured height on a wide viewport and the legacy band on a short one',
    (t) async {
      final d = await _styled(t);
      try {
        await d.hover();
        final wide = _styledExtent(d);
        expect(wide, isNotNull, reason: 'the styled dock is on screen');
        expect(wide, greaterThan(100), reason: 'taller than the legacy band');
        await _expectBand(d, 800, math.max(72, wide!));
        // A 200-pixel window cannot seat the styled dock: classic fallback.
        t.view.physicalSize = const Size(1280, 200);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        expect(_styledExtent(d), isNull, reason: 'classic fallback');
        await _expectBand(d, 200, 72);
        // Back on the wide window the styled band is measured again.
        t.view.physicalSize = const Size(1280, 800);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        expect(_styledExtent(d), wide);
        await _expectBand(d, 800, math.max(72, wide));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a styled dock carrying an info panel bands its full height and falls back on a short viewport',
    (t) async {
      final d = await _styled(
        t,
        screen: const VideoPlayerScreen(
          videoUrl: 'https://p21.test/panel.mp4',
          title: 'P21 panel',
          showChannelName: true,
          channelName: 'Alpha',
          channelNumber: 7,
        ),
      );
      try {
        await d.hover();
        await d.wait(100);
        final plain = d.controls.infoPanel;
        expect(plain, isNotNull, reason: 'the channel panel rides the dock');
        final wide = _styledExtent(d)!;
        expect(wide, greaterThan(100));
        // The reserved panel height is the measured one, not the bound.
        final reserved = d.controls.infoPanelHeight;
        await _expectBand(d, 800, math.max(72, wide));
        t.view.physicalSize = const Size(1280, 200);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        expect(_styledExtent(d), isNull);
        await _expectBand(d, 200, 72);
        t.view.physicalSize = const Size(1280, 800);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        expect(_styledExtent(d), wide);
        expect(d.controls.infoPanelHeight, reserved);
        await _expectBand(d, 800, math.max(72, wide));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 the top band stays the legacy 72 pixels under a styled dock and under its classic fallback',
    (t) async {
      final d = await _styled(t);
      try {
        await d.hover();
        final wide = _styledExtent(d)!;
        expect(wide, greaterThan(100));
        Future<void> expectTop() async {
          for (final sample in <(double, bool)>[
            (71.5, false),
            (72.5, true),
            // Inside the styled dock's height but far from the bottom.
            (wide - 1, true),
          ]) {
            expect(
              await _doubleTapSeeks(d, sample.$1),
              sample.$2,
              reason: 'double tap y=${sample.$1}',
            );
            expect(
              await _panLive(d, sample.$1),
              sample.$2,
              reason: 'pan y=${sample.$1}',
            );
          }
        }

        await expectTop();
        t.view.physicalSize = const Size(1280, 200);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        expect(_styledExtent(d), isNull, reason: 'classic fallback');
        for (final sample in <(double, bool)>[(71.5, false), (72.5, true)]) {
          expect(await _doubleTapSeeks(d, sample.$1), sample.$2);
          expect(await _panLive(d, sample.$1), sample.$2);
        }
        t.view.physicalSize = const Size(1280, 800);
        await d.wait(100);
        await d.hover();
        await d.wait(100);
        await expectTop();
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 the classic dock bands are the legacy 72 pixels at the top and the bottom',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        await d.at(const Duration(seconds: 300));
        await d.hover();
        expect(_styledExtent(d), isNull);
        for (final sample in <(double, bool)>[
          (71.5, false),
          (72.5, true),
          (727.5, true),
          (728.5, false),
        ]) {
          expect(
            await _doubleTapSeeks(d, sample.$1),
            sample.$2,
            reason: 'double tap y=${sample.$1}',
          );
          expect(
            await _panLive(d, sample.$1),
            sample.$2,
            reason: 'pan y=${sample.$1}',
          );
        }
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
