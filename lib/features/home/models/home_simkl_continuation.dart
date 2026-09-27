import '../../../models/media_identity.dart';
import '../../../models/simkl_continue_watching_item.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/continue_watching_presentation.dart';

/// Detached, read-only Simkl shelf containers. Legacy metadata and descriptors
/// retain their identities for the existing playback handoff.
class HomeSimklContinuation {
  const HomeSimklContinuation.empty()
    : movies = const [],
      series = const [],
      all = const [],
      progress = const {},
      episode = const {},
      episodeRefs = const {},
      byImdb = const {};

  HomeSimklContinuation._({
    required List<StremioMeta> movies,
    required List<StremioMeta> series,
    required List<StremioMeta> all,
    required Map<String, double> progress,
    required Map<String, String> episode,
    required Map<String, ({int season, int episode})> episodeRefs,
    required Map<String, SimklContinueWatchingItem> byImdb,
  }) : movies = List.unmodifiable(movies),
       series = List.unmodifiable(series),
       all = List.unmodifiable(all),
       progress = Map.unmodifiable(progress),
       episode = Map.unmodifiable(episode),
       episodeRefs = Map.unmodifiable(episodeRefs),
       byImdb = Map.unmodifiable(byImdb);

  static String cardKey(StremioMeta item) {
    final id = item.progressId ?? item.id;
    return item.type == 'movie' && id.startsWith('tmdb:') ? 'movie|$id' : id;
  }

  factory HomeSimklContinuation.fromRows({
    required List<SimklContinueWatchingItem> movies,
    required List<SimklContinueWatchingItem> shows,
  }) {
    final movieMetas = <StremioMeta>[];
    final showMetas = <StremioMeta>[];
    final progress = <String, double>{};
    final episode = <String, String>{};
    final episodeRefs = <String, ({int season, int episode})>{};
    final byImdb = <String, SimklContinueWatchingItem>{};
    void ingest(List<SimklContinueWatchingItem> items, List<StremioMeta> into) {
      for (final it in items) {
        final id = cardKey(it.meta);
        if (id.isEmpty || byImdb.containsKey(id)) continue; // dedup by imdbId
        into.add(it.meta);
        byImdb[id] = it;
        // "Up next" entries have no paused position — no progress bar for them.
        final p = it.progress;
        if (p != null) progress[id] = (p / 100).clamp(0.0, 1.0);
        final se = continueWatchingEpisodeLabel(it.season, it.episode);
        if (se != null) episode[id] = se;
        if (MediaIdentity.isImdb(it.id) &&
            it.season != null &&
            it.episode != null &&
            it.season! > 0 &&
            it.episode! > 0) {
          episodeRefs[id] = (season: it.season!, episode: it.episode!);
        }
      }
    }

    ingest(movies, movieMetas);
    ingest(shows, showMetas);
    // Merge into one paused-order list for the See-All grid: newest paused_at
    // first, timestamp-less items last, ties fall back to movies-then-shows.
    final allMetas = [...movieMetas, ...showMetas];
    final origIndex = <StremioMeta, int>{
      for (var i = 0; i < allMetas.length; i++) allMetas[i]: i,
    };
    allMetas.sort((a, b) {
      final pa = byImdb[cardKey(a)]?.pausedAtMs;
      final pb = byImdb[cardKey(b)]?.pausedAtMs;
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

    return HomeSimklContinuation._(
      movies: movieMetas,
      series: showMetas,
      all: allMetas,
      progress: progress,
      episode: episode,
      episodeRefs: episodeRefs,
      byImdb: byImdb,
    );
  }

  final List<StremioMeta> movies;
  final List<StremioMeta> series;
  final List<StremioMeta> all;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, ({int season, int episode})> episodeRefs;
  final Map<String, SimklContinueWatchingItem> byImdb;
}
