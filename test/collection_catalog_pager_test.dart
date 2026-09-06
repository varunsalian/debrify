import 'dart:async';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/collection_catalog_pager.dart';
import 'package:debrify/services/collection_folder_loader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final addon = StremioAddon(
    id: 'a',
    name: 'A',
    manifestUrl: 'https://example.invalid/manifest.json',
    baseUrl: 'https://example.invalid',
    catalogs: const [
      StremioAddonCatalog(id: 'popular', type: 'movie', name: 'Popular'),
    ],
  );
  StremioMeta meta(String id, {String type = 'movie'}) =>
      StremioMeta(id: id, type: type, name: id);
  CollectionCatalogPager pager(CatalogFetch fetch) => CollectionCatalogPager(
    addon: addon,
    catalog: addon.catalogs.single,
    fetch: fetch,
  );
  test(
    'watched-only collection windows remain resumable in rails and All',
    () async {
      Future<List<StremioMeta>> fetch(
        StremioAddon a,
        StremioAddonCatalog c, {
        int skip = 0,
        String? genre,
        void Function(int)? onRawCount,
      }) async {
        onRawCount?.call(skip < 10 ? 1 : 0);
        return skip < 10 ? [meta('$skip')] : [];
      }

      bool hides(StremioMeta m) => int.parse(m.id) < 8;
      final rail = CollectionCatalogPager(
        addon: addon,
        catalog: addon.catalogs.single,
        fetch: fetch,
        hides: hides,
      );
      expect(await rail.nextPage(), isEmpty);
      expect(rail.exhausted, isFalse);
      expect(rail.skip, 8);
      expect((await rail.nextPage()).single.id, '8');
      final folder = HomeCollectionFolder(
        id: 'filtered',
        title: 'Filtered',
        sources: [
          CollectionCatalogSource(
            addonId: addon.id,
            catalogId: addon.catalogs.single.id,
            type: 'movie',
          ),
        ],
      );
      final all = CollectionFolderLoader(
        folder: folder,
        installedAddons: [addon],
        fetch: fetch,
        hides: hides,
      );
      expect(await all.nextPage(), isEmpty);
      expect(all.exhausted, isFalse);
      expect(all.hasErrors, isTrue);
      expect(all.hasLoadFailures, isFalse);
      expect((await all.nextPage()).single.id, '8');
      expect(all.hasErrors, isFalse);
    },
  );

  test(
    'transport failure preserves cursor and successful retry preserves source',
    () async {
      var failed = true;
      final requested = <int>[];
      final p = pager((a, c, {skip = 0, genre, onRawCount}) async {
        requested.add(skip);
        if (failed) return [];
        onRawCount?.call(2);
        return [meta('same'), meta('same', type: 'series')];
      });
      expect(await p.nextPage(), isEmpty);
      expect(p.skip, 0);
      expect(p.error, isNotNull);
      expect(p.exhausted, false);
      failed = false;
      final items = await p.nextPage();
      expect(requested, [0, 0]);
      expect(items, hasLength(2));
      expect(items.every((m) => identical(m.sourceAddon, addon)), true);
      expect(p.error, isNull);
      expect(p.skip, 2);
    },
  );
  test('addon ignoring skip reaches a bounded retryable stop', () async {
    var calls = 0;
    final p = pager((a, c, {skip = 0, genre, onRawCount}) async {
      calls++;
      onRawCount?.call(1);
      return [meta('repeat')];
    });
    expect(await p.nextPage(), hasLength(1));
    expect(await p.nextPage(), isEmpty);
    expect(calls, 1 + CollectionCatalogPager.maxEmptyWindows);
    expect(p.exhausted, false);
    expect(p.error, isNotNull);
  });
  test(
    'All has one shared eight-request budget per repeating source',
    () async {
      var calls = 0;
      final loader = CollectionFolderLoader(
        folder: const HomeCollectionFolder(
          id: 'f',
          title: 'F',
          sources: [
            CollectionCatalogSource(
              addonId: 'a',
              type: 'movie',
              catalogId: 'popular',
            ),
          ],
        ),
        installedAddons: [addon],
        fetch: (a, c, {skip = 0, genre, onRawCount}) async {
          calls++;
          onRawCount?.call(1);
          return [meta('same')];
        },
      );
      await loader.nextPage();
      calls = 0;
      expect(await loader.nextPage(), isEmpty);
      expect(calls, CollectionCatalogPager.maxEmptyWindows);
      expect(loader.exhausted, false);
      expect(loader.hasErrors, true);
    },
  );
  for (final filtered in [false, true]) {
    test(
      'All keeps paging when one source ${filtered ? 'is filtered' : 'overlaps'}',
      () async {
        final other = StremioAddon(
          id: 'b',
          name: 'B',
          manifestUrl: 'https://example.invalid/b/manifest.json',
          baseUrl: 'https://example.invalid/b',
          catalogs: addon.catalogs,
        );
        final loader = CollectionFolderLoader(
          folder: const HomeCollectionFolder(
            id: 'f',
            title: 'F',
            sources: [
              CollectionCatalogSource(
                addonId: 'a',
                type: 'movie',
                catalogId: 'popular',
              ),
              CollectionCatalogSource(
                addonId: 'b',
                type: 'movie',
                catalogId: 'popular',
              ),
            ],
          ),
          installedAddons: [addon, other],
          fetch: (a, c, {skip = 0, genre, onRawCount}) async {
            onRawCount?.call(skip < 3 ? 1 : 0);
            if (skip >= 3) return [];
            if (a.id == 'b') return [meta('b$skip')];
            if (skip == 1) return filtered ? [] : [meta('a0')];
            return [meta('a$skip')];
          },
        );
        expect((await loader.nextPage()).map((m) => m.id), ['a0', 'b0']);
        expect((await loader.nextPage()).map((m) => m.id), ['b1']);
        expect(loader.hasErrors, false);
        expect(loader.exhausted, false);
        expect((await loader.nextPage()).map((m) => m.id), ['a2', 'b2']);
        expect(await loader.nextPage(), isEmpty);
        expect(loader.exhausted, true);
        expect(loader.hasErrors, false);
      },
    );
  }

  test('All still reports genuine transport failures', () async {
    final loader = CollectionFolderLoader(
      folder: const HomeCollectionFolder(
        id: 'f',
        title: 'F',
        sources: [
          CollectionCatalogSource(
            addonId: 'a',
            type: 'movie',
            catalogId: 'popular',
          ),
        ],
      ),
      installedAddons: [addon],
      fetch: (a, c, {skip = 0, genre, onRawCount}) async => [],
    );
    expect(await loader.nextPage(), isEmpty);
    expect(loader.hasErrors, true);
    expect(loader.hasLoadFailures, true);
    expect(loader.exhausted, false);
  });

  test('raw end of catalog stops future network calls', () async {
    var calls = 0;
    final p = pager((a, c, {skip = 0, genre, onRawCount}) async {
      calls++;
      onRawCount?.call(0);
      return [];
    });
    await p.nextPage();
    await p.nextPage();
    expect(calls, 1);
    expect(p.exhausted, true);
  });
  test(
    'merged loader bounds concurrency and does not duplicate concurrent loads',
    () async {
      final release = Completer<void>();
      var running = 0, maximum = 0, calls = 0;
      final addons = [
        for (var i = 0; i < 12; i++)
          StremioAddon(
            id: 'a$i',
            name: 'A$i',
            manifestUrl: 'https://example.invalid/$i/manifest.json',
            baseUrl: 'https://example.invalid/$i',
            catalogs: addon.catalogs,
          ),
      ];
      final loader = CollectionFolderLoader(
        folder: HomeCollectionFolder(
          id: 'f',
          title: 'F',
          sources: [
            for (final a in addons)
              CollectionCatalogSource(
                addonId: a.id,
                type: 'movie',
                catalogId: 'popular',
              ),
          ],
        ),
        installedAddons: addons,
        fetch: (a, c, {skip = 0, genre, onRawCount}) async {
          calls++;
          running++;
          if (running > maximum) maximum = running;
          await release.future;
          running--;
          onRawCount?.call(1);
          return [meta(a.id)];
        },
      );
      final pending = loader.nextPage();
      expect(await loader.nextPage(), isEmpty);
      expect(calls, CollectionFolderLoader.maxConcurrent);
      release.complete();
      expect(await pending, hasLength(12));
      expect(maximum, CollectionFolderLoader.maxConcurrent);
      expect(calls, 12);
    },
  );
}
