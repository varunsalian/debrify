import 'package:debrify/services/trakt/trakt_continue_watching_merge.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> show(int id) => {
  'title': 'Show $id',
  'ids': {'trakt': id, 'imdb': 'tt$id'},
};
String at(int day) => '2026-09-${day.toString().padLeft(2, '0')}T12:00:00Z';
Map<String, dynamic> paused(
  int id,
  int day, {
  int episode = 1,
  int season = 1,
}) => {
  'id': id * 100 + episode,
  'show': show(id),
  'episode': {'season': season, 'number': episode},
  'progress': 35.0,
  'paused_at': at(day),
};
Map<String, dynamic> next(int id, int day, {int episode = 2}) => {
  'show': show(id),
  'episode': {'season': 1, 'number': episode},
  'type': 'episode',
  'paused_at': at(day),
};
List<dynamic> merge(
  List<dynamic> playback,
  List<Map<String, dynamic>> upNext, {
  List<dynamic> hidden = const [],
  List<dynamic> watched = const [],
}) => mergeTraktContinueWatching(
  playback,
  upNext,
  hidden: hidden,
  watched: watched,
);

void main() {
  test('live-verified hidden season shape resolves its parent show', () {
    // Shape verified against /users/hidden/progress_watched on 2026-09-07.
    // Account timestamp and public content identifiers replaced with fixtures.
    final hidden = {
      'hidden_at': at(2),
      'type': 'season',
      'season': {
        'number': 1,
        'ids': {'trakt': 7609, 'tvdb': 5511, 'tmdb': 7240, 'tvrage': null},
      },
      'show': {
        'title': 'Fixture show',
        'year': 2005,
        'ids': {
          'trakt': 1,
          'slug': 'fixture-show',
          'tvdb': 10,
          'imdb': 'tt1',
          'tmdb': 20,
          'tvrage': null,
        },
      },
    };
    final result = merge(
      [paused(1, 3), paused(2, 3)],
      [next(1, 2)],
      hidden: [hidden],
    );
    expect(result, hasLength(1));
    expect(result.single['show']['ids']['trakt'], 2);
    expect(
      merge([paused(1, 3, season: 2)], [], hidden: [hidden]),
      hasLength(1),
    );
  });

  test('same-second matching Up Next checkpoint retains resume progress', () {
    final result = merge(
      [paused(1, 2, episode: 2)],
      [next(1, 2)],
      watched: [
        {'show': show(1), 'last_watched_at': at(2)},
      ],
    );
    expect(result.single['episode']['number'], 2);
    expect(result.single['progress'], 35);
  });

  test('same-second conflicting episode cannot replace Up Next', () {
    final result = merge([paused(1, 2)], [next(1, 2)]);
    expect(result.single['episode']['number'], 2);
    expect(result.single.containsKey('progress'), isFalse);
  });

  test('newer history still rejects matching Up Next checkpoint', () {
    final result = merge(
      [paused(1, 2, episode: 2)],
      [next(1, 2)],
      watched: [
        {'show': show(1), 'last_watched_at': at(3)},
      ],
    );
    expect(result.single.containsKey('progress'), isFalse);
  });

  test('equal-time checkpoints cannot overwrite selected progress', () {
    final result = merge(
      [
        paused(1, 2, episode: 2),
        {...paused(1, 2, episode: 2), 'progress': 5},
      ],
      [next(1, 2)],
    );
    expect(result.single['progress'], 35);
  });

  test('malformed known hidden season suppresses only its show', () {
    final result = merge(
      [paused(1, 2), paused(2, 2)],
      [next(1, 1)],
      hidden: [
        {
          'show': show(1),
          'type': 'season',
          'season': {'number': 'bad'},
        },
      ],
    );
    expect(result, hasLength(1));
    expect(result.single['show']['ids']['trakt'], 2);
  });

  test(
    'unknown watch date blocks only that show playback, preserving Up Next',
    () {
      final result = merge(
        [paused(1, 3), paused(2, 3), paused(3, 3)],
        [next(1, 1)],
        watched: [
          {'show': show(1)},
          {'show': show(1), 'last_watched_at': at(1)},
          {'show': show(3), 'last_watched_at': 'bad'},
        ],
      );
      expect(result, hasLength(2));
      final one = result.singleWhere((r) => r['show']['ids']['trakt'] == 1);
      expect(one['episode']['number'], 2);
      expect(one.containsKey('progress'), isFalse);
      expect(result.first['show']['ids']['trakt'], 2);
    },
  );

  test(
    'first unfinished episode appears without watched history or Up Next',
    () {
      final result = merge([paused(1, 2)], []);
      expect(result, hasLength(1));
      expect(result.single['episode']['number'], 1);
      expect(result.single['progress'], 35);
      expect(result.single['_playback_ids'], [101]);
    },
  );

  test('newer paused episode wins over a different Up Next episode', () {
    final result = merge([paused(1, 3, episode: 10)], [next(1, 2)]);
    expect(result, hasLength(1));
    expect(result.single['episode']['number'], 10);
    expect(result.single['paused_at'], at(3));
  });

  test('newer completed activity rejects stale playback', () {
    final result = merge([paused(1, 1)], [next(1, 2)]);
    expect(result.single['episode']['number'], 2);
    expect(result.single.containsKey('progress'), isFalse);
  });

  test('finished show does not reappear from an old checkpoint', () {
    final history = [
      {'show': show(1), 'last_watched_at': at(3)},
    ];
    expect(merge([paused(1, 2)], [], watched: history), isEmpty);
    expect(merge([paused(1, 3)], [], watched: history), isEmpty);
    expect(merge([paused(1, 4)], [], watched: history), hasLength(1));
  });

  test(
    'newest checkpoint wins regardless of input order; one card per show',
    () {
      for (final rows in [
        [paused(1, 2), paused(1, 3, episode: 4)],
        [paused(1, 3, episode: 4), paused(1, 2)],
      ]) {
        final result = merge(rows, []);
        expect(result, hasLength(1));
        expect(result.single['episode']['number'], 4);
        expect(result.single['_playback_ids'], unorderedEquals([101, 104]));
      }
    },
  );

  test(
    'mixed IMDb/Trakt identities do not duplicate or bypass hidden shows',
    () {
      final checkpoint = paused(1, 3);
      checkpoint['show'] = {
        'ids': {'imdb': 'TT1'},
      };
      expect(merge([checkpoint], [next(1, 2)]), hasLength(1));
      expect(
        merge(
          [checkpoint],
          [next(1, 2)],
          hidden: [
            {
              'show': {
                'ids': {'trakt': 1},
              },
              'type': 'show',
            },
          ],
        ),
        isEmpty,
      );
    },
  );

  test('hidden season filters only that season, hidden show filters all', () {
    final hidden = [
      {
        'show': show(1),
        'type': 'season',
        'season': {'number': 1},
      },
      {'show': show(2), 'type': 'show'},
    ];
    final result = merge(
      [paused(1, 4), paused(1, 3, season: 2), paused(2, 5)],
      [next(1, 2), next(2, 2)],
      hidden: hidden,
    );
    expect(result, hasLength(1));
    expect(result.single['episode']['season'], 2);
  });

  test('invalid checkpoints cannot create cards', () {
    for (final changes in [
      {'progress': 0},
      {'progress': 100},
      {'progress': double.nan},
      {'progress': '35'},
      {'paused_at': null},
      {'paused_at': 'bad'},
      {
        'episode': {'season': 1, 'number': 0},
      },
      {'show': {}},
    ]) {
      expect(
        merge([
          {...paused(1, 2), ...changes},
        ], []),
        isEmpty,
      );
    }
    expect(merge([paused(1, 2, season: 0)], []), hasLength(1));
  });

  test('merged feed follows latest activity and keeps provider tie order', () {
    final result = merge([paused(3, 4)], [next(2, 2), next(1, 2)]);
    expect(result.map((r) => r['show']['ids']['trakt']), [3, 2, 1]);
  });

  test('inputs remain unchanged', () {
    final a = paused(1, 2);
    final b = next(1, 1);
    merge([a], [b]);
    expect(a.containsKey('_playback_ids'), isFalse);
    expect(b.containsKey('progress'), isFalse);
  });

  Future<List<dynamic>?> load({
    String? fail,
    bool throws = false,
    bool emptyPlayback = false,
    List<dynamic> hidden = const [],
    List<dynamic> dropped = const [],
    List<dynamic> watched = const [],
  }) {
    Future<List<dynamic>?> read(String name, List<dynamic> rows) async {
      if (fail == name) {
        if (throws) throw StateError('offline');
        return null;
      }
      return rows;
    }

    return loadTraktContinueWatching(
      upNext: () => read('upNext', [next(2, 1)]),
      playback: () => read('playback', emptyPlayback ? [] : [paused(1, 2)]),
      hidden: () => read('hidden', hidden),
      dropped: () => read('dropped', dropped),
      watched: () => read('watched', watched),
    );
  }

  test(
    'snapshot loader includes paused-only shows and excludes dropped shows',
    () async {
      expect(await load(), hasLength(2));
      final result = await load(
        dropped: [
          {'show': show(1), 'type': 'show'},
        ],
      );
      expect(result, hasLength(1));
      expect(result!.single['show']['ids']['trakt'], 2);
    },
  );

  for (final name in ['upNext', 'playback', 'hidden', 'dropped', 'watched']) {
    test('$name failure retains the prior UI snapshot via null', () async {
      expect(await load(fail: name), isNull);
      expect(await load(fail: name, throws: true), isNull);
    });
  }

  test('no playback needs no additional filter/history requests', () async {
    expect(
      await load(emptyPlayback: true, fail: 'hidden', throws: true),
      hasLength(1),
    );
  });

  test(
    'unidentifiable rows retain snapshot; identifiable bad dates are isolated',
    () async {
      expect(await load(hidden: [{}]), isNull);
      expect(await load(watched: [{}]), isNull);
      expect(
        await load(
          watched: [
            {'show': show(1)},
          ],
        ),
        hasLength(1),
      );
    },
  );
}
