import 'package:debrify/utils/stremio_episode_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StremioEpisodeSelector', () {
    test('finds requested episode in parsed filenames', () {
      final filenames = [
        'Show.Name.S01E01.1080p.mkv',
        'Show.Name.S01E02.1080p.mkv',
        'Show.Name.S01E03.1080p.mkv',
      ];

      final index = StremioEpisodeSelector.findEpisodeFileIndex(
        filenames,
        season: 1,
        episode: 2,
      );

      expect(index, 1);
    });

    test('uses folder path context when basename lacks season number', () {
      final filenames = [
        'Show Name/Season 1/Episode 01.mkv',
        'Show Name/Season 2/Episode 05.mkv',
      ];

      final index = StremioEpisodeSelector.findEpisodeFileIndex(
        filenames,
        season: 2,
        episode: 5,
      );

      expect(index, 1);
    });

    test('supports S01 folder with numeric episode filename', () {
      final filenames = ['Show Name/S01/02.mkv', 'Show Name/S01/03.mkv'];

      final index = StremioEpisodeSelector.findEpisodeFileIndex(
        filenames,
        season: 1,
        episode: 2,
      );

      expect(index, 0);
    });

    test('returns null when requested episode is absent', () {
      final filenames = [
        'Show.Name.S01E01.1080p.mkv',
        'Show.Name.S01E02.1080p.mkv',
      ];

      final index = StremioEpisodeSelector.findEpisodeFileIndex(
        filenames,
        season: 1,
        episode: 9,
      );

      expect(index, isNull);
    });

    test('verifies a single-file PikPak episode from its direct title', () {
      expect(
        StremioEpisodeSelector.namesContainEpisode(
          ['Show.Name.S02E07.1080p.mkv', 'Show Name'],
          season: 2,
          episode: 7,
        ),
        isTrue,
      );
    });

    test('verifies a single-file episode from the torrent-name fallback', () {
      expect(
        StremioEpisodeSelector.namesContainEpisode(
          ['video.mkv', 'Show.Name.S03E04.2160p'],
          season: 3,
          episode: 4,
        ),
        isTrue,
      );
    });

    test(
      'does not treat an unverified single file as the requested episode',
      () {
        expect(
          StremioEpisodeSelector.namesContainEpisode(
            ['video.mkv', 'Show.Name.Season.3.Complete'],
            season: 3,
            episode: 4,
          ),
          isFalse,
        );
      },
    );

    test('accepts a generic single file when the torrent name is exact', () {
      final index =
          StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
            ['video.mkv'],
            sourceName: 'Show.Name.S02E07.1080p',
            season: 2,
            episode: 7,
          );

      expect(index, 0);
    });

    test('does not apply the torrent-name fallback to a multi-file pack', () {
      final index =
          StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
            ['video-1.mkv', 'video-2.mkv'],
            sourceName: 'Show.Name.S02E07.1080p',
            season: 2,
            episode: 7,
          );

      expect(index, isNull);
    });

    test('manifest episode match takes precedence over source fallback', () {
      final index =
          StremioEpisodeSelector.findEpisodeFileIndexWithSingleFileFallback(
            ['Show.Name.S02E06.mkv', 'Show.Name.S02E07.mkv'],
            sourceName: 'Show.Name.S02E06.1080p',
            season: 2,
            episode: 7,
          );

      expect(index, 1);
    });

    test('picks the largest file index for movie-style selection', () {
      final index = StremioEpisodeSelector.findLargestFileIndex([
        100,
        null,
        350,
        200,
      ]);

      expect(index, 2);
    });
  });
}
