import 'package:debrify/models/sidebar_configuration.dart';
import 'package:debrify/screens/settings/sidebar_customization_page.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _host() => MaterialApp(
  home: AppThemeScope(
    theme: AppThemes.legacy,
    child: const SidebarCustomizationPage(),
  ),
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlatformUtil.debugSetAndroidTvCached(false);
  });

  tearDown(() {
    PlatformUtil.debugSetAndroidTvCached(null);
    ProfileRuntime.debugReset();
  });

  testWidgets('desktop editor exposes every destination and renames one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(find.byKey(SidebarCustomizationPage.listKey), findsOneWidget);
    final homeRow = find.byKey(
      const ValueKey('sidebar-item-home'),
      skipOffstage: false,
    );
    expect(homeRow, findsOneWidget);
    await tester.ensureVisible(homeRow);
    await tester.pumpAndSettle();

    final homeTapTarget = find.descendant(
      of: homeRow,
      matching: find.byType(InkWell, skipOffstage: false),
      skipOffstage: false,
    );
    expect(homeTapTarget, findsOneWidget);
    tester.widget<InkWell>(homeTapTarget).onTap!();
    await tester.pumpAndSettle();
    final field = tester.widget<TvTextField>(find.byType(TvTextField));
    field.controller.text = 'Start Here';
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Start Here', skipOffstage: false), findsOneWidget);
    expect(
      (await StorageService.getSidebarConfiguration()).labelForId('home'),
      'Start Here',
    );
  });

  testWidgets('TV DPAD can pick up, move, drop, and open rename', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'sidebar-customization-search',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('MOVING', skipOffstage: false), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final moved = await StorageService.getSidebarConfiguration();
    expect(moved.order.take(2), <String>['home', 'search']);
    expect(find.text('MOVING', skipOffstage: false), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('Rename Search'), findsOneWidget);
  });

  testWidgets('TV DPAD reaches rows below the initial viewport and reset', (
    tester,
  ) async {
    PlatformUtil.debugSetAndroidTvCached(true);
    await tester.binding.setSurfaceSize(const Size(960, 540));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    // Make reset actionable while preserving focus on the second row.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    for (var i = 0; i < 10; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'sidebar-customization-settings',
    );
    final settingsRow = find.byKey(const ValueKey('sidebar-item-settings'));
    final editorScroll = find.ancestor(
      of: settingsRow,
      matching: find.byType(SingleChildScrollView),
    );
    expect(editorScroll, findsOneWidget);
    final editorRect = tester.getRect(editorScroll);
    final settingsRect = tester.getRect(settingsRow);
    expect(
      editorRect.overlaps(settingsRect),
      isTrue,
      reason: 'editor viewport $editorRect did not reveal row $settingsRect',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'sidebar-customization-reset',
    );
  });

  testWidgets('reset restores both default order and names', (tester) async {
    await StorageService.setSidebarConfiguration(
      SidebarConfiguration(
        order: const <String>['settings', 'home'],
        labels: const <String, String>{'home': 'Start'},
      ),
    );
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(SidebarCustomizationPage.resetKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect((await StorageService.getSidebarConfiguration()).isDefault, isTrue);
    expect(find.text('Start'), findsNothing);
  });
}
