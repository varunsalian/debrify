import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildEpisodeTrackerSnapshot', () {
    test('watched wins and partial progress only raises meaningful values', () {
      final result = buildEpisodeTrackerSnapshot(
        watched: const {'1-1'},
        playback: const {'1-1': 20, '1-2': 5, '1-3': 42.5, '2_1': 101},
      );

      expect(result, const {'1_1': 100.0, '1_3': 42.5, '2_1': 100.0});
    });

    test('ignores malformed episode keys and non-finite progress', () {
      final result = buildEpisodeTrackerSnapshot(
        watched: const {'bad', '1-2'},
        playback: {'also-bad': 50, '1-3': double.nan},
      );

      expect(result, const {'1_2': 100.0});
    });
  });

  test(
    'furthestEpisodeTrackerPercent clamps and selects the furthest source',
    () {
      expect(furthestEpisodeTrackerPercent([null, 35, 72.5]), 72.5);
      expect(furthestEpisodeTrackerPercent([-5, 140]), 100.0);
      expect(furthestEpisodeTrackerPercent([null, double.infinity]), isNull);
    },
  );

  group('active Trakt rewatch migration', () {
    test('neutralizes an unproven local completion without deleting it', () {
      final resolved = resolveEpisodeLocalWatchState(
        locallyWatched: true,
        localPositionMs: 3000000,
        localDurationMs: 3000000,
        traktPercent: 37,
        simklPercent: null,
        mdblistPercent: null,
      );

      expect(resolved.watched, isFalse);
      expect(resolved.positionMs, 0);
    });

    test('keeps a genuine local partial during the remote rewatch', () {
      final resolved = resolveEpisodeLocalWatchState(
        locallyWatched: true,
        localPositionMs: 1800000,
        localDurationMs: 3000000,
        traktPercent: 37,
        simklPercent: 42,
        mdblistPercent: null,
      );

      expect(resolved.watched, isFalse);
      expect(resolved.positionMs, 1800000);
    });

    test('independent provider completion is never downgraded', () {
      final resolved = resolveEpisodeLocalWatchState(
        locallyWatched: true,
        localPositionMs: 3000000,
        localDurationMs: 3000000,
        traktPercent: 37,
        simklPercent: 100,
        mdblistPercent: null,
      );

      expect(resolved.watched, isTrue);
      expect(resolved.positionMs, 3000000);
    });

    test('zero and completed Trakt values are not active rewatches', () {
      expect(
        hasActiveTraktEpisodeRewatch(
          traktPercent: 0,
          simklPercent: null,
          mdblistPercent: null,
        ),
        isFalse,
      );
      expect(
        hasActiveTraktEpisodeRewatch(
          traktPercent: 95,
          simklPercent: null,
          mdblistPercent: null,
        ),
        isFalse,
      );
    });
  });

  group('mergedEpisodeUpNext', () {
    const episodes = [
      (season: 1, episode: 1),
      (season: 1, episode: 2),
      (season: 1, episode: 3),
    ];

    test('active merged playback overrides a stale tracker suggestion', () {
      final result = mergedEpisodeUpNext(
        episodes: episodes,
        progress: const {'1-1': 100, '1-2': 49.13},
        trackerNext: const (season: 1, episode: 1),
      );

      expect(result, const (season: 1, episode: 2));
    });

    test('falls forward when the tracker suggestion is already watched', () {
      final result = mergedEpisodeUpNext(
        episodes: episodes,
        progress: const {'1_1': 100},
        trackerNext: const (season: 1, episode: 1),
      );

      expect(result, const (season: 1, episode: 2));
    });

    test('retains an unfinished tracker suggestion without playback', () {
      final result = mergedEpisodeUpNext(
        episodes: episodes,
        progress: const {},
        trackerNext: const (season: 1, episode: 2),
      );

      expect(result, const (season: 1, episode: 2));
    });
  });
}
