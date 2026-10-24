import 'package:debrify/screens/video_player/widgets/dock_style.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/p21_controls_driver.dart';

Future<void> _prefs(
  P21Driver d, {
  String style = 'auto',
  String palette = 'ultraviolet',
  String size = 'auto',
}) async {
  await d.t.runAsync(() async {
    await PlayerAppearanceStorage.setPlayerDockStyle(style);
    await PlayerAppearanceStorage.setPlayerDockPalette(palette);
    await PlayerAppearanceStorage.setPlayerDockSize(size);
  });
}

/// Rebuilds the same State with a new widget configuration.
Future<void> _rebuild(P21Driver d, VideoPlayerScreen screen) async {
  await d.t.pumpWidget(
    MaterialApp(
      navigatorKey: d.f.navigator,
      theme: ThemeData.dark(),
      home: screen,
    ),
  );
  await d.wait(50);
}

/// (dock geometry generation, info-panel generation). A re-measure bumps the
/// panel generation twice: once itself, and once more in the next build,
/// which finds the cleared panel signature changed.
(int, int) _generations(P21Driver d) =>
    (d.controls.geometryGeneration, d.controls.infoPanelGeneration);

void main() {
  p21Timeouts();

  testWidgets('P21 the three dock preferences reach the dock after load', (
    t,
  ) async {
    final d = P21Driver(t);
    await d.initialize();
    try {
      await _prefs(d, style: 'cinema', palette: 'aurum', size: 'large');
      await d.mount(screen: P21Driver.screen());
      expect(d.controls.dockStyle, PlayerDockStyle.cinema);
      expect(d.controls.dockPalette, PlayerDockPalette.aurum);
      expect(d.controls.dockSize, PlayerDockSize.large);
      expect(d.errors, isEmpty);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P21 the first rebuild after the preferences land re-measures once, then identical rebuilds do not',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await _prefs(d, style: 'tiers', size: 'medium');
        await d.mount(screen: P21Driver.screen());
        final (geometry, panel) = _generations(d);
        await _rebuild(d, P21Driver.screen());
        expect(_generations(d), (geometry + 1, panel + 2));
        await _rebuild(d, P21Driver.screen());
        await _rebuild(d, P21Driver.screen());
        expect(_generations(d), (geometry + 1, panel + 2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P21 a viewport, safe-area or text-scale change re-measures the dock and a repeat does not',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await _prefs(d);
        await d.mount(screen: P21Driver.screen());
        await _rebuild(d, P21Driver.screen());
        var (geometry, panel) = _generations(d);
        Future<void> expectBump(Future<void> Function() change) async {
          await change();
          await d.wait(50);
          expect(_generations(d), (geometry + 1, panel + 2));
          (geometry, panel) = _generations(d);
          // The same inputs again: no further bump.
          await _rebuild(d, P21Driver.screen());
          expect(_generations(d), (geometry, panel));
        }

        await expectBump(
          () async => t.view.physicalSize = const Size(1000, 800),
        );
        await expectBump(
          () async => t.view.physicalSize = const Size(1000, 700),
        );
        await expectBump(
          () async => t.view.padding = const FakeViewPadding(top: 30),
        );
        await expectBump(
          () async =>
              t.view.padding = const FakeViewPadding(top: 30, bottom: 24),
        );
        await expectBump(
          () async => t.platformDispatcher.textScaleFactorTestValue = 1.3,
        );
        expect(d.errors, isEmpty);
      } finally {
        t.view.resetPadding();
        t.platformDispatcher.clearTextScaleFactorTestValue();
        await d.close();
      }
    },
  );

  testWidgets('P21 a sub-pixel viewport change keeps the dock measurement', (
    t,
  ) async {
    final d = P21Driver(t);
    await d.initialize();
    try {
      await _prefs(d);
      await d.mount(screen: P21Driver.screen());
      await _rebuild(d, P21Driver.screen());
      final before = _generations(d);
      t.view.physicalSize = const Size(1280.4, 800.3);
      await d.wait(50);
      expect(_generations(d), before, reason: 'rounded to whole pixels');
      // Text scale is compared as a rounded percentage of 100.
      t.platformDispatcher.textScaleFactorTestValue = 1.00496;
      await d.wait(50);
      expect(_generations(d), before, reason: '100.496 rounds to 100');
      t.platformDispatcher.textScaleFactorTestValue = 1.006;
      await d.wait(50);
      expect(_generations(d).$1, before.$1 + 1);
      expect(d.errors, isEmpty);
    } finally {
      t.platformDispatcher.clearTextScaleFactorTestValue();
      await d.close();
    }
  });

  testWidgets(
    'P21 loading default dock preferences still forces one re-measure on the next rebuild',
    (t) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await d.mount(screen: P21Driver.screen());
        expect(d.controls.dockStyle, PlayerDockStyle.classic);
        final (geometry, panel) = _generations(d);
        await _rebuild(d, P21Driver.screen());
        expect(_generations(d), (geometry + 1, panel + 2));
        await _rebuild(d, P21Driver.screen());
        expect(_generations(d), (geometry + 1, panel + 2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  for (final flag in ['hideOptions', 'hideSeekbar']) {
    testWidgets('P21 toggling $flag on the same screen re-measures the dock', (
      t,
    ) async {
      final d = P21Driver(t);
      await d.initialize();
      try {
        await _prefs(d);
        await d.mount(screen: P21Driver.screen());
        await _rebuild(d, P21Driver.screen());
        final (geometry, panel) = _generations(d);
        await _rebuild(
          d,
          P21Driver.screen(
            hideOptions: flag == 'hideOptions',
            hideSeekbar: flag == 'hideSeekbar',
          ),
        );
        expect(_generations(d), (geometry + 1, panel + 2));
        await _rebuild(d, P21Driver.screen());
        expect(_generations(d), (geometry + 2, panel + 4));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    });
  }
}
