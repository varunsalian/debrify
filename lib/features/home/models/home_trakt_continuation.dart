import '../../../models/stremio_addon.dart';
import '../../../models/trakt_continue_watching_item.dart';
import '../../../utils/continue_watching_presentation.dart';

/// Trakt shelf projection. Containers are detached and read-only; legacy
/// metadata and playback descriptors retain their identities for handoff.
class HomeTraktContinuation {
  HomeTraktContinuation._({
    required List<StremioMeta> movies,
    required List<StremioMeta> series,
    required List<StremioMeta> all,
    required Map<String, double> progress,
    required Map<String, String> episode,
    required Map<String, int> remainingMinutes,
    required Map<String, ({int season, int episode})> episodeRefs,
    required Map<String, TraktContinueWatchingItem> byImdb,
  }) : movies = List.unmodifiable(movies),
       series = List.unmodifiable(series),
       all = List.unmodifiable(all),
       progress = Map.unmodifiable(progress),
       episode = Map.unmodifiable(episode),
       remainingMinutes = Map.unmodifiable(remainingMinutes),
       episodeRefs = Map.unmodifiable(episodeRefs),
       byImdb = Map.unmodifiable(byImdb);

  factory HomeTraktContinuation.fromRows({
    required List<TraktContinueWatchingItem> movies,
    required List<TraktContinueWatchingItem> shows,
  }) {
    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final remainingMinutes = <String, int>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, TraktContinueWatchingItem>{};
    void ingest(List<TraktContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = it.id;
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = continueWatchingEpisodeLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
        final left = continueWatchingMinutesLeftFromProgress(
          progress: it.progress,
          runtimeMinutes: it.runtime,
        );
        if (left != null) remainingMinutes[id] = left;
      }
    }

    ingest(movies, movieMetas);
    ingest(shows, showMetas);
    // Merge into one last-watched-ordered list for the See-All grid: sort by
    // Trakt's paused_at / last_watched_at (newest first). Items without either
    // sort last. Ties use the original movies-then-shows order so the sort is
    // deterministic (Dart's List.sort isn't stable).
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[a.progressId]?.pausedAtMs;
      final pb = byImdb[b.progressId]?.pausedAtMs;
      if (pa != null && pb != null) {
        final c = pb.compareTo(pa);
        if (c != 0) return c;
      } else if (pa == null && pb != null) {
        return 1;
      } else if (pa != null && pb == null) {
        return -1;
      }
      return origIndex[a]!.compareTo(origIndex[b]!);
    });
    return HomeTraktContinuation._(
      movies: movieMetas,
      series: showMetas,
      all: allMetas,
      progress: progress,
      episode: episode,
      remainingMinutes: remainingMinutes,
      episodeRefs: episodeRefs,
      byImdb: byImdb,
    );
  }

  final List<StremioMeta> movies;
  final List<StremioMeta> series;
  final List<StremioMeta> all;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, int> remainingMinutes;
  final Map<String, ({int season, int episode})> episodeRefs;
  final Map<String, TraktContinueWatchingItem> byImdb;
}
