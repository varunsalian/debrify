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

  testWidgets('Restore defaults re-enables all optional features and restores the cast default', (tester) async {
    await MetadataPreferencesService.save(MetadataPreferences(
      providers: {for (final c in MetadataCategory.values) c: 'current'},
      features: {},
      fallback: true,
      language: 'hi-IN', artworkLanguage: 'original',
      trailerLanguage: 'hi-IN', region: 'IN',
    ));
    await open(tester);
    await tester.scrollUntilVisible(find.text('Restore defaults'), 400);
    await tester.tap(find.text('Restore defaults'));
    await tester.pumpAndSettle();
    final prefs = await MetadataPreferencesService.load();
    expect(prefs.toJson(), MetadataPreferences().toJson());
    expect(prefs.features, MetadataFeature.values.toSet());
    expect(prefs.provider(MetadataCategory.credits),
      const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN').trim().isEmpty
          ? MetadataPreferences.current : MetadataPreferences.tmdb);
  });

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

  testWidgets('opening settings does not persist defaults', (tester) async {
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
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('TMDB')));
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
      expect(prefs.provider(category), category == MetadataCategory.credits ? MetadataPreferences.defaultCreditsProvider : 'current');
    }
    expect(prefs.features, MetadataFeature.values.toSet());
    expect(prefs.fallback, isFalse);
  });

  testWidgets('language controls follow their consumers and preserve saved values', (tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    Future<bool> enabled(String title) async {
      return tester.widget<ListTile>(find.ancestor(of: find.text(title), matching: find.byType(ListTile))).enabled;
    }
    expect(await enabled('Metadata language'), isTrue);
    expect(await enabled('Artwork language'), isFalse);
    expect(await enabled('Trailer language'), isFalse);
    expect(await enabled('Country / region'), isTrue);
    var prefs = MetadataPreferences(providers: {MetadataCategory.posters: 'tmdb'},
      language: 'hi-IN', region: 'IN');
    await MetadataPreferencesService.save(prefs);
    await tester.pumpAndSettle();
    expect(await enabled('Metadata language'), isTrue);
    expect(await enabled('Artwork language'), isTrue);
    expect(await enabled('Trailer language'), isFalse);
    prefs = prefs.copyWith(providers: {MetadataCategory.trailers: 'tmdb'}, features: {MetadataFeature.availability});
    await MetadataPreferencesService.save(prefs);
    await tester.pumpAndSettle();
    expect(await enabled('Trailer language'), isTrue);
    expect(await enabled('Country / region'), isTrue);
    await MetadataPreferencesService.save(prefs.copyWith(providers: {}, features: {}));
    await tester.pumpAndSettle();
    expect(await enabled('Country / region'), isFalse);
    final saved = await MetadataPreferencesService.load();
    expect(saved.language, 'hi-IN');
    expect(saved.region, 'IN');
  });

  testWidgets('language picker includes TMDB configuration results', (
    tester,
  ) async {
    await open(tester);
    await MetadataPreferencesService.save(MetadataPreferences(
      providers: {MetadataCategory.information: MetadataPreferences.tmdb}));
    await tester.pumpAndSettle();
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
    expect(prefs.provider(MetadataCategory.information), MetadataPreferences.tmdb);
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
    await tester.tap(find.descendant(of: find.byType(SimpleDialog), matching: find.text('TMDB')));
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
