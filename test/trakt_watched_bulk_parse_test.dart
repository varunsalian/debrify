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
}
