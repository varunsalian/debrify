import 'package:debrify/features/home/models/home_simkl_continuation.dart';
import 'package:debrify/models/simkl_continue_watching_item.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

SimklContinueWatchingItem item(
  String id, {
  String? imdbId,
  bool series = false,
  double? progress,
  int? season,
  int? episode,
  int? pausedAt,
  bool upNext = false,
}) => SimklContinueWatchingItem(
  meta: StremioMeta(
    id: id,
    imdbId: imdbId ?? (id.startsWith('tt') ? id : null),
    name: id,
    type: series ? 'series' : 'movie',
  ),
  progress: progress,
  season: season,
  episode: episode,
  pausedAtMs: pausedAt,
  isMovie: !series,
  isUpNext: upNext,
);

void main() {
  test(
    'native movie and show namespaces remain distinct and aliases deduplicate',
    () {
      final movie = item('tmdb:7', progress: 20);
      final show = item('tmdb:7', series: true, progress: 70);
      final snapshot = HomeSimklContinuation.fromRows(
        movies: [movie, item('tmdb:movie:7', progress: 99)],
        shows: [show],
      );
      expect(snapshot.movies, [movie.meta]);
      expect(snapshot.series, [show.meta]);
      expect(snapshot.progress, {'movie|tmdb:movie:7': .2, 'tmdb:7': .7});
      expect(HomeSimklContinuation.cardKey(movie.meta), 'movie|tmdb:movie:7');
      expect(HomeSimklContinuation.cardKey(show.meta), 'tmdb:7');
      expect(snapshot.byImdb['movie|tmdb:movie:7'], same(movie));
      expect(snapshot.byImdb['tmdb:7'], same(show));
    },
  );

  test(
    'first resolved ID wins across feeds; empty IDs drop without trimming others',
    () {
      final first = item('catalog', imdbId: 'tt1', progress: 25);
      final whitespace = item(' ');
      final snapshot = HomeSimklContinuation.fromRows(
        movies: [item(''), first, whitespace],
        shows: [item('different', imdbId: 'tt1', series: true)],
      );
      expect(snapshot.movies, [first.meta, whitespace.meta]);
      expect(snapshot.series, isEmpty);
      expect(snapshot.byImdb.keys, ['tt1', ' ']);
      expect(snapshot.progress, {'tt1': .25});
    },
  );

  test(
    'merged recency includes native keys and keeps stable ties and undated order',
    () {
      final movies = [
        item('tmdb:1', pausedAt: 20),
        item('tt2'),
        item('tt3', pausedAt: 10),
      ];
      final shows = [
        item('tmdb:2', series: true, pausedAt: 30),
        item('tt4', series: true, pausedAt: 10),
        item('tt5', series: true),
      ];
      final snapshot = HomeSimklContinuation.fromRows(
        movies: movies,
        shows: shows,
      );
      expect(snapshot.movies.map((m) => m.id), ['tmdb:1', 'tt2', 'tt3']);
      expect(snapshot.series.map((m) => m.id), ['tmdb:2', 'tt4', 'tt5']);
      expect(snapshot.all.map((m) => m.id), [
        'tmdb:2',
        'tmdb:1',
        'tt3',
        'tt4',
        'tt2',
        'tt5',
      ]);
    },
  );

  test('up-next stays without progress while paused progress clamps', () {
    final next = item('tt1', series: true, season: 2, episode: 3, upNext: true);
    final snapshot = HomeSimklContinuation.fromRows(
      movies: [item('tt2', progress: -10), item('tt3', progress: 120)],
      shows: [next, item('tt4', series: true, progress: 25)],
    );
    expect(snapshot.progress, {'tt2': 0, 'tt3': 1, 'tt4': .25});
    expect(snapshot.episode, {'tt1': 'S2 · E3'});
    expect(snapshot.byImdb['tt1'], same(next));
    expect(snapshot.byImdb['tt1']!.isUpNext, isTrue);
  });

  test(
    'episode labels allow native titles but artwork requires IMDb and positive pairs',
    () {
      final snapshot = HomeSimklContinuation.fromRows(
        movies: [],
        shows: [
          item('tt1', series: true, season: 2, episode: 3),
          item('tmdb:2', series: true, season: 2, episode: 4),
          item('simkl:3', series: true, season: 1, episode: 5),
          item('tt4', series: true, season: 0, episode: 3),
          item('tt5', series: true, season: 1),
          item('tt6', series: true, season: 1, episode: -2),
        ],
      );
      expect(snapshot.episode, {
        'tt1': 'S2 · E3',
        'tmdb:2': 'S2 · E4',
        'simkl:3': 'S1 · E5',
      });
      expect(snapshot.episodeRefs, {'tt1': (season: 2, episode: 3)});
    },
  );

  test('snapshot containers detach from inputs and are read-only', () {
    final descriptor = item('tt1', progress: 50, season: 1, episode: 2);
    final movies = [descriptor];
    final snapshot = HomeSimklContinuation.fromRows(movies: movies, shows: []);
    movies.clear();
    expect(snapshot.movies.single, same(descriptor.meta));
    expect(snapshot.byImdb['tt1'], same(descriptor));
    for (final list in [snapshot.movies, snapshot.series, snapshot.all]) {
      expect(list.clear, throwsUnsupportedError);
    }
    for (final map in <Map>[
      snapshot.progress,
      snapshot.episode,
      snapshot.episodeRefs,
      snapshot.byImdb,
    ]) {
      expect(map.clear, throwsUnsupportedError);
    }
    final empty = HomeSimklContinuation.fromRows(movies: [], shows: []);
    expect(empty.all, isEmpty);
    expect(empty.byImdb, isEmpty);
  });
}
