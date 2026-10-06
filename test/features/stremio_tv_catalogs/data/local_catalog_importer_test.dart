import 'dart:convert';
import 'package:debrify/services/mdblist/mdblist_list_source.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/stremio_tv_catalogs_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CatalogFixture f;
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  setUp(() async {
    net.reset();
    f = CatalogFixture();
    await f.open();
  });
  tearDown(() => f.close());
  test('validation message precedence and every malformed item branch', () {
    expect(LocalCatalogImporter.validate('{'), startsWith('Invalid JSON:'));
    expect(LocalCatalogImporter.validate('[]'), 'Expected a JSON object');
    expect(LocalCatalogImporter.validate('{}'), 'Missing "name" field');
    expect(
      LocalCatalogImporter.validate('{"name":" "}'),
      'Missing "name" field',
    );
    expect(
      LocalCatalogImporter.validate('{"name":"N"}'),
      '"items" is missing or empty',
    );
    expect(
      LocalCatalogImporter.validate('{"name":"N","items":[]}'),
      '"items" is missing or empty',
    );
    for (final entry in [
      (7, 'Item 0: not an object'),
      (<String, dynamic>{}, 'Item 0: missing "id"'),
      ({'id': 'tt1'}, 'Item 0: missing "name"'),
    ]) {
      expect(
        LocalCatalogImporter.validate(
          jsonEncode({
            'name': 'N',
            'items': [entry.$1],
          }),
        ),
        entry.$2,
      );
    }
    expect(LocalCatalogImporter.validate(jsonEncode(catalog())), isNull);
  });
  test(
    'Trakt detection examines nonempty list first map and movie or show keys',
    () {
      for (final value in [
        null,
        {},
        [],
        [1],
        [{}],
        [
          {'name': 'x'},
        ],
      ]) {
        expect(LocalCatalogImporter.isTrakt(value), isFalse);
      }
      expect(
        LocalCatalogImporter.isTrakt([
          {'movie': {}},
        ]),
        isTrue,
      );
      expect(
        LocalCatalogImporter.isTrakt([
          {'show': {}},
        ]),
        isTrue,
      );
    },
  );
  test('transform majority ties movie and retains complete field mapping', () {
    final result = LocalCatalogImporter.transformTrakt(mixedTrakt, 'Both');
    expect(result['type'], 'movie');
    expect(result['name'], 'Both');
    expect((result['items'] as List).first, {
      'id': 'tt10',
      'name': 'Title tt10',
      'type': 'movie',
      'year': 2020,
      'overview': 'Overview tt10',
      'rating': 8.5,
      'poster': 'https://poster.test/tt10',
      'fanart': 'https://fanart.test/tt10',
      'genres': ['Science Fiction'],
    });
    final fallback = LocalCatalogImporter.transformTrakt([
      traktItem('tt1', series: true, year: 'unknown', genres: []),
    ], 'Series');
    expect(fallback['type'], 'series');
    expect((fallback['items'] as List).single['year'], 'unknown');
    expect((fallback['items'] as List).single.containsKey('genres'), isFalse);
  });
  test('generateId sanitizes and uses a base36 millisecond suffix', () {
    final before = DateTime.now().millisecondsSinceEpoch;
    final id = LocalCatalogImporter.generateId('  My / CATALOG!  ');
    expect(id, startsWith('my_catalog_'));
    final ms = int.parse(id.split('_').last, radix: 36);
    expect(ms, inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch));
    expect(LocalCatalogImporter.generateId('!!!'), startsWith('_'));
  });
  test(
    'import invalid JSON, nameless and untransformable Trakt reject without writes',
    () async {
      expect(
        await LocalCatalogImporter.import('{'),
        startsWith('Invalid JSON:'),
      );
      expect(
        await LocalCatalogImporter.import(jsonEncode(mixedTrakt)),
        'Trakt list detected — please enter a catalog name',
      );
      expect(
        await LocalCatalogImporter.import(
          '[{"movie":{"ids":{}}}]',
          catalogName: 'Bad',
        ),
        'No items with IMDB IDs found in Trakt list',
      );
      expect(await f.rows(), isEmpty);
    },
  );
  test(
    'mixed split skips an existing side and preserves write order and payload',
    () async {
      final existing = catalog(name: 'Both — Movies', id: 'keep');
      await f.seed([existing]);
      expect(
        await LocalCatalogImporter.import(
          jsonEncode(mixedTrakt),
          catalogName: ' Both ',
        ),
        isNull,
      );
      final rows = await f.rows();
      expect(rows.map((r) => r['name']), ['Both — Movies', 'Both — Series']);
      expect(rows.first, existing);
      expect(rows.last['type'], 'series');
      expect((rows.last['items'] as List).single['id'], 'tt20');
      expect(
        await LocalCatalogImporter.import(
          jsonEncode(mixedTrakt),
          catalogName: 'Both',
        ),
        isNull,
      );
      expect(await f.rows(), rows);
      await f.seed([]);
      await LocalCatalogImporter.import(
        jsonEncode(mixedTrakt),
        catalogName: 'Both',
      );
      expect((await f.rows()).map((r) => r['type']), ['movie', 'series']);
    },
  );
  test(
    'single-type import trims, defaults, rejects duplicates and drops unportable metadata',
    () async {
      expect(
        await LocalCatalogImporter.import(
          jsonEncode([traktItem('tt1')]),
          catalogName: ' Solo ',
        ),
        isNull,
      );
      expect((await f.rows()).single['name'], 'Solo');
      expect(
        await LocalCatalogImporter.import(jsonEncode(catalog(name: ' Solo '))),
        'Catalog "Solo" already exists',
      );
      for (final source in [
        'watchlist',
        'history',
        'collection',
        'ratings',
        'recommendations',
        'custom',
        'unknown',
      ]) {
        await f.seed([]);
        await LocalCatalogImporter.import(
          jsonEncode(
            catalog(
              type: null,
              meta: {
                'traktSource': source,
                'mdblistListId': 12,
                'traktSlug': 'slug',
                'traktOwner': 'owner',
              },
            ),
          ),
        );
        final row = (await f.rows()).single;
        expect(row['type'], 'movie');
        expect(row.containsKey('traktSource'), isFalse, reason: source);
        expect(row.containsKey('mdblistListId'), isFalse);
      }
    },
  );
  test(
    'portable direct sources and liked require both slug and owner',
    () async {
      for (final source in ['trending', 'popular', 'anticipated']) {
        await f.seed([]);
        await LocalCatalogImporter.import(
          jsonEncode(
            catalog(
              meta: {
                'traktSource': source,
                'traktSlug': 'drop',
                'traktOwner': 'drop',
              },
            ),
          ),
        );
        final row = (await f.rows()).single;
        expect(row['traktSource'], source);
        expect(row.containsKey('traktSlug'), isFalse);
      }
      for (final meta in [
        {'traktSource': 'liked'},
        {'traktSource': 'liked', 'traktSlug': 's'},
        {'traktSource': 'liked', 'traktSlug': '', 'traktOwner': 'o'},
        {'traktSource': 'liked', 'traktSlug': 's', 'traktOwner': ''},
      ]) {
        await f.seed([]);
        await LocalCatalogImporter.import(jsonEncode(catalog(meta: meta)));
        expect(
          (await f.rows()).single.containsKey('traktSource'),
          isFalse,
          reason: meta.toString(),
        );
      }
      await f.seed([]);
      await LocalCatalogImporter.import(
        jsonEncode(
          catalog(
            meta: {
              'traktSource': 'liked',
              'traktSlug': 's',
              'traktOwner': 'o',
              'traktListId': 'drop',
              'traktOwnerSlug': 'drop',
            },
          ),
        ),
      );
      final row = (await f.rows()).single;
      expect(row['traktSource'], 'liked');
      expect(row['traktSlug'], 's');
      expect(row['traktOwner'], 'o');
      expect(row.containsKey('traktListId'), isFalse);
    },
  );
  test(
    'refresh Trakt missing source, slug and unknown source errors',
    () async {
      expect(
        await LocalCatalogImporter.refreshTraktCatalog(catalog()),
        'Not a Trakt catalog',
      );
      expect(
        await LocalCatalogImporter.refreshTraktCatalog(
          catalog(meta: {'traktSource': 'custom'}),
        ),
        'Missing list slug',
      );
      expect(
        await LocalCatalogImporter.refreshTraktCatalog(
          catalog(meta: {'traktSource': 'liked', 'traktOwner': 'o'}),
        ),
        'Missing list slug',
      );
      expect(
        await LocalCatalogImporter.refreshTraktCatalog(
          catalog(meta: {'traktSource': 'liked'}),
        ),
        'Unknown Trakt source: liked',
      );
      expect(
        await LocalCatalogImporter.refreshTraktCatalog(
          catalog(meta: {'traktSource': 'other'}),
        ),
        'Unknown Trakt source: other',
      );
    },
  );
  for (final source in ['watchlist', 'custom', 'liked']) {
    test(
      'refresh Trakt $source requests movies then shows, filters and preserves metadata',
      () async {
        await f.auth();
        final c = catalog(
          type: 'series',
          meta: {
            'traktSource': source,
            'traktSlug': 'slug',
            'traktOwner': 'owner',
            'traktOwnerSlug': 'owner-slug',
            'traktListId': '42',
          },
        );
        await f.seed([c]);
        net.handler = (r) async => response(
          r.url.path.endsWith('/shows') || r.url.path.endsWith('/show')
              ? [traktItem('tt20', series: true)]
              : [traktItem('tt10')],
        );
        await net.run(() async {
          expect(await LocalCatalogImporter.refreshTraktCatalog(c), isNull);
        });
        expect(net.requests.length, 2);
        expect(
          net.requests.first.url.path,
          contains(
            source == 'watchlist'
                ? '/watchlist/movies'
                : source == 'custom'
                ? '/users/me/lists/slug/items/movie'
                : '/lists/42/items/movie',
          ),
        );
        final row = (await f.rows()).single;
        expect(
          row['items'],
          hasLength(1),
          reason: 'refresh retains only series items',
        );
        expect((row['items'] as List).single['id'], 'tt20');
        expect(row['traktSource'], source);
        expect(row['addedAt'], isNotNull);
      },
    );
  }
  test(
    'refresh liked ownerSlug and owner fallback routes without listId',
    () async {
      await f.auth();
      net.handler = (r) async => response([traktItem('tt10')]);
      for (final ownerSlug in [null, 'owner-slug']) {
        final c = catalog(
          meta: {
            'traktSource': 'liked',
            'traktSlug': 'slug',
            'traktOwner': 'owner',
            if (ownerSlug != null) 'traktOwnerSlug': ownerSlug,
          },
        );
        await f.seed([c]);
        net.requests.clear();
        await net.run(() async {
          expect(await LocalCatalogImporter.refreshTraktCatalog(c), isNull);
        });
        expect(
          net.requests.first.url.path,
          '/users/${ownerSlug ?? 'owner'}/lists/slug/items/movie',
        );
      }
    },
  );
  test(
    'refresh Trakt empty, empty-after-filter and deleted catalog never write',
    () async {
      await f.auth();
      final c = catalog(meta: {'traktSource': 'watchlist'});
      await f.seed([c]);
      await net.run(() async {
        expect(
          await LocalCatalogImporter.refreshTraktCatalog(c),
          'No items found in list',
        );
      });
      net.handler = (r) async => response([traktItem('tt20', series: true)]);
      await net.run(() async {
        expect(
          await LocalCatalogImporter.refreshTraktCatalog(c),
          'No matching items after filtering by type',
        );
      });
      expect((await f.rows()).single, c);
      net.handler = (r) async => response([traktItem('tt10')]);
      await f.seed([]);
      await net.run(() async {
        expect(
          await LocalCatalogImporter.refreshTraktCatalog(c),
          'Catalog not found — it may have been deleted',
        );
      });
      expect(await f.rows(), isEmpty);
    },
  );
  test(
    'MDB refresh bypasses warm cache and persists newly fetched filtered items',
    () async {
      await f.auth();
      final c = catalog(meta: {'mdblistListId': 42});
      await f.seed([c]);
      net.handler = (r) async => response(mdblistItems);
      final warm = await MdblistListSource.instance.loadListItems(
        const MdblistListChoice(id: 42, name: 'warm'),
      );
      expect(warm.items.map((m) => m.id), ['tt10', 'tt20']);
      final before = net.requests.length;
      net.handler = (r) async => response({
        'movies': [
          {'imdb_id': 'tt99', 'title': 'New', 'mediatype': 'movie'},
        ],
        'shows': mdblistItems['shows'],
      });
      expect(await LocalCatalogImporter.refreshMdblistCatalog(c), isNull);
      expect(
        net.requests.length,
        before + 1,
        reason: 'forceRefresh must bypass a warm cache',
      );
      expect((await f.rows()).single['items'], [containsPair('id', 'tt99')]);
    },
  );
  test(
    'MDB refresh missing id, failure, incomplete, empty-filter and not-found',
    () async {
      await f.auth();
      expect(
        await LocalCatalogImporter.refreshMdblistCatalog(catalog()),
        'Not an MDBList catalog',
      );
      final c = catalog(meta: {'mdblistListId': 42});
      await f.seed([c]);
      net.handler = (r) async => response({}, status: 403);
      expect(
        await LocalCatalogImporter.refreshMdblistCatalog(c),
        'Failed to refresh from MDBList',
      );
      net.handler = (r) async => r.url.queryParameters.containsKey('cursor')
          ? response({}, status: 403)
          : response({
              ...mdblistItems,
              'pagination': {'next_cursor': 'next'},
            });
      expect(
        await LocalCatalogImporter.refreshMdblistCatalog(c),
        'Failed to refresh from MDBList',
      );
      net.handler = (r) async =>
          response({'movies': [], 'shows': mdblistItems['shows']});
      expect(
        await LocalCatalogImporter.refreshMdblistCatalog(c),
        'No matching items after filtering by type',
      );
      expect((await f.rows()).single, c);
      await f.seed([]);
      net.handler = (r) async => response(mdblistItems);
      expect(
        await LocalCatalogImporter.refreshMdblistCatalog(c),
        'Catalog not found — it may have been deleted',
      );
    },
  );
}
