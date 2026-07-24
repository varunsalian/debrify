import '../../models/stremio_addon.dart';
import 'simkl_constants.dart';
import 'simkl_item_transformer.dart';
import 'simkl_service.dart';

/// The Simkl lists a See-All / Discover view can switch between.
///
/// Simkl's data model doesn't mirror Trakt's: no Collection/Recommendations
/// concept, no Watchlist/History split — instead a fixed five-state watchlist
/// (Plan to Watch / Watching / On Hold / Completed / Dropped) plus Ratings,
/// and a smaller, differently-shaped set of public discovery endpoints.
enum SimklSeeAllList {
  /// The user's Continue Watching (paused + up-next). Unlike every other list,
  /// this is NOT fetched via [SimklListSource] — the host hands it in already
  /// loaded (from SimklContinueWatchingService), so [loadList] returns empty for
  /// it. Leads the enum so it's the first "List" dropdown option, mirroring
  /// TraktSeeAllScreen.
  continueWatching,
  planToWatch,
  watching,
  onHold,
  completed,
  dropped,
  ratings,
  trending,
  topRated,
  newAndUpcoming,
}

extension SimklSeeAllListX on SimklSeeAllList {
  String get label {
    switch (this) {
      case SimklSeeAllList.continueWatching:
        return 'Continue Watching';
      case SimklSeeAllList.planToWatch:
        return 'Plan to Watch';
      case SimklSeeAllList.watching:
        return 'Watching';
      case SimklSeeAllList.onHold:
        return 'On Hold';
      case SimklSeeAllList.completed:
        return 'Completed';
      case SimklSeeAllList.dropped:
        return 'Dropped';
      case SimklSeeAllList.ratings:
        return 'Ratings';
      case SimklSeeAllList.trending:
        return 'Trending';
      case SimklSeeAllList.topRated:
        return 'Top Rated';
      case SimklSeeAllList.newAndUpcoming:
        return 'New & Upcoming';
    }
  }

  /// Global (non-personal) lists — served without auth and phrased as "No X
  /// titles" rather than "Nothing in your X" when empty.
  bool get isPublic =>
      this == SimklSeeAllList.trending ||
      this == SimklSeeAllList.topRated ||
      this == SimklSeeAllList.newAndUpcoming;

  /// Simkl's `/sync/all-items/{type}/{status}` status slug, for the five
  /// watchlist-state lists. Null for everything else (ratings/discovery).
  String? get statusValue {
    switch (this) {
      case SimklSeeAllList.planToWatch:
        return 'plantowatch';
      case SimklSeeAllList.watching:
        return 'watching';
      case SimklSeeAllList.onHold:
        return 'hold';
      case SimklSeeAllList.completed:
        return 'completed';
      case SimklSeeAllList.dropped:
        return 'dropped';
      default:
        return null;
    }
  }

  /// Movies don't have a Watching/On Hold state (single-session content) —
  /// Simkl's own constraint, not a bug when that bucket comes back empty.
  bool get includesMovies =>
      this != SimklSeeAllList.watching && this != SimklSeeAllList.onHold;
}

/// Loads Simkl lists into [StremioMeta] grids for the See-All / Discover
/// views. Pure data logic — no UI. Stateless; construct one or use
/// [instance]. Deliberately independent of [TraktListSource] — see
/// [SimklService]'s doc comment on why Simkl stays parallel, not shared.
class SimklListSource {
  SimklListSource._();
  static final SimklListSource instance = SimklListSource._();

  Future<({List<StremioMeta> items, bool failed})> loadList(
    SimklSeeAllList list,
  ) async {
    switch (list) {
      case SimklSeeAllList.continueWatching:
        // Continue Watching is host-provided (see the enum doc), never fetched
        // here — return empty so callers that reach this by mistake no-op.
        return (items: const <StremioMeta>[], failed: false);
      case SimklSeeAllList.planToWatch:
      case SimklSeeAllList.watching:
      case SimklSeeAllList.onHold:
      case SimklSeeAllList.completed:
      case SimklSeeAllList.dropped:
        return _loadAllItems(list);
      case SimklSeeAllList.ratings:
        return _loadRatings();
      case SimklSeeAllList.trending:
        return _loadTrending();
      case SimklSeeAllList.topRated:
        return _loadTopRated();
      case SimklSeeAllList.newAndUpcoming:
        return _loadNewAndUpcoming();
    }
  }

  /// The five watchlist-state lists: one call with `type=all` returns
  /// `{movies, shows, anime}` in a single response (Simkl supports an `all`
  /// type value, unlike the per-type-call shape Trakt's equivalent needs).
  Future<({List<StremioMeta> items, bool failed})> _loadAllItems(
    SimklSeeAllList list,
  ) async {
    final data = await SimklService.instance.fetchAllItemsOrNull(
      'all',
      list.statusValue!,
    );
    if (data == null) return (items: const <StremioMeta>[], failed: true);

    return _mergeBuckets(
      movies: list.includesMovies ? data['movies'] as List<dynamic>? : null,
      shows: data['shows'] as List<dynamic>?,
      anime: data['anime'] as List<dynamic>?,
    );
  }

  /// Ratings: `/sync/ratings/{type}/...` only documents movies/shows/anime as
  /// type values (no confirmed `all`), so this fetches the three concurrently.
  Future<({List<StremioMeta> items, bool failed})> _loadRatings() async {
    final results = await Future.wait([
      SimklService.instance.fetchRatingsOrNull('movies'),
      SimklService.instance.fetchRatingsOrNull('shows'),
      SimklService.instance.fetchRatingsOrNull('anime'),
    ]);
    return _mergeBuckets(
      movies: results[0]?['movies'] as List<dynamic>?,
      shows: results[1]?['shows'] as List<dynamic>?,
      anime: results[2]?['anime'] as List<dynamic>?,
      anyFetchFailed: results.any((r) => r == null),
    );
  }

  /// Trending: a single combined CDN file already returns `{movies, tv,
  /// anime}` — no per-type calls needed.
  Future<({List<StremioMeta> items, bool failed})> _loadTrending() async {
    final data = await SimklService.instance.fetchPublicOrNull(
      kSimklTrendingUrl,
    );
    if (data == null || data is! Map) {
      return (items: const <StremioMeta>[], failed: true);
    }
    return _mergeBuckets(
      movies: _asItemList(data['movies']),
      shows: _asItemList(data['tv']),
      anime: _asItemList(data['anime']),
    );
  }

  /// Top Rated: no single "best movies" endpoint exists, so this merges three
  /// independent public endpoints (TV best, anime best, movies sorted by
  /// rank).
  Future<({List<StremioMeta> items, bool failed})> _loadTopRated() async {
    final results = await Future.wait([
      SimklService.instance.fetchPublicOrNull('$kSimklApiBaseUrl/tv/best/all'),
      SimklService.instance.fetchPublicOrNull(
        '$kSimklApiBaseUrl/anime/best/all',
      ),
      SimklService.instance.fetchPublicOrNull(
        '$kSimklApiBaseUrl/movies/genres/all/movies/all/all/rank',
      ),
    ]);
    return _mergeThreeFlatLists(results, showIndex: 0, animeIndex: 1, movieIndex: 2);
  }

  /// New & Upcoming: TV/anime premieres ("soon") merged with movies sorted by
  /// release date — the closest Simkl equivalent to Trakt's "Anticipated".
  Future<({List<StremioMeta> items, bool failed})> _loadNewAndUpcoming() async {
    final results = await Future.wait([
      SimklService.instance.fetchPublicOrNull(
        '$kSimklApiBaseUrl/tv/premieres/soon',
      ),
      SimklService.instance.fetchPublicOrNull(
        '$kSimklApiBaseUrl/anime/premieres/soon',
      ),
      SimklService.instance.fetchPublicOrNull(
        '$kSimklApiBaseUrl/movies/genres/all/movies/all/all/release-date',
      ),
    ]);
    return _mergeThreeFlatLists(results, showIndex: 0, animeIndex: 1, movieIndex: 2);
  }

  /// Three independent public fetches merged by index. [failed] is true if
  /// ANY of the three failed (not just if all three did) — a partial result
  /// still shows what loaded, but callers can tell it's incomplete.
  ({List<StremioMeta> items, bool failed}) _mergeThreeFlatLists(
    List<dynamic> results, {
    required int movieIndex,
    required int showIndex,
    required int animeIndex,
  }) {
    return _mergeBuckets(
      movies: _asItemList(results[movieIndex]),
      shows: _asItemList(results[showIndex]),
      anime: _asItemList(results[animeIndex]),
      anyFetchFailed: results.any((r) => r == null),
    );
  }

  /// Transform, interleave, and dedup a list's movies/shows/anime buckets —
  /// shared by every loader above. A null bucket (a status Simkl doesn't
  /// support for that type, e.g. no movies for Watching) contributes nothing;
  /// [anyFetchFailed] surfaces a partial-fetch failure without discarding
  /// whatever did load.
  ({List<StremioMeta> items, bool failed}) _mergeBuckets({
    List<dynamic>? movies,
    List<dynamic>? shows,
    List<dynamic>? anime,
    bool anyFetchFailed = false,
  }) {
    final movieMetas = movies == null
        ? const <StremioMeta>[]
        : SimklItemTransformer.transformList(movies, inferredType: 'movie');
    final showMetas = shows == null
        ? const <StremioMeta>[]
        : SimklItemTransformer.transformList(shows, inferredType: 'series');
    final animeMetas = anime == null
        ? const <StremioMeta>[]
        : SimklItemTransformer.transformList(anime, inferredType: 'series');
    return (
      items: _dedup(_interleave([movieMetas, showMetas, animeMetas])),
      failed: anyFetchFailed,
    );
  }

  /// Normalize a decoded JSON body into an item list — some Simkl endpoints
  /// return a bare array, others (unconfirmed from docs alone) may wrap it.
  /// Falls back to `[]` rather than throwing on an unexpected shape.
  List<dynamic> _asItemList(dynamic decoded) {
    if (decoded == null) return const [];
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in const ['movies', 'shows', 'tv', 'anime', 'data']) {
        final v = decoded[key];
        if (v is List) return v;
      }
    }
    return const [];
  }

  /// Round-robin interleave so no single content type buries the others at
  /// the top of the grid, mirroring how [TraktListSource] interleaves
  /// movies/shows for its rank-ordered lists.
  List<StremioMeta> _interleave(List<List<StremioMeta>> lists) {
    final ordered = <StremioMeta>[];
    final maxLen = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
    for (var i = 0; i < maxLen; i++) {
      for (final l in lists) {
        if (i < l.length) ordered.add(l[i]);
      }
    }
    return ordered;
  }

  List<StremioMeta> _dedup(List<StremioMeta> metas) {
    final seen = <String>{};
    final out = <StremioMeta>[];
    for (final m in metas) {
      if (seen.add(m.imdbId ?? m.id)) out.add(m);
    }
    return out;
  }
}
