import 'dart:convert';

import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_constants.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/simkl_storage.dart';
import 'package:debrify/services/storage/trakt_storage.dart';
import 'package:debrify/services/storage/tracking_source_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../../../support/episodes_panel_fixture.dart';

const simklQuery = {
  'client_id': kSimklClientId,
  'app-name': kSimklAppName,
  'app-version': kSimklAppVersion,
};
final simklQueryString = Uri(queryParameters: simklQuery).query;

Map<String, Object> episodeBody(
  Map<String, Object> ids, {
  Map<String, Object> attributes = const {},
}) => {
  'shows': [
    {
      'ids': ids,
      'seasons': [
        {
          'number': 1,
          'episodes': [
            {'number': 1, ...attributes},
          ],
        },
      ],
    },
  ],
};

void expectRequest(
  http.Request r, {
  required String method,
  required String host,
  required String path,
  required Map<String, String> query,
  required Object? body,
}) {
  expect(r.method, method);
  expect(r.url.scheme, 'https');
  expect(r.url.host, host);
  expect(r.url.path, path);
  expect(r.url.queryParameters, query);
  expect(r.body.isEmpty ? null : jsonDecode(r.body), body);
}

String timestampInWindow(
  http.Request r,
  String field,
  DateTime before,
  DateTime after,
) {
  final body = jsonDecode(r.body) as Map<String, dynamic>;
  final value = body['shows'][0]['seasons'][0]['episodes'][0][field] as String;
  expect(value, endsWith('Z'));
  final parsed = DateTime.parse(value);
  expect(parsed.isUtc, isTrue);
  expect(!parsed.isBefore(before) && !parsed.isAfter(after), isTrue);
  return value;
}

Future<void> actWatched(
  WidgetTester t,
  EpisodesPanelFixture f,
  bool watched,
) async {
  await f.sheet(t);
  await t.tap(find.text(watched ? 'Mark as Watched' : 'Mark as Unwatched'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await f.until(
    t,
    () => find
        .textContaining('Marked as ${watched ? 'Watched' : 'Unwatched'}')
        .evaluate()
        .isNotEmpty,
  );
}

void main() {
  for (final watched in [true, false]) {
    testWidgets(
      'all selected signed-in trackers exact ${watched ? 'watch plus paused deletion' : 'unwatch'} requests and local write',
      (t) async {
        await episodesPanelCase(t, 'all-$watched', watched ? 50 : 51, (
          f,
        ) async {
          await t.runAsync(() async {
            await f.authenticate({
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            });
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            });
            if (!watched) {
              await EpisodeCompletionStorage.markEpisodeAsFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              );
            }
          });
          final map = <String, double>{if (!watched) '1-1': 100};
          f.progressLoader = () async => map;
          f.simklPlayback = {'1-1': 25};
          await f.mount(t);
          expect(
            f.requests.where((r) => r.url.path == '/sync/playback/episodes'),
            isEmpty,
            reason:
                'Direct progress loader leaves the Simkl account-wide cache cold',
          );
          f.requests.clear();
          f.nextEmissions.clear();
          f.completionEmissions.clear();
          final before = DateTime.now().toUtc();
          await actWatched(t, f, watched);
          final after = DateTime.now().toUtc();
          expect(
            f.requests.map(f.requestIdentity),
            watched
                ? [
                    'POST api.trakt.tv/sync/history',
                    'POST api.simkl.com/sync/history?$simklQueryString',
                    'GET api.simkl.com/sync/playback/episodes?$simklQueryString',
                    'DELETE api.simkl.com/sync/playback/981?$simklQueryString',
                    'POST api.mdblist.com/sync/watched?apikey=episodes-test-mdblist',
                  ]
                : [
                    'POST api.trakt.tv/sync/history/remove',
                    'POST api.simkl.com/sync/history/remove?$simklQueryString',
                    'POST api.mdblist.com/sync/watched/remove?apikey=episodes-test-mdblist',
                  ],
          );
          final ids = <String, Object>{'imdb': f.id};
          expectRequest(
            f.requests[0],
            method: 'POST',
            host: 'api.trakt.tv',
            path: watched ? '/sync/history' : '/sync/history/remove',
            query: {},
            body: episodeBody(ids),
          );
          expectRequest(
            f.requests[1],
            method: 'POST',
            host: 'api.simkl.com',
            path: watched ? '/sync/history' : '/sync/history/remove',
            query: simklQuery,
            body: episodeBody(ids),
          );
          if (watched) {
            expectRequest(
              f.requests[2],
              method: 'GET',
              host: 'api.simkl.com',
              path: '/sync/playback/episodes',
              query: simklQuery,
              body: null,
            );
            expectRequest(
              f.requests[3],
              method: 'DELETE',
              host: 'api.simkl.com',
              path: '/sync/playback/981',
              query: simklQuery,
              body: null,
            );
          }
          final mdb = f.requests.last;
          expectRequest(
            mdb,
            method: 'POST',
            host: 'api.mdblist.com',
            path: watched ? '/sync/watched' : '/sync/watched/remove',
            query: {'apikey': 'episodes-test-mdblist'},
            body: episodeBody(
              ids,
              attributes: {
                if (watched)
                  'watched_at': timestampInWindow(
                    mdb,
                    'watched_at',
                    before,
                    after,
                  ),
              },
            ),
          );
          await t.runAsync(() async {
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              watched,
            );
          });
          expect(map, watched ? {'1-1': 100.0} : isEmpty);
          expect(
            f.view.progressOf(f.view.episodes.first),
            watched ? 100 : null,
          );
          expect(f.nextEmissions, [
            (
              target: (season: 1, episode: watched ? 2 : 1, started: watched),
              mutation: true,
            ),
          ]);
          expect(f.completionEmissions, [false]);
          // The test-held map is the actual published map, including later writes.
          map['1-1'] = 37;
          await t.pumpWidget(f.shell(f.panel()));
          expect(f.view.progressOf(f.view.episodes.first), 37);
        });
      },
    );
  }
  for (final watched in [true, false]) {
    testWidgets(
      'none selected remains local only in both directions watched=$watched',
      (t) async {
        await episodesPanelCase(t, 'none-$watched', watched ? 52 : 53, (
          f,
        ) async {
          await t.runAsync(() async {
            await f.authenticate({
              TrackingSource.trakt,
              TrackingSource.simkl,
              TrackingSource.mdblist,
            });
            await TrackingSourceStorage.setTrackingScrobbleTargets({});
            if (!watched) {
              await EpisodeCompletionStorage.markEpisodeAsFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              );
            }
          });
          f.progressLoader = () async => {if (!watched) '1-1': 100};
          await f.mount(t);
          f.requests.clear();
          await actWatched(t, f, watched);
          expect(f.requests, isEmpty);
          expect(
            find.text(
              'Marked as ${watched ? 'Watched' : 'Unwatched'} on this device',
            ),
            findsOneWidget,
          );
          await t.runAsync(() async {
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              watched,
            );
          });
        });
      },
    );
  }
  testWidgets(
    'cached auth still names signed-out selected trackers while fresh auth makes no request',
    (t) async {
      await episodesPanelCase(t, 'cached-auth', 54, (f) async {
        await t.runAsync(() async {
          await f.authenticate({
            TrackingSource.trakt,
            TrackingSource.simkl,
            TrackingSource.mdblist,
          });
          await TrackingSourceStorage.setTrackingScrobbleTargets({
            TrackingSource.trakt,
            TrackingSource.simkl,
            TrackingSource.mdblist,
          });
        });
        f.progressLoader = () async => {};
        await f.mount(t);
        await t.runAsync(() async {
          await TraktStorage.clearTraktAuth();
          await SimklStorage.clearSimklAuth();
          await MdblistStorage.clearMdblistAuth();
        });
        f.requests.clear();
        await actWatched(t, f, true);
        expect(f.requests, isEmpty);
        expect(
          find.text(
            'Marked as Watched on Trakt, Simkl, MDBList and this device',
          ),
          findsOneWidget,
        );
        await t.runAsync(() async {
          expect(
            await EpisodeProgressStorage.isEpisodeFinished(
              seriesTitle: f.show.name,
              season: 1,
              episode: 1,
              imdbId: f.id,
            ),
            isTrue,
          );
        });
      });
    },
  );
  testWidgets('Simkl failure preserves local write and smart optimistic tick', (
    t,
  ) async {
    await episodesPanelCase(t, 'simkl-failure', 55, (f) async {
      await t.runAsync(() async {
        await f.authenticate({TrackingSource.simkl});
        await TrackingSourceStorage.setTrackingScrobbleTargets({
          TrackingSource.simkl,
        });
      });
      f.simklFails = true;
      f.progressLoader = () async => {};
      await f.mount(t);
      f.requests.clear();
      await actWatched(t, f, true);
      expect(f.requests, hasLength(1));
      expectRequest(
        f.requests.single,
        method: 'POST',
        host: 'api.simkl.com',
        path: '/sync/history',
        query: simklQuery,
        body: episodeBody({'imdb': f.id}),
      );
      expect(
        find.text('Marked as Watched on this device — failed on Simkl'),
        findsOneWidget,
      );
      expect(f.view.progressOf(f.view.episodes.first), 100);
      await t.runAsync(() async {
        expect(
          await EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: f.show.name,
            season: 1,
            episode: 1,
            imdbId: f.id,
          ),
          isTrue,
        );
      });
    });
  });
  testWidgets(
    'rendered source not written leaves the optimistic tick unchanged',
    (t) async {
      await episodesPanelCase(t, 'renders-here', 56, (f) async {
        await t.runAsync(() async {
          await f.authenticate({TrackingSource.trakt});
          await TrackingSourceStorage.setTrackingScrobbleTargets({});
          await TrackingSourceStorage.setWatchProgressSource(
            WatchProgressSource.trakt,
          );
        });
        final map = <String, double>{'1-1': 23};
        f.progressLoader = () async => map;
        await f.mount(t);
        f.requests.clear();
        f.nextEmissions.clear();
        f.completionEmissions.clear();
        await actWatched(t, f, true);
        expect(f.requests, isEmpty);
        expect(map, {'1-1': 23.0});
        expect(f.view.progressOf(f.view.episodes.first), 23);
        expect(f.nextEmissions, isEmpty);
        expect(f.completionEmissions, isEmpty);
        await t.runAsync(() async {
          expect(
            await EpisodeProgressStorage.isEpisodeFinished(
              seriesTitle: f.show.name,
              season: 1,
              episode: 1,
              imdbId: f.id,
            ),
            isTrue,
          );
        });
      });
    },
  );
  for (final native in [false, true]) {
    testWidgets(
      '${native ? 'native id writes MDBList' : 'custom id stays local'} with exact identity',
      (t) async {
        await episodesPanelCase(t, 'id-$native', native ? 58 : 57, (f) async {
          f.id = native
              ? 'tmdb:9800058'
              : CustomSeriesIdentity(
                  f.addon.sourceBindingKey,
                  'provider-custom-57',
                ).id;
          f.show = StremioMeta(
            id: native ? f.id : 'provider-custom-57',
            imdbId: native ? null : f.id,
            type: 'series',
            name: f.show.name,
          );
          f.videosOverride = [
            {'season': 1, 'episode': 1, 'title': 'Pilot', 'imdbRating': 7.5},
          ];
          if (native) {
            f.addon = StremioAddon(
              id: 'episodes-native-58',
              name: 'Native',
              baseUrl: '',
              manifestUrl: '',
            );
          }
          f.progressLoader = () async => {};
          f.onRequest = (r) async =>
              native && r.url.host == 'api.themoviedb.org'
              ? http.Response('{}', 404)
              : null;
          await t.runAsync(() async {
            await f.authenticate({TrackingSource.mdblist});
            await TrackingSourceStorage.setTrackingScrobbleTargets({
              TrackingSource.mdblist,
            });
          });
          // Native guide uses its real adapter; this case's deterministic guide is
          // served at the addon URL while its progress ID remains native.
          if (native) {
            f.addon = StremioAddon(
              id: 'episodes-native-58',
              name: 'Native',
              baseUrl: 'https://episodes-original.invalid',
              manifestUrl: 'https://episodes-original.invalid/manifest.json',
              resources: const ['meta'],
              types: const ['series'],
            );
            await t.runAsync(f.rememberCanonical);
          }
          await f.mount(t);
          f.requests.clear();
          final before = DateTime.now().toUtc();
          await actWatched(t, f, true);
          final after = DateTime.now().toUtc();
          if (native) {
            expect(f.requests, hasLength(1));
            final r = f.requests.single;
            expectRequest(
              r,
              method: 'POST',
              host: 'api.mdblist.com',
              path: '/sync/watched',
              query: {'apikey': 'episodes-test-mdblist'},
              body: episodeBody(
                {'tmdb': 9800058},
                attributes: {
                  'watched_at': timestampInWindow(
                    r,
                    'watched_at',
                    before,
                    after,
                  ),
                },
              ),
            );
          } else {
            expect(f.requests, isEmpty);
          }
          await t.runAsync(() async {
            expect(
              await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: f.show.name,
                season: 1,
                episode: 1,
                imdbId: f.id,
              ),
              isTrue,
            );
          });
        });
      },
    );
  }
}
