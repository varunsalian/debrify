import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_repo_browser_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_catalogs_fixture.dart';

Future<void> choose(WidgetTester t, String current, String target) async {
  await t.tap(find.text(current).first);
  await pumpCatalog(t, rounds: 4);
  await t.tap(find.text(target).last);
  await pumpCatalog(t);
}

Map<String, dynamic> list({bool owner = true, bool id = true}) => {
  'name': 'My List',
  'ids': {'slug': 'my-list', if (id) 'trakt': 42},
  'item_count': 2,
  if (owner)
    'user': {
      'username': 'owner',
      'ids': {'slug': 'owner-slug'},
    },
};

void main() {
  final net = CatalogNetwork();
  setUpAll(net.install);
  tearDownAll(() => net.client.close());
  setUp(net.reset);
  for (final kind in ['Trakt', 'MDBList']) {
    final show = kind == 'Trakt'
        ? StremioTvLocalCatalogsDialog.importFromTrakt
        : StremioTvLocalCatalogsDialog.importFromMdblist;
    testWidgets(
      '$kind unauthenticated message and OK returns false',
      (t) => catalogCase(t, (f) async {
        await f.mount(t);
        await f.dialog(t, show);
        expect(
          find.text(
            kind == 'Trakt'
                ? 'Sign in to Trakt first in Settings.'
                : 'Connect MDBList first in Settings.',
          ),
          findsOneWidget,
        );
        await t.tap(find.text('OK'));
        await pumpCatalog(t);
        expect(f.result, isFalse);
      }),
    );
  }
  testWidgets(
    'repo static delegates browser and converts result to true only',
    (t) => catalogCase(t, (f) async {
      await f.mount(t);
      await f.dialog(t, StremioTvLocalCatalogsDialog.importFromRepo);
      expect(find.byType(StremioTvRepoBrowserDialog), findsOneWidget);
      Navigator.of(
        t.element(find.byType(StremioTvRepoBrowserDialog)),
      ).pop(true);
      await pumpCatalog(t);
      expect(f.result, isTrue);
    }),
  );
  for (final source in [
    'Watchlist',
    'History',
    'Collection',
    'Ratings',
    'Trending',
    'Popular',
    'Anticipated',
    'Recommendations',
  ]) {
    testWidgets(
      'Trakt source $source labels and direct API metadata',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await t.runAsync(f.auth);
          net.handler = (r) async => response([traktItem('tt11')]);
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
          final dropdown = t.widget<DropdownButton>(
            find.byWidgetPredicate((w) => w is DropdownButton),
          );
          expect(dropdown.items!.map((i) => (i.child as Text).data), [
            'Watchlist',
            'History',
            'Collection',
            'Ratings',
            'Trending',
            'Popular',
            'Anticipated',
            'Recommendations',
            'Custom Lists',
            'Liked Lists',
          ]);
          if (source != 'Watchlist') {
            await choose(t, 'Watchlist', source);
          }
          expect(find.text('Import $source'), findsOneWidget);
          await t.tap(find.text('Import $source'));
          await pumpCatalog(t);
          expect(f.result, isTrue);
          final row = (await t.runAsync(f.rows))!.single;
          expect(row['name'], 'Trakt $source');
          expect(row['traktSource'], source.toLowerCase());
          expect(net.requests, hasLength(2));
        }),
      ),
    );
  }
  testWidgets(
    'Trakt direct exact name, movies then shows and split metadata returns true',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        net.handler = (r) async => response([
          traktItem(
            r.url.path.endsWith('/shows') ? 'tt20' : 'tt10',
            series: r.url.path.endsWith('/shows'),
          ),
        ]);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
        await t.tap(find.text('Import Watchlist'));
        await pumpCatalog(t);
        expect(f.result, isTrue);
        final rows = (await t.runAsync(f.rows))!;
        expect(rows.map((r) => r['name']), [
          'Trakt Watchlist — Movies',
          'Trakt Watchlist — Series',
        ]);
        expect(rows.map((r) => r['traktSource']), ['watchlist', 'watchlist']);
        expect(rows.map((r) => r['type']), ['movie', 'series']);
        expect(net.requests.map((r) => r.url.path), [
          '/sync/watchlist/movies',
          '/sync/watchlist/shows',
        ]);
        expect(rows.first['id'], startsWith('trakt_watchlist_movies_'));
        expect((rows.first['items'] as List).single['year'], 2020);
      }),
    ),
  );
  for (final name in [
    'Trakt Watchlist',
    'Trakt Watchlist — Movies',
    'Trakt Watchlist — Series',
  ]) {
    testWidgets(
      'Trakt direct duplicate guard $name',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await t.runAsync(f.auth);
          await t.runAsync(() => f.seed([catalog(name: name)]));
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
          await t.tap(find.text('Import Watchlist'));
          await pumpCatalog(t);
          expect(
            find.text('"Trakt Watchlist" already imported'),
            findsOneWidget,
          );
          expect(net.requests, isEmpty);
          expect(await t.runAsync(f.rows), hasLength(1));
        }),
      ),
    );
  }
  for (final liked in [false, true]) {
    testWidgets(
      'Trakt ${liked ? 'liked' : 'custom'} list metadata and save split',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await t.runAsync(f.auth);
          net.handler = (r) async {
            if (r.url.path == '/users/me/lists') return response([list()]);
            if (r.url.path == '/users/me/likes/lists') {
              return response([
                {'list': list()},
              ]);
            }
            return response([
              traktItem(
                r.url.path.endsWith('/show') ? 'tt20' : 'tt10',
                series: r.url.path.endsWith('/show'),
              ),
            ]);
          };
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
          await choose(t, 'Watchlist', liked ? 'Liked Lists' : 'Custom Lists');
          await t.tap(find.text('My List'));
          await pumpCatalog(t);
          expect(f.result, isTrue);
          final rows = (await t.runAsync(f.rows))!;
          expect(rows.map((r) => r['name']), [
            'My List — Movies',
            'My List — Series',
          ]);
          expect(rows.map((r) => r['type']), ['movie', 'series']);
          expect(
            rows.map(
              (r) => (r['items'] as List).map((item) => item['id']).toList(),
            ),
            [
              ['tt10'],
              ['tt20'],
            ],
          );
          expect(rows.first['id'], startsWith('my_list_movies_'));
          expect(rows.last['id'], startsWith('my_list_series_'));
          for (final row in rows) {
            expect(row['traktSource'], liked ? 'liked' : 'custom');
            expect(row['traktSlug'], 'my-list');
            expect(row['traktListId'], '42');
            expect(row['traktOwnerSlug'], 'owner-slug');
            expect(row['traktOwner'], 'owner');
          }
          expect(
            net.requests.skip(1).map((r) => r.url.path),
            liked
                ? ['/lists/42/items/movie', '/lists/42/items/show']
                : [
                    '/users/me/lists/my-list/items/movie',
                    '/users/me/lists/my-list/items/show',
                  ],
          );
        }),
      ),
    );
  }
  testWidgets(
    'Trakt liked missing owner rejects and leaves storage empty',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        net.handler = (r) async => response([
          {'list': list(owner: false, id: false)},
        ]);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
        await choose(t, 'Watchlist', 'Liked Lists');
        await t.tap(find.text('My List'));
        await pumpCatalog(t);
        expect(find.text('Missing list owner'), findsOneWidget);
        expect(await t.runAsync(f.rows), isEmpty);
      }),
    ),
  );
  for (final noImdb in [false, true]) {
    testWidgets(
      'Trakt ${noImdb ? 'no IMDB' : 'empty'} errors and no save',
      (t) => net.run(
        () => catalogCase(t, (f) async {
          await t.runAsync(f.auth);
          net.handler = (r) async => response(
            noImdb
                ? [
                    {
                      'movie': {'title': 'Missing', 'ids': {}},
                    },
                  ]
                : [],
          );
          await f.mount(t);
          await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
          await t.tap(find.text('Import Watchlist'));
          await pumpCatalog(t);
          expect(
            find.text(
              noImdb
                  ? 'No items with IMDB IDs found'
                  : '"Trakt Watchlist" is empty',
            ),
            findsOneWidget,
          );
          expect(await t.runAsync(f.rows), isEmpty);
        }),
      ),
    );
  }
  testWidgets(
    'Trakt single-type save and empty custom and liked list directories',
    (t) => net.run(
      () => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromTrakt);
        await choose(t, 'Watchlist', 'Custom Lists');
        expect(find.text('No custom lists found.'), findsOneWidget);
        await choose(t, 'Custom Lists', 'Liked Lists');
        expect(find.text('No liked lists found.'), findsOneWidget);
        await choose(t, 'Liked Lists', 'Popular');
        net.handler = (r) async => response([traktItem('tt1')]);
        await t.tap(find.text('Import Popular'));
        await pumpCatalog(t);
        expect(f.result, isTrue);
        expect((await t.runAsync(f.rows))!.single['name'], 'Trakt Popular');
      }),
    ),
  );
  for (final category in ['My Lists', 'Liked Lists', 'Top Lists']) {
    testWidgets(
      'MDB $category directory and split metadata save',
      (t) => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        net.handler = (r) async => r.url.path.endsWith('/items')
            ? response(mdblistItems)
            : response([
                {
                  'id': 42,
                  'name': 'MDB Choice',
                  'items': 2,
                  'user_name': 'owner',
                },
              ]);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromMdblist);
        if (category != 'My Lists') await choose(t, 'My Lists', category);
        expect(
          net.requests.last.url.path,
          {
            'My Lists': '/lists/user',
            'Liked Lists': '/lists/liked',
            'Top Lists': '/lists/top',
          }[category],
        );
        await t.tap(find.text('MDB Choice'));
        await pumpCatalog(t);
        expect(f.result, isTrue);
        final rows = (await t.runAsync(f.rows))!;
        expect(rows.map((r) => r['name']), [
          'MDB Choice — Movies',
          'MDB Choice — Series',
        ]);
        expect(rows.map((r) => r['mdblistListId']), [42, 42]);
        expect(rows.map((r) => r['mdblistOwner']), ['owner', 'owner']);
        expect(rows.map((r) => r['type']), ['movie', 'series']);
      }),
    );
  }
  for (final suffix in ['', ' — Movies', ' — Series']) {
    testWidgets(
      'MDB duplicate guard suffix $suffix',
      (t) => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        await t.runAsync(() => f.seed([catalog(name: 'MDB Choice$suffix')]));
        net.handler = (r) async => response([
          {'id': 42, 'name': 'MDB Choice'},
        ]);
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromMdblist);
        await t.tap(find.text('MDB Choice'));
        await pumpCatalog(t);
        expect(find.text('"MDB Choice" already imported'), findsOneWidget);
        expect(net.requests, hasLength(1));
        expect(await t.runAsync(f.rows), hasLength(1));
      }),
    );
  }
  for (final branch in ['failed', 'incomplete', 'empty', 'single']) {
    testWidgets(
      'MDB $branch list import contract',
      (t) => catalogCase(t, (f) async {
        await t.runAsync(f.auth);
        net.handler = (r) async {
          if (!r.url.path.endsWith('/items')) {
            return response([
              {'id': 42, 'name': 'MDB Choice'},
            ]);
          }
          if (branch == 'failed' ||
              r.url.queryParameters.containsKey('cursor')) {
            return response({}, status: 403);
          }
          if (branch == 'incomplete') {
            return response({
              ...mdblistItems,
              'pagination': {'next_cursor': 'next'},
            });
          }
          return response({
            'movies': branch == 'empty' ? [] : mdblistItems['movies'],
            'shows': [],
          });
        };
        await f.mount(t);
        await f.dialog(t, StremioTvLocalCatalogsDialog.importFromMdblist);
        await t.tap(find.text('MDB Choice'));
        await pumpCatalog(t);
        if (branch == 'single') {
          expect(f.result, isTrue);
          final rows = (await t.runAsync(f.rows))!;
          expect(rows.single['name'], 'MDB Choice');
          expect(rows.single['type'], 'movie');
        } else {
          expect(
            find.text(
              branch == 'empty'
                  ? '"MDB Choice" is empty'
                  : 'Failed to load "MDB Choice"',
            ),
            findsOneWidget,
          );
          expect(await t.runAsync(f.rows), isEmpty);
        }
      }),
    );
  }
}
