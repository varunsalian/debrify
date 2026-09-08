import 'dart:async';
import 'dart:convert';

import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/imdb_enrichment_service.dart';
import 'package:debrify/services/metadata_details_service.dart';
import 'package:debrify/services/metadata_episode_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const movie = StremioMeta(id: 'tmdb:550', type: 'movie', name: 'Title');

  test('automatic credits retain IMDb in a build without TMDB credentials', () async {
    const configured = String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
    final service = MetadataDetailsService(repository: TmdbMetadataRepository(
      token: configured,
      clientFactory: () => MockClient((_) async => http.Response(
        '{"cast":[{"id":1,"name":"TMDB Actor"}]}', 200)),
    ));
    const existing = ImdbEnrichment(cast: [CastMember(name: 'IMDb Actor')]);
    final result = await service.enrich(movie,
      loadExisting: () async => existing, preferences: MetadataPreferences());
    expect(result!.cast.single.name,
      configured.trim().isEmpty ? 'IMDb Actor' : 'TMDB Actor');
  });

  test(
    'credits begin while IMDb is pending and retain its eventual rating',
    () async {
      final imdb = Completer<ImdbEnrichment?>();
      final requested = Completer<void>();
      final service = MetadataDetailsService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            requested.complete();
            return http.Response('{"cast":[{"id":1,"name":"Cast"}]}', 200);
          }),
        ),
      );
      final result = service.enrich(
        movie,
        loadExisting: () => imdb.future,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.credits: 'tmdb'},
        ),
      );
      await requested.future.timeout(const Duration(seconds: 2));
      imdb.complete(const ImdbEnrichment(rating: 8.8));
      final extra = await result;
      expect(extra!.rating, 8.8);
      expect(extra.cast.single.name, 'Cast');
    },
  );

  test(
    'TMDB cast does not overwrite IMDb ratings or unrelated detail fields',
    () async {
      final service = MetadataDetailsService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient(
            (_) async => http.Response(
              '{"cast":[{"id":12,"name":"Person","character":"Role"},null,{}],'
              '"crew":[{"name":"Director","job":"Director"}]}',
              200,
            ),
          ),
        ),
      );
      const original = ImdbEnrichment(
        rating: 8.8,
        metacriticScore: 90,
        plot: 'Plot',
        awardWins: 3,
        certificate: 'R',
      );
      final result = await service.credits(
        movie,
        original,
        preferences: MetadataPreferences(
          providers: {MetadataCategory.credits: 'tmdb'},
        ),
      );
      expect(result!.rating, 8.8);
      expect(result.metacriticScore, 90);
      expect(result.plot, 'Plot');
      expect(result.awardWins, 3);
      expect(result.certificate, 'R');
      expect(result.cast.single.tmdbPersonId, 12);
      expect(result.director, 'Director');
    },
  );

  test(
    'default recommendations still invoke the original loader once',
    () async {
      var calls = 0;
      final service = MetadataDetailsService();
      final result = await service.recommendations(movie, () async {
        calls++;
        return [movie];
      }, preferences: MetadataPreferences());
      expect(result.single, same(movie));
      expect(calls, 1);
    },
  );

  test(
    'trailers reject malformed entries and rank official trailers first',
    () {
      final result = MetadataDetailsService.parseTrailers([
        null,
        {'site': 'YouTube', 'key': '<invalid>'},
        {'site': 'Vimeo', 'key': 'abcdefghijk'},
        {'site': 'YouTube', 'key': 'abcdefghijk', 'type': 'Teaser'},
        {
          'site': 'YouTube',
          'key': '12345678901',
          'type': 'Trailer',
          'official': true,
        },
        {'site': 'YouTube', 'key': '12345678901', 'type': 'Trailer'},
      ]);
      expect(result.map((r) => r.key), ['12345678901', 'abcdefghijk']);
    },
  );

  test(
    'episode enrichment preserves original inventory, IDs and playback URL',
    () async {
      final service = MetadataEpisodeService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient(
            (_) async => http.Response(
              '{"episodes":[{"season_number":1,"episode_number":1,"name":"Localized",'
              '"overview":"Description","still_path":"/still.jpg"},'
              '{"season_number":1,"episode_number":99,"name":"Do not add"}]}',
              200,
            ),
          ),
        ),
      );
      final season = TraktSeason(
        number: 1,
        episodeCount: 1,
        episodes: [
          TraktEpisode(
            season: 1,
            number: 1,
            title: 'Original',
            imdbId: 'tt123',
            rating: 9,
            playbackUrl: 'https://example.test/episode',
            firstAired: '2020-01-01',
          ),
        ],
      );
      final result = await service.present(
        const StremioMeta(id: 'tmdb:1', type: 'series', name: 'Show'),
        season,
        preferences: MetadataPreferences(
          providers: {
            MetadataCategory.episodeInformation: 'tmdb',
            MetadataCategory.episodeArtwork: 'tmdb',
          },
        ),
      );
      expect(result.episodes, hasLength(1));
      final episode = result.episodes.single;
      expect(episode.number, 1);
      expect(episode.season, 1);
      expect(episode.title, 'Localized');
      expect(episode.imdbId, 'tt123');
      expect(episode.rating, 9);
      expect(episode.playbackUrl, 'https://example.test/episode');
      expect(episode.firstAired, '2020-01-01');
      expect(episode.thumbnailUrl, 'https://image.tmdb.org/t/p/w300/still.jpg');
    },
  );
  for (final fallback in [false, true]) {
    for (final failEnglish in [false, true]) {
      test(
        'episode language fallback=$fallback failed=$failEnglish preserves fields',
        () async {
          final languages = <String>[];
          final service = MetadataEpisodeService(
            repository: TmdbMetadataRepository(
              token: 'test',
              clientFactory: () => MockClient((request) async {
                final language = request.url.queryParameters['language']!;
                languages.add(language);
                if (language == 'en-US' && failEnglish) {
                  return http.Response('{}', 503);
                }
                return http.Response(
                  jsonEncode({
                    'episodes': [
                      {
                        'season_number': 1,
                        'episode_number': 1,
                        'name': language == 'en-US'
                            ? 'English title'
                            : 'Localized title',
                        'overview': language == 'en-US'
                            ? 'English description'
                            : '',
                        'still_path': language == 'en-US'
                            ? '/english.jpg'
                            : '/localized.jpg',
                      },
                      if (language == 'en-US')
                        {
                          'season_number': 1,
                          'episode_number': 99,
                          'name': 'Extra episode',
                        },
                    ],
                  }),
                  200,
                );
              }),
            ),
          );
          final original = TraktSeason(
            number: 1,
            episodeCount: 1,
            episodes: [
              TraktEpisode(
                season: 1,
                number: 1,
                title: 'Current title',
                overview: 'Current description',
                imdbId: 'tt123',
                rating: 8,
                thumbnailUrl: 'https://current.test/still.jpg',
              ),
            ],
          );
          final result = await service.present(
            const StremioMeta(id: 'tmdb:1', type: 'series', name: 'Show'),
            original,
            preferences: MetadataPreferences(
              language: 'fr-FR',
              fallback: fallback,
              providers: {
                MetadataCategory.episodeInformation: 'tmdb',
                MetadataCategory.episodeArtwork: 'tmdb',
              },
            ),
          );
          expect(languages, fallback ? ['fr-FR', 'en-US'] : ['fr-FR']);
          expect(result.episodes, hasLength(1));
          final episode = result.episodes.single;
          expect(episode.title, 'Localized title');
          expect(
            episode.overview,
            !fallback
                ? null
                : failEnglish
                ? 'Current description'
                : 'English description',
          );
          expect(
            episode.thumbnailUrl,
            'https://image.tmdb.org/t/p/w300/localized.jpg',
          );
          expect(episode.imdbId, 'tt123');
          expect(episode.rating, 8);
        },
      );
    }
  }

  test(
    'current episode settings return the original inventory without requests',
    () async {
      var requests = 0;
      final service = MetadataEpisodeService(
        repository: TmdbMetadataRepository(
          token: 'test',
          clientFactory: () => MockClient((_) async {
            requests++;
            return http.Response('{}', 200);
          }),
        ),
      );
      final original = TraktSeason(number: 1, episodeCount: 0, episodes: []);
      expect(
        await service.present(
          movie,
          original,
          preferences: MetadataPreferences(),
        ),
        same(original),
      );
      expect(requests, 0);
    },
  );
}
