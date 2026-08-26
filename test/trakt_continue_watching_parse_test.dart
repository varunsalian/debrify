import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes authoritative Trakt Continue Watching shows', () {
    final normalized = TraktService.debugNormalizeContinueWatchingShows([
      {
        'show': {
          'title': 'Example',
          'ids': {'trakt': 1, 'imdb': 'tt123'},
        },
        'progress': {
          'last_watched_at': '2026-08-25T10:00:00.000Z',
          'next_episode': {'season': 2, 'number': 4, 'runtime': 45},
        },
      },
      {
        'show': {
          'title': 'Completed',
          'ids': {'trakt': 2, 'imdb': 'tt456'},
        },
        'progress': {'next_episode': null},
      },
    ]);

    expect(normalized, [
      {
        'show': {
          'title': 'Example',
          'ids': {'trakt': 1, 'imdb': 'tt123'},
        },
        'type': 'episode',
        'episode': {'season': 2, 'number': 4, 'runtime': 45},
        'paused_at': '2026-08-25T10:00:00.000Z',
      },
    ]);
  });

  test('rejects malformed Trakt Continue Watching payloads', () {
    expect(
      TraktService.debugNormalizeContinueWatchingShows([
        {
          'show': {'title': 'Example'},
          'progress': {'next_episode': 'S02E04'},
        },
      ]),
      isNull,
    );
  });

  test('authoritative membership and episode win over playback', () {
    final exactCheckpoint = {
      'id': 10,
      'progress': 42.0,
      'show': {
        'ids': {'trakt': 100, 'imdb': 'tt100'},
      },
      'episode': {'season': 1, 'number': 2, 'runtime': 44},
      'paused_at': '2026-08-26T10:00:00.000Z',
    };
    final wrongEpisodeCheckpoint = {
      'id': 11,
      'progress': 77.0,
      'show': {
        'ids': {'trakt': 100, 'imdb': 'tt100'},
      },
      'episode': {'season': 1, 'number': 1, 'runtime': 40},
    };
    final excludedShowCheckpoint = {
      'id': 20,
      'progress': 55.0,
      'show': {
        'ids': {'trakt': 200, 'imdb': 'tt200'},
      },
      'episode': {'season': 3, 'number': 4},
    };
    final authoritativeOnly = {
      'show': {
        'ids': {'imdb': 'tt300'},
      },
      'type': 'episode',
      'episode': {'season': 2, 'number': 1},
    };

    final merged = TraktService.debugMergeContinueWatchingShows(
      [wrongEpisodeCheckpoint, excludedShowCheckpoint, exactCheckpoint],
      [
        {
          'show': {
            'ids': {'trakt': 100, 'imdb': 'TT100'},
          },
          'type': 'episode',
          'episode': {'season': 1, 'number': 2, 'runtime': 45},
          'paused_at': '2026-08-25T10:00:00.000Z',
        },
        authoritativeOnly,
      ],
    );

    expect(merged, [
      {
        'show': {
          'ids': {'trakt': 100, 'imdb': 'TT100'},
        },
        'type': 'episode',
        'episode': {'season': 1, 'number': 2, 'runtime': 45},
        'paused_at': '2026-08-25T10:00:00.000Z',
        '_playback_ids': [11, 10],
        'progress': 42.0,
      },
      authoritativeOnly,
    ]);
  });

  test('unmatched playback cannot replace the authoritative next episode', () {
    final merged = TraktService.debugMergeContinueWatchingShows(
      [
        {
          'id': 30,
          'progress': 80.0,
          'show': {
            'ids': {'trakt': 300, 'imdb': 'tt300'},
          },
          'episode': {'season': 2, 'number': 3},
        },
      ],
      [
        {
          'show': {
            'ids': {'trakt': 300, 'imdb': 'tt300'},
          },
          'type': 'episode',
          'episode': {'season': 2, 'number': 4},
          'paused_at': '2026-08-24T10:00:00.000Z',
        },
      ],
    );

    expect(merged, [
      {
        'show': {
          'ids': {'trakt': 300, 'imdb': 'tt300'},
        },
        'type': 'episode',
        'episode': {'season': 2, 'number': 4},
        'paused_at': '2026-08-24T10:00:00.000Z',
        '_playback_ids': [30],
      },
    ]);
  });
}
