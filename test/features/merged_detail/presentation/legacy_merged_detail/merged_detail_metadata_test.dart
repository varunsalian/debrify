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
import '../../../../support/merged_detail_fixture.dart';

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
                  (w) => w.runtimeType.toString() == '_RecCard',
                ),
              )
              .toList();
          expect(cards, hasLength(2));
          (cards[1] as dynamic).onTap();
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
            () => f.model.imdbExtra != null && f.model.parentsGuide != null,
          );
          expect(f.model.imdbExtra!.rating, 8.7);
          expect(
            find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_CastTile',
            ),
            findsNWidgets(12),
          );
          final parents = f.model.parentsGuide;
          f.next((season: 2, episode: 3, started: true), mutation: true);
          f.model.onToggleMyWatchlist!();
          await f.until(
            t,
            () => find
                .textContaining('Added to My Watchlist')
                .evaluate()
                .isNotEmpty,
          );
          final generation = f.access['metadataGeneration'] as int;
          final trailer = f.access['trailerGeneration'] as int;
          final source = f.model.boundSources.single;
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
          await f.until(
            t,
            () => f.access['metadataGeneration'] == generation + 1,
          );
          expect(f.access['trailerGeneration'], trailer + 2);
          expect(f.access['recommendations'], isEmpty);
          final empty = f.access['recommendations'] as List;
          empty.add(f.item);
          empty.removeLast();
          expect(f.model.parentsGuide, same(parents));
          expect(f.model.primaryLabel, 'Resume · S2E3');
          expect(
            [f.model.traktRating, f.model.simklRating, f.model.mdblistRating],
            [8, 7, 6],
          );
          expect(f.model.inMyWatchlist, true);
          expect(f.model.boundSources.single, same(source));
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
          await f.until(t, () => f.model.imdbExtra != null);
          expect(f.model.imdbExtra!.rating, 8.7);
        });
      },
    );
  }
}
