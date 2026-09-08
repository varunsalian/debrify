import 'package:flutter/services.dart';
import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/screens/settings/metadata_settings_page.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    StremioService.instance.invalidateCache();
  });

  Future<void> open(WidgetTester tester) async {
    final repository = TmdbMetadataRepository(
      token: 'test',
      clientFactory: () => MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('languages')
              ? '[{"iso_639_1":"nl","english_name":"Dutch"}]'
              : '[{"iso_3166_1":"NL","english_name":"Netherlands"}]',
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: MetadataSettingsPage(repository: repository)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'external metadata revision is retained by the next settings edit',
    (tester) async {
      await open(tester);
      await MetadataPreferencesService.save(
        MetadataPreferences(
          providers: {MetadataCategory.information: 'tmdb'},
          region: 'IN',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Posters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('TMDB').last);
      await tester.pumpAndSettle();
      final prefs = await MetadataPreferencesService.load();
      expect(prefs.provider(MetadataCategory.information), 'tmdb');
      expect(prefs.provider(MetadataCategory.posters), 'tmdb');
      expect(prefs.region, 'IN');
    },
  );

  testWidgets('opening settings does not opt anyone into TMDB', (tester) async {
    await open(tester);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(MetadataPreferencesService.key), isNull);
    expect(find.text('Metadata'), findsOneWidget);
    expect(find.text('Current behaviour'), findsWidgets);
  });

  testWidgets('selecting posters preserves all other provider defaults', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Posters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TMDB'));
    await tester.pumpAndSettle();
    final raw = (await SharedPreferences.getInstance()).getString(
      MetadataPreferencesService.key,
    )!;
    final prefs = MetadataPreferences.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    expect(prefs.provider(MetadataCategory.posters), 'tmdb');
    for (final category in MetadataCategory.values.where(
      (c) => c != MetadataCategory.posters,
    )) {
      expect(prefs.provider(category), 'current');
    }
    expect(prefs.features, isEmpty);
    expect(prefs.fallback, isFalse);
  });

  testWidgets('language picker includes TMDB configuration results', (
    tester,
  ) async {
    await open(tester);
    await tester.scrollUntilVisible(find.text('Metadata language'), 350);
    await tester.tap(find.text('Metadata language'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dutch'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Dutch'));
    await tester.pumpAndSettle();
    final prefs = await MetadataPreferencesService.load();
    expect(prefs.language, 'nl');
    expect(prefs.isCurrent, isTrue);
  });
  testWidgets('metadata picker fits a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await open(tester);
    await tester.scrollUntilVisible(find.text('Posters'), 250);
    await tester.tap(find.text('Posters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TMDB'));
    await tester.pumpAndSettle();
    expect(
      (await MetadataPreferencesService.load()).provider(
        MetadataCategory.posters,
      ),
      'tmdb',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider dialog supports directional remote selection', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Posters'));
    await tester.pumpAndSettle();
    final current = find.descendant(
      of: find.byType(SimpleDialog),
      matching: find.text('Current behaviour'),
    );
    Focus.of(tester.element(current)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      (await MetadataPreferencesService.load()).provider(
        MetadataCategory.posters,
      ),
      'tmdb',
    );
    expect(find.byType(SimpleDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
