import 'package:debrify/services/storage/detail_page_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/screens/settings/app_theme_page.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  Future<void> pump(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: AppThemeScope(theme: AppThemes.legacy, child: const AppThemePage()),
    ));
    await t.pump();
  }

  tearDown(() => DetailPageStorage.detailPageStyleCached =
      DetailPageStorage.kDetailPageStyleDefault);

  testWidgets('warns when Classic is the details layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    DetailPageStorage.detailPageStyleCached = 'classic';
    await pump(tester);
    expect(find.textContaining('keeps its own look'), findsOneWidget);
  });

  testWidgets('silent under a themed layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    DetailPageStorage.detailPageStyleCached = 'console';
    await pump(tester);
    expect(find.textContaining('keeps its own look'), findsNothing);
  });
}
