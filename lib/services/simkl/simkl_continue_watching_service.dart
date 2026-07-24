import 'package:flutter/foundation.dart';

import '../../models/advanced_search_selection.dart';
import '../../models/stremio_addon.dart';
import 'simkl_item_transformer.dart';
import 'simkl_service.dart';

/// One Simkl "continue watching" entry: a paused movie, the paused episode of a
/// show, OR an "up next" entry (the next unwatched episode of a show you're
/// watching but haven't paused). Wraps a [StremioMeta] (for row rendering) plus
/// the resume detail the CW row needs. Parallel to TraktContinueWatchingItem;
/// deliberately not shared (Simkl stays independent of Trakt — see
/// [SimklService]'s class doc).
class SimklContinueWatchingItem {
  final StremioMeta meta;

  /// Paused progress, 0–100 (Simkl's scale). In (0,100) for a paused entry;
  /// NULL for an "up next" entry (the next episode hasn't been started, so
  /// there's no resume position and the card shows no progress bar).
  final double? progress;

  /// Season/episode — of the paused episode, or the next-to-watch episode for
  /// an up-next entry (null for movies).
  final int? season;
  final int? episode;

  /// Recency epoch ms for newest-first ordering: `paused_at` for a paused entry,
  /// `last_watched_at` for an up-next entry (null if unparseable/absent).
  final int? pausedAtMs;

  final bool isMovie;

  /// True when this is an "up next" series entry (no paused session — derived
  /// from the show's `next_to_watch`). Used to keep the explicit
  /// "Remove from Continue Watching" action off it (nothing to delete).
  final bool isUpNext;

  const SimklContinueWatchingItem({
    required this.meta,
    required this.progress,
    required this.season,
    required this.episode,
    required this.pausedAtMs,
    required this.isMovie,
    this.isUpNext = false,
  });

  String get id => meta.imdbId ?? meta.id;
  bool get isSeries => !isMovie;
}

/// Builds the Simkl "Continue Watching" rows from the account-wide paused
/// playback sessions (`/sync/playback/{episodes,movies}`) that the scrobble
/// integration already fetches + caches. Simkl's sessions are keyed only by
/// ids/progress, so title + poster are enriched from the user's cached library
/// snapshot (with a metahub poster fallback from the IMDb id). Parallel to
/// TraktContinueWatchingService, sharing none of its Trakt-specific logic.
class SimklContinueWatchingService {
  SimklContinueWatchingService._();
  static final SimklContinueWatchingService instance =
      SimklContinueWatchingService._();

  /// Fetch the paused movies + shows, each newest-first. Returns:
  ///  - empty lists when DISCONNECTED (authoritative — the caller clears rows);
  ///  - NULL on a transient fetch failure (a session/library GET failed while
  ///    authenticated) so the caller keeps whatever rows it already shows,
  ///    mirroring TraktContinueWatchingService's keep-on-error behaviour;
  ///  - the paused items otherwise. Never throws. One shared library-snapshot
  ///    read enriches both lists.
  Future<
    ({
      List<SimklContinueWatchingItem> movies,
      List<SimklContinueWatchingItem> shows,
    })?
  >
  fetchItems() async {
    try {
      if (!await SimklService.instance.isAuthenticated()) {
        return (
          movies: const <SimklContinueWatchingItem>[],
          shows: const <SimklContinueWatchingItem>[],
        );
      }
      // The GETs are independent — kick them off together, then await, so a
      // cold start (no warm caches) costs one round-trip, not several.
      final episodeFuture =
          SimklService.instance.fetchEpisodePlaybackSessions();
      final movieFuture = SimklService.instance.fetchMoviePlaybackSessions();
      final libFuture = SimklService.instance.fetchLibrarySnapshotOrNull();
      final upNextFuture = SimklService.instance.fetchUpNextShowsOrNull();
      final episodeSessions = await episodeFuture;
      final movieSessions = await movieFuture;
      final lib = await libFuture;
      final upNextShows = await upNextFuture;
      // The SESSION lists ARE the CW data: a null (while authed) is a transient
      // fetch failure (a genuinely empty account returns []), so bail to null and
      // the board keeps its existing rows. The library snapshot only ENRICHES
      // title/poster — _buildLibraryIndex(null) + _metaFor's metahub/session-
      // title fallbacks handle a null lib — so a library failure must NOT hide
      // otherwise-valid rows. The up-next fetch is pure augmentation: a null just
      // means no up-next entries this time, never a reason to hide paused ones.
      if (episodeSessions == null || movieSessions == null) return null;
      final lib0 = _buildLibraryIndex(lib);
      final libIndex = lib0.meta;
      final statusIndex = lib0.status;
      // Paused rows exclude parked/finished/dropped titles (up-next already
      // fetches only 'watching', so it's inherently filtered).
      final paused = _buildShowItems(episodeSessions, libIndex, statusIndex);
      // Up-next entries for shows NOT already paused (the paused entry is more
      // specific and wins). Merge with the paused shows and re-sort by recency.
      final pausedShowIds = paused.map((i) => i.id).toSet();
      final upNext = _buildUpNextItems(upNextShows, libIndex, pausedShowIds);
      return (
        movies: _buildMovieItems(movieSessions, libIndex, statusIndex),
        shows: _sortedNewestFirst([...paused, ...upNext]),
      );
    } catch (e) {
      debugPrint('SimklContinueWatchingService: fetch failed: $e');
      return null;
    }
  }

  /// A ready-to-play selection for a CW item — carries the Simkl resume percent
  /// and the paused season/episode so [_playSelection] resumes exactly there.
  AdvancedSearchSelection selectionForItem(SimklContinueWatchingItem item) {
    return AdvancedSearchSelection(
      imdbId: item.id,
      isSeries: item.isSeries,
      title: item.meta.name,
      year: item.meta.year,
      season: item.season,
      episode: item.episode,
      contentType: item.meta.type,
      posterUrl: item.meta.poster,
      simklProgressPercent: item.progress,
      simklSource: true,
    );
  }

  // ── Parsing ────────────────────────────────────────────────────────────────

  /// Library statuses whose paused session should NOT show in Continue Watching.
  /// Only 'hold' (explicitly parked) — hiding it by status preserves the resume
  /// position (vs deleting the session), and up-next already excludes it
  /// (watching-only). 'completed'/'dropped' are deliberately NOT here: a fresh
  /// paused session on such a title means an ACTIVE rewatch (Simkl keeps a movie
  /// 'completed' on rewatch — there's no 'watching' movie status), which must
  /// still show. Those leave CW via the menu handlers' session-clear instead.
  static const Set<String> _hiddenStatuses = {'hold'};

  /// Index the user's library snapshot by IMDb id → [StremioMeta] (title +
  /// poster) AND → watchlist status. Meta reuses the same transformer the
  /// Discover/See-All views use; status drives the "hide parked/finished
  /// titles" filter below.
  ({Map<String, StremioMeta> meta, Map<String, String> status})
  _buildLibraryIndex(Map<String, dynamic>? lib) {
    final meta = <String, StremioMeta>{};
    final status = <String, String>{};
    if (lib == null) return (meta: meta, status: status);
    for (final bucket in const ['movies', 'shows', 'anime']) {
      final list = lib[bucket];
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        // Extract imdb straight from the ids so status is captured even if the
        // transformer drops the item (e.g. imdb-less anime — no meta, but if it
        // has a tt id here we still want its status).
        final content = raw['show'] ?? raw['movie'];
        final imdb = _imdbOf(content is Map ? content['ids'] : null);
        if (imdb == null) continue;
        final s = raw['status'];
        if (s is String) status[imdb] = s;
        final m = SimklItemTransformer.transformItem(raw);
        if (m != null) meta[imdb] = m;
      }
    }
    return (meta: meta, status: status);
  }

  List<SimklContinueWatchingItem> _buildMovieItems(
    List<dynamic>? sessions,
    Map<String, StremioMeta> libIndex,
    Map<String, String> statusIndex,
  ) {
    if (sessions == null) return const [];
    final byImdb = <String, SimklContinueWatchingItem>{};
    for (final raw in sessions) {
      if (raw is! Map) continue;
      final movie = raw['movie'];
      if (movie is! Map) continue;
      final imdb = _imdbOf(movie['ids']);
      if (imdb == null) continue;
      // Parked/finished/dropped in the library ⇒ not "continue watching".
      if (_hiddenStatuses.contains(statusIndex[imdb])) continue;
      final progress = _visibleProgress(raw['progress']);
      if (progress == null) continue;
      final cand = SimklContinueWatchingItem(
        meta: _metaFor(imdb, 'movie', libIndex[imdb], movie['title']),
        progress: progress,
        season: null,
        episode: null,
        pausedAtMs: _pausedAtMs(raw['paused_at']),
        isMovie: true,
      );
      _keepNewest(byImdb, imdb, cand);
    }
    return _sortedNewestFirst(byImdb.values);
  }

  List<SimklContinueWatchingItem> _buildShowItems(
    List<dynamic>? sessions,
    Map<String, StremioMeta> libIndex,
    Map<String, String> statusIndex,
  ) {
    if (sessions == null) return const [];
    // One row per show — the most-recently-paused episode of each.
    final byImdb = <String, SimklContinueWatchingItem>{};
    for (final raw in sessions) {
      if (raw is! Map) continue;
      final show = raw['show'];
      if (show is! Map) continue;
      final imdb = _imdbOf(show['ids']);
      if (imdb == null) continue;
      // Parked/finished/dropped in the library ⇒ not "continue watching".
      if (_hiddenStatuses.contains(statusIndex[imdb])) continue;
      final ep = raw['episode'];
      if (ep is! Map) continue;
      final season = _asInt(ep['season']);
      final number = _asInt(ep['number']);
      final progress = _visibleProgress(raw['progress']);
      if (season == null || number == null || progress == null) continue;
      final cand = SimklContinueWatchingItem(
        meta: _metaFor(imdb, 'series', libIndex[imdb], show['title']),
        progress: progress,
        season: season,
        episode: number,
        pausedAtMs: _pausedAtMs(raw['paused_at']),
        isMovie: false,
      );
      _keepNewest(byImdb, imdb, cand);
    }
    return _sortedNewestFirst(byImdb.values);
  }

  /// "Up next" entries — the next unwatched episode of each watching show, from
  /// Simkl's server-computed `next_to_watch`. Skips shows already in [pausedIds]
  /// (a paused entry is more specific and wins) and shows with no next episode
  /// (`next_to_watch == null`). TV-only: an anime `next_to_watch` is absolute
  /// (`"E01"`, no season) which doesn't map to the app's IMDb S/E model, so
  /// [SimklService.parseSimklEpisodeCode] returns null for it and it's skipped.
  List<SimklContinueWatchingItem> _buildUpNextItems(
    List<dynamic>? shows,
    Map<String, StremioMeta> libIndex,
    Set<String> pausedIds,
  ) {
    if (shows == null) return const [];
    final byImdb = <String, SimklContinueWatchingItem>{};
    for (final raw in shows) {
      if (raw is! Map) continue;
      final se = SimklService.parseSimklEpisodeCode(raw['next_to_watch']);
      if (se == null) continue; // null / completed / anime-absolute → no up-next
      final show = raw['show'];
      if (show is! Map) continue;
      final imdb = _imdbOf(show['ids']);
      if (imdb == null || pausedIds.contains(imdb)) continue;
      byImdb[imdb] = SimklContinueWatchingItem(
        meta: _metaFor(imdb, 'series', libIndex[imdb], show['title']),
        progress: null, // not started — no resume position / progress bar
        season: se.season,
        episode: se.episode,
        pausedAtMs: _pausedAtMs(raw['last_watched_at']),
        isMovie: false,
        isUpNext: true,
      );
    }
    return byImdb.values.toList();
  }

  /// Keep whichever of the existing/candidate item was paused most recently.
  void _keepNewest(
    Map<String, SimklContinueWatchingItem> byImdb,
    String imdb,
    SimklContinueWatchingItem cand,
  ) {
    final existing = byImdb[imdb];
    if (existing == null ||
        (cand.pausedAtMs ?? 0) > (existing.pausedAtMs ?? 0)) {
      byImdb[imdb] = cand;
    }
  }

  List<SimklContinueWatchingItem> _sortedNewestFirst(
    Iterable<SimklContinueWatchingItem> items,
  ) {
    final list = items.toList();
    // Newest paused first; items without a timestamp sort last, ties stable-ish
    // (Dart's sort isn't stable, but same-timestamp CW ties don't matter).
    list.sort((a, b) {
      final pa = a.pausedAtMs;
      final pb = b.pausedAtMs;
      if (pa == null && pb == null) return 0;
      if (pa == null) return 1;
      if (pb == null) return -1;
      return pb.compareTo(pa);
    });
    return list;
  }

  StremioMeta _metaFor(
    String imdb,
    String type,
    StremioMeta? libMeta,
    dynamic sessionTitle,
  ) {
    final title = libMeta?.name ?? (sessionTitle is String ? sessionTitle : null);
    return StremioMeta(
      id: imdb,
      imdbId: imdb,
      type: type,
      name: title ?? imdb,
      poster:
          libMeta?.poster ??
          'https://images.metahub.space/poster/medium/$imdb/img',
      background: libMeta?.background,
      year: libMeta?.year,
    );
  }

  String? _imdbOf(dynamic ids) {
    if (ids is! Map) return null;
    final imdb = ids['imdb'];
    return (imdb is String && imdb.startsWith('tt')) ? imdb : null;
  }

  /// Progress in (0,100), else null — mirrors the "hide un-started/finished"
  /// rule the Trakt CW list uses (TraktContinueWatchingService._visibleProgress).
  double? _visibleProgress(dynamic raw) {
    final p = raw is num
        ? raw.toDouble()
        : (raw is String ? double.tryParse(raw) : null);
    if (p == null || p <= 0 || p >= 100) return null;
    return p;
  }

  int? _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  int? _pausedAtMs(dynamic v) {
    if (v is! String) return null;
    return DateTime.tryParse(v)?.millisecondsSinceEpoch;
  }
}
