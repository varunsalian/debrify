import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/settings_widgets_fixture.dart';
import '../../../support/settings_widgets_theme_table.dart';

void main() {
  final expected =
      jsonDecode(
            File(
              'test/features/settings_widgets/presentation/fixtures/settings_widgets_theme_table.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  for (final look in ['legacy', 'spotlight', 'broadsheet']) {
    testWidgets('resolved settings theme table look=$look', (tester) async {
      await settingsWidgetsCase(tester, (f) async {
        f.app = AppThemes.byId(look);
        f.base =
            (f.app.brightness == Brightness.light
                    ? ThemeData.light()
                    : ThemeData.dark())
                .copyWith(platform: TargetPlatform.android);
        if (look == 'broadsheet') expect(f.app.brightness, Brightness.light);
        Map<String, Object?>? actual;
        await tester.pumpWidget(
          f.host(
            Builder(
              builder: (context) {
                actual = settingsThemeTable(settingsPageTheme(context));
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(actual, expected[look]);
      });
    });
  }
}
