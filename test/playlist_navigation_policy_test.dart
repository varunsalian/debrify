import 'dart:math';

import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/screens/video_player/playlist_navigation_policy.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter_test/flutter_test.dart';

// Keep Fisher-Yates swaps at their original positions. The requested bounds also
// prove that the caller's Random is borrowed only when the bag needs refilling.
class _LastRandom implements Random {
  final bounds = <int>[];
  @override
  int nextInt(int max) {
    bounds.add(max);
    return max - 1;
  }

  @override
  bool nextBool() => throw StateError('Unexpected nextBool');
  @override
  double nextDouble() => throw StateError('Unexpected nextDouble');
}

List<PlaylistEntry> _entries(int count) => List.generate(
  count,
  (i) => PlaylistEntry(url: 'https://navigation.invalid/$i', title: 'File $i'),
);

SeriesPlaylist _series(List<int> indices) => SeriesPlaylist(
  seasons: [],
  allEpisodes: [
    for (final i in indices)
      SeriesEpisode(
        url: 'https://navigation.invalid/$i',
        title: 'Episode $i',
        filename: 'episode-$i.mkv',
        seriesInfo: const SeriesInfo(isSeries: true),
        originalIndex: i,
      ),
  ],
  isSeries: true,
);

void main() {
  late PlaylistNavigationPolicy policy;
  late _LastRandom random;
  setUp(() {
    policy = PlaylistNavigationPolicy();
    random = _LastRandom();
  });

  int? pick(
    List<PlaylistEntry>? entries,
    int current, {
    SeriesPlaylist? series,
    PlaylistViewMode? mode = PlaylistViewMode.raw,
  }) => policy.pickShuffleIndex(entries, series, current, mode, random);

  test(
    'shuffle consumes other entries once, then refills with borrowed Random',
    () {
      final entries = _entries(4);
      expect(pick(entries, 0), 3);
      expect(random.bounds, [3, 2]);
      expect(pick(entries, 3), 2);
      expect(pick(entries, 2), 1);
      expect(random.bounds, [3, 2]);
      expect(pick(entries, 1), 3);
      expect(random.bounds, [3, 2, 3, 2]);
    },
  );

  test('empty and singleton keep the existing repeat-current behavior', () {
    expect(pick(null, 0), isNull);
    expect(pick([], 0), isNull);
    expect(pick(_entries(1), 0), 0);
    expect(random.bounds, isEmpty);
  });

  test(
    'bag removes a newly selected current entry and invalidated indices',
    () {
      expect(pick(_entries(5), 0), 4);
      // Remaining [1,2,3]: shrink removes 3; explicit selection removes 2.
      expect(pick(_entries(3), 2), 1);
      expect(random.bounds, [4, 3, 2]);
    },
  );

  test(
    'bag is indexed in the current launch list, not cached entry identity',
    () {
      final entries = _entries(4);
      expect(pick(entries, 0), 3);
      final reversed = entries.reversed.toList();
      expect(reversed[pick(reversed, 3)!].url, entries[1].url);
      expect(random.bounds, [3, 2]);
    },
  );

  test('changing continuous mode clears any partially consumed bag', () {
    final entries = _entries(4);
    expect(policy.continuousEnabled, isFalse);
    expect(pick(entries, 0), 3);
    policy.setContinuousAndClear(true);
    expect(policy.continuousEnabled, isTrue);
    expect(pick(entries, 0), 3);
    policy.setContinuousAndClear(false);
    expect(policy.continuousEnabled, isFalse);
    expect(pick(entries, 0), 3);
    expect(random.bounds, [3, 2, 3, 2, 3, 2]);
  });

  test('clearing the bag preserves continuous mode', () {
    policy.setContinuousAndClear(true);
    expect(pick(_entries(4), 0), 3);
    policy.clearBag();
    expect(policy.continuousEnabled, isTrue);
    expect(pick(_entries(4), 0), 3);
  });

  test('collection includes exact forty percent and unknown sizes', () {
    const entries = [
      PlaylistEntry(url: 'a', title: 'Largest', sizeBytes: 1000),
      PlaylistEntry(url: 'b', title: 'Boundary', sizeBytes: 400),
      PlaylistEntry(url: 'c', title: 'Small', sizeBytes: 399),
      PlaylistEntry(url: 'd', title: 'Unknown'),
    ];
    expect(policy.mainGroupIndices(entries), [0, 1, 3]);
    expect(policy.nextIndex(entries, null, 2, false), 0);
    expect(policy.previousIndex(entries, null, 2, false), 0);
    expect(pick(entries, 0, mode: null), 3);
    expect(pick(entries, 3, mode: null), 1);
  });

  test(
    'both years sort oldest first, equal years preserve comparison ties',
    () {
      const entries = [
        PlaylistEntry(url: 'a', title: 'Later 2005', sizeBytes: 1000),
        PlaylistEntry(url: 'b', title: 'First 1999', sizeBytes: 400),
        PlaylistEntry(url: 'c', title: 'Second 1999', sizeBytes: 900),
      ];
      expect(policy.mainGroupIndices(entries), [1, 2, 0]);
    },
  );

  test(
    'sequential boundaries and absent collections return no destination',
    () {
      final entries = _entries(3);
      expect(policy.nextIndex(entries, null, 0, true), 1);
      expect(policy.nextIndex(entries, null, 2, true), -1);
      expect(policy.previousIndex(entries, null, 2, true), 1);
      expect(policy.previousIndex(entries, null, 0, true), -1);
      for (final sequential in [true, false]) {
        expect(policy.nextIndex(null, null, 0, sequential), -1);
        expect(policy.previousIndex([], null, 0, sequential), -1);
      }
    },
  );

  test(
    'series traversal uses original indices and missing-current fallback',
    () {
      final entries = _entries(3);
      final series = _series([1, 2, 0]);
      expect(policy.nextIndex(entries, series, 1, true), 2);
      expect(policy.previousIndex(entries, series, 0, true), 2);
      expect(policy.nextIndex(entries, series, 99, false), 2);
      expect(policy.previousIndex(entries, series, 99, false), -1);
      expect(policy.nextIndex(entries, _series([]), 0, false), -1);
      expect(policy.previousIndex(entries, _series([]), 0, false), -1);
      // Preserve the host's existing traversal behavior even for stale metadata.
      expect(policy.nextIndex(entries, _series([1, 99]), 1, false), 99);
    },
  );

  test('series shuffle deduplicates and rejects invalid original indices', () {
    final entries = _entries(4);
    final series = _series([2, 2, -1, 8, 1]);
    expect(pick(entries, 0, series: series), 1);
    expect(pick(entries, 1, series: series), 2);
    expect(random.bounds, [2]);
  });

  test('series with no valid shuffle indices falls back to launch mode', () {
    expect(pick(_entries(4), 0, series: _series([-1, 8])), 3);
    expect(random.bounds, [3, 2]);
  });
}
