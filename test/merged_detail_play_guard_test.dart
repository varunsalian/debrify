import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/merged_series_detail_screen.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/theme/app_theme_scope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('merged detail admits only one playback launch at a time', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final previousStyle = StorageService.detailPageStyleCached;
    StorageService.detailPageStyleCached = 'showcase';
    addTearDown(() => StorageService.detailPageStyleCached = previousStyle);
    final firstLaunch = Completer<void>();
    var launches = 0;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppThemeScope(theme: AppThemes.legacy, child: child!),
        home: MergedDetailScreen(
          item: const StremioMeta(
            id: 'movie-without-external-lookups',
            type: 'movie',
            name: 'Guarded Movie',
          ),
          addon: StremioAddon(
            id: 'test-addon',
            name: 'Test Addon',
            manifestUrl: '',
            baseUrl: '',
          ),
          onResume: () {
            launches++;
            return launches == 1 ? firstLaunch.future : Future<void>.value();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(launches, 1);

    firstLaunch.complete();
    await tester.pump();
    await tester.tap(find.text('Play'));
    await tester.pump();
    expect(launches, 2);
  });
}
