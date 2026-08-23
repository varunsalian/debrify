import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/services/mdblist/mdblist_continue_watching_service.dart';
import 'package:debrify/services/mdblist/mdblist_discover_models.dart';
import 'package:debrify/services/mdblist/mdblist_discover_source.dart';
import 'package:debrify/services/mdblist/mdblist_item_transformer.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

MdblistService _service(Future<http.Response> Function(http.Request) handler) =>
    MdblistService.forTesting(
      client: MockClient(handler),
      apiKeyProvider: () async => 'test-key',
    );

void main() {
  group('MDBList Discover transport contracts', () {
    test('parses advertised recommendation sections without probing', () async {
      final service = _service((request) async {
        expect(request.url.path, '/lists/recommended');
        return http.Response(
          jsonEncode({
            'sections': [
              {'section': 'rising', 'name': 'Rising Fast'},
            ],
          }),
          200,
        );
      });

      final result = await service.fetchRecommendationSections();

      expect(result.kind, MdblistResultKind.success);
      expect(result.data, hasLength(1));
      expect(result.data!.single['section'], 'rising');
    });

    test(
      'accepts bare recommendation arrays and bucketed item pages',
      () async {
        var call = 0;
        final service = _service((request) async {
          call++;
          if (call == 1) {
            expect(request.url.path, '/lists/recommended/rising/items');
            return http.Response(
              jsonEncode([
                {'imdb_id': 'tt1', 'title': 'One', 'mediatype': 'movie'},
              ]),
              200,
            );
          }
          expect(request.url.path, '/lists/official/popular/items');
          return http.Response(
            jsonEncode({
              'movies': [
                {'imdb_id': 'tt2', 'title': 'Two', 'mediatype': 'movie'},
              ],
              'shows': const [],
              'pagination': {'next_cursor': 'next'},
            }),
            200,
          );
        });

        final recommendations = await service.fetchRecommendationItemsPage(
          'rising',
        );
        final official = await service.fetchOfficialListItemsPage('popular');

        expect(recommendations.data!.items, hasLength(1));
        expect(recommendations.data!.nextCursor, isNull);
        expect(official.data!.items, hasLength(1));
        expect(official.data!.nextCursor, 'next');
      },
    );

    test('preserves cursor pagination delivered in response headers', () async {
      final service = _service(
        (_) async => http.Response(
          jsonEncode([
            {'imdb_id': 'tt1', 'title': 'One', 'mediatype': 'movie'},
          ]),
          200,
          headers: const {'x-next-cursor': 'header-next'},
        ),
      );

      final result = await service.fetchRecommendationItemsPage('rising');

      expect(result.data!.nextCursor, 'header-next');
      expect(result.headers?['x-next-cursor'], 'header-next');
    });

    test('walks enveloped list directories without truncating them', () async {
      var requests = 0;
      final service = _service((request) async {
        requests++;
        expect(request.url.path, '/lists/liked');
        final offset = request.url.queryParameters['offset'];
        if (offset == null) {
          return http.Response(
            jsonEncode({
              'lists': [
                {'id': 1, 'name': 'First'},
              ],
              'pagination': {'offset': 0, 'limit': 1, 'has_more': true},
            }),
            200,
          );
        }
        expect(offset, '1');
        return http.Response(
          jsonEncode({
            'lists': [
              {'id': 2, 'name': 'Second'},
            ],
            'pagination': {'offset': 1, 'limit': 1, 'has_more': false},
          }),
          200,
        );
      });

      final result = await service.fetchLikedListsResult();

      expect(requests, 2);
      expect(result.kind, MdblistResultKind.success);
      expect(result.data!.map((row) => row['name']), ['First', 'Second']);
    });

    test('walks watchlist pages advertised only by response headers', () async {
      var requests = 0;
      final service = _service((request) async {
        requests++;
        expect(request.url.path, '/watchlist/items');
        final offset = request.url.queryParameters['offset'];
        if (offset == null) {
          return http.Response(
            jsonEncode({
              'movies': [
                {
                  'imdb_id': 'tt0111161',
                  'title': 'The Shawshank Redemption',
                  'mediatype': 'movie',
                },
              ],
              'shows': const [],
            }),
            200,
            headers: const {'x-has-more': 'true'},
          );
        }
        expect(offset, '1');
        return http.Response(
          jsonEncode({
            'movies': [
              {
                'imdb_id': 'tt0068646',
                'title': 'The Godfather',
                'mediatype': 'movie',
              },
            ],
            'shows': const [],
          }),
          200,
          headers: const {'x-has-more': 'false'},
        );
      });

      final result = await service.fetchWatchlist();

      expect(requests, 2);
      expect(result.kind, MdblistResultKind.success);
      expect(result.data!.map((row) => row['title']), [
        'The Shawshank Redemption',
        'The Godfather',
      ]);
    });

    test('parses catalog cursor and special quota', () async {
      final service = _service((request) async {
        expect(request.url.path, '/catalog/movie');
        expect(request.url.queryParameters['sort'], 'score');
        return http.Response(
          jsonEncode({
            'movies': [
              {'imdb_id': 'tt3', 'title': 'Three', 'mediatype': 'movie'},
            ],
            'pagination': {'next_cursor': 'catalog-next'},
            'quota': {
              'limit': 4,
              'used': 3,
              'remaining': 1,
              'first_expires_at': '2026-08-30T09:26:56Z',
            },
          }),
          200,
        );
      });

      final result = await service.fetchCatalogPage(
        const MdblistCatalogQuery(),
      );

      expect(result.data!.items, hasLength(1));
      expect(result.data!.nextCursor, 'catalog-next');
      expect(result.data!.quota!.remaining, 1);
      expect(result.data!.quota!.firstExpiresAt, isNotNull);
    });

    test('normalizes invalid catalog path, ranges, sort, and order', () async {
      final service = _service((request) async {
        expect(request.url.path, '/catalog/movie');
        expect(request.url.queryParameters['score_min'], '20');
        expect(request.url.queryParameters['score_max'], '90');
        expect(request.url.queryParameters['runtime_min'], '60');
        expect(request.url.queryParameters['runtime_max'], '180');
        expect(request.url.queryParameters['released_from'], '2025-01-01');
        expect(request.url.queryParameters['released_to'], '2026-01-01');
        expect(request.url.queryParameters['sort'], 'score');
        expect(request.url.queryParameters['sort_order'], 'desc');
        return http.Response(jsonEncode({'movies': const []}), 200);
      });

      await service.fetchCatalogPage(
        const MdblistCatalogQuery(
          mediaType: '../user',
          scoreMin: 90,
          scoreMax: 20,
          runtimeMin: 180,
          runtimeMax: 60,
          releasedFrom: '2026-01-01',
          releasedTo: '2025-01-01',
          sort: 'unknown',
          sortOrder: 'sideways',
        ),
      );
    });

    test('rejects filters that could waste a catalog query', () {
      expect(
        const MdblistCatalogQuery(releasedFrom: '2026-02-31').validationError,
        contains('valid YYYY-MM-DD'),
      );
      expect(
        const MdblistCatalogQuery(country: 'United States').validationError,
        contains('two-letter codes'),
      );
      expect(
        const MdblistCatalogQuery(scoreMin: 101).validationError,
        contains('between 0 and 100'),
      );
    });
  });

  group('MDBList Discover source', () {
    test('Continue Watching carries MDBList progress into the grid', () async {
      final service = _service(
        (_) async => fail('Continue Watching should use the injected snapshot'),
      );
      final source = MdblistDiscoverSource.forTesting(
        service,
        fetchContinueWatching: ({bool force = false}) async =>
            const MdblistResult.success(
              MdblistContinueWatchingSnapshot(
                movies: [
                  MdblistContinueWatchingItem(
                    selection: AdvancedSearchSelection(
                      imdbId: 'tt0111161',
                      isSeries: false,
                      title: 'The Shawshank Redemption',
                      mdblistProgressPercent: 42.5,
                      mdblistSource: true,
                    ),
                    paused: true,
                  ),
                ],
              ),
            ),
      );

      final page = await source.loadLibrary(
        MdblistLibraryView.continueWatching,
      );

      expect(page.items.single.imdbId, 'tt0111161');
      expect(page.progressByImdb['tt0111161'], 0.425);
    });

    test(
      'history unwraps movie/show rows and excludes episode cards',
      () async {
        final service = _service((request) async {
          final type = request.url.queryParameters['mediatype'];
          return http.Response(
            jsonEncode({
              'movies': type == 'movie'
                  ? [
                      {
                        'watched_at': '2026-08-20T00:00:00Z',
                        'movie': {
                          'title': 'Movie',
                          'ids': {'imdb': 'tt1'},
                        },
                      },
                    ]
                  : const [],
              'shows': type == 'show'
                  ? [
                      {
                        'last_watched_at': '2026-08-21T00:00:00Z',
                        'show': {
                          'title': 'Show',
                          'ids': {'imdb': 'tt2'},
                        },
                      },
                    ]
                  : const [],
              'episodes': [
                {
                  'episode': {
                    'title': 'Do not render me',
                    'ids': {'imdb': 'tt-episode'},
                  },
                },
              ],
              'pagination': {'next_cursor': null},
            }),
            200,
          );
        });
        final source = MdblistDiscoverSource.forTesting(service);

        final page = await source.loadLibrary(MdblistLibraryView.history);

        expect(page.kind, MdblistResultKind.success);
        expect(page.items.map((e) => e.name), ['Show', 'Movie']);
        expect(page.items.where((e) => e.id == 'tt-episode'), isEmpty);
      },
    );

    test('failed refresh preserves the previous authoritative page', () async {
      var failing = false;
      final service = _service((request) async {
        if (failing && request.url.queryParameters['mediatype'] == 'movie') {
          return http.Response('offline', 503);
        }
        return http.Response(
          jsonEncode({
            'movies': request.url.queryParameters['mediatype'] == 'movie'
                ? [
                    {
                      'movie': {
                        'title': 'Retained',
                        'ids': {'imdb': 'tt1'},
                      },
                    },
                  ]
                : const [],
            'shows': const [],
            'pagination': {'next_cursor': null},
          }),
          200,
        );
      });
      final source = MdblistDiscoverSource.forTesting(service);

      final first = await source.loadLibrary(MdblistLibraryView.history);
      failing = true;
      final refresh = await source.loadLibrary(
        MdblistLibraryView.history,
        force: true,
      );

      expect(first.complete, isTrue);
      expect(refresh.kind, MdblistResultKind.partial);
      expect(refresh.fromCache, isTrue);
      expect(refresh.items.single.name, 'Retained');
    });

    test(
      'successful watchlist mutation invalidates a cached empty page',
      () async {
        var watchlisted = false;
        var reads = 0;
        final service = _service((request) async {
          if (request.method == 'POST' &&
              request.url.path == '/watchlist/items/add') {
            watchlisted = true;
            return http.Response('{}', 200);
          }
          expect(request.url.path, '/watchlist/items');
          reads++;
          return http.Response(
            jsonEncode({
              'movies': watchlisted
                  ? [
                      {
                        'title': 'The Shawshank Redemption',
                        'imdb_id': 'tt0111161',
                        'mediatype': 'movie',
                      },
                    ]
                  : const [],
              'shows': const [],
              'pagination': {'next_cursor': null},
            }),
            200,
          );
        });
        final source = MdblistDiscoverSource.forTesting(service);

        final empty = await source.loadLibrary(MdblistLibraryView.watchlist);
        final added = await service.addToWatchlist(
          const MdblistMediaIds(imdb: 'tt0111161'),
          'movie',
        );
        final refreshed = await source.loadLibrary(
          MdblistLibraryView.watchlist,
        );

        expect(empty.items, isEmpty);
        expect(added, isTrue);
        expect(refreshed.items.single.name, 'The Shawshank Redemption');
        expect(reads, 2);
      },
    );

    test(
      'same-profile credential changes invalidate directory caches',
      () async {
        var accountName = 'Account A';
        var requests = 0;
        final service = _service((_) async {
          requests++;
          return http.Response(
            jsonEncode([
              {'id': requests, 'name': accountName},
            ]),
            200,
          );
        });
        final source = MdblistDiscoverSource.forTesting(service);

        final first = await source.loadDirectory(MdblistListDirectory.top);
        accountName = 'Account B';
        service.resetProfileScope();
        final second = await source.loadDirectory(MdblistListDirectory.top);

        expect(first.choices.single.label, 'Account A');
        expect(second.choices.single.label, 'Account B');
        expect(requests, 2);
      },
    );

    test(
      'a first partial directory remains usable and visibly partial',
      () async {
        var requests = 0;
        final service = _service((_) async {
          requests++;
          if (requests == 1) {
            return http.Response(
              jsonEncode({
                'lists': [
                  {'id': 1, 'name': 'Retained partial'},
                ],
                'pagination': {'offset': 0, 'limit': 1, 'has_more': true},
              }),
              200,
            );
          }
          return http.Response('offline', 503);
        });
        final source = MdblistDiscoverSource.forTesting(service);

        final result = await source.loadDirectory(MdblistListDirectory.liked);

        expect(result.kind, MdblistResultKind.partial);
        expect(result.choices.single.label, 'Retained partial');
        expect(result.fromCache, isFalse);
      },
    );

    test('profile reset rejects an in-flight directory publication', () async {
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final service = _service((_) async {
        if (!started.isCompleted) started.complete();
        return response.future;
      });
      final source = MdblistDiscoverSource.forTesting(service);

      final pending = source.loadDirectory(MdblistListDirectory.top);
      await started.future;
      service.resetProfileScope();
      response.complete(
        http.Response(
          jsonEncode([
            {'id': 1, 'name': 'Old account'},
          ]),
          200,
        ),
      );

      final result = await pending;
      expect(result.kind, MdblistResultKind.transientFailure);
      expect(result.choices, isEmpty);
    });

    test(
      'catalog performs no request until explicitly applied and caches it',
      () async {
        var requests = 0;
        final service = _service((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'movies': const [],
              'pagination': {'next_cursor': null},
              'quota': {'remaining': 3},
            }),
            200,
          );
        });
        final source = MdblistDiscoverSource.forTesting(service);

        expect(requests, 0);
        final first = await source.applyCatalog(const MdblistCatalogQuery());
        final cached = await source.applyCatalog(const MdblistCatalogQuery());

        expect(requests, 1);
        expect(first.fromCache, isFalse);
        expect(cached.fromCache, isTrue);
      },
    );

    test('library mutations preserve quota-sensitive catalog caches', () async {
      var catalogRequests = 0;
      final service = _service((request) async {
        if (request.url.path == '/watchlist/items/add') {
          return http.Response('{}', 200);
        }
        expect(request.url.path, '/catalog/movie');
        catalogRequests++;
        return http.Response(
          jsonEncode({
            'movies': const [],
            'quota': {'remaining': 3},
          }),
          200,
        );
      });
      final source = MdblistDiscoverSource.forTesting(service);

      await source.applyCatalog(const MdblistCatalogQuery());
      await service.addToWatchlist(
        const MdblistMediaIds(imdb: 'tt0111161'),
        'movie',
      );
      final cached = await source.applyCatalog(const MdblistCatalogQuery());

      expect(catalogRequests, 1);
      expect(cached.fromCache, isTrue);
    });

    test(
      'catalog refuses uncached queries after special quota exhaustion',
      () async {
        var requests = 0;
        final service = _service((_) async {
          requests++;
          return http.Response(
            jsonEncode({
              'movies': const [],
              'quota': {
                'remaining': 0,
                'first_expires_at': '2099-01-01T00:00:00Z',
              },
            }),
            200,
          );
        });
        final source = MdblistDiscoverSource.forTesting(service);

        final first = await source.applyCatalog(const MdblistCatalogQuery());
        final cached = await source.applyCatalog(const MdblistCatalogQuery());
        final blocked = await source.applyCatalog(
          const MdblistCatalogQuery(genre: 'Drama'),
        );

        expect(first.kind, MdblistResultKind.success);
        expect(cached.fromCache, isTrue);
        expect(blocked.kind, MdblistResultKind.rateLimited);
        expect(requests, 1);
      },
    );

    test('an expired catalog slot is no longer treated as exhausted', () {
      final quota = MdblistCatalogQuota.fromJson({
        'remaining': 0,
        'first_expires_at': '2020-01-01T00:00:00Z',
      });

      expect(quota.exhausted, isFalse);
    });
  });

  test('item transformer accepts flat rich rows and nested sync rows', () {
    final flat = MdblistItemTransformer.transformItem({
      'imdb_id': 'tt10',
      'title': 'Flat',
      'mediatype': 'movie',
      'poster': 'https://example/poster.jpg',
      'genre': ['Drama'],
      'runtime': 120,
    });
    final nested = MdblistItemTransformer.transformItem({
      'rated_at': '2026-08-23T00:00:00Z',
      'show': {
        'title': 'Nested',
        'ids': {'imdb': 'tt11'},
      },
    });
    final episode = MdblistItemTransformer.transformItem({
      'imdb_id': 'tt12',
      'title': 'Standalone episode',
      'mediatype': 'episode',
    });

    expect(flat!.poster, 'https://example/poster.jpg');
    expect(flat.genres, ['Drama']);
    expect(flat.runtime, '120 min');
    expect(nested!.type, 'series');
    expect(nested.addedAtMs, isNotNull);
    expect(episode, isNull);
  });
}
