import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/settings/quick_play_settings_page.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';

/// TV DPAD reachability of the "Addon priority" list.
///
/// The rows used to live in a shrinkwrapped ReorderableListView — a NESTED
/// scrollable, whose children directional focus traversal never visits: DPAD
/// DOWN from "Prefer torrents" skipped the whole list and landed on "Restore
/// defaults". On TV the rows are now a plain Column.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpTvPage(WidgetTester tester) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const QuickPlaySettingsPage(),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    // The provider enumeration decodes addon JSON on a real isolate, which
    // fake-async pumping never completes — let real async run it out.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pumpAndSettle();
  }

  void seedAddons() {
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([
        for (final name in ['Alpha', 'Beta', 'Gamma'])
          StremioAddon(
            id: 'test.${name.toLowerCase()}',
            name: name,
            manifestUrl: 'https://$name.test/manifest.json',
            baseUrl: 'https://$name.test',
            types: const ['movie', 'series'],
            resources: const ['stream'],
          ).toJson(),
      ]),
    });
  }

  String focusLabel() =>
      FocusManager.instance.primaryFocus?.debugLabel ?? '<none>';

  Future<void> down(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
  }

  Future<void> ok(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  testWidgets('DPAD DOWN walks through every priority row', (tester) async {
    seedAddons();
    await pumpTvPage(tester);

    expect(focusLabel(), 'quick-play-movies-tab');
    await down(tester);
    expect(focusLabel(), 'quick-play-prefer-torrents');
    await down(tester);
    expect(focusLabel(), 'quick-play-max-attempts');
    await down(tester);
    expect(focusLabel(), 'quick-play-priority-stremio:alpha');
    await down(tester);
    expect(focusLabel(), 'quick-play-priority-stremio:beta');
    await down(tester);
    expect(focusLabel(), 'quick-play-priority-stremio:gamma');
    await down(tester);
    expect(focusLabel(), 'quick-play-reset');

    // And back UP re-enters the list from below.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusLabel(), 'quick-play-priority-stremio:gamma');
    expect(tester.takeException(), isNull);
  });

  testWidgets('OK picks a row, DPAD moves it, order persists', (tester) async {
    seedAddons();
    await pumpTvPage(tester);

    await down(tester); // prefer-torrents
    await down(tester); // streams-to-try
    await down(tester); // alpha
    await down(tester); // beta

    await ok(tester); // pick up Beta
    expect(find.text('Moving…'), findsOneWidget);

    // While picked, RIGHT must not let focus wander off the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusLabel(), 'quick-play-priority-stremio:beta');

    // UP moves Beta above Alpha; focus follows the moved row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusLabel(), 'quick-play-priority-stremio:beta');

    await ok(tester); // drop
    expect(find.text('Moving…'), findsNothing);

    final rules = await StorageService.getQuickPlayRules(isMovie: true);
    expect(rules.sourcePriority, [
      'stremio:beta',
      'stremio:alpha',
      'stremio:gamma',
    ]);
    expect(tester.takeException(), isNull);
  });
}
