import '../../models/stremio_addon.dart';
import 'trakt_item_transformer.dart';
import 'trakt_service.dart';

/// The built-in Trakt lists a See-All / Discover view can switch between.
/// [continueWatching] is special — it reuses already-loaded rows the caller
/// passes in (no fetch); every other entry is fetched on demand.
enum TraktSeeAllList {
  continueWatching,
  watchlist,
  history,
  collection,
  ratings,
  recommendations,
  trending,
  popular,
  anticipated,
}

extension TraktSeeAllListX on TraktSeeAllList {
  String get label {
    switch (this) {
      case TraktSeeAllList.continueWatching:
        return 'Continue Watching';
      case TraktSeeAllList.watchlist:
        return 'Watchlist';
      case TraktSeeAllList.history:
        return 'History';
      case TraktSeeAllList.collection:
        return 'Collection';
      case TraktSeeAllList.ratings:
        return 'Ratings';
      case TraktSeeAllList.recommendations:
        return 'Recommendations';
      case TraktSeeAllList.trending:
        return 'Trending';
      case TraktSeeAllList.popular:
        return 'Popular';
      case TraktSeeAllList.anticipated:
        return 'Anticipated';
    }
  }

  /// Trakt API list slug. Empty for [continueWatching] (served from cached rows).
  String get apiValue {
    switch (this) {
      case TraktSeeAllList.continueWatching:
        return '';
      case TraktSeeAllList.watchlist:
        return 'watchlist';
      case TraktSeeAllList.history:
        return 'history';
      case TraktSeeAllList.collection:
        return 'collection';
      case TraktSeeAllList.ratings:
        return 'ratings';
      case TraktSeeAllList.recommendations:
        return 'recommendations';
      case TraktSeeAllList.trending:
        return 'trending';
      case TraktSeeAllList.popular:
        return 'popular';
      case TraktSeeAllList.anticipated:
        return 'anticipated';
    }
  }

  /// Global (non-personal) lists — served without auth and phrased as "No X
  /// titles" rather than "Nothing in your X" when empty.
  bool get isPublic =>
      this == TraktSeeAllList.trending ||
      this == TraktSeeAllList.popular ||
      this == TraktSeeAllList.anticipated;

  /// Lists whose natural order is a genuine cross-type timeline (watched_at /
  /// rated_at / collected_at recency), so merging movies + shows must sort by
  /// that timestamp rather than interleave. Excludes Watchlist (user-curated
  /// rank order) and the rank-ordered public/recommendation lists.
  bool get isTimeOrdered =>
      this == TraktSeeAllList.history ||
      this == TraktSeeAllList.ratings ||
      this == TraktSeeAllList.collection;
}

/// A selectable Trakt list: either one of the built-ins ([builtin]) or a
/// specific user list — an own custom list or a liked list ([userList], with
/// [liked] distinguishing the two, since they fetch from different endpoints).
/// Value-equal by the built-in enum or the list's Trakt id so a dropdown can
/// match the current selection across rebuilds.
class TraktListChoice {
  final TraktSeeAllList? builtin;
  final Map<String, dynamic>? userList;
  final bool liked;

  const TraktListChoice.builtin(TraktSeeAllList list)
      : builtin = list,
        userList = null,
        liked = false;

  const TraktListChoice.userList(Map<String, dynamic> list,
      {required this.liked})
      : builtin = null,
        userList = list;

  bool get isBuiltin => builtin != null;
  bool get isContinueWatching => builtin == TraktSeeAllList.continueWatching;

  /// Trakt id (or slug) of a user list — its stable identity for equality and
  /// for the items endpoint.
  String? get userListId {
    final ids = userList?['ids'];
    if (ids is Map) {
      final trakt = ids['trakt'];
      if (trakt != null) return trakt.toString();
      final slug = ids['slug'];
      if (slug != null) return slug.toString();
    }
    return null;
  }

  /// Own-custom-list reference for the items endpoint — the slug (what Trakt's
  /// examples use) when present, else the Trakt id.
  String get customListRef {
    final ids = userList?['ids'];
    if (ids is Map) {
      final slug = ids['slug'];
      if (slug != null && slug.toString().isNotEmpty) return slug.toString();
      final trakt = ids['trakt'];
      if (trakt != null) return trakt.toString();
    }
    return userListId ?? '';
  }

  String get label {
    if (builtin != null) return builtin!.label;
    final name = userList?['name'] as String?;
    return (name == null || name.trim().isEmpty) ? 'Untitled list' : name;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TraktListChoice) return false;
    if (other.builtin != builtin || other.liked != liked) return false;
    if (userList == null && other.userList == null) return true;
    final id = userListId;
    if (id != null || other.userListId != null) return id == other.userListId;
    return identical(userList, other.userList);
  }

  @override
  int get hashCode => Object.hash(builtin, liked, userListId);
}

/// Loads Trakt lists into [StremioMeta] grids for the See-All / Discover views.
/// Pure data logic — no UI — so it can be shared by every screen that browses
/// Trakt lists. Stateless; construct one or use [instance].
class TraktListSource {
  TraktListSource._();
  static final TraktListSource instance = TraktListSource._();

  /// The user's own custom lists + liked lists, ready to append to a list
  /// dropdown. A self-liked list (owned and liked) is deduped to one entry.
  /// Returns [] when Trakt isn't connected or on error.
  Future<List<TraktListChoice>> loadUserLists() async {
    List<Map<String, dynamic>> custom;
    List<Map<String, dynamic>> liked;
    try {
      final results = await Future.wait([
        TraktService.instance.fetchCustomLists(),
        TraktService.instance.fetchLikedLists(),
      ]);
      custom = results[0];
      liked = results[1];
    } catch (_) {
      return const [];
    }
    final ownChoices = [
      for (final l in custom) TraktListChoice.userList(l, liked: false),
    ];
    final ownIds = <String>{
      for (final c in ownChoices)
        if (c.userListId != null) c.userListId!,
    };
    final likedChoices = <TraktListChoice>[];
    for (final l in liked) {
      final choice = TraktListChoice.userList(l, liked: true);
      final id = choice.userListId;
      if (id == null || !ownIds.contains(id)) likedChoices.add(choice);
    }
    return [...ownChoices, ...likedChoices];
  }

  /// Load a list's items + whether the fetch failed.
  ///
  /// [continueWatching] returns the caller-provided [cwItems] verbatim. Built-in
  /// lists fetch the movies + shows endpoints concurrently and merge; [failed]
  /// is true when either side failed. User (custom/liked) lists fetch in one
  /// ordered call — preserving the list's own cross-type order and returning
  /// null on failure — so they also get a real error signal.
  Future<({List<StremioMeta> items, bool failed})> loadList(
    TraktListChoice choice, {
    List<StremioMeta> cwItems = const [],
  }) async {
    if (choice.isContinueWatching) {
      return (items: cwItems, failed: false);
    }
    final builtin = choice.builtin;
    if (builtin != null) {
      final results = await Future.wait([
        _safeFetchBuiltin(builtin, 'movies'),
        _safeFetchBuiltin(builtin, 'shows'),
      ]);
      final movies = results[0];
      final shows = results[1];
      return (
        items: _mergeFetched(builtin, movies ?? const [], shows ?? const []),
        failed: movies == null || shows == null,
      );
    }

    // User list: single ordered call (null on failure).
    List<dynamic>? raw;
    try {
      raw = choice.liked
          ? await TraktService.instance
              .fetchLikedListItemsOrderedOrNull(choice.userList!)
          : await TraktService.instance
              .fetchCustomListItemsOrderedOrNull(choice.customListRef);
    } catch (_) {
      raw = null;
    }
    if (raw == null) return (items: const <StremioMeta>[], failed: true);
    final metas = TraktItemTransformer.transformList(raw);
    return (items: _dedup(metas), failed: false);
  }

  Future<List<dynamic>?> _safeFetchBuiltin(
      TraktSeeAllList list, String contentType) async {
    try {
      return await TraktService.instance
          .fetchListOrNull(list.apiValue, contentType);
    } catch (_) {
      return null;
    }
  }

  /// Merge the movies + shows payloads. Time-ordered lists sort by row timestamp
  /// (newest first); rank-ordered lists interleave (movie, show, …) so each side
  /// keeps its API rank and a top show isn't buried beneath every movie.
  List<StremioMeta> _mergeFetched(
      TraktSeeAllList list, List<dynamic> movies, List<dynamic> shows) {
    final List<StremioMeta> ordered;
    if (list.isTimeOrdered) {
      final pairs = <({StremioMeta meta, int key})>[
        ..._pairedByTime(movies, inferredType: 'movie', episodeShaped: false),
        ..._pairedByTime(shows,
            inferredType: 'show',
            episodeShaped: list == TraktSeeAllList.history),
      ];
      pairs.sort((a, b) => b.key.compareTo(a.key)); // newest first
      ordered = [for (final p in pairs) p.meta];
    } else {
      final movieMetas =
          TraktItemTransformer.transformList(movies, inferredType: 'movie');
      final showMetas =
          TraktItemTransformer.transformList(shows, inferredType: 'show');
      ordered = <StremioMeta>[];
      final maxLen = movieMetas.length > showMetas.length
          ? movieMetas.length
          : showMetas.length;
      for (var i = 0; i < maxLen; i++) {
        if (i < movieMetas.length) ordered.add(movieMetas[i]);
        if (i < showMetas.length) ordered.add(showMetas[i]);
      }
    }
    return _dedup(ordered);
  }

  List<StremioMeta> _dedup(List<StremioMeta> metas) {
    final seen = <String>{};
    final out = <StremioMeta>[];
    for (final m in metas) {
      if (seen.add(m.imdbId ?? m.id)) out.add(m);
    }
    return out;
  }

  /// Transform a raw Trakt payload into (meta, timestamp) pairs for time-ordered
  /// lists. [episodeShaped] pulls the show out of an episode-shaped history row
  /// (whose own imdb is null); otherwise the row is a plain typed item.
  List<({StremioMeta meta, int key})> _pairedByTime(
    List<dynamic> raw, {
    required String inferredType,
    required bool episodeShaped,
  }) {
    final out = <({StremioMeta meta, int key})>[];
    for (final r in raw) {
      if (r is! Map<String, dynamic>) continue;
      StremioMeta? meta;
      if (episodeShaped) {
        final show = r['show'];
        if (show is Map<String, dynamic>) {
          // Keep the WHOLE row and just retype it: `type: 'episode'` would make
          // the transformer pick the episode (whose own imdb is null), but a
          // stripped `{'show': show}` would throw away `watched_at` with it —
          // and the transformer now stamps that onto the meta for the grid's
          // date sort. Dropping it left every show in History undated while
          // the movies beside them kept their date.
          meta = TraktItemTransformer.transformItem(
              {...r, 'type': 'show'},
              inferredType: 'show');
        }
      } else {
        meta = TraktItemTransformer.transformItem(r, inferredType: inferredType);
      }
      if (meta == null) continue;
      out.add((meta: meta, key: _rowTime(r)));
    }
    return out;
  }

  /// Epoch-ms of whichever known Trakt date field a row carries; 0 when absent
  /// so the item sorts last rather than crashing. The field list lives on the
  /// transformer, which stamps the same value onto every meta it builds — one
  /// definition, so the merge order here and the "Date Added" sort in the grid
  /// can never disagree about what a row's date is.
  int _rowTime(Map<String, dynamic> r) =>
      TraktItemTransformer.rowDateMs(r) ?? 0;
}
