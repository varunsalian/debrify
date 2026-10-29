// "Mark earlier episodes watched": which episodes count as earlier, and how a
// batch fans out per provider and season.
import 'package:debrify/features/episodes_panel/application/earlier_episodes.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:flutter_test/flutter_test.dart';

TraktEpisode _e(int season, int number, {String? aired}) => TraktEpisode(
  season: season,
  number: number,
  title: 'S${season}E$number',
  firstAired: aired,
);

TraktSeason _s(int number, List<TraktEpisode> episodes) => TraktSeason(
  number: number,
  episodeCount: episodes.length,
  episodes: episodes,
);

void main() {
  final now = DateTime.utc(2026, 10, 30);
  final seasons = [
    _s(2, [_e(2, 2), _e(2, 1), _e(2, 3)]),
    _s(0, [_e(0, 1), _e(0, 2)]),
    _s(1, [_e(1, 1), _e(1, 2)]),
  ];

  group('earlierEpisodes', () {
    test('earlier seasons and earlier numbers, in order, no specials', () {
      expect(earlierEpisodes(seasons, season: 2, episode: 3, now: now), [
        (season: 1, episode: 1),
        (season: 1, episode: 2),
        (season: 2, episode: 1),
        (season: 2, episode: 2),
      ]);
    });

    test('the first episode has nothing before it', () {
      expect(
        earlierEpisodes(seasons, season: 1, episode: 1, now: now),
        isEmpty,
      );
    });

    test('a special only counts earlier specials', () {
      expect(earlierEpisodes(seasons, season: 0, episode: 2, now: now), [
        (season: 0, episode: 1),
      ]);
    });

    test('unaired episodes are skipped; unknown air dates count as aired', () {
      final withDates = [
        _s(1, [
          _e(1, 1, aired: '2026-01-01T00:00:00.000Z'),
          _e(1, 2, aired: '2027-01-01T00:00:00.000Z'),
          _e(1, 3, aired: 'not a date'),
          _e(1, 4),
        ]),
      ];
      expect(earlierEpisodes(withDates, season: 1, episode: 5, now: now), [
        (season: 1, episode: 1),
        (season: 1, episode: 3),
        (season: 1, episode: 4),
      ]);
    });

    test('duplicates appear once', () {
      final dup = [
        _s(1, [_e(1, 1), _e(1, 1)]),
        _s(1, [_e(1, 1)]),
      ];
      expect(earlierEpisodes(dup, season: 1, episode: 2, now: now), [
        (season: 1, episode: 1),
      ]);
    });
  });

  group('markEarlierEpisodesWatched', () {
    test(
      'one call per provider and season, in order, sorted numbers',
      () async {
        final calls = <String>[];
        final result = await markEarlierEpisodesWatched(
          imdbId: 'tt9',
          seriesTitle: 'Show',
          episodes: const [
            (season: 2, episode: 2),
            (season: 1, episode: 2),
            (season: 2, episode: 1),
            (season: 1, episode: 1),
          ],
          providers: const [TrackingSource.local, TrackingSource.trakt],
          mark: (id, season, episodes, provider, {seriesTitle}) async {
            calls.add(
              '$id ${provider.name} S$season ${episodes.toList()} $seriesTitle',
            );
            return 0;
          },
        );
        expect(calls, [
          'tt9 local S1 [1, 2] Show',
          'tt9 local S2 [1, 2] Show',
          'tt9 trakt S1 [1, 2] Show',
          'tt9 trakt S2 [1, 2] Show',
        ]);
        expect(result.marked, 4);
        expect(result.failed, isEmpty);
        expect(result.hasFailures, isFalse);
      },
    );

    test(
      'failures are counted per provider; a throw fails that season only',
      () async {
        final result = await markEarlierEpisodesWatched(
          imdbId: 'tt9',
          seriesTitle: 'Show',
          episodes: const [
            (season: 1, episode: 1),
            (season: 1, episode: 2),
            (season: 2, episode: 1),
          ],
          providers: const [TrackingSource.local, TrackingSource.simkl],
          mark: (id, season, episodes, provider, {seriesTitle}) async {
            if (provider == TrackingSource.simkl && season == 1) {
              throw StateError('offline');
            }
            if (provider == TrackingSource.simkl) return 1;
            return 0;
          },
        );
        expect(result.marked, 3);
        expect(result.failed, {TrackingSource.simkl: 3});
        expect(result.hasFailures, isTrue);
      },
    );

    test('stops before the next call once canContinue is false', () async {
      final calls = <int>[];
      var allowed = true;
      final result = await markEarlierEpisodesWatched(
        imdbId: 'tt9',
        seriesTitle: 'Show',
        episodes: const [(season: 1, episode: 1), (season: 2, episode: 1)],
        providers: const [TrackingSource.local],
        canContinue: () => allowed,
        mark: (id, season, episodes, provider, {seriesTitle}) async {
          calls.add(season);
          allowed = false;
          return 0;
        },
      );
      expect(calls, [1]);
      expect(result.cancelled, isTrue);
    });

    test('nothing to mark makes no calls', () async {
      var calls = 0;
      final result = await markEarlierEpisodesWatched(
        imdbId: 'tt9',
        seriesTitle: 'Show',
        episodes: const [],
        providers: const [TrackingSource.local],
        mark: (id, season, episodes, provider, {seriesTitle}) async {
          calls++;
          return 0;
        },
      );
      expect(calls, 0);
      expect(result.marked, 0);
    });
  });
}
