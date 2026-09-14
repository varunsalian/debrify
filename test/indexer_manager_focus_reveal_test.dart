import 'dart:convert';

import 'package:debrify/models/indexer_manager_config.dart';
import 'package:debrify/screens/settings/indexer_managers_settings_page.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final control in ['switch', 'Test connection', 'Edit', 'Delete']) {
    testWidgets('$control reveals an offscreen manager on focus', (
      tester,
    ) async {
      PlatformUtil.debugSetAndroidTvCached(true);
      addTearDown(() => PlatformUtil.debugSetAndroidTvCached(null));
      tester.view.physicalSize = const Size(960, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SecretVault.debugReset(deviceIdOverride: 'indexer-focus-test');
      addTearDown(SecretVault.debugReset);
      SharedPreferences.setMockInitialValues({
        'indexer_manager_configs_v1': [
          for (var i = 0; i < 12; i++)
            jsonEncode(
              IndexerManagerConfig(
                id: '$i',
                name: 'Manager $i',
                type: IndexerManagerType.jackett,
                baseUrl: 'https://example.invalid/$i',
                apiKey: 'test',
              ).toJson(),
            ),
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppThemeScope(theme: AppThemes.legacy, child: child!),
          home: const IndexerManagersSettingsPage(),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final controls = control == 'switch'
          ? find.byType(Switch)
          : find.byTooltip(control);
      expect(controls, findsNWidgets(12));
      final scroll = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      final viewport = tester.getRect(find.byType(SingleChildScrollView).first);
      // Programmatic DPAD handoffs bypass traversal's implicit reveal.
      Future<void> focusAndCheck(Finder target) async {
        final focus = find
            .descendant(of: target, matching: find.byType(Focus))
            .last;
        final child = tester.widget<Focus>(focus).child;
        final node = Focus.of(tester.element(find.byWidget(child)));
        node.requestFocus();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(node.hasFocus, isTrue);
        final rect = tester.getRect(target);
        expect(rect.top, greaterThanOrEqualTo(viewport.top));
        expect(rect.bottom, lessThanOrEqualTo(viewport.bottom));
      }

      expect(tester.getRect(controls.last).top, greaterThan(viewport.bottom));
      await focusAndCheck(controls.last);
      expect(scroll.position.pixels, greaterThan(0));
      await focusAndCheck(controls.first);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
