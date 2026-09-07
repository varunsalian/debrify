import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/collection_catalog_pager.dart';
import 'package:debrify/services/collection_folder_loader.dart';
import 'package:debrify/services/collection_native_source_service.dart';

CollectionCatalogSource source(
  String kind, {
  String media = 'MOVIE',
  Map<String, dynamic> filters = const {},
}) => CollectionCatalogSource.fromJson({
  'provider': 'tmdb',
  'tmdbSourceType': kind,
  'tmdbId': 42,
  'mediaType': media,
  'title': 'Example',
  'filters': filters,
})!;

void main() {
  test(
    'native source IDs accept integral JSON doubles without truncating fractions',
    () {
      expect(
        CollectionCatalogSource.fromJson({
          'provider': 'tmdb',
          'tmdbSourceType': 'LIST',
          'tmdbId': 42.0,
        })!.tmdbId,
        42,
      );
      expect(
        CollectionCatalogSource.fromJson({
          'provider': 'tmdb',
          'tmdbSourceType': 'LIST',
          'tmdbId': 42.5,
        })!.tmdbId,
        isNull,
      );
    },
  );

  test('independent first-page readers reuse a sorted list snapshot', () async {
    final pages = <int>[];
    final service = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      resolveIds: false,
      client: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        pages.add(page);
        return http.Response(
          jsonEncode({
            'total_pages': 3,
            'items': [
              for (var i = 0; i < 20; i++)
                {
                  'id': page * 20 + i,
                  'title': 'Film',
                  'popularity': page * 20 + i,
                },
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final list = CollectionCatalogSource.fromJson({
      ...source('LIST').toJson(),
      'sortBy': 'popularity.desc',
    })!;
    final first = await service.fetch(list, 1);
    final again = await service.fetch(list, 1);
    await service.fetch(list, 2);
    expect(pages, [1, 2, 3]);
    expect(again.items.map((i) => i.id), first.items.map((i) => i.id));
  });

  test('LIST without sort loads one remote page in author order', () async {
    final pages = <int>[];
    final service = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      resolveIds: false,
      client: MockClient((request) async {
        pages.add(int.parse(request.url.queryParameters['page']!));
        return http.Response(
          jsonEncode({
            'total_pages': 9999,
            'items': [
              for (var i = 1; i <= 20; i++)
                {'id': i, 'title': 'Film $i', 'popularity': i},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final page = await service.fetch(source('LIST'), 1);
    expect(pages, [1]);
    expect(page.items.first.id, 'tmdb:1');
    expect(page.items.last.id, 'tmdb:20');
    expect(page.hasMore, true);
  });

  test(
    'explicit list sorting has a finite page cap and a useful error',
    () async {
      var pages = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'total_pages': 99999,
              'items': [
                {'id': ++pages, 'title': 'Film'},
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(service.close);
      final list = CollectionCatalogSource.fromJson({
        ...source('LIST').toJson(),
        'sortBy': 'vote_count.desc',
      })!;
      await expectLater(
        service.fetch(list, 1),
        throwsA(
          isA<CollectionSourceException>().having(
            (e) => e.toString(),
            'message',
            contains('Original order'),
          ),
        ),
      );
      expect(pages, 50);
    },
  );

  test(
    'editor-generated identical IDs retain separate titled list entries',
    () {
      final first = CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 42,
        'title': 'A',
      })!;
      final second = CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 42,
        'title': 'B',
      })!;
      final folder = HomeCollectionFolder.fromJson({
        'id': 'f',
        'title': 'F',
        'sources': [first.toJson(), second.toJson()],
      }, collectionId: 'c')!;
      expect(folder.sources.map((s) => s.title), ['A', 'B']);
      expect(folder.sources.map((s) => s.key).toSet().length, 2);
      expect(
        HomeCollectionFolder.fromJson(
          folder.toJson(),
          collectionId: 'c',
        )!.sources.map((s) => s.key),
        folder.sources.map((s) => s.key),
      );
    },
  );

  test(
    'native row identity survives renaming and unrelated imported fields',
    () {
      final original = source('LIST');
      final renamed = CollectionCatalogSource.fromJson({
        ...original.toJson(),
        'title': 'New title',
        'foreignField': 'ignored for identity',
      })!;
      expect(renamed.catalogId, original.catalogId);
      final a = CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 42,
        'title': 'A',
      })!;
      final b = CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 42,
        'title': 'B',
        'extra': true,
      })!;
      expect(a.catalogId, b.catalogId);
      final folder = HomeCollectionFolder.fromJson({
        'id': 'f',
        'title': 'F',
        'sources': [
          {'provider': 'trakt', 'traktListId': 42, 'title': 'A'},
          {'provider': 'trakt', 'traktListId': 42, 'title': 'B'},
        ],
      }, collectionId: 'c')!;
      expect(folder.sources.length, 2);
      expect(folder.sources.map((s) => s.catalogId).toSet().length, 2);
      expect(
        HomeCollectionFolder.fromJson(
          folder.toJson(),
          collectionId: 'c',
        )!.sources.map((s) => s.key),
        folder.sources.map((s) => s.key),
      );
    },
  );

  test(
    'slow enrichment returns titles promptly and leaves catalog capacity free',
    () async {
      var identities = 0;
      final pending = Completer<http.Response>();
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        enrichmentBudget: const Duration(milliseconds: 30),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            identities++;
            return pending.future;
          }
          return http.Response(
            jsonEncode({
              'results': [
                for (var i = 1; i <= 20; i++) {'id': i, 'title': 'Film $i'},
              ],
              'total_pages': 1,
            }),
            200,
          );
        }),
      );
      final first = await service
          .fetch(source('DISCOVER'), 1)
          .timeout(const Duration(seconds: 1));
      expect(first.items.length, 20);
      expect(identities, lessThanOrEqualTo(2));
      final second = await service
          .fetch(source('COMPANY'), 1)
          .timeout(const Duration(seconds: 1));
      expect(second.items.length, 20);
      pending.complete(http.Response('{"imdb_id":null}', 200));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      service.close();
    },
  );

  test(
    'IMDb enrichment completes, coalesces lookups, and caches identities',
    () async {
      var calls = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        client: MockClient((request) async {
          calls++;
          expect(request.url.path, '/3/movie/42/external_ids');
          return http.Response('{"imdb_id":"tt1234567"}', 200);
        }),
      );
      const meta = StremioMeta(id: 'tmdb:42', type: 'movie', name: 'Film');
      final result = await Future.wait([
        service.resolveIdentity(meta),
        service.resolveIdentity(meta),
      ]).timeout(const Duration(seconds: 2));
      expect(result.map((m) => m.id), ['tt1234567', 'tt1234567']);
      expect(result.first.imdbId, 'tt1234567');
      await service.resolveIdentity(meta);
      expect(calls, 1);
      service.close();
    },
  );
  test('Trakt titles with only TMDB IDs are retained and enriched', () async {
    final service = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      client: MockClient((request) async {
        if (request.url.host == 'api.trakt.tv') {
          return http.Response(
            '[{"type":"show","show":{"title":"Series","year":2026,"ids":{"tmdb":42}}}]',
            200,
            headers: {'x-pagination-page-count': '1'},
          );
        }
        expect(request.url.path, '/3/tv/42/external_ids');
        return http.Response('{"imdb_id":"tt1234567"}', 200);
      }),
    );
    addTearDown(service.close);
    final page = await service.fetch(
      CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 5,
        'mediaType': 'TV',
      })!,
      1,
    );
    expect(page.rawCount, 1);
    expect(page.items.single.id, 'tt1234567');
    expect(page.items.single.type, 'series');
    expect(page.items.single.year, '2026');
    expect(page.hasMore, false);
  });

  test(
    'merged addon and native lists deduplicate IMDb titles and keep paging',
    () async {
      final native = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            final id = request.url.path.split('/')[3];
            return http.Response(jsonEncode({'imdb_id': 'tt$id'}), 200);
          }
          final page = int.parse(request.url.queryParameters['page']!);
          return http.Response(
            jsonEncode({
              'results': [
                {'id': 41 + page, 'title': 'Film $page'},
              ],
              'total_pages': 2,
            }),
            200,
          );
        }),
      );
      addTearDown(native.close);
      final addon = StremioAddon(
        id: 'a',
        name: 'Addon',
        manifestUrl: 'https://example.invalid/manifest.json',
        baseUrl: 'https://example.invalid',
        resources: ['catalog'],
        catalogs: const [
          StremioAddonCatalog(id: 'top', type: 'movie', name: 'Top'),
        ],
      );
      final skips = <int>[];
      final loader = CollectionFolderLoader(
        folder: HomeCollectionFolder(
          id: 'f',
          title: 'Mixed',
          sources: [
            const CollectionCatalogSource(
              addonId: 'a',
              type: 'movie',
              catalogId: 'top',
            ),
            source('DISCOVER'),
          ],
        ),
        installedAddons: [addon],
        native: native,
        hides: (_) => false,
        fetch: (_, __, {skip = 0, genre, onRawCount}) async {
          skips.add(skip);
          onRawCount?.call(skip == 0 ? 1 : 0);
          return skip == 0
              ? [const StremioMeta(id: 'tt42', type: 'movie', name: 'Film 1')]
              : [];
        },
      );
      expect((await loader.nextPage()).map((m) => m.id), ['tt42']);
      expect((await loader.nextPage()).map((m) => m.id), ['tt43']);
      expect(skips, [0, 1]);
      expect(loader.exhausted, true);
      expect(loader.errors, isEmpty);
    },
  );

  test('native identities survive round trips and filter key reordering', () {
    final a = source('DISCOVER', filters: {'year': 2026, 'withGenres': '28'});
    final b = source('DISCOVER', filters: {'withGenres': '28', 'year': 2026});
    expect(a.key, b.key);
    expect(CollectionCatalogSource.fromJson(a.toJson())!.key, a.key);
    final withoutDefaults = CollectionCatalogSource.fromJson({
      'provider': 'tmdb',
      'tmdbSourceType': 'DISCOVER',
    })!;
    expect(
      CollectionCatalogSource.fromJson(withoutDefaults.toJson())!.key,
      withoutDefaults.key,
    );
    expect(source('DISCOVER', filters: {'year': 2025}).key, isNot(a.key));
    final paddedSort = CollectionCatalogSource.fromJson({
      'provider': 'trakt',
      'traktListId': 5,
      'sortBy': ' rank ',
      'sortHow': ' asc ',
    })!;
    expect(
      CollectionCatalogSource.fromJson(paddedSort.toJson())!.key,
      paddedSort.key,
    );
  });

  test(
    'mixed sources, unknown providers, and visual settings survive export',
    () {
      final collection = HomeCollection.fromJson({
        'id': 'c',
        'title': 'Mixed',
        'viewMode': 'TABBED_GRID',
        'folders': [
          {
            'id': 'f',
            'title': 'Folder',
            'focusGifEnabled': false,
            'heroVideoUrl': 'https://example.com/hero.mp4',
            'catalogSources': [
              {'addonId': 'a', 'type': 'movie', 'catalogId': 'popular'},
            ],
            'sources': [
              source('LIST').toJson(),
              {'provider': 'trakt', 'traktListId': 5},
              {'provider': 'future', 'endpoint': 'example'},
            ],
          },
        ],
      })!;
      final restored = HomeCollection.fromJson(collection.toJson())!;
      expect(restored.sourceCount, 4);
      expect(
        restored.folders.single.sources.map((s) => s.key),
        collection.folders.single.sources.map((s) => s.key),
      );
      expect(restored.folders.single.focusGifEnabled, false);
      expect(
        restored.folders.single.heroVideoUrl,
        'https://example.com/hero.mp4',
      );
      expect(restored.viewMode, 'TABBED_GRID');
    },
  );

  test(
    'real addon pack preserves folders and configured sources through export',
    () {
      final raw = utf8.decode(
        gzip.decode(
          File(
            'test/fixtures/collections/kollection-addon.json.gz',
          ).readAsBytesSync(),
        ),
      );
      final input = jsonDecode(raw) as List;
      final pack = HomeCollectionParser.parse(raw);
      expect(pack.length, input.length);
      expect(
        pack.fold<int>(0, (n, c) => n + c.folders.length),
        input.fold<int>(0, (n, c) => n + (c['folders'] as List).length),
      );
      expect(
        pack
            .expand((c) => c.folders)
            .expand((f) => f.sources)
            .every((s) => s.isAddon),
        true,
      );
      expect(pack.fold<int>(0, (n, c) => n + c.sourceCount), 289);
      final restored = HomeCollectionParser.parse(
        jsonEncode(pack.map((c) => c.toJson()).toList()),
      );
      expect(restored.map((c) => c.toJson()), pack.map((c) => c.toJson()));
    },
  );

  test('real native pack preserves all 1755 sources through export', () {
    final file = File('test/fixtures/collections/kaptain-native-0.61.json.gz');
    final pack = HomeCollectionParser.parse(
      utf8.decode(gzip.decode(file.readAsBytesSync())),
    );
    final sources = pack
        .expand((c) => c.folders)
        .expand((f) => f.sources)
        .toList();
    expect(sources.where((s) => s.provider == 'tmdb'), hasLength(822));
    expect(sources.where((s) => s.provider == 'trakt'), hasLength(933));
    final restored = HomeCollectionParser.parse(
      jsonEncode(pack.map((c) => c.toJson()).toList()),
    );
    expect(
      restored
          .expand((c) => c.folders)
          .expand((f) => f.sources)
          .map((s) => s.key),
      sources.map((s) => s.key),
    );
  });

  test('native discover preserves Nuvio streaming and network defaults', () {
    final query = CollectionNativeSourceService.discoverQuery(
      source('NETWORK', filters: {'withWatchProviders': '8'}),
      1,
    );
    expect(query['watch_region'], 'US');
    expect(
      query['with_watch_monetization_types'],
      'flatrate|free|ads|rent|buy',
    );
    expect(query['with_status'], '0|3|4');
    expect(
      query['first_air_date.lte'],
      DateTime.now().toIso8601String().substring(0, 10),
    );
    final explicit = CollectionNativeSourceService.discoverQuery(
      source(
        'NETWORK',
        filters: {
          'releaseDateLte': '2027-01-01',
          'watchRegion': 'IN',
          'withoutWatchProviders': '8',
        },
      ),
      1,
    );
    expect(explicit['first_air_date.lte'], '2027-01-01');
    expect(explicit['watch_region'], 'IN');
    expect(explicit.containsKey('with_watch_monetization_types'), false);
  });

  test('TMDB discover translates TV dates and all supplied filters', () async {
    late Uri uri;
    final service = CollectionNativeSourceService(
      resolveIds: false,
      tmdbToken: 'dummy',
      client: MockClient((request) async {
        uri = request.url;
        expect(request.headers['Authorization'], 'Bearer dummy');
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 1, 'name': 'Series', 'first_air_date': '2026-01-01'},
            ],
            'total_pages': 3,
          }),
          200,
        );
      }),
    );
    final result = await service.fetch(
      source(
        'NETWORK',
        filters: {
          'releaseDateGte': '2020-01-01',
          'releaseDateLte': '2026-12-31',
          'year': 2026,
          'withGenres': '18',
          'withoutGenres': '16',
          'watchRegion': 'IN',
          'withWatchProviders': '8',
          'voteCountGte': 20,
        },
      ),
      2,
    );
    expect(uri.path, '/3/discover/tv');
    expect(
      uri.queryParameters,
      containsPair('first_air_date.gte', '2020-01-01'),
    );
    expect(uri.queryParameters, containsPair('first_air_date_year', '2026'));
    expect(uri.queryParameters, containsPair('with_networks', '42'));
    expect(uri.queryParameters, containsPair('watch_region', 'IN'));
    expect(result.hasMore, true);
    expect(result.items.single.type, 'series');
  });

  for (final kind in ['LIST', 'COLLECTION', 'PERSON', 'DIRECTOR']) {
    test('large $kind enriches only the requested local page', () async {
      var catalogCalls = 0;
      final lookups = <int>[];
      final delayed = Completer<http.Response>();
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/external_ids')) {
            final id = int.parse(request.url.path.split('/')[3]);
            lookups.add(id);
            if (id > CollectionNativeSourceService.tmdbLocalPageSize) {
              return delayed.future;
            }
            return http.Response(jsonEncode({'imdb_id': 'tt$id'}), 200);
          }
          catalogCalls++;
          final key = switch (kind) {
            'LIST' => 'items',
            'COLLECTION' => 'parts',
            'PERSON' => 'cast',
            _ => 'crew',
          };
          return http.Response(
            jsonEncode({
              key: [
                for (var id = 1; id <= 400; id++)
                  {
                    'id': id,
                    'title': 'Film $id',
                    'media_type': 'movie',
                    'job': 'Director',
                  },
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(() {
        if (!delayed.isCompleted) {
          delayed.complete(http.Response('{"imdb_id":null}', 200));
        }
        service.close();
      });
      final ref = CollectionCatalogSource.fromJson({
        ...source(kind).toJson(),
        'sortBy': 'original',
      })!;
      final first = await service
          .fetch(ref, 1)
          .timeout(const Duration(seconds: 2));
      expect(first.items.map((m) => m.id), [
        for (var i = 1; i <= 20; i++) 'tt$i',
      ]);
      expect(first.rawCount, 20);
      expect(first.hasMore, true);
      expect(lookups, [for (var i = 1; i <= 20; i++) i]);
      delayed.complete(http.Response('{"imdb_id":null}', 200));
      final second = await service.fetch(ref, 2);
      expect(second.items.first.id, 'tmdb:21');
      expect(second.items.last.id, 'tmdb:40');
      expect(catalogCalls, 1);
      expect(lookups.length, 40);
      final last = await service.fetch(ref, 20);
      expect(last.items.first.id, 'tmdb:381');
      expect(last.items.last.id, 'tmdb:400');
      expect(last.hasMore, false);
      final beyond = await service.fetch(ref, 21);
      expect(beyond.items, isEmpty);
      expect(beyond.hasMore, false);
      expect(catalogCalls, 1);
      expect(lookups.length, 60);
    });
  }

  test(
    'local LIST pages span remote page boundaries without losing titles',
    () async {
      final calls = <int>[];
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          calls.add(page);
          return http.Response(
            jsonEncode({
              'total_pages': 3,
              'items': [
                for (var i = (page - 1) * 15 + 1; i <= page * 15; i++)
                  {'id': i, 'title': 'Film $i'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final ref = CollectionCatalogSource.fromJson({
        ...source('LIST').toJson(),
        'sortBy': 'original',
      })!;
      final pages = [
        for (var page = 1; page <= 3; page++) await service.fetch(ref, page),
      ];
      expect(pages.map((p) => p.rawCount), [20, 20, 5]);
      expect(pages.map((p) => p.hasMore), [true, true, false]);
      expect(pages.expand((p) => p.items).map((m) => m.id), [
        for (var i = 1; i <= 45; i++) 'tmdb:$i',
      ]);
      expect(calls, [1, 2, 3]);
    },
  );

  for (final sort in [
    'popularity.desc',
    'vote_average.desc',
    'vote_count.desc',
    'primary_release_date.desc',
    'first_air_date.desc',
    'vote_count.asc',
  ]) {
    test(
      'LIST $sort orders across remote pages before local enrichment',
      () async {
        final remotePages = <int>[];
        final identities = <int>[];
        final service = CollectionNativeSourceService(
          tmdbToken: 'dummy',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/external_ids')) {
              expect(remotePages, [1, 2]);
              final id = int.parse(request.url.path.split('/')[3]);
              identities.add(id);
              return http.Response(jsonEncode({'imdb_id': 'tt$id'}), 200);
            }
            final page = int.parse(request.url.queryParameters['page']!);
            remotePages.add(page);
            return http.Response(
              jsonEncode({
                'total_pages': 2,
                'items': [
                  for (var id = (page - 1) * 20 + 1; id <= page * 20; id++)
                    {
                      'id': id,
                      'title': 'Film $id',
                      'popularity': id,
                      'vote_average': id / 4,
                      'vote_count': sort.endsWith('.asc') ? 41 - id : id,
                      'release_date': '${1980 + id}-01-01',
                    },
                ],
              }),
              200,
            );
          }),
        );
        addTearDown(service.close);
        final ref = CollectionCatalogSource.fromJson({
          ...source('LIST').toJson(),
          'sortBy': sort,
        })!;
        final first = await service.fetch(ref, 1);
        expect(first.items.map((m) => m.id), [
          for (var id = 40; id >= 21; id--) 'tt$id',
        ]);
        expect(first.hasMore, true);
        expect(identities, [for (var id = 40; id >= 21; id--) id]);
        final second = await service.fetch(ref, 2);
        expect(second.items.map((m) => m.id), [
          for (var id = 20; id >= 1; id--) 'tt$id',
        ]);
        expect(second.hasMore, false);
        expect(remotePages, [1, 2]);
        expect(identities.length, 40);
      },
    );
  }

  test(
    'sorted LIST retries incomplete snapshot before showing any titles',
    () async {
      final pages = <int>[];
      var fail = true;
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          pages.add(page);
          if (page == 2 && fail) {
            fail = false;
            return http.Response('{}', 503);
          }
          return http.Response(
            jsonEncode({
              'total_pages': 2,
              'items': [
                for (var id = (page - 1) * 20 + 1; id <= page * 20; id++)
                  {'id': id, 'title': 'Film $id', 'vote_count': id},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final ref = CollectionCatalogSource.fromJson({
        ...source('LIST').toJson(),
        'sortBy': 'vote_count.desc',
      })!;
      await expectLater(
        service.fetch(ref, 1),
        throwsA(isA<CollectionSourceException>()),
      );
      final first = await service.fetch(ref, 1);
      expect(pages, [1, 2, 2]);
      expect(first.items.map((m) => m.id), [
        for (var id = 40; id >= 21; id--) 'tmdb:$id',
      ]);
    },
  );

  test('local LIST retry preserves buffered items and remote cursor', () async {
    final calls = <int>[];
    var fail = true;
    final service = CollectionNativeSourceService(
      tmdbToken: 'dummy',
      resolveIds: false,
      client: MockClient((request) async {
        final page = int.parse(request.url.queryParameters['page']!);
        calls.add(page);
        if (page == 2 && fail) {
          fail = false;
          return http.Response('{}', 503);
        }
        return http.Response(
          jsonEncode({
            'total_pages': 2,
            'items': [
              for (var i = (page - 1) * 30 + 1; i <= page * 30; i++)
                {'id': i, 'title': 'Film $i'},
            ],
          }),
          200,
        );
      }),
    );
    addTearDown(service.close);
    final ref = CollectionCatalogSource.fromJson({
      ...source('LIST').toJson(),
      'sortBy': 'original',
    })!;
    final pager = NativeCollectionPager(
      fetch: (page) => service.fetch(ref, page),
    );
    expect((await pager.nextPage()).first.id, 'tmdb:1');
    expect(await pager.nextPage(), isEmpty);
    expect(pager.error, isNotNull);
    expect(pager.skip, 20);
    final retried = await pager.nextPage();
    expect(retried.first.id, 'tmdb:21');
    expect(retried.last.id, 'tmdb:40');
    expect(calls, [1, 2, 2]);
    expect((await pager.nextPage()).last.id, 'tmdb:60');
    expect(pager.exhausted, true);
  });

  test(
    'whole list sorting happens before local slicing and repeated readers reuse it',
    () async {
      var requests = 0;
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'items': [
                for (var i = 1; i <= 40; i++)
                  {'id': i, 'title': 'Film $i', 'vote_count': i},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      final ref = CollectionCatalogSource.fromJson({
        ...source('LIST').toJson(),
        'sortBy': 'vote_count.desc',
      })!;
      expect((await service.fetch(ref, 1)).items.map((m) => m.id), [
        for (var i = 40; i >= 21; i--) 'tmdb:$i',
      ]);
      expect((await service.fetch(ref, 2)).items.map((m) => m.id), [
        for (var i = 20; i >= 1; i--) 'tmdb:$i',
      ]);
      expect(requests, 1);
      await service.fetch(ref, 1);
      expect(requests, 1);
    },
  );

  test(
    'retry advances past a bounded window of empty remote list pages',
    () async {
      final calls = <int>[];
      final service = CollectionNativeSourceService(
        tmdbToken: 'dummy',
        resolveIds: false,
        client: MockClient((request) async {
          final page = int.parse(request.url.queryParameters['page']!);
          calls.add(page);
          return http.Response(
            jsonEncode({
              'total_pages': 9,
              'items': [
                if (page == 9) {'id': 1, 'title': 'Film'},
              ],
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      await expectLater(
        service.fetch(source('LIST'), 1),
        throwsA(isA<CollectionSourceException>()),
      );
      expect(calls, [1, 2, 3, 4, 5, 6, 7, 8]);
      final retry = await service.fetch(source('LIST'), 1);
      expect(retry.items.single.id, 'tmdb:1');
      expect(retry.hasMore, false);
      expect(calls.last, 9);
    },
  );

  for (final kind in ['LIST', 'COLLECTION', 'PERSON', 'DIRECTOR']) {
    test('TMDB $kind uses its own endpoint and complete result', () async {
      final service = CollectionNativeSourceService(
        resolveIds: false,
        tmdbToken: 'dummy',
        client: MockClient((request) async {
          final field = switch (kind) {
            'LIST' => 'items',
            'COLLECTION' => 'parts',
            'PERSON' => 'cast',
            _ => 'crew',
          };
          expect(
            request.url.path,
            kind == 'LIST'
                ? '/3/list/42'
                : kind == 'COLLECTION'
                ? '/3/collection/42'
                : '/3/person/42/combined_credits',
          );
          return http.Response(
            jsonEncode({
              field: [
                {
                  'id': 1,
                  'title': 'Film',
                  'media_type': 'movie',
                  'job': 'Director',
                },
                if (kind == 'DIRECTOR')
                  {
                    'id': 2,
                    'title': 'Not directed',
                    'media_type': 'movie',
                    'job': 'Producer',
                  },
              ],
            }),
            200,
          );
        }),
      );
      final page = await service.fetch(source(kind), 1);
      expect(page.items.single.name, 'Film');
      expect(page.hasMore, false);
    });
  }

  test('Trakt sends media, sort, and page and keeps raw count', () async {
    final service = CollectionNativeSourceService(
      resolveIds: false,
      client: MockClient((request) async {
        expect(request.url.path, '/lists/42/items/show');
        expect(request.url.queryParameters, containsPair('sort_by', 'votes'));
        expect(request.url.queryParameters, containsPair('sort_how', 'desc'));
        expect(request.url.queryParameters, containsPair('page', '2'));
        return http.Response(
          jsonEncode([
            {
              'type': 'show',
              'show': {
                'title': 'Series',
                'ids': {'imdb': 'tt123'},
              },
            },
            {
              'type': 'show',
              'show': {'ids': {}},
            },
          ]),
          200,
          headers: {'x-pagination-page-count': '3'},
        );
      }),
    );
    final page = await service.fetch(
      CollectionCatalogSource.fromJson({
        'provider': 'trakt',
        'traktListId': 42,
        'mediaType': 'TV',
        'sortBy': 'votes',
        'sortHow': 'desc',
      })!,
      2,
    );
    expect(page.rawCount, 2);
    expect(page.items.single.type, 'series');
    expect(page.hasMore, true);
  });

  test(
    'native cursor skips watched pages, retries failures, and resets',
    () async {
      final requests = <int>[];
      var fail = true;
      final pager = NativeCollectionPager(
        hides: (m) => m.id == 'watched',
        fetch: (page) async {
          requests.add(page);
          if (page == 2 && fail) {
            throw const CollectionSourceException('Retry later');
          }
          return CollectionSourcePage(
            items: [
              StremioMeta(
                id: page == 1 ? 'watched' : 'new',
                type: 'movie',
                name: 'Title',
              ),
            ],
            rawCount: 1,
            hasMore: page == 1,
          );
        },
      );
      expect(await pager.nextPage(), isEmpty);
      expect(pager.error, 'Retry later');
      expect(pager.skip, 1);
      fail = false;
      expect((await pager.nextPage()).single.id, 'new');
      expect(requests, [1, 2, 2]);
      expect(pager.exhausted, true);
      pager.reset();
      expect(pager.skip, 0);
      expect(pager.exhausted, false);
    },
  );

  test(
    'provider errors are actionable and never include credentials',
    () async {
      for (final status in [401, 404, 429, 500]) {
        final service = CollectionNativeSourceService(
          resolveIds: false,
          tmdbToken: 'private-token',
          client: MockClient(
            (_) async => http.Response('private-token', status),
          ),
        );
        await expectLater(
          service.fetch(source('LIST'), 1),
          throwsA(
            isA<CollectionSourceException>().having(
              (e) => e.message,
              'message',
              isNot(contains('private-token')),
            ),
          ),
        );
      }
    },
  );
}
