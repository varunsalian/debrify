import 'dart:convert';
import 'package:debrify/screens/settings/stream_badges_settings_page.dart';
import 'package:debrify/services/stream_badges_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('oversized synced presets show a warning and can be disabled', (
    tester,
  ) async {
    final source = StreamBadgeSource(
      id: 'old',
      name: 'Old preset',
      json: jsonEncode({
        'filters': [
          for (var i = 0; i < 513; i++) {'name': 'Rule $i', 'pattern': 'x'},
        ],
      }),
    );
    SharedPreferences.setMockInitialValues({
      StreamBadgesService.sourcesKey: jsonEncode([source.toJson()]),
    });
    final svc = StreamBadgesService.instance;
    svc.resetProfileScope();
    addTearDown(svc.resetProfileScope);
    await tester.pumpWidget(
      const MaterialApp(home: StreamBadgesSettingsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many active badge rules'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await svc.setSourceEnabled('old', false);
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many active badge rules'), findsNothing);
    expect((await svc.getSources()).single.enabled, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('corrupt presets offer recovery instead of continuous loading', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      StreamBadgesService.sourcesKey: 'broken',
    });
    StreamBadgesService.instance.resetProfileScope();
    await tester.pumpWidget(
      const MaterialApp(home: StreamBadgesSettingsPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Reset presets'), findsOneWidget);
    await tester.tap(find.text('Reset presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Show stream badges'), findsOneWidget);
    expect(await StreamBadgesService.instance.getSources(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
