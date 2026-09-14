import 'package:debrify/models/metadata_preferences.dart';
import 'package:debrify/services/episode_artwork_service.dart';
import 'package:debrify/services/metadata_episode_service.dart';
import 'package:debrify/services/tmdb_metadata_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('profile-read failure does not fail optional CW artwork', () async {
    final service = EpisodeArtworkService(
      preferencesLoader: () async => throw StateError('Profile changed'),
    );
    expect(
      await service.resolve(imdbId: 'tt1234567', season: 1, episode: 1),
      isNull,
    );
  });

  test(
    'failed explicit artwork can retry while successful stills remain cached',
    () async {
      var requests = 0;
      final service = EpisodeArtworkService(
        preferencesLoader: () async => MetadataPreferences(
          providers: {MetadataCategory.episodeArtwork: 'tmdb'},
        ),
        metadataEpisodes: MetadataEpisodeService(
          repository: TmdbMetadataRepository(
            token: 'test',
            clientFactory: () => MockClient((request) async {
              requests++;
              if (requests == 1) return http.Response('{}', 503);
              return http.Response(
                request.url.path.contains('/find/')
                    ? '{"tv_results":[{"id":1}]}'
                    : '{"episodes":[{"season_number":1,"episode_number":1,"still_path":"/still.jpg"}]}',
                200,
              );
            }),
          ),
        ),
      );
      expect(
        await service.resolve(imdbId: 'tt1234567', season: 1, episode: 1),
        isNull,
      );
      expect(
        await service.resolve(imdbId: 'tt1234567', season: 1, episode: 1),
        'https://image.tmdb.org/t/p/w300/still.jpg',
      );
      final afterSuccess = requests;
      expect(
        await service.resolve(imdbId: 'tt1234567', season: 1, episode: 1),
        'https://image.tmdb.org/t/p/w300/still.jpg',
      );
      expect(requests, afterSuccess);
    },
  );
}
