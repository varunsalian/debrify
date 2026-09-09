import 'dart:convert';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/screens/collections/collection_folder_screen.dart';
import 'package:debrify/screens/settings/collections_settings_page.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/widgets/see_all/see_all_poster_grid.dart';
import 'package:debrify/widgets/see_all/stremio_dropdown.dart';
import 'package:debrify/widgets/see_all/discover_card_settings_scope.dart';
import 'package:debrify/widgets/collections/collection_list_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final addon = StremioAddon(
    id: 'responsive',
    name: 'A very long addon name that should never overflow a phone screen',
    manifestUrl: 'https://example.invalid/responsive/manifest.json',
    baseUrl: 'https://example.invalid/responsive',
    resources: ['catalog'],
    catalogs: const [
      StremioAddonCatalog(
        id: 'popular',
        type: 'movie',
        name: 'Popular films with a very long title',
      ),
      StremioAddonCatalog(id: 'recent', type: 'movie', name: 'Recent'),
    ],
  );
  const collection = HomeCollection(
    id: 'responsive',
    title: 'Streaming services with a very long collection title',
    folders: [
      HomeCollectionFolder(
        id: 'folder',
        title: 'Netflix and other streaming services with a very long title',
        coverImageUrl: 'https://example.invalid/cover.png',
        sources: [
          CollectionCatalogSource(
            addonId: 'responsive',
            type: 'movie',
            catalogId: 'popular',
          ),
          CollectionCatalogSource(
            addonId: 'responsive',
            type: 'movie',
            catalogId: 'recent',
          ),
        ],
      ),
    ],
  );
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    StremioService.instance.invalidateCache();
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> seed(WidgetTester tester, String layout) async {
    SharedPreferences.setMockInitialValues({
      'stremio_addons_v1': jsonEncode([addon.toJson()]),
      HomeCollectionsStore.folderLayoutKey: layout,
      HomeCollectionsStore.prefsKey: jsonEncode([collection.toJson()]),
    });
    await tester.runAsync(() async {
      await StremioService.instance.getCatalogAddons();
      await http.runWithClient(
        () async {
          for (final catalog in addon.catalogs) {
            await StremioService.instance.fetchCatalog(addon, catalog);
          }
        },
        () => MockClient(
          (_) async => http.Response(
            jsonEncode({
              'metas': [
                for (var i = 0; i < 100; i++)
                  {'id': 'tt$i', 'type': 'movie', 'name': 'Title $i'},
              ],
            }),
            200,
          ),
        ),
      );
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(768, 1024),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final layout in ['rows', 'tabs']) {
      testWidgets('$layout folder fits $size and refreshes after removal', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await seed(tester, layout);
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionFolderScreen(
              collection: collection,
              isTelevision: size.width >= 1280,
              onOpenItem: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(layout == 'rows' ? CollectionListGallery : SeeAllPosterGrid), findsWidgets);
        final narrow = size.width < 640;
        if (narrow) {
          await tester.tap(find.text('Filters'));
          await tester.pumpAndSettle();
        }
        final selector = find.byWidgetPredicate(
          (w) =>
              w is StremioDropdown &&
              w.label == (layout == 'tabs' ? 'List' : 'View'),
        );
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('All').last);
        await tester.pumpAndSettle();
        if (narrow) {
          await tester.tap(find.byIcon(Icons.close_rounded));
          await tester.pumpAndSettle();
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(SeeAllPosterGrid), findsOneWidget);
        final grid = tester.widget<SeeAllPosterGrid>(
          find.byType(SeeAllPosterGrid),
        );
        expect(
          grid.items,
          hasLength(100),
          reason: 'Overlapping lists are deduplicated in All',
        );
        expect(grid.items.every((m) => m.sourceAddon?.id == addon.id), true);
        await HomeCollectionsStore.instance.clear();
        MainPageBridge.notifyHomeSettingsChanged();
        await tester.pumpAndSettle();
        expect(find.text('This collection has no folders'), findsOneWidget);
        expect(find.byType(SeeAllPosterGrid), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('damaged settings offer an in-app reset', (tester) async {
    await seed(tester, 'rows');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(HomeCollectionsStore.prefsKey, '{broken');
    await tester.pumpWidget(const MaterialApp(home: CollectionsSettingsPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reset damaged collections'));
    await tester.tap(find.text('Reset damaged collections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reset collections'));
    await tester.pumpAndSettle();
    expect(find.text('Damaged collection data'), findsNothing);
    expect(
      (await HomeCollectionsStore.instance.getInventory()).hadCorruption,
      false,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplicate sources sharing a catalog produce one rail', (
    tester,
  ) async {
    await seed(tester, 'rows');
    final original = collection.folders.first.sources.first;
    final duplicate = HomeCollection(
      id: collection.id,
      title: collection.title,
      folders: [
        HomeCollectionFolder(
          id: 'f',
          title: 'F',
          sources: [
            original,
            CollectionCatalogSource(
              addonId: original.addonId,
              type: original.type,
              catalogId: original.catalogId,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionFolderScreen(
          collection: duplicate,
          isTelevision: true,
          onOpenItem: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<CollectionListGallery>(find.byType(CollectionListGallery)).lists, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a list preserves hidden Discover card details', (tester) async {
    await seed(tester, 'rows');
    await tester.pumpWidget(MaterialApp(
      home: DiscoverCardSettingsScope(
        showTitles: false, showRatings: false, showTypeTags: false,
        child: CollectionFolderScreen(
          collection: collection, onOpenItem: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    tester.widget<CollectionListGallery>(find.byType(CollectionListGallery)).onOpen(0);
    await tester.pumpAndSettle();
    expect(find.byType(SeeAllPosterGrid), findsOneWidget);
    final scope = DiscoverCardSettingsScope.maybeOf(tester.element(find.byType(SeeAllPosterGrid)));
    expect(scope, isNotNull);
    expect(scope!.showTitles, isFalse);
    expect(scope.showRatings, isFalse);
    expect(scope.showTypeTags, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('open settings refreshes after remote collection changes', (
    tester,
  ) async {
    await seed(tester, 'rows');
    await tester.pumpWidget(const MaterialApp(home: CollectionsSettingsPage()));
    await tester.pumpAndSettle();
    expect(find.text(collection.title), findsOneWidget);
    await HomeCollectionsStore.instance.clear();
    MainPageBridge.notifyHomeSettingsChanged();
    await tester.pumpAndSettle();
    expect(find.text(collection.title), findsNothing);
    expect(find.text('No collections yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paste dialog remains usable with landscape keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seed(tester, 'rows');
    await tester.pumpWidget(const MaterialApp(home: CollectionsSettingsPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Paste JSON'));
    await tester.tap(find.text('Paste JSON'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 140);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byType(TextField),
      jsonEncode([
        const HomeCollection(id: 'pasted', title: 'Pasted').toJson(),
      ]),
    );
    await tester.tap(find.widgetWithText(TextButton, 'Import'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      (await HomeCollectionsStore.instance.getCollections()).map((c) => c.id),
      contains('pasted'),
    );
    expect(find.text('Imported 1 collection'), findsOneWidget);
  });

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(1280, 720),
  ]) {
    testWidgets(
      'settings and long collection dialog fit $size with large text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await seed(tester, 'rows');
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
            home: const CollectionsSettingsPage(),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text(collection.title));
        await tester.tap(find.text(collection.title));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
