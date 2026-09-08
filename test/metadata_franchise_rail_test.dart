import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/metadata_explore_service.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/widgets/catalog_item_tile.dart';
import 'package:debrify/widgets/metadata_franchise_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const item = StremioMeta(id: 'tmdb:1', type: 'movie', name: 'Movie');

  testWidgets(
    'franchise section is absent by default and restores that state',
    (tester) async {
      var reads = 0;
      StremioMeta? opened;
      final service = MetadataExploreService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            reads++;
            return http.Response(
              jsonEncode(
                request.url.path.contains('/collection/')
                    ? {
                        'name': 'Movie saga',
                        'parts': [
                          {'id': 1, 'title': 'Movie'},
                          {'id': 2, 'title': 'Sequel'},
                        ],
                      }
                    : {
                        'belongs_to_collection': {'id': 10},
                      },
              ),
              200,
            );
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MetadataFranchiseRail(
                item: item,
                service: service,
                onOpen: (item) => opened = item,
                isTelevision: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reads, 0);
      expect(find.byType(CatalogItemTile), findsNothing);
      await MetadataPreferencesService.save(
        MetadataPreferences(features: {MetadataFeature.franchises}),
      );
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('Movie saga'), findsOneWidget);
      expect(find.byType(CatalogItemTile), findsNWidgets(2));
      Focus.of(tester.element(find.text('Movie').last)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened?.id, 'tmdb:2');
      await MetadataPreferencesService.save(MetadataPreferences());
      await tester.pumpAndSettle();
      expect(find.text('Movie saga'), findsNothing);
      expect(find.byType(CatalogItemTile), findsNothing);
      expect(reads, 2);
    },
  );

  testWidgets('disabling franchise while it loads rejects the late section', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final service = MetadataExploreService(
      repository: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient((_) => pending.future),
      ),
    );
    await MetadataPreferencesService.save(
      MetadataPreferences(features: {MetadataFeature.franchises}),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetadataFranchiseRail(
            item: item,
            service: service,
            onOpen: (_) {},
            isTelevision: true,
          ),
        ),
      ),
    );
    await tester.pump();
    await MetadataPreferencesService.save(MetadataPreferences());
    await tester.pump();
    pending.complete(http.Response('{}', 200));
    await tester.pumpAndSettle();
    expect(find.byType(CatalogItemTile), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
