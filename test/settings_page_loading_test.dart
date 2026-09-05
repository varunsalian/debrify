import 'dart:async';

import 'package:debrify/screens/settings/discover_layout_page.dart';
import 'package:debrify/screens/settings/provider_settings_page.dart';
import 'package:debrify/screens/settings/simkl_settings_page.dart';
import 'package:debrify/screens/settings/widgets/settings_load_error.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
  });
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
  });

  for (final entry in <(String, Widget, String)>[
    ('Discover', const DiscoverLayoutPage(), 'discover_layout'),
    ('Provider', const ProviderSettingsPage(), 'torbox_api_key'),
    ('Simkl', const SimklSettingsPage(), 'simkl_access_token'),
  ]) {
    final (label, page, corruptKey) = entry;
    testWidgets('$label read error stops loading and can retry', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({corruptKey: false});
      await _mount(tester, page);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SettingsLoadError), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.get(corruptKey),
        false,
        reason: 'Error UI must not save a fallback.',
      );
      await prefs.remove(corruptKey);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsLoadError), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$label times out and ignores late completion until retry', (
      tester,
    ) async {
      final store = _DelayedPreferences();
      SharedPreferencesStorePlatform.instance = store;
      await _mount(tester, page);
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SettingsLoadError), findsOneWidget);
      store.release.complete();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsLoadError), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsLoadError), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unavailable provider does not erase the saved selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'default_torrent_provider_v1': 'torbox',
    });
    await _mount(tester, const ProviderSettingsPage());
    await tester.pumpAndSettle();
    expect(find.byType(SettingsLoadError), findsNothing);
    expect(
      (await SharedPreferences.getInstance()).getString(
        'default_torrent_provider_v1',
      ),
      'torbox',
    );
  });
}

Future<void> _mount(WidgetTester tester, Widget page) => tester.pumpWidget(
  MaterialApp(
    home: AppThemeScope(theme: AppThemes.byId('spotlight'), child: page),
  ),
);

class _DelayedPreferences extends InMemorySharedPreferencesStore {
  _DelayedPreferences() : super.empty();
  final release = Completer<void>();

  @override
  Future<Map<String, Object>> getAll() async {
    await release.future;
    return super.getAll();
  }
}
