import 'dart:convert';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'TMDB-native episode guide retains revival numbering and specials',
    () async {
      final requests = <String>[];
      final service = NativeSeriesMetadataService(
        tmdb: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((request) async {
            requests.add(request.url.path);
            Object body;
            switch (request.url.path) {
              case '/3/tv/237243':
                body = {
                  'seasons': [
                    {'season_number': 4},
                    {'season_number': 0},
                    {'season_number': 4},
                  ],
                };
              case '/3/tv/237243/season/4':
                body = {
                  'episodes': [
                    {
                      'season_number': 4,
                      'episode_number': 6,
                      'name': 'Day 5 - Live Eviction',
                      'air_date': '2026-09-18',
                      'still_path': '/still.jpg',
                    },
                    {'season_number': 99, 'episode_number': 2},
                  ],
                };
              case '/3/tv/237243/season/0':
                body = {
                  'episodes': [
                    {
                      'season_number': 0,
                      'episode_number': 1,
                      'name': 'Special',
                    },
                  ],
                };
              default:
                throw StateError('Unexpected ${request.url}');
            }
            return http.Response(jsonEncode(body), 200);
          }),
        ),
      );
      final videos = await service.episodes('tmdb:237243');
      expect(videos.map((v) => v['id']), [
        'tmdb:237243:0:1',
        'tmdb:237243:4:6',
      ]);
      expect(videos.last['title'], 'Day 5 - Live Eviction');
      expect(videos.last['released'], '2026-09-18');
      expect(requests.toSet(), {
        '/3/tv/237243',
        '/3/tv/237243/season/0',
        '/3/tv/237243/season/4',
      });
      await service.episodes('tmdb:237243');
      expect(requests, hasLength(3));
    },
  );

  test('Simkl-only TV IDs use the exact show episode endpoint', () async {
    await http.runWithClient(
      () async {
        final rows = await NativeSeriesMetadataService().episodes(
          'simkl:2274121',
        );
        expect(rows.single['id'], 'simkl:2274121:4:6');
        expect(rows.single['season'], 4);
        expect(rows.single['episode'], 6);
      },
      () => MockClient((request) async {
        expect(request.url.path, '/tv/episodes/2274121');
        expect(request.url.queryParameters['extended'], 'full');
        return http.Response(
          jsonEncode([
            {
              'season': 4,
              'episode': 6,
              'title': 'Eviction',
              'date': '2026-09-18',
            },
            {'season': -1, 'episode': 2},
          ]),
          200,
        );
      }),
    );
  });

  test('a failed season does not publish an incomplete guide', () async {
    final service = NativeSeriesMetadataService(
      tmdb: TmdbMetadataRepository(
        token: 'test',
        clientFactory: () => MockClient(
          (request) async => request.url.path == '/3/tv/1'
              ? http.Response('{"seasons":[{"season_number":1}]}', 200)
              : http.Response('{}', 503),
        ),
      ),
    );
    await expectLater(
      service.episodes('tmdb:1'),
      throwsA(isA<TmdbMetadataException>()),
    );
  });
}
