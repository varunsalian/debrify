import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:debrify/screens/settings/collections_settings_page.dart';
import 'package:debrify/services/home_collections_store.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/screens/collections/collection_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(900, 700),
    const Size(1920, 1080),
  ]) {
    testWidgets('collection editor fits ${size.width.toInt()}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(home: CollectionEditorScreen(addons: [])),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create collection'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter Collection title'), findsOneWidget);
    });
  }

  for (final kind in ['DISCOVER', 'COMPANY', 'NETWORK']) {
    for (final edit in [false, true]) {
      testWidgets('existing $kind filters can save (edited: $edit)', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1000, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final originalSource = CollectionCatalogSource.fromJson({
          'provider': 'tmdb',
          'tmdbSourceType': kind,
          'tmdbId': 42,
          'title': 'Existing source',
          'filters': {'withGenres': '28', 'year': 2025},
        })!;
        final original = HomeCollection(
          id: 'c',
          title: 'Collection',
          folders: [
            HomeCollectionFolder(
              id: 'f',
              title: 'Folder',
              sources: [originalSource],
            ),
          ],
        );
        HomeCollection? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    saved = await Navigator.of(context).push<HomeCollection>(
                      MaterialPageRoute(
                        builder: (_) => CollectionEditorScreen(
                          collection: original,
                          addons: const [],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Folder'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Existing source · tmdb'));
        await tester.tap(find.text('Existing source · tmdb'));
        await tester.pumpAndSettle();
        if (edit) {
          final field = find.widgetWithText(TextFormField, 'Include genre IDs');
          await tester.ensureVisible(field);
          await tester.enterText(field, '35');
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Edit folder'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(saved!.folders.single.sources.single.filters, {
          'withGenres': edit ? '35' : '28',
          'year': 2025,
        });
        expect(originalSource.filters, {'withGenres': '28', 'year': 2025});
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('create a collection with folder and native source', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    HomeCollection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<HomeCollection>(
                  MaterialPageRoute(
                    builder: (_) => const CollectionEditorScreen(addons: []),
                  ),
                );
              },
              child: const Text('Create'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Collection title'),
      'My collection',
    );
    await tester.tap(find.text('Add folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Folder title'),
      'New movies',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Cover emoji'),
      '🎬',
    );
    await tester.scrollUntilVisible(
      find.text('Add source'),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'List title'),
      'Discover',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.title, 'My collection');
    expect(result!.folders.single.coverEmoji, '🎬');
    expect(result!.folders.single.sources.single.provider, 'tmdb');
    expect(result!.folders.single.sources.single.tmdbSourceType, 'DISCOVER');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Save validates fields after they scroll out of view', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: CollectionEditorScreen(
          addons: const [],
          collection: HomeCollection(
            id: 'large',
            title: '',
            folders: [
              for (var i = 0; i < 25; i++)
                HomeCollectionFolder(id: '$i', title: 'Folder $i'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add folder'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Edit collection'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enter Collection title'),
      -500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enter Collection title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'settings edit saves folder order and exports native definitions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = HomeCollection(
        id: 'editable',
        title: 'Editable collection',
        folders: [
          const HomeCollectionFolder(id: 'first', title: 'First'),
          HomeCollectionFolder(
            id: 'second',
            title: 'Second',
            coverEmoji: '⭐',
            sources: [
              CollectionCatalogSource.fromJson({
                'provider': 'trakt',
                'traktListId': 5,
                'title': 'Public list',
              })!,
            ],
          ),
        ],
      );
      SharedPreferences.setMockInitialValues({
        HomeCollectionsStore.prefsKey: jsonEncode([original.toJson()]),
      });
      StremioService.instance.invalidateCache();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: CollectionsSettingsPage()),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Editable collection'));
      await tester.tap(find.text('Editable collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved =
          (await HomeCollectionsStore.instance.getCollections()).single;
      expect(saved.folders.map((f) => f.id), ['second', 'first']);
      expect(original.folders.map((f) => f.id), ['first', 'second']);
      await tester.ensureVisible(find.text('Editable collection'));
      await tester.tap(find.text('Editable collection'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export JSON'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy JSON'));
      await tester.pumpAndSettle();
      final exported = HomeCollectionParser.parse(copied!).single;
      expect(exported.toJson(), saved.toJson());
      expect(exported.folders.first.sources.single.traktListId, 5);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('editing and cancelling does not mutate original collection', (
    tester,
  ) async {
    const original = HomeCollection(
      id: 'c',
      title: 'Original',
      folders: [HomeCollectionFolder(id: 'f', title: 'Folder')],
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: CollectionEditorScreen(collection: original, addons: []),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Collection title'),
      'Changed',
    );
    expect(original.title, 'Original');
    expect(original.folders.single.title, 'Folder');
  });
}
