import 'dart:convert';
import 'package:debrify/services/episode_tracker_snapshot_revision.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/season_watched_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({
      'trakt_access_token': 'token',
      'simkl_access_token': 'token',
    });
  });
  tearDown(ProfileRuntime.debugReset);
  test('Trakt skips watched episodes and rechecks history on retry', () async {
    final watched = <int>{1};
    final writes = <int>[];
    var reads = 0;
    await http.runWithClient(
      () async {
        expect(
          await SeasonWatchedService.mark('tt001', 2, [
            1,
            3,
            7,
          ], TrackingSource.trakt),
          1,
        );
        expect(
          await SeasonWatchedService.mark('tt001', 2, [
            1,
            3,
            7,
          ], TrackingSource.trakt),
          0,
        );
        expect(
          await SeasonWatchedService.mark('tt001', 2, [
            1,
            3,
            7,
          ], TrackingSource.trakt),
          0,
        );
      },
      () => MockClient((request) async {
        if (request.method == 'GET') {
          reads++;
          expect(request.url.path, '/shows/tt001/progress/watched');
          return http.Response(
            jsonEncode({
              'seasons': [
                {
                  'number': 2,
                  'episodes': [
                    for (final n in watched) {'number': n, 'completed': true},
                  ],
                },
              ],
            }),
            200,
          );
        }
        final n =
            jsonDecode(
                  request.body,
                )['shows'][0]['seasons'][0]['episodes'][0]['number']
                as int;
        writes.add(n);
        if (n == 7 && reads == 1) return http.Response('{}', 503);
        watched.add(n);
        return http.Response('{}', 200);
      }),
    );
    expect(reads, 3);
    expect(writes, [3, 7, 7]);
  });
  for (final response in [http.Response('{}', 503), http.Response('{}', 200)]) {
    test(
      'Trakt does not write when inventory is unavailable ${response.statusCode}',
      () async {
        await http.runWithClient(
          () async {
            expect(
              await SeasonWatchedService.mark('tt001', 2, [
                1,
                3,
              ], TrackingSource.trakt),
              2,
            );
          },
          () => MockClient((request) async {
            expect(request.method, 'GET');
            return response;
          }),
        );
      },
    );
  }
  test('local marks only selected season without tracker requests', () async {
    final revision = EpisodeTrackerSnapshotRevision.identity('local', 'tt001');
    await http.runWithClient(
      () async {
        expect(
          await SeasonWatchedService.mark(
            'tt001',
            2,
            [1, 3, 3, 7],
            TrackingSource.local,
            seriesTitle: 'Example',
          ),
          0,
        );
        expect(
          await StorageService.getFinishedEpisodesByImdbId(imdbId: 'tt001'),
          {
            '2': {1, 3, 7},
          },
        );
        expect(
          await StorageService.getFinishedEpisodesByImdbId(imdbId: 'tt002'),
          isEmpty,
        );
        expect(
          EpisodeTrackerSnapshotRevision.identity('local', 'tt001'),
          greaterThan(revision),
        );
      },
      () => MockClient((request) async {
        fail('Local action must not contact trackers');
      }),
    );
  });
  test(
    'MDBList marks each season episode without touching another tracker',
    () async {
      final numbers = <int>[];
      final service = MdblistService.forTesting(
        apiKeyProvider: () async => 'key',
        client: MockClient((request) async {
          expect(request.url.host, contains('mdblist'));
          expect(request.url.path, '/sync/watched');
          final show = jsonDecode(request.body)['shows'].single;
          expect(show['ids']['imdb'], 'tt001');
          final season = show['seasons'].single;
          expect(season['number'], 0);
          numbers.add(season['episodes'].single['number'] as int);
          return http.Response('{}', 200);
        }),
      );
      expect(
        await SeasonWatchedService.mark(
          'tt001',
          0,
          [2, 5],
          TrackingSource.mdblist,
          mdblistService: service,
        ),
        0,
      );
      expect(numbers, [2, 5]);
    },
  );
  for (final provider in [TrackingSource.trakt, TrackingSource.simkl]) {
    test(
      '$provider marks only chosen season episodes and reports partial failure',
      () async {
        final numbers = <int>[];
        final deleted = <String>[];
        await http.runWithClient(
          () async {
            expect(
              await SeasonWatchedService.mark('tt001', 2, [
                1,
                3,
                3,
                7,
              ], provider),
              1,
            );
          },
          () => MockClient((request) async {
            expect(request.url.host, contains(provider.name));
            if (request.url.path == '/shows/tt001/progress/watched') {
              return http.Response('{"seasons":[]}', 200);
            }
            if (request.method == 'GET' &&
                request.url.path == '/sync/playback/episodes') {
              return http.Response(
                jsonEncode([
                  for (final n in [1, 3, 7])
                    {
                      'id': n,
                      'show': {
                        'ids': {'imdb': 'tt001'},
                      },
                      'episode': {'season': 2, 'number': n},
                    },
                ]),
                200,
              );
            }
            if (request.method == 'DELETE') {
              deleted.add(request.url.path);
              return http.Response('', 204);
            }
            expect(request.url.path, '/sync/history');
            final show = jsonDecode(request.body)['shows'].single;
            expect(show['ids']['imdb'], 'tt001');
            final season = show['seasons'].single;
            expect(season['number'], 2);
            final number = season['episodes'].single['number'] as int;
            numbers.add(number);
            return http.Response('{}', number == 3 ? 503 : 200);
          }),
        );
        expect(numbers, [1, 3, 7]);
        expect(
          deleted,
          provider == TrackingSource.simkl
              ? ['/sync/playback/1', '/sync/playback/7']
              : isEmpty,
        );
      },
    );
  }
}
