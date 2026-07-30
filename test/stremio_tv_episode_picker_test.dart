import 'package:debrify/utils/stremio_tv_episode_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StremioTvEpisodePicker', () {
    test('selects from the real episode list beyond episodes 1-5', () {
      final rows = List.generate(
        12,
        (index) => <String, dynamic>{
          'season': 1,
          'number': index + 1,
          'airdate': '2020-01-${(index + 1).toString().padLeft(2, '0')}',
        },
      );

      final picked = <int>{};
      for (var i = 0; i < 50; i++) {
        picked.add(
          StremioTvEpisodePicker.pick(
            rows,
            seed: 'channel:slot:$i',
            now: DateTime.utc(2026),
          )!.episode,
        );
      }

      expect(picked.any((episode) => episode > 5), isTrue);
    });

    test('ignores specials, invalid rows, duplicates, and future episodes', () {
      final result = StremioTvEpisodePicker.pick(
        <Map<String, dynamic>>[
          {'season': 0, 'number': 1},
          {'season': 1, 'number': 0},
          {'season': 1, 'number': 7, 'airdate': '2024-01-01'},
          {'season': 1, 'number': 7, 'airdate': '2024-01-01'},
          {'season': 1, 'number': 8, 'airdate': '2030-01-01'},
        ],
        seed: 'only-valid-episode',
        now: DateTime.utc(2026),
      );

      expect(result, (season: 1, episode: 7));
    });

    test('accepts numeric strings and the alternate episode key', () {
      final result = StremioTvEpisodePicker.pick(const [
        {'season': '2', 'episode': '11'},
      ], seed: 'string-fields');

      expect(result, (season: 2, episode: 11));
    });

    test('TVMaze mode rejects numbered episodes without an air date', () {
      final result = StremioTvEpisodePicker.pick(
        const [
          {'season': 1, 'number': 8},
          {'season': 1, 'number': 9, 'airdate': ''},
          {'season': 1, 'number': 7, 'airdate': '2024-01-01'},
        ],
        seed: 'tvmaze-undated',
        now: DateTime.utc(2026),
        requireAirDate: true,
      );

      expect(result, (season: 1, episode: 7));
    });

    test('Stremio mode remains permissive when historical rows omit dates', () {
      final result = StremioTvEpisodePicker.pick(
        const [
          {'season': 4, 'number': 3},
        ],
        seed: 'stremio-undated',
        now: DateTime.utc(2026),
      );

      expect(result, (season: 4, episode: 3));
    });
  });
}
