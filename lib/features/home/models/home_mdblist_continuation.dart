import '../../../models/mdblist_continue_watching.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/continue_watching_presentation.dart';

/// Read-only shelf containers; resume/removal descriptors retain their identity.
class HomeMdblistContinuation {
  HomeMdblistContinuation._({
    required List<StremioMeta> movies,
    required List<StremioMeta> series,
    required List<StremioMeta> all,
    required Map<String, double> progress,
    required Map<String, String> episode,
    required Map<String, MdblistContinueWatchingItem> byImdb,
  }) : movies = List.unmodifiable(movies),
       series = List.unmodifiable(series),
       all = List.unmodifiable(all),
       progress = Map.unmodifiable(progress),
       episode = Map.unmodifiable(episode),
       byImdb = Map.unmodifiable(byImdb);

  factory HomeMdblistContinuation.fromSnapshot(
    MdblistContinueWatchingSnapshot snapshot,
  ) {
    final movies = <StremioMeta>[];
    final shows = <StremioMeta>[];
    final progress = <String, double>{};
    final episodes = <String, String>{};
    final byImdb = <String, MdblistContinueWatchingItem>{};
    StremioMeta metaFor(MdblistContinueWatchingItem item) {
      final selection = item.selection;
      return StremioMeta(
        id: selection.imdbId,
        imdbId: selection.imdbId,
        type: selection.isSeries ? 'series' : 'movie',
        name: selection.title,
        poster: selection.posterUrl,
        background:
            'https://images.metahub.space/background/medium/${selection.imdbId}/img',
        year: selection.year,
      );
    }

    void ingest(
      Iterable<MdblistContinueWatchingItem> items,
      List<StremioMeta> target,
    ) {
      for (final item in items) {
        final id = item.selection.imdbId;
        if (byImdb.containsKey(id)) continue;
        target.add(metaFor(item));
        byImdb[id] = item;
        final pct = item.selection.mdblistProgressPercent;
        if (pct != null) progress[id] = (pct / 100).clamp(0, 1);
        final se = continueWatchingEpisodeLabel(
          item.selection.season,
          item.selection.episode,
        );
        if (se != null) episodes[id] = se;
      }
    }

    ingest(snapshot.movies, movies);
    ingest(snapshot.shows, shows);
    final all = [...movies, ...shows]
      ..sort((a, b) {
        final aa = byImdb[a.progressId]?.updatedAt;
        final bb = byImdb[b.progressId]?.updatedAt;
        return (bb ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          aa ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    return HomeMdblistContinuation._(
      movies: movies,
      series: shows,
      all: all,
      progress: progress,
      episode: episodes,
      byImdb: byImdb,
    );
  }

  final List<StremioMeta> movies;
  final List<StremioMeta> series;
  final List<StremioMeta> all;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, MdblistContinueWatchingItem> byImdb;
}
