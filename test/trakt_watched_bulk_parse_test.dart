import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('regular watched movie response retains IMDb IDs for card matching', () {
    final watched = TraktService.debugParseWatchedMovies([
      {
        'plays': 1,
        'movie': {
          'ids': {'trakt': 123, 'imdb': 'TT7654321'},
        },
      },
      // The compact extended=min shape is intentionally not accepted: its
      // Trakt IDs cannot be matched against IMDb-keyed catalog cards.
      {
        '123': ['2026-08-01T00:00:00.000Z'],
      },
    ]);

    expect(watched, {'tt7654321': 100.0});
  });

  test('fully watched series requires every aired regular episode', () {
    final watched = TraktService.debugParseFullyWatchedShows([
      {
        'show': {
          'aired_episodes': 3,
          'ids': {'imdb': 'TT1111111'},
        },
        'seasons': [
          {
            'number': 1,
            'episodes': [
              {'number': 1},
              {'number': 2},
              {'number': 3},
            ],
          },
        ],
      },
      {
        'show': {
          'aired_episodes': 3,
          'ids': {'imdb': 'tt2222222'},
        },
        'seasons': [
          {
            'number': 1,
            'episodes': [
              {'number': 1},
              {'number': 2},
            ],
          },
        ],
      },
    ]);

    expect(watched, {'tt1111111'});
  });

  test(
    'fully watched series does not become the movie-style watched toggle',
    () {
      const status = TraktTitleStatus(seriesFullyWatched: true);

      expect(status.titleWatched, isTrue);
      expect(status.watched, isNull);
    },
  );
}
