import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/screens/settings/quick_play_settings_page.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppThemeScope(
          theme: AppThemes.legacy,
          child: const QuickPlaySettingsPage(),
        ),
      ),
    );
    // _load intentionally awaits three independent preference reads. Pump
    // their microtask turns even when no frame has been scheduled yet.
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('default profile explains the shipped movie behavior', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);
    expect(find.text('Debrify default'), findsWidgets);
    expect(find.text('Torrent engines'), findsOneWidget);
    expect(find.text('Addon fallback'), findsOneWidget);
    expect(find.textContaining('today\'s shipped behavior'), findsOneWidget);
  });

  testWidgets('movie and series tabs expose visibly different default routes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('quick-play-tab-series')));
    await tester.pumpAndSettle();
    expect(find.text('Series pack'), findsOneWidget);
    expect(find.text('Exact episode'), findsOneWidget);
    expect(find.text('Prefer a reusable pack'), findsOneWidget);
  });

  testWidgets('series advanced source order names the compatibility route', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('quick-play-tab-series')));
    await tester.pumpAndSettle();
    final advanced = find.text('Advanced control');
    await tester.ensureVisible(advanced);
    await tester.pumpAndSettle();
    await tester.tap(advanced);
    await tester.pumpAndSettle();
    expect(find.text('Today\'s series route'), findsOneWidget);
    expect(
      find.textContaining('packs search both; episodes use addon fallback'),
      findsOneWidget,
    );
  });

  testWidgets('DPAD traverses tabs, presets, then the first useful setting', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await pumpPage(tester);

    final movieTabInk = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('quick-play-tab-movie')),
        matching: find.byType(InkWell),
      ),
    );
    movieTabInk.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-play-preset-0',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-play-preset-1',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-play-filters',
    );
  });

  testWidgets('compact phone layout has no render overflow', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DPAD follows the one-column preset geometry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);

    final movieTabInk = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('quick-play-tab-movie')),
        matching: find.byType(InkWell),
      ),
    );
    movieTabInk.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-play-preset-1',
    );
  });

  testWidgets('DPAD follows the two-column preset geometry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpPage(tester);

    final movieTabInk = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('quick-play-tab-movie')),
        matching: find.byType(InkWell),
      ),
    );
    movieTabInk.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'quick-play-preset-3',
    );
  });
}
