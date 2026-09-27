import 'package:debrify/features/home/models/home_mdblist_continuation.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/mdblist_continue_watching.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:flutter_test/flutter_test.dart';

MdblistContinueWatchingItem item(
  String id, {
  bool series = false,
  double? progress,
  int? season,
  int? episode,
  int? updated,
}) => MdblistContinueWatchingItem(
  selection: AdvancedSearchSelection(
    imdbId: id,
    isSeries: series,
    title: 'Title $id',
    year: '2026',
    posterUrl: 'https://fixture.invalid/$id',
    season: season,
    episode: episode,
    mdblistProgressPercent: progress,
    mdblistSource: true,
  ),
  paused: progress != null,
  playbackId: 17,
  updatedAt: updated == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(updated, isUtc: true),
  clearTarget: const MdblistScrobbleTarget.movie(MdblistMediaIds(imdb: 'tt1')),
);

void main() {
  test(
    'selection builds exact metadata and preserves original resume/removal descriptor',
    () {
      final entry = item(
        'tt1',
        series: true,
        season: 2,
        episode: 3,
        progress: 40,
      );
      final result = HomeMdblistContinuation.fromSnapshot(
        MdblistContinueWatchingSnapshot(shows: [entry]),
      );
      final meta = result.series.single;
      expect(meta.id, 'tt1');
      expect(meta.imdbId, 'tt1');
      expect(meta.type, 'series');
      expect(meta.name, 'Title tt1');
      expect(meta.year, '2026');
      expect(meta.poster, 'https://fixture.invalid/tt1');
      expect(
        meta.background,
        'https://images.metahub.space/background/medium/tt1/img',
      );
      expect(result.byImdb['tt1'], same(entry));
      expect(result.byImdb['tt1']!.playbackId, 17);
      expect(result.byImdb['tt1']!.clearTarget, same(entry.clearTarget));
    },
  );

  test('first ID wins across feeds and empty IDs retain legacy inclusion', () {
    final first = item('tt1', progress: 20);
    final result = HomeMdblistContinuation.fromSnapshot(
      MdblistContinueWatchingSnapshot(
        movies: [first, item(''), item('tt1', progress: 90)],
        shows: [item('tt1', series: true), item('tt2', series: true)],
      ),
    );
    expect(result.movies.map((m) => m.id), ['tt1', '']);
    expect(result.series.map((m) => m.id), ['tt2']);
    expect(result.byImdb['tt1'], same(first));
    expect(result.progress, {'tt1': .2});
  });

  test(
    'merged timestamps sort descending with missing dates treated as epoch',
    () {
      final result = HomeMdblistContinuation.fromSnapshot(
        MdblistContinueWatchingSnapshot(
          movies: [
            item('tt1', updated: -1),
            item('tt2'),
            item('tt3', updated: 20),
          ],
          shows: [item('tt4', series: true, updated: 10)],
        ),
      );
      expect(result.movies.map((m) => m.id), ['tt1', 'tt2', 'tt3']);
      expect(result.all.map((m) => m.id), ['tt3', 'tt4', 'tt2', 'tt1']);
    },
  );

  test(
    'progress clamps and episode labels require complete positive pairs',
    () {
      final result = HomeMdblistContinuation.fromSnapshot(
        MdblistContinueWatchingSnapshot(
          movies: [item('tt1', progress: -20), item('tt2', progress: 140)],
          shows: [
            item('tt3', series: true, season: 2, episode: 4),
            item('tt4', series: true, progress: 25, season: 0, episode: 1),
            item('tt5', series: true, season: 1),
          ],
        ),
      );
      expect(result.progress, {'tt1': 0, 'tt2': 1, 'tt4': .25});
      expect(result.episode, {'tt3': 'S2 · E4'});
    },
  );

  test('result containers detach from feeds and reject mutation', () {
    final movies = [item('tt1')];
    final result = HomeMdblistContinuation.fromSnapshot(
      MdblistContinueWatchingSnapshot(movies: movies),
    );
    movies.clear();
    expect(result.movies.single.id, 'tt1');
    for (final list in [result.movies, result.series, result.all]) {
      expect(list.clear, throwsUnsupportedError);
    }
    for (final map in <Map>[result.progress, result.episode, result.byImdb]) {
      expect(map.clear, throwsUnsupportedError);
    }
    expect(
      HomeMdblistContinuation.fromSnapshot(
        const MdblistContinueWatchingSnapshot(),
      ).all,
      isEmpty,
    );
  });
}
