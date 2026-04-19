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
