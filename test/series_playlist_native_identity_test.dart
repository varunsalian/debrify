import 'dart:convert';

import 'package:debrify/models/media_identity.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/native_series_metadata_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/secret_vault.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    SharedPreferences.setMockInitialValues({});
    SecretVault.debugReset(deviceIdOverride: 'playlist-identity-test');
    SimklService.instance.resetProfileScope();
    await StorageService.setSimklAccessToken('synthetic');
  });
  tearDown(() {
    SimklService.instance.resetProfileScope();
    SecretVault.debugReset();
    ProfileRuntime.debugReset();
  });

  for (final identity in ['tmdb:237243', 'simkl:2274121']) {
    for (final fails in [false, true]) {
      test(
        '$identity survives background metadata and pause; failure=$fails',
        () async {
          final episode = SeriesEpisode(
            url: 'https://example.invalid/episode',
            title: 'Big Brother',
            filename: 'Big.Brother.S04E06.mkv',
            seriesInfo: const SeriesInfo(
              title: 'Big Brother',
              season: 4,
              episode: 6,
              isSeries: true,
            ),
            originalIndex: 0,
          );
          final playlist = SeriesPlaylist(
            seriesTitle: 'Big Brother',
            seasons: [
              SeriesSeason(seasonNumber: 4, episodes: [episode]),
            ],
            allEpisodes: [episode],
            isSeries: true,
            // Deliberately stale metadata must not win over the selected show.
            imdbId: 'tt0251497',
            tvmazeShowId: 1,
          );
          final requests = <String>[];
          Map<String, dynamic>? scrobble;
          http.Client client() => MockClient((request) async {
            requests.add(request.url.path);
            if (request.url.path == '/scrobble/pause') {
              scrobble = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response('{"action":"pause"}', 200);
            }
            if (request.url.path == '/3/tv/237243') {
              if (fails) return http.Response('{}', 404);
              return http.Response('{"seasons":[{"season_number":4}]}', 200);
            }
            if (request.url.path == '/3/tv/237243/season/4') {
              return http.Response(
                jsonEncode({
                  'episodes': [
                    {
                      'season_number': 4,
                      'episode_number': 6,
                      'name': 'UK eviction',
                      'overview': 'UK episode',
                      'air_date': '2026-09-18',
                      'still_path': '/uk.jpg',
                    },
                  ],
                }),
                200,
              );
            }
            if (request.url.path == '/tv/episodes/2274121') {
              if (fails) return http.Response('{}', 404);
              return http.Response(
                jsonEncode([
                  {
                    'season': 4,
                    'episode': 6,
                    'title': 'UK eviction',
                    'description': 'UK episode',
                    'date': '2026-09-18',
                    'img': 'uk',
                  },
                ]),
                200,
              );
            }
            fail('Unexpected title-based request: ${request.url.path}');
          });
          await http.runWithClient(() async {
            await playlist.fetchEpisodeInfo(
              imdbId: identity,
              nativeMetadata: NativeSeriesMetadataService(
                tmdb: TmdbMetadataRepository(
                  token: 'test',
                  clientFactory: client,
                ),
              ),
            );
            expect(playlist.imdbId, identity);
            expect(playlist.tvmazeShowId, isNull);
            if (fails) {
              expect(playlist.fullTvmazeEpisodes, isEmpty);
              expect(episode.episodeInfo, isNull);
            } else {
              expect(playlist.fullTvmazeEpisodes.single['season'], 4);
              expect(playlist.fullTvmazeEpisodes.single['number'], 6);
              expect(episode.episodeInfo?.title, 'UK eviction');
              expect(episode.episodeInfo?.plot, 'UK episode');
              expect(episode.episodeInfo?.poster, contains('uk'));
              expect(
                (await playlist.getEpisodeInfoForEpisode(
                  'Big Brother',
                  4,
                  6,
                ))?.title,
                'UK eviction',
              );
              expect(
                await playlist.getEpisodeInfoForEpisode('Big Brother', 99, 1),
                isNull,
              );
            }
            final ok = await SimklService.instance.scrobblePause(
              playlist.imdbId!,
              25,
              season: 4,
              episode: 6,
            );
            expect(ok, isTrue);
          }, client);
          expect(scrobble?['show'], {'ids': MediaIdentity.apiIds(identity)});
          expect(scrobble?['episode'], {'season': 4, 'number': 6});
          expect(requests, isNot(contains('/search/shows')));
        },
      );
    }
  }
}
