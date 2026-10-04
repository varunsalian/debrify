import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import '../../../../support/merged_detail_fixture.dart';

void main() {
  for (final failure in [false, true]) {
    testWidgets(
      'hosted episode watch fan-out ${failure ? 'failure preserves local union' : 'watch unwatch and paused-session deletion'}',
      (t) async {
        await mergedDetailCase(t, (f) async {
          final id = failure ? 'tt0099982' : 'tt0099981';
          var remotelyWatched = false;
          f.item = StremioMeta(
            id: id,
            imdbId: id,
            type: 'series',
            name: 'Original Watched Series',
          );
          f.addon = StremioAddon(
            id: 'merged-watch-$failure',
            name: 'Original Watched',
            baseUrl: 'https://merged-watch.invalid',
            manifestUrl: 'https://merged-watch.invalid/manifest.json',
            resources: const ['meta'],
            types: const ['series'],
          );
          f.onRequest = (r) async {
            Object? body = [];
            var status = 200;
            if (r.url.host == 'merged-watch.invalid') {
              body = {
                'meta': {
                  'videos': [
                    {
                      'id': '$id:1:1',
                      'season': 1,
                      'episode': 1,
                      'title': 'Pilot',
                    },
                    {
                      'id': '$id:1:2',
                      'season': 1,
                      'episode': 2,
                      'title': 'Second',
                    },
                  ],
                },
              };
            } else if (r.url.host.contains('simkl')) {
              switch (r.url.path) {
                case '/sync/watched':
                  body = [
                    {
                      'result': true,
                      'seasons': [
                        {
                          'number': 1,
                          'episodes': [
                            if (remotelyWatched) {'number': 1, 'watched': true},
                          ],
                        },
                      ],
                    },
                  ];
                case '/sync/all-items/all/all':
                  body = {
                    'shows': [
                      {
                        'show': {
                          'title': f.item.name,
                          'ids': {'imdb': id},
                        },
                        'status': 'watching',
                      },
                    ],
                  };
                case '/sync/playback/episodes':
                  body = [
                    {
                      'id': 981,
                      'progress': 25,
                      'show': {
                        'ids': {'imdb': id},
                      },
                      'episode': {'season': 1, 'number': 1},
                    },
                  ];
                case '/sync/history':
                  remotelyWatched = !failure;
                  status = failure ? 500 : 200;
                  body = {
                    'added': {'episodes': failure ? 0 : 1},
                  };
                case '/sync/history/remove':
                  remotelyWatched = false;
                  body = {
                    'deleted': {'episodes': 1},
                  };
                case '/sync/playback/981':
                  status = 204;
                  body = null;
              }
            }
            return http.Response(body == null ? '' : jsonEncode(body), status);
          };
          await t.runAsync(() async {
            await SimklStorage.setSimklAccessToken('merged-fixture-simkl');
            await TraktStorage.setTraktAccessToken('merged-fixture-trakt');
            await TraktStorage.setTraktTokenExpiry(
              DateTime.now()
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch,
            );
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.simkl,
              TrackingSource.mdblist,
            });
            await TrackingSourceStorage.setWatchProgressSource(
              WatchProgressSource.smart,
            );
          });
          await f.mount(t);
          await f.until(
            t,
            () =>
                find
                    .byWidgetPredicate(
                      (w) => w.runtimeType.toString() == '_CompactEpisodeRow',
                    )
                    .evaluate()
                    .length ==
                2,
          );
          dynamic pilot() => t
              .widgetList(
                find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_CompactEpisodeRow',
                ),
              )
              .singleWhere((row) => (row as dynamic).episode.number == 1);
          await f.until(
            t,
            () =>
                f.requests.any((r) => r.url.path == '/sync/watched') &&
                pilot().watchProgress != null,
          );
          for (var frame = 0; frame < 8; frame++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await t.pump();
          }
          SimklService.instance.resetProfileScope();
          f.requests.clear();
          pilot().onOptions();
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          expect(find.text('Mark as Watched'), findsOneWidget);
          expect(find.textContaining('Simkl and this device'), findsOneWidget);
          await t.tap(find.text('Mark as Watched'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 400));
          await f.until(
            t,
            () =>
                find.textContaining('Marked as Watched').evaluate().isNotEmpty,
          );
          final writes = f.requests
              .where(
                (r) =>
                    r.method != 'GET' &&
                    !(r.url.host.contains('simkl') &&
                        r.url.path == '/sync/watched'),
              )
              .map((r) => '${r.method} ${r.url.path}')
              .toList();
          expect(
            writes,
            failure
                ? ['POST /sync/history']
                : ['POST /sync/history', 'DELETE /sync/playback/981'],
          );
          if (!failure) {
            expect(
              f.requests.where(
                (r) =>
                    r.method == 'GET' &&
                    r.url.path == '/sync/playback/episodes',
              ),
              hasLength(1),
            );
          }
          await t.runAsync(() async {
            expect(
              (await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
                seriesTitle: f.item.name,
                imdbId: id,
              ))['1'],
              {1},
            );
          });
          expect(pilot().watchProgress, 100);
          if (failure) {
            expect(find.textContaining('failed on Simkl'), findsOneWidget);
          } else {
            await t.pump(const Duration(seconds: 3));
            await t.pump(const Duration(milliseconds: 400));
            f.requests.clear();
            pilot().onOptions();
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            expect(find.text('Mark as Unwatched'), findsOneWidget);
            final tile = t.widget<ListTile>(
              find.ancestor(
                of: find.text('Mark as Unwatched'),
                matching: find.byType(ListTile),
              ),
            );
            await t.runAsync(() async {
              tile.onTap!();
              for (
                var attempt = 0;
                attempt < 80 &&
                    !f.requests.any(
                      (r) => r.url.path == '/sync/history/remove',
                    );
                attempt++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            });
            await t.pump();
            await t.pump(const Duration(milliseconds: 400));
            for (
              var frame = 0;
              frame < 80 &&
                  find.textContaining('Marked as Unwatched').evaluate().isEmpty;
              frame++
            ) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 10)),
              );
              await t.pump(const Duration(milliseconds: 50));
            }
            expect(find.textContaining('Marked as Unwatched'), findsOneWidget);
            expect(
              f.requests
                  .where(
                    (r) =>
                        r.method != 'GET' &&
                        !(r.url.host.contains('simkl') &&
                            r.url.path == '/sync/watched'),
                  )
                  .map((r) => '${r.method} ${r.url.path}')
                  .toList(),
              ['POST /sync/history/remove'],
            );
            await t.runAsync(() async {
              expect(
                await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
                  seriesTitle: f.item.name,
                  imdbId: id,
                ),
                isEmpty,
              );
            });
          }
          await t.pumpWidget(const SizedBox.shrink());
          SimklService.instance.resetProfileScope();
          await f.mount(t);
          await f.until(
            t,
            () =>
                find
                    .byWidgetPredicate(
                      (w) => w.runtimeType.toString() == '_CompactEpisodeRow',
                    )
                    .evaluate()
                    .length ==
                2,
          );
          await f.until(t, () => pilot().watchProgress != null);
          expect(pilot().watchProgress, failure ? 100 : lessThan(100));
        });
      },
    );
  }
}
