import 'dart:convert';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/metadata_preferences_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import '../../../../support/merged_detail_fixture.dart';

class RecordingWatchlistStore extends InMemorySharedPreferencesStore {
  RecordingWatchlistStore(super.data) : super.withData();
  final watchlistWrites = <String>[];
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.endsWith('my_watchlist_v1')) {
      watchlistWrites.add('set:$key');
    }
    return super.setValue(type, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    if (key.endsWith('my_watchlist_v1')) {
      watchlistWrites.add('remove:$key');
    }
    return super.remove(key);
  }

  Future<Map<String, Object>> watchlistRows() async => {
    for (final entry in (await getAll()).entries)
      if (entry.key.endsWith('my_watchlist_v1')) entry.key: entry.value,
  };
}

void main() {
  for (final profile in [false, true]) {
    testWidgets(
      '${profile ? 'profile' : 'policy'} change rejects stale recommendations and retains original identity for taps',
      (t) async {
        await mergedDetailCase(t, (f) async {
          await MetadataPreferencesService.save(
            MetadataPreferences(
              providers: {
                MetadataCategory.information: MetadataPreferences.tmdb,
              },
            ),
          );
          f.item = const StremioMeta(
            id: 'merged-rec-movie',
            type: 'movie',
            name: 'Original Recommendations',
          );
          final stale = Completer<List<StremioMeta>>();
          final fresh = Completer<List<StremioMeta>>();
          f.heldRecommendations = stale;
          await f.mount(t, wait: false);
          await f.until(t, () => f.calls.contains('recommendations'));
          expect(f.access['recommendations'], isNull);
          f.calls.clear();
          f.heldRecommendations = fresh;
          if (profile) {
            ProfileRuntime.scope.value = ProfileScope(
              profileId: 'merged-metadata-next',
              dataGeneration: 1,
              sessionEpoch: 1,
            );
          } else {
            MetadataPreferencesService.revision.value++;
          }
          await f.until(t, () => f.calls.contains('recommendations'));
          final originals = [
            StremioMeta(
              id: 'same-original',
              type: 'movie',
              name: 'First Original',
            ),
            StremioMeta(
              id: 'same-original',
              type: 'movie',
              name: 'Second Original',
            ),
          ];
          fresh.complete(originals);
          await f.until(
            t,
            () => (f.access['recommendationOriginals'] as Map).length == 2,
          );
          for (var frame = 0; frame < 8; frame++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          final presented = f.access['recommendations'] as List;
          final mapping = f.access['recommendationOriginals'] as Map;
          expect(mapping[presented[0]], same(originals[0]));
          expect(mapping[presented[1]], same(originals[1]));
          final cards = t
              .widgetList(
                find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_ConsolePoster',
                ),
              )
              .toList();
          expect(cards, hasLength(2));
          await t.tap(
            find.descendant(
              of: find.byWidget(cards[1]),
              matching: find.byType(InkWell),
            ),
          );
          await t.pump();
          expect(f.openedRecommendations, [same(originals[1])]);
          stale.complete([
            const StremioMeta(
              id: 'stale-original',
              type: 'movie',
              name: 'Stale Original',
            ),
          ]);
          for (var frame = 0; frame < 8; frame++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await t.pump();
          }
          expect(f.access['recommendations'], same(presented));
          expect(mapping, hasLength(2));
          expect(f.calls, ['recommendations']);
        });
      },
    );
  }
  for (final profile in [false, true]) {
    testWidgets(
      '${profile ? 'profile' : 'policy'} refresh retains parents resume trackers watchlist and sources',
      (t) async {
        await mergedDetailCase(t, (f) async {
          await MetadataPreferencesService.save(MetadataPreferences());
          final id = profile ? 'tt0088821' : 'tt0088822';
          f.item = StremioMeta(
            id: id,
            imdbId: id,
            type: 'series',
            name: 'Original Retention Series',
          );
          f.xtream = true;
          final store = RecordingWatchlistStore(
            await SharedPreferencesStorePlatform.instance.getAll(),
          );
          SharedPreferencesStorePlatform.instance = store;
          f.traktStatus = const TraktTitleStatus(rating: 8);
          f.simklStatus = const SimklTitleStatus(rating: 7);
          f.mdblistStatus = const MdblistTitleStatus(id: 1, rating: 6);
          f.onRequest = (r) async {
            if (r.url.host != 'graphql.imdb.com') {
              return http.Response('{}', 404);
            }
            final query = (jsonDecode(r.body) as Map)['query'] as String;
            final title = query.contains('query ParentsGuide')
                ? {
                    'parentsGuide': {
                      'categories': [
                        {
                          'category': {'id': 'violence', 'text': 'Violence'},
                          'severity': {
                            'text': 'Mild',
                            'voteType': 'Mild',
                            'votedFor': 1,
                          },
                          'totalSeverityVotes': 1,
                          'guideItems': {
                            'edges': [
                              {
                                'node': {
                                  'isSpoiler': false,
                                  'text': {'plainText': 'Original guide'},
                                },
                              },
                            ],
                          },
                        },
                      ],
                    },
                  }
                : {
                    'ratingsSummary': {
                      'aggregateRating': 8.7,
                      'voteCount': 123,
                    },
                    'principalCredits': [
                      {
                        'category': {'text': 'Stars'},
                        'credits': List.generate(
                          17,
                          (i) => {
                            'name': {
                              'nameText': {'text': 'C$i'},
                            },
                          },
                        ),
                      },
                    ],
                  };
            return http.Response(
              jsonEncode({
                'data': {'title': title},
              }),
              200,
            );
          };
          await t.runAsync(
            () => SeriesSourceService.addSource(
              id,
              SeriesSource(
                torrentHash: 'retained',
                torrentName: 'retained',
                debridService: 'realdebrid',
                debridTorrentId: 'retained',
                boundAt: 1,
              ),
            ),
          );
          await f.mount(t);
          await f.until(
            t,
            () =>
                f.observation.imdbExtra != null &&
                f.observation.parentsGuide != null,
          );
          expect(f.observation.imdbExtra!.rating, 8.7);
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_CastTile',
            ),
            findsNWidgets(12),
          );
          final parents = f.observation.parentsGuide;
          f.next((season: 2, episode: 3, started: true), mutation: true);
          await t.pump();
          expect(find.text('My Watchlist'), findsOneWidget);
          await t.tap(find.text('My Watchlist'));
          await f.until(
            t,
            () => find
                .textContaining('Added to My Watchlist')
                .evaluate()
                .isNotEmpty,
          );
          expect(find.text('In My Watchlist'), findsOneWidget);
          final persisted = await store.watchlistRows();
          expect(persisted, hasLength(1));
          final saved = jsonDecode(persisted.values.single as String) as List;
          expect((saved.single as Map)['item']['id'], id);
          expect(store.watchlistWrites, hasLength(1));
          final writesBefore = [...store.watchlistWrites];
          final imdb = f.observation.imdbExtra;
          final extraRequests = f.requests
              .where(
                (r) =>
                    r.url.host == 'graphql.imdb.com' &&
                    !r.body.contains('query ParentsGuide'),
              )
              .length;
          final generation = f.access['metadataGeneration'] as int;
          final trailer = f.access['trailerGeneration'] as int;
          final source = f.observation.boundSources.single;
          final parentsRequests = f.requests
              .where(
                (r) =>
                    r.url.host == 'graphql.imdb.com' &&
                    r.body.contains('query ParentsGuide'),
              )
              .length;
          f.heldRecommendations = Completer<List<StremioMeta>>();
          f.calls.clear();
          if (profile) {
            ProfileRuntime.scope.value = ProfileScope(
              profileId: 'merged-retention-next',
              dataGeneration: 1,
              sessionEpoch: 1,
            );
          } else {
            MetadataPreferencesService.revision.value++;
          }
          // Observe synchronously, before the cached future can republish.
          expect(f.observation.imdbExtra, isNull);
          await f.until(
            t,
            () => f.access['metadataGeneration'] == generation + 1,
          );
          expect(f.access['trailerGeneration'], trailer + 2);
          expect(f.access['recommendations'], isEmpty);
          final empty = f.access['recommendations'] as List;
          empty.add(f.item);
          empty.removeLast();
          expect(f.observation.parentsGuide, same(parents));
          expect(f.observation.primaryLabel, 'Resume · S2E3');
          expect(
            [
              f.observation.traktRating,
              f.observation.simklRating,
              f.observation.mdblistRating,
            ],
            [8, 7, 6],
          );
          expect(f.observation.inMyWatchlist, true);
          expect(find.text('In My Watchlist'), findsOneWidget);
          expect(find.text('Resume · S2E3'), findsOneWidget);
          expect(await store.watchlistRows(), persisted);
          expect(store.watchlistWrites, writesBefore);
          expect(f.observation.boundSources.single, same(source));
          expect(
            f.calls
                .where(
                  (c) => [
                    'resume',
                    'trakt',
                    'simkl',
                    'mdblist',
                    'recommendations',
                    'selectSource',
                  ].contains(c),
                )
                .toList(),
            ['recommendations'],
          );
          expect(
            f.requests.where(
              (r) =>
                  r.url.host == 'graphql.imdb.com' &&
                  r.body.contains('query ParentsGuide'),
            ),
            hasLength(parentsRequests),
          );
          f.heldRecommendations!.complete([]);
          await f.until(t, () => f.observation.imdbExtra != null);
          expect(f.observation.imdbExtra!.rating, 8.7);
          expect(f.observation.imdbExtra, same(imdb));
          expect(
            f.requests.where(
              (r) =>
                  r.url.host == 'graphql.imdb.com' &&
                  !r.body.contains('query ParentsGuide'),
            ),
            hasLength(extraRequests),
          );
        });
      },
    );
  }
  for (final profile in [false, true]) {
    testWidgets(
      '${profile ? 'profile' : 'policy'} reload retries uncached IMDb extra with exactly one GraphQL request',
      (t) async {
        await mergedDetailCase(t, (f) async {
          await MetadataPreferencesService.save(MetadataPreferences());
          final id = profile ? 'tt0088823' : 'tt0088824';
          f.item = StremioMeta(
            id: id,
            imdbId: id,
            type: 'movie',
            name: 'Uncached IMDb Extra',
          );
          var succeed = false;
          var extras = 0;
          f.onRequest = (r) async {
            if (r.url.host != 'graphql.imdb.com') {
              return http.Response('{}', 404);
            }
            if (r.body.contains('query ParentsGuide')) {
              return http.Response('{}', 404);
            }
            extras++;
            return http.Response(
              jsonEncode({
                'data': {
                  'title': {
                    'ratingsSummary': {
                      'aggregateRating': 8.9,
                      'voteCount': 456,
                    },
                  },
                },
              }),
              succeed ? 200 : 500,
            );
          };
          await f.mount(t);
          await f.until(t, () => extras == 1);
          expect(f.model.imdbExtra, isNull);
          final before = extras;
          succeed = true;
          if (profile) {
            ProfileRuntime.scope.value = ProfileScope(
              profileId: 'merged-extra-next',
              dataGeneration: 1,
              sessionEpoch: 1,
            );
          } else {
            MetadataPreferencesService.revision.value++;
          }
          expect(f.observation.imdbExtra, isNull);
          await f.until(t, () => f.model.imdbExtra != null);
          expect(extras, before + 1);
          expect(f.model.imdbExtra!.rating, 8.9);
          final requests = f.requests
              .where(
                (r) =>
                    r.url.host == 'graphql.imdb.com' &&
                    !r.body.contains('query ParentsGuide'),
              )
              .toList();
          expect(requests, hasLength(before + 1));
          expect((jsonDecode(requests.last.body) as Map)['variables'], {
            'id': id,
          });
        });
      },
    );
  }
}
