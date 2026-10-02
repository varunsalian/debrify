import 'package:debrify/screens/settings_screen.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Start in legacy mode with empty accounts, at the production default state.
/// Inspect the index before async summaries publish; no network account exists.
Future<State<SettingsScreen>> pumpSettingsHub(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  ProfileRuntime.debugReset();
  ProfileRuntime.initializeLegacy();
  addTearDown(ProfileRuntime.debugReset);
  PackageInfo.setMockInitialValues(
    appName: 'Debrify',
    packageName: 'test.debrify',
    version: '1.0',
    buildNumber: '1',
    buildSignature: '',
  );
  await tester.pumpWidget(
    MaterialApp(
      home: AppThemeScope(
        theme: AppThemes.byId('spotlight'),
        child: const Scaffold(body: SettingsScreen()),
      ),
    ),
  );
  return tester.state<State<SettingsScreen>>(find.byType(SettingsScreen));
}
