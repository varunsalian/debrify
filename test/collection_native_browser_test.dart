import 'dart:convert';
import 'dart:async';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/services/collection_native_source_service.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      HomeCollectionsStore.folderLayoutKey: 'rows',
    });
    StremioService.instance.invalidateCache();
  });

  HomeCollection collection({String? viewMode, bool unknown = false}) =>
      HomeCollection(
        id: 'native',
        title: 'Native collection',
        viewMode: viewMode,
        folders: [
          HomeCollectionFolder(
            id: 'f',
            title: 'Folder',
            sources: [
              CollectionCatalogSource.fromJson({
                'provider': 'tmdb',
                'tmdbSourceType': 'DISCOVER',
                'title': 'New movies',
              })!,
              if (unknown)
                CollectionCatalogSource.fromJson({
                  'provider': 'future',
                  'title': 'Unavailable',
                })!,
            ],
          ),
        ],
      );

  CollectionNativeSourceService service({int status = 200}) =>
      CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'results': [
                {'id': 42, 'title': 'Native movie'},
              ],
              'total_pages': 1,
            }),
            status,
          ),
        ),
      );

  for (final tv in [false, true]) {
    testWidgets(
      'native folder browses without addons; imported tabs win (TV $tv)',
      (tester) async {
        await tester.binding.setSurfaceSize(
          tv ? const Size(1280, 720) : const Size(390, 844),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final native = service();
        addTearDown(native.close);
        StremioMeta? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: collection(viewMode: 'TABBED_GRID'),
              nativeSources: native,
              isTelevision: tv,
              onOpenItem: (item) => opened = item,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SeeAllPosterGrid), findsOneWidget);
        final dropdowns = tester.widgetList<StremioDropdown<int>>(
          find.byType(StremioDropdown<int>),
        );
        if (tv) expect(dropdowns.any((d) => d.label == 'List'), true);
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(grid.items.single.name, 'Native movie');
        if (tv) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
        } else {
          grid.onOpen(grid.items.single);
        }
        expect(opened?.id, 'tmdb:42');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('native See all pushes a grid and Back restores its rail', (
    tester,
  ) async {
    final native = service();
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'FOLLOW_LAYOUT'),
          nativeSources: native,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('See all'), findsOneWidget);
    await tester.tap(find.text('See all'));
    await tester.pumpAndSettle();
    final child = tester.widget<CollectionFolderScreen>(
      find.byType(CollectionFolderScreen),
    );
    expect(child.sourceKey, collection().folders.single.sources.single.key);
    expect(find.text('See all'), findsNothing);
    final grid = tester.widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid));
    expect(grid.items.single.name, 'Native movie');
    Navigator.of(tester.element(find.byType(SeeAllPosterGrid))).pop();
    await tester.pumpAndSettle();
    expect(find.text('See all'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final action in ['cancel', 'replace', 'refresh']) {
    final cancel = action == 'cancel';
    final refresh = action == 'refresh';
    testWidgets('TV pending title handles $action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <String, Completer<http.Response>>{};
      var opening = false;
      final native = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        enrichmentBudget: const Duration(seconds: 10),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            if (!opening) return http.Response('{}', 503);
            final id = request.url.path.split('/')[3];
            return requests
                .putIfAbsent(id, Completer<http.Response>.new)
                .future;
          }
          return http.Response(
            '{"results":[{"id":42,"title":"First"},{"id":43,"title":"Second"}],"total_pages":1}',
            200,
          );
        }),
      );
      addTearDown(native.close);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(viewMode: 'TABBED_GRID'),
            nativeSources: native,
            isTelevision: true,
            onOpenItem: (m) => opened.add(m.name),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await HomeCollectionsStore.instance.saveCollections([
        collection(viewMode: 'TABBED_GRID'),
      ]);
      opening = true;
      final grid = tester.widget<SeeAllPosterGrid>(
        find.byType(SeeAllPosterGrid),
      );
      grid.onOpen(grid.items.first);
      await tester.pump();
      expect(find.text('Opening First…'), findsOneWidget);
      if (cancel) {
        await tester.tap(find.text('Cancel'));
        await tester.pump();
      } else if (refresh) {
        MainPageBridge.notifyHomeSettingsChanged();
        await tester.pump();
        await tester.pump();
      } else {
        grid.onOpen(grid.items.last);
        await tester.pump();
        expect(find.text('Opening Second…'), findsOneWidget);
      }
      requests['42']!.complete(http.Response('{"imdb_id":"tt42"}', 200));
      await tester.pump();
      expect(opened, refresh ? ['First'] : isEmpty);
      if (!cancel && !refresh) {
        requests['43']!.complete(http.Response('{"imdb_id":"tt43"}', 200));
      }
      await tester.pumpAndSettle();
      expect(opened, cancel ? isEmpty : [refresh ? 'First' : 'Second']);
      expect(find.textContaining('Opening '), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('opening a native title retries failed IMDb enrichment', (
    tester,
  ) async {
    var lookups = 0;
    final native = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/external_ids')) {
          lookups++;
          return lookups == 1
              ? http.Response('{}', 503)
              : http.Response('{"imdb_id":"tt1234567"}', 200);
        }
        return http.Response(
          '{"results":[{"id":42,"title":"Film"}],"total_pages":1}',
          200,
        );
      }),
    );
    addTearDown(native.close);
    StremioMeta? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID'),
          nativeSources: native,
          onOpenItem: (item) => opened = item,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<SeeAllPosterGrid>(find.byType(SeeAllPosterGrid));
    expect(grid.items.single.id, 'tmdb:42');
    grid.onOpen(grid.items.single);
    await tester.pumpAndSettle();
    expect(lookups, 2);
    expect(opened?.id, 'tt1234567');
  });

  testWidgets(
    'partial unsupported sources remain visible as actionable issues',
    (tester) async {
      final native = service();
      addTearDown(native.close);
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionFolderScreen(
            collection: collection(viewMode: 'TABBED_GRID', unknown: true),
            nativeSources: native,
            onOpenItem: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 source(s) need attention'), findsOneWidget);
      await tester.tap(find.text('1 source(s) need attention'));
      await tester.pumpAndSettle();
      expect(find.text('Unsupported provider: future'), findsOneWidget);
    },
  );

  testWidgets('provider denial is shown rather than an empty addon message', (
    tester,
  ) async {
    final native = service(status: 401);
    addTearDown(native.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: collection(viewMode: 'TABBED_GRID'),
          nativeSources: native,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('TMDB denied access'), findsOneWidget);
    expect(find.text('No matching addon installed'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });
}
