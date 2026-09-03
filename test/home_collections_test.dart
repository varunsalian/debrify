import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/collection_folder_loader.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/services/home_collections_store.dart';

const _xperienceSample = '''
[
  {
    "id": "ee8e31f3-14b6-4295-8ac1-782d294d70d0",
    "title": "Streaming",
    "pinToTop": true,
    "focusGlowEnabled": true,
    "viewMode": "FOLLOW_LAYOUT",
    "showAllTab": true,
    "backdropImageUrl": null,
    "folders": [
      {
        "id": "dd534772-7be8-4d52-a17a-45cc65cce83b",
        "title": "Netflix",
        "hideTitle": true,
        "coverImageUrl": "https://cdn.example/netflix.webp",
        "coverEmoji": null,
        "heroBackdropUrl": "https://cdn.example/netflix.backdrop.webp",
        "titleLogoUrl": "https://cdn.example/netflix.logo.webp",
        "focusGifUrl": "https://cdn.example/netflix.focus.gif",
        "focusGifEnabled": false,
        "tileShape": "LANDSCAPE",
        "catalogSources": [
          {"addonId": "app.xperience.abc", "type": "movie", "catalogId": "streaming_netflix_movies", "genre": null},
          {"addonId": "app.xperience.abc", "type": "series", "catalogId": "streaming_netflix_series", "genre": null}
        ],
        "sources": [
          {"provider": "addon", "addonId": "app.xperience.abc", "type": "movie", "catalogId": "streaming_netflix_movies", "genre": null},
          {"provider": "addon", "addonId": "app.xperience.abc", "type": "series", "catalogId": "streaming_netflix_series", "genre": null}
        ]
      },
      {
        "title": "Action",
        "tileShape": "PORTRAIT",
        "catalogSources": [
          {"addonId": "com.linvo.cinemeta", "type": "movie", "catalogId": "top", "genre": "Action"}
        ]
      }
    ]
  }
]
''';

StremioMeta _meta(String id) => StremioMeta(id: id, type: 'movie', name: id);

void main() {
  group('HomeCollectionParser', () {
    test('parses the Nuvio / Xperience export shape', () {
      final collections = HomeCollectionParser.parse(_xperienceSample);
      expect(collections, hasLength(1));
      final c = collections.single;
      expect(c.id, 'ee8e31f3-14b6-4295-8ac1-782d294d70d0');
      expect(c.title, 'Streaming');
      expect(c.pinToTop, isTrue);
      expect(c.enabled, isTrue);
      expect(c.folders, hasLength(2));

      final netflix = c.folders.first;
      expect(netflix.title, 'Netflix');
      expect(netflix.hideTitle, isTrue);
      expect(netflix.tileShape, CollectionTileShape.landscape);
      expect(netflix.coverImageUrl, 'https://cdn.example/netflix.webp');
      // catalogSources + sources describe the same two catalogs — deduped.
      expect(netflix.sources, hasLength(2));
      expect(netflix.sources.first.addonId, 'app.xperience.abc');
      expect(netflix.sources.first.catalogId, 'streaming_netflix_movies');
      expect(netflix.sources.first.genre, isNull);

      final action = c.folders[1];
      expect(action.tileShape, CollectionTileShape.portrait);
      expect(action.sources.single.genre, 'Action');
      // A folder without an id gets a stable one so re-imports replace.
      expect(action.id, isNotEmpty);
      expect(
        action.id,
        HomeCollectionParser.parse(_xperienceSample).single.folders[1].id,
      );
    });

    test('accepts a wrapped object and a single collection', () {
      final wrapped = HomeCollectionParser.parse(
        '{"collections": $_xperienceSample}',
      );
      expect(wrapped.single.title, 'Streaming');

      final single = HomeCollectionParser.parse(
        '{"title": "Solo", "folders": [{"title": "F", "catalogSources": []}]}',
      );
      expect(single.single.title, 'Solo');
      expect(single.single.folders.single.title, 'F');
    });

    test('wraps a bare folder list into one collection', () {
      final parsed = HomeCollectionParser.parse(
        '[{"title": "Only folder", "catalogSources": '
        '[{"addonId": "a", "type": "movie", "catalogId": "c"}]}]',
      );
      expect(parsed.single.title, 'Imported');
      expect(parsed.single.folders.single.title, 'Only folder');
    });

    test('rejects non-JSON and empty documents with readable messages', () {
      expect(
        () => HomeCollectionParser.parse('not json'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
      expect(() => HomeCollectionParser.parse('[]'), throwsFormatException);
      expect(
        () => HomeCollectionParser.parse('{"foo": 1}'),
        throwsFormatException,
      );
    });

    test('round-trips through toJson', () {
      final original = HomeCollectionParser.parse(_xperienceSample).single;
      final again = HomeCollection.fromJson(original.toJson())!;
      expect(again.id, original.id);
      expect(again.folders.length, original.folders.length);
      expect(
        again.folders.first.sources.map((s) => s.key),
        original.folders.first.sources.map((s) => s.key),
      );
      expect(again.folders[1].tileShape, CollectionTileShape.portrait);
    });
  });

  group('CollectionFolderLayout', () {
    test('parses leniently and defaults to rows', () {
      expect(CollectionFolderLayout.parse('tabs'), CollectionFolderLayout.tabs);
      expect(
        CollectionFolderLayout.parse(' TABS '),
        CollectionFolderLayout.tabs,
      );
      expect(CollectionFolderLayout.parse('rows'), CollectionFolderLayout.rows);
      expect(CollectionFolderLayout.parse(null), CollectionFolderLayout.rows);
      expect(CollectionFolderLayout.parse(42), CollectionFolderLayout.rows);
      expect(CollectionFolderLayout.tabs.storageValue, 'tabs');
    });
  });

  group('HomeCollectionRowIds', () {
    test('row id grammar', () {
      expect(HomeCollectionRowIds.collection('x'), 'collection:x');
      expect(HomeCollectionRowIds.isCollection('collection:x'), isTrue);
      expect(HomeCollectionRowIds.isCollection('traktlist:x'), isFalse);
      expect(HomeCollectionRowIds.collectionId('collection:abc'), 'abc');
      expect(HomeCollectionRowIds.collectionId('cw:movies'), isNull);
    });
  });

  group('HomeCollectionSection', () {
    test('one tile per folder, folders resolvable from tiles', () {
      final c = HomeCollectionParser.parse(_xperienceSample).single;
      final section = HomeCollectionSection(collection: c);
      expect(section.rowId, 'collection:${c.id}');
      expect(section.items, hasLength(2));
      expect(section.items.first.type, 'folder');
      expect(section.items.first.poster, 'https://cdn.example/netflix.webp');
      expect(section.exhausted, isTrue);
      expect(section.folderOf(section.items[1])?.title, 'Action');
      expect(section.folderIndexOf(section.items[1]), 1);
      expect(section.folderOf(_meta('tt1')), isNull);
      expect(
        section.focusArtOf(section.items.first),
        'https://cdn.example/netflix.focus.gif',
      );
      expect(section.focusArtOf(section.items[1]), isNull);
      expect(c.folders.first.heroBackdropUrl, endsWith('backdrop.webp'));
      expect(c.folders.first.titleLogoUrl, endsWith('logo.webp'));
      expect(section.landscapeTiles, isTrue);
    });
  });

  group('HomeCollectionsStore addon resolution', () {
    final cinemeta = StremioAddon(
      id: 'com.linvo.cinemeta',
      name: 'Cinemeta',
      manifestUrl: 'https://v3-cinemeta.strem.io/manifest.json',
      baseUrl: 'https://v3-cinemeta.strem.io',
      resources: const ['catalog'],
      catalogs: const [
        StremioAddonCatalog(id: 'top', type: 'movie', name: 'Popular'),
        StremioAddonCatalog(id: 'top', type: 'series', name: 'Popular'),
      ],
    );
    final fork = StremioAddon(
      id: 'someone.elses.fork',
      name: 'Fork',
      manifestUrl: 'https://fork/manifest.json',
      baseUrl: 'https://fork',
      resources: const ['catalog'],
      catalogs: const [
        StremioAddonCatalog(
          id: 'streaming_netflix_movies',
          type: 'movie',
          name: 'Netflix',
        ),
      ],
    );

    test('matches by manifest id first, then by catalog type+id', () {
      const byId = CollectionCatalogSource(
        addonId: 'com.linvo.cinemeta',
        type: 'movie',
        catalogId: 'top',
      );
      expect(
        HomeCollectionsStore.resolveAddon(byId, [fork, cinemeta]),
        cinemeta,
      );

      const byCatalog = CollectionCatalogSource(
        addonId: 'app.xperience.abc',
        type: 'movie',
        catalogId: 'streaming_netflix_movies',
      );
      expect(
        HomeCollectionsStore.resolveAddon(byCatalog, [cinemeta, fork]),
        fork,
      );

      const missing = CollectionCatalogSource(
        addonId: 'app.xperience.abc',
        type: 'series',
        catalogId: 'streaming_netflix_series',
      );
      expect(
        HomeCollectionsStore.resolveAddon(missing, [cinemeta, fork]),
        isNull,
      );
    });

    test('unresolvedAddonIds reports only what nothing can serve', () {
      final c = HomeCollectionParser.parse(_xperienceSample).single;
      final unresolved = HomeCollectionsStore.unresolvedAddonIds(
        [c],
        [cinemeta, fork],
      );
      // Netflix movies matched the fork by catalog id; Netflix series did not.
      expect(unresolved, {'app.xperience.abc'});
      expect(HomeCollectionsStore.unresolvedAddonIds([c], [cinemeta]), {
        'app.xperience.abc',
      });
    });

    test('claimedCatalogKeys names the board rows a folder takes over', () {
      final c = HomeCollectionParser.parse(_xperienceSample).single;
      // Netflix movies resolve to the fork by catalog id; Action resolves to
      // Cinemeta by manifest id; Netflix series resolve to nothing.
      expect(HomeCollectionsStore.claimedCatalogKeys([c], [cinemeta, fork]), {
        'someone.elses.fork:movie:streaming_netflix_movies',
        'com.linvo.cinemeta:movie:top',
      });
      // A disabled collection claims nothing — its catalogs return to Home.
      expect(
        HomeCollectionsStore.claimedCatalogKeys(
          [c.copyWith(enabled: false)],
          [cinemeta, fork],
        ),
        isEmpty,
      );
    });

    test('folder list ids are distinct per source and never board rows', () {
      final c = HomeCollectionParser.parse(_xperienceSample).single;
      final netflix = c.folders.first;
      final ids = [
        for (final s in netflix.sources)
          HomeCollectionRowIds.folderList(c.id, netflix.id, s),
      ];
      expect(ids.toSet(), hasLength(2));
      expect(ids.every(HomeCollectionRowIds.isFolderList), isTrue);
      expect(ids.every(HomeCollectionRowIds.isCollection), isFalse);
      final action = c.folders[1];
      expect(
        HomeCollectionRowIds.folderList(c.id, action.id, action.sources.single),
        endsWith(':com.linvo.cinemeta:movie:top:Action'),
      );
      expect(netflix.copyWith(sources: const []).sources, isEmpty);
    });

    test('signature changes with enabled state and membership', () {
      final c = HomeCollectionParser.parse(_xperienceSample).single;
      final a = HomeCollectionsStore.signatureOf([c]);
      final b = HomeCollectionsStore.signatureOf([c.copyWith(enabled: false)]);
      expect(a, isNot(b));
      expect(HomeCollectionsStore.signatureOf([]), isNot(a));
    });
  });

  group('CollectionFolderLoader', () {
    test('interleave merges round-robin and drops exhausted lists', () {
      final merged = CollectionFolderLoader.interleave([
        [_meta('a1'), _meta('a2'), _meta('a3')],
        [_meta('b1')],
        [_meta('c1'), _meta('c2')],
      ]);
      expect(merged.map((m) => m.id), ['a1', 'b1', 'c1', 'a2', 'c2', 'a3']);
    });

    test('pages every source, dedupes across them, and exhausts', () async {
      final addon = StremioAddon(
        id: 'com.test',
        name: 'Test',
        manifestUrl: 'https://t/manifest.json',
        baseUrl: 'https://t',
        resources: const ['catalog'],
        catalogs: const [
          StremioAddonCatalog(id: 'popular', type: 'movie', name: 'Popular'),
          StremioAddonCatalog(id: 'top', type: 'movie', name: 'Top'),
        ],
      );
      const folder = HomeCollectionFolder(
        id: 'f',
        title: 'Mixed',
        sources: [
          CollectionCatalogSource(
            addonId: 'com.test',
            type: 'movie',
            catalogId: 'popular',
          ),
          CollectionCatalogSource(
            addonId: 'com.test',
            type: 'movie',
            catalogId: 'top',
            genre: 'Action',
          ),
          CollectionCatalogSource(
            addonId: 'missing.addon',
            type: 'movie',
            catalogId: 'nope',
          ),
        ],
      );
      final calls = <String>[];
      final loader = CollectionFolderLoader(
        folder: folder,
        installedAddons: [addon],
        fetch: (a, c, {skip = 0, genre, onRawCount}) async {
          calls.add('${c.id}:$skip:${genre ?? ''}');
          if (skip > 0) return const [];
          onRawCount?.call(2);
          return c.id == 'popular'
              ? [_meta('tt1'), _meta('tt2')]
              : [_meta('tt2'), _meta('tt3')];
        },
      );
      expect(loader.resolvedSourceCount, 2);
      expect(loader.unresolved, ['missing.addon']);

      final first = await loader.nextPage();
      expect(first.map((m) => m.id), ['tt1', 'tt2', 'tt3']);
      expect(first.every((m) => m.sourceAddon?.id == 'com.test'), isTrue);
      expect(calls, ['popular:0:', 'top:0:Action']);
      expect(loader.exhausted, isFalse);

      final second = await loader.nextPage();
      expect(second, isEmpty);
      expect(loader.exhausted, isTrue);
      expect(calls.length, 4);

      loader.reset();
      expect(loader.exhausted, isFalse);
      expect((await loader.nextPage()).length, 3);
    });
  });
}
