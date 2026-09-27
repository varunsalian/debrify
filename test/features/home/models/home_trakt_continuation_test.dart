import 'package:debrify/features/home/models/home_trakt_continuation.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:flutter_test/flutter_test.dart';

TraktContinueWatchingItem item(
  String id, {
  String? imdbId,
  bool series = false,
  int? pausedAt,
  double? progress,
  int? season,
  int? episode,
  int? runtime,
}) => TraktContinueWatchingItem(
  meta: StremioMeta(
    id: id,
    imdbId: imdbId ?? (id.startsWith('tt') ? id : null),
    name: id,
    type: series ? 'series' : 'movie',
  ),
  traktContentType: series ? 'episodes' : 'movies',
  progress: progress,
  season: season,
  episode: episode,
  runtime: runtime,
  pausedAtMs: pausedAt,
  playbackIds: const [17, 29],
);

void main() {
  test('first movie or show for a resolved ID wins across both feeds', () {
    final first = item('catalog-movie', imdbId: 'tt1', progress: 25);
    final second = item('tt2', series: true, season: 2, episode: 3);
    final snapshot = HomeTraktContinuation.fromRows(
      movies: [
        item(''),
        first,
        item('duplicate', imdbId: 'tt1', progress: 99),
      ],
      shows: [item('tt1', series: true), second, item('tt2', series: true)],
    );
    expect(snapshot.movies, [first.meta]);
    expect(snapshot.series, [second.meta]);
    expect(snapshot.byImdb, {'tt1': first, 'tt2': second});
    expect(snapshot.progress, {'tt1': .25});
    expect(snapshot.episode, {'tt2': 'S2 · E3'});
  });

  test('merged recency order is stable while split rows retain feed order', () {
    final movies = [
      item('tt1', pausedAt: 10),
      item('tt2'),
      item('tt3', pausedAt: 10),
    ];
    final shows = [
      item('tt4', series: true, pausedAt: 20),
      item('tt5', series: true, pausedAt: 10),
      item('tt6', series: true),
    ];
    final snapshot = HomeTraktContinuation.fromRows(
      movies: movies,
      shows: shows,
    );
    expect(snapshot.movies.map((m) => m.id), ['tt1', 'tt2', 'tt3']);
    expect(snapshot.series.map((m) => m.id), ['tt4', 'tt5', 'tt6']);
    expect(snapshot.all.map((m) => m.id), [
      'tt4',
      'tt1',
      'tt3',
      'tt5',
      'tt2',
      'tt6',
    ]);
  });

  test(
    'progress clamps, remaining time rounds up, and absent progress stays absent',
    () {
      final snapshot = HomeTraktContinuation.fromRows(
        movies: [
          item('tt1', progress: -10, runtime: 50),
          item('tt2', progress: 110, runtime: 50),
          item('tt3', progress: 33, runtime: 10),
          item('tt4', runtime: 50),
          item('tt5', progress: 50, runtime: 0),
        ],
        shows: [],
      );
      expect(snapshot.progress, {'tt1': 0, 'tt2': 1, 'tt3': .33, 'tt5': .5});
      expect(snapshot.remainingMinutes, {'tt3': 7});
    },
  );

  test('only complete positive episode pairs request artwork or labels', () {
    final snapshot = HomeTraktContinuation.fromRows(
      movies: [],
      shows: [
        item('tt1', series: true, season: 2, episode: 3),
        item('tt2', series: true, season: 0, episode: 3),
        item('tt3', series: true, season: 2),
        item('tt4', series: true, season: 2, episode: -1),
      ],
    );
    expect(snapshot.episode, {'tt1': 'S2 · E3'});
    expect(snapshot.episodeRefs, {'tt1': (season: 2, episode: 3)});
  });

  test('unresolved metadata retains legacy progress-key sort lookup', () {
    // A native movie's normalized progress key can differ from its item ID.
    // Preserve the old lookup semantics here; identity normalization is separate.
    final snapshot = HomeTraktContinuation.fromRows(
      movies: [item('tmdb:10', pausedAt: 500), item('unknown', pausedAt: 900)],
      shows: [item('tt1', series: true, pausedAt: 1)],
    );
    expect(snapshot.all.map((m) => m.id), ['tt1', 'tmdb:10', 'unknown']);
    expect(snapshot.byImdb.keys, ['tmdb:10', 'unknown', 'tt1']);
  });

  test('snapshot containers detach from inputs and reject mutation', () {
    final descriptor = item(
      'tt1',
      progress: 50,
      season: 1,
      episode: 2,
      runtime: 30,
    );
    final movies = [descriptor];
    final snapshot = HomeTraktContinuation.fromRows(movies: movies, shows: []);
    movies.clear();
    expect(snapshot.movies.single, same(descriptor.meta));
    expect(snapshot.byImdb['tt1'], same(descriptor));
    expect(snapshot.byImdb['tt1']!.playbackIds, [17, 29]);
    for (final list in [snapshot.movies, snapshot.series, snapshot.all]) {
      expect(list.clear, throwsUnsupportedError);
    }
    for (final map in <Map>[
      snapshot.progress,
      snapshot.episode,
      snapshot.remainingMinutes,
      snapshot.episodeRefs,
      snapshot.byImdb,
    ]) {
      expect(map.clear, throwsUnsupportedError);
    }
    final empty = HomeTraktContinuation.fromRows(movies: [], shows: []);
    expect(empty.all, isEmpty);
    expect(empty.byImdb, isEmpty);
  });
}
