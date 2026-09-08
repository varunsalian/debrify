import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/screens/metadata_explore_page.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('direct discovery is opt-in and reacts to a settings reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: MetadataExploreButton.discover(
            isTelevision: false,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await MetadataPreferencesService.save(
      MetadataPreferences(features: {MetadataFeature.people}),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    await MetadataPreferencesService.save(
      MetadataPreferences(features: {MetadataFeature.discovery}),
    );
    await tester.pumpAndSettle();
    expect(find.text('TMDB Discover'), findsOneWidget);
    await MetadataPreferencesService.save(MetadataPreferences());
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('direct discovery opens without requiring an existing title', (
    tester,
  ) async {
    await MetadataPreferencesService.save(
      MetadataPreferences(features: {MetadataFeature.discovery}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: MetadataExploreButton.discover(
            isTelevision: false,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('TMDB Discover'));
    await tester.pumpAndSettle();
    expect(find.byType(MetadataBrowsePage), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
