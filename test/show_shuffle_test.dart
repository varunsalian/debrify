import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/utils/show_shuffle.dart';

void main() {
  test('visits every season before repeating across pack changes', () {
    final shuffle = ShowShuffle(random: Random(7));
    const episodes = [(1, 1), (1, 2), (2, 1), (3, 1)];
    var current = episodes.first;
    final visited = {current};
    for (var i = 1; i < episodes.length; i++) {
      final next = shuffle.pick(List.of(episodes).reversed, current)!;
      expect(visited.add(next), isTrue);
      current = next;
    }
    expect(visited, episodes.toSet());
    expect(shuffle.pick(episodes, current), isNot(current));
  });

  test('failed candidates are excluded even when a cycle is exhausted', () {
    final shuffle = ShowShuffle(random: Random(1));
    const episodes = [(1, 1), (2, 1), (3, 1)];
    final first = shuffle.pick(episodes, (1, 1))!;
    final second = shuffle.pick(episodes, (1, 1), excluded: {first})!;
    expect(second, isNot(first));
    expect(shuffle.pick(episodes, (1, 1), excluded: {first, second}), isNull);
  });

  test('empty and current-only shows have no next episode', () {
    final shuffle = ShowShuffle();
    expect(shuffle.pick([], null), isNull);
    expect(shuffle.pick([(1, 1), (1, 1)], (1, 1)), isNull);
    expect(shuffle.pick([(2, 1)], (1, 1)), (2, 1));
  });

  test('updated catalog never returns removed episodes', () {
    final shuffle = ShowShuffle(random: Random(5));
    shuffle.pick([(1, 1), (2, 1), (3, 1)], (1, 1));
    expect(shuffle.pick([(1, 1), (4, 1)], (1, 1)), (4, 1));
    shuffle.clear();
    expect(shuffle.pick([(1, 1), (2, 1)], (1, 1)), (2, 1));
  });

  test('excludes specials, invalid identities and future air dates', () {
    final now = DateTime.utc(2026, 9, 16, 12);
    bool eligible(Map<String, dynamic> m) =>
        isShuffleEpisodeEligible(m, now: now);
    expect(eligible({'season': 0, 'number': 1}), isFalse);
    expect(eligible({'season': 1, 'number': 0}), isFalse);
    expect(eligible({'season': '1', 'number': 1}), isFalse);
    expect(
      eligible({'season': 1, 'number': 1, 'airdate': '2026-09-17'}),
      isFalse,
    );
    expect(
      eligible({'season': 1, 'number': 1, 'airdate': '2026-09-15'}),
      isTrue,
    );
    expect(
      eligible({'season': 1, 'number': 1, 'airstamp': '2026-09-16T13:00:00Z'}),
      isFalse,
    );
    expect(eligible({'season': 1, 'number': 1}), isTrue);
  });

  test(
    'raw TMDB and addon guides exclude upcoming episodes from initial shuffle',
    () {
      final now = DateTime.utc(2026, 9, 25);
      for (final field in ['number', 'episode']) {
        expect(
          isShuffleEpisodeEligible({
            'season': 1,
            field: 3,
            'released': '2026-09-26T00:00:00Z',
          }, now: now),
          isFalse,
        );
        expect(
          isShuffleEpisodeEligible({
            'season': 1,
            field: 3,
            'released': '2026-09-24',
          }, now: now),
          isTrue,
        );
        expect(
          isShuffleEpisodeEligible({'season': 1, field: 3}, now: now),
          isTrue,
        );
        expect(
          isShuffleEpisodeEligible({'season': 1, field: 0}, now: now),
          isFalse,
        );
      }
    },
  );
}
