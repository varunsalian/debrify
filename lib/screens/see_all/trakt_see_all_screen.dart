import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/trakt/trakt_item_transformer.dart';
import '../../services/trakt/trakt_service.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// The Trakt lists this See-All screen can switch between. [continueWatching] is
/// special — it reuses the already-loaded rows the host passed in (no fetch);
/// every other entry is fetched on demand via [TraktService.fetchList].
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

extension _TraktSeeAllListX on TraktSeeAllList {
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

  /// Trakt API list slug for [TraktService.fetchList]. Empty for
  /// [continueWatching], which is served from the host's cached rows.
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

  /// Lists whose natural order is a genuine cross-type timeline (a watched_at /
  /// rated_at / collected_at recency), so merging movies + shows must sort by
  /// that timestamp rather than interleave. Excludes Watchlist — its order is
  /// user-curated (rank), so forcing a date sort would destroy it — and the
  /// rank-ordered public/recommendation lists.
  bool get isTimeOrdered =>
      this == TraktSeeAllList.history ||
      this == TraktSeeAllList.ratings ||
      this == TraktSeeAllList.collection;
}

/// A selectable entry in the "List" dropdown: either one of the built-in Trakt
/// lists ([builtin]) or a specific user list — an own custom list or a liked
/// list ([userList], with [liked] distinguishing the two, since they fetch from
/// different endpoints). Value-equal by the built-in enum or the list's Trakt id
/// so the dropdown can match the current selection across rebuilds.
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

  String get label {
    if (builtin != null) return builtin!.label;
    final name = userList?['name'] as String?;
    return (name == null || name.trim().isEmpty) ? 'Untitled list' : name;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TraktListChoice) return false;
    if (other.builtin != builtin || other.liked != liked) return false;
    // Match user lists by their Trakt id; when a list carries no usable id, fall
    // back to object identity so two id-less lists don't collide in the dropdown.
    if (userList == null && other.userList == null) return true;
    final id = userListId;
    if (id != null || other.userListId != null) return id == other.userListId;
    return identical(userList, other.userList);
  }

  @override
  int get hashCode => Object.hash(builtin, liked, userListId);
}

/// Sort orders for the grid. [natural] keeps the list's incoming order —
/// last-watched for Continue Watching, the API's own rank for fetched lists.
enum _Sort { natural, az, za }

/// Full-screen "See All" for the Trakt source. Opens on Continue Watching (the
/// row the user came from, handed in already-loaded via [cwItems]) and lets them
/// switch — via the "List" dropdown — to any standard Trakt list (Watchlist,
/// History, Collection, Ratings, Recommendations, Trending, Popular,
/// Anticipated) as well as their own custom lists and liked lists, which are
/// loaded lazily and appended to the dropdown.
///
/// Continue Watching is a client-side view over the cached rows (with the
/// progress/watched filters the local grid has). Every other list is fetched on
/// selection from both the movies and shows endpoints, merged, then filtered by
/// category/sort in memory. Progress-based controls (Sort "Last Watched", the
/// Watched/Unwatched filter) only appear for Continue Watching.
class TraktSeeAllScreen extends StatefulWidget {
  /// Cached Continue Watching rows (last-watched order), shown without a fetch.
  final List<StremioMeta> cwItems;

  /// Resume progress (0..1) for a Continue Watching item; null for fetched lists.
  final Map<String, double> cwProgress;

  /// Pre-selected category ('all' / 'movie' / 'series') — the type of the row
  /// the user opened See-All from.
  final String initialCategory;

  final void Function(StremioMeta item) onOpen;
  final void Function(StremioMeta item)? onQuickPlay;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;

  const TraktSeeAllScreen({
    super.key,
    required this.cwItems,
    required this.cwProgress,
    required this.onOpen,
    this.initialCategory = 'all',
    this.onQuickPlay,
    this.isBound,
    this.isTelevision = false,
  });

  @override
  State<TraktSeeAllScreen> createState() => _TraktSeeAllScreenState();
}

class _TraktSeeAllScreenState extends State<TraktSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  TraktListChoice _list =
      const TraktListChoice.builtin(TraktSeeAllList.continueWatching);

  // The user's own custom lists + liked lists, loaded lazily and appended to the
  // "List" dropdown after the built-in entries.
  List<TraktListChoice> _userLists = const [];

  // Source list for the current selection + the derived, cached view.
  late List<StremioMeta> _items;
  List<StremioMeta> _visible = const [];

  late String _category; // all | movie | series
  _Sort _sort = _Sort.natural;
  String _watch = 'all'; // all | watched | unwatched

  bool _loading = false;
  bool _error = false;

  // Guards against a slow fetch landing after the user has moved on to another
  // list (or left the screen).
  int _fetchToken = 0;

  // A title is "watched" once past this fraction, matching the app's
  // quick-play/continue-watching threshold.
  static const double _watchedAt = 0.9;

  final FocusNode _backNode = FocusNode(debugLabel: 'tsa_back');
  final FocusNode _listNode = FocusNode(debugLabel: 'tsa_list');
  final FocusNode _catNode = FocusNode(debugLabel: 'tsa_category');
  final FocusNode _sortNode = FocusNode(debugLabel: 'tsa_sort');
  final FocusNode _watchNode = FocusNode(debugLabel: 'tsa_watch');

  bool get _isCw => _list.isContinueWatching;

  /// The State (Watched/Unwatched) filter only makes sense where we have
  /// per-item progress — i.e. Continue Watching.
  bool get _showState => _isCw;

  /// Global (non-personal) built-in lists — used to phrase the empty state
  /// correctly ("No Trending titles" vs "Nothing in your Watchlist").
  bool get _isPublicList => _list.builtin?.isPublic ?? false;

  /// Filter-bar focus order, recomputed because the State control comes and goes
  /// with the selected list.
  List<FocusNode> get _filterNodes => [
        _listNode,
        _catNode,
        _sortNode,
        if (_showState) _watchNode,
      ];

  @override
  void initState() {
    super.initState();
    _items = widget.cwItems;
    _category = widget.initialCategory;
    _recompute();
    if (widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
    }
    _loadUserLists();
  }

  /// Load the user's own custom lists + liked lists in the background and append
  /// them to the "List" dropdown. Both fetches return [] when Trakt isn't
  /// connected or on error, so the dropdown simply keeps only the built-in
  /// entries — no failure surfaced for a feature the user may not use.
  Future<void> _loadUserLists() async {
    final svc = TraktService.instance;
    List<Map<String, dynamic>> custom;
    List<Map<String, dynamic>> liked;
    try {
      final results = await Future.wait([
        svc.fetchCustomLists(),
        svc.fetchLikedLists(),
      ]);
      custom = results[0];
      liked = results[1];
    } catch (_) {
      return;
    }
    if (!mounted || (custom.isEmpty && liked.isEmpty)) return;
    final ownChoices = [
      for (final l in custom) TraktListChoice.userList(l, liked: false),
    ];
    final ownIds = <String>{
      for (final c in ownChoices)
        if (c.userListId != null) c.userListId!,
    };
    // Drop any liked list the user also owns (a self-liked list) so it doesn't
    // appear twice under the same name.
    final likedChoices = <TraktListChoice>[];
    for (final l in liked) {
      final choice = TraktListChoice.userList(l, liked: true);
      final id = choice.userListId;
      if (id == null || !ownIds.contains(id)) likedChoices.add(choice);
    }
    setState(() {
      _userLists = [...ownChoices, ...likedChoices];
    });
  }

  /// Land DPAD focus somewhere usable: the first grid tile, or — when the grid
  /// is empty — the back button, so the remote is never stranded.
  void _focusEntry() {
    if (!mounted) return;
    if (_visible.isEmpty) {
      _backNode.requestFocus();
    } else {
      _gridKey.currentState?.focusFirst();
    }
  }

  @override
  void dispose() {
    _backNode.dispose();
    _listNode.dispose();
    _catNode.dispose();
    _sortNode.dispose();
    _watchNode.dispose();
    super.dispose();
  }

  // ── Derived list (memoized; recomputed only on data/filter change) ──────────

  double? _progressOf(StremioMeta m) =>
      _isCw ? widget.cwProgress[m.imdbId] : null;

  bool _isWatched(StremioMeta m) => (_progressOf(m) ?? 0) >= _watchedAt;

  void _recompute() {
    Iterable<StremioMeta> it = _items;
    if (_category == 'movie') {
      it = it.where((m) => m.type != 'series');
    } else if (_category == 'series') {
      it = it.where((m) => m.type == 'series');
    }
    if (_showState && _watch == 'watched') {
      it = it.where(_isWatched);
    } else if (_showState && _watch == 'unwatched') {
      it = it.where((m) => !_isWatched(m));
    }
    final list = it.toList();
    switch (_sort) {
      case _Sort.natural:
        break; // items already arrive in the list's natural order
      case _Sort.az:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _Sort.za:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
    }
    _visible = list;
  }

  void _setFilter(VoidCallback change) {
    setState(() {
      change();
      _recompute();
    });
  }

  /// Switch the active Trakt list. Continue Watching restores the cached rows;
  /// everything else fetches. Progress-only filters reset so a stale
  /// Watched/Unwatched pick doesn't hide a fetched list.
  void _setList(TraktListChoice choice) {
    if (choice == _list) return;
    setState(() {
      _list = choice;
      // The rail's category ('movie'/'series') that seeded the screen must not
      // silently truncate an unrelated fetched list, so reset it to 'all' — but
      // restore it when returning to Continue Watching so CW matches the rail the
      // user opened from. State/Sort are progress-specific to CW, so reset them.
      _category = choice.isContinueWatching ? widget.initialCategory : 'all';
      _watch = 'all';
      _sort = _Sort.natural;
    });
    if (choice.isContinueWatching) {
      setState(() {
        _fetchToken++; // cancel any in-flight fetch
        _items = widget.cwItems;
        _loading = false;
        _error = false;
        _recompute();
      });
      if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
    } else {
      _fetchList(choice);
    }
  }

  /// Fetch and display a non-CW list. Surfaces the error state only when nothing
  /// loaded AND the fetch actually failed (a partial built-in success still
  /// shows what loaded); a genuinely empty list reads as empty, not error.
  Future<void> _fetchList(TraktListChoice choice) async {
    final token = ++_fetchToken;
    setState(() {
      _loading = true;
      _error = false;
      _visible = const [];
    });
    final loaded = await _loadItems(choice);
    if (!mounted || token != _fetchToken) return;
    if (loaded.items.isEmpty && loaded.failed) {
      setState(() {
        _loading = false;
        _error = true;
        _items = const [];
        _visible = const [];
      });
      if (widget.isTelevision) _listNode.requestFocus();
      return;
    }
    setState(() {
      _items = loaded.items;
      _loading = false;
      _recompute();
    });
    if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
  }

  /// Load a list's items + whether the fetch failed.
  ///
  /// Built-in lists fetch the movies + shows endpoints concurrently ([_safeFetch]
  /// returns null on failure) and merge (see [_mergeFetched]); [failed] is true
  /// when either side failed. User (custom/liked) lists fetch in one ordered
  /// call — preserving the list's own cross-type order and returning null on
  /// failure — so they also get a real error state (no longer just "empty").
  Future<({List<StremioMeta> items, bool failed})> _loadItems(
      TraktListChoice choice) async {
    final builtin = choice.builtin;
    if (builtin != null) {
      // Fetch each endpoint independently so one failing can't discard the other.
      final results = await Future.wait([
        _safeFetch(builtin, 'movies'),
        _safeFetch(builtin, 'shows'),
      ]);
      final movies = results[0];
      final shows = results[1];
      return (
        items: _mergeFetched(choice, movies ?? const [], shows ?? const []),
        failed: movies == null || shows == null,
      );
    }

    List<dynamic>? raw;
    try {
      raw = choice.liked
          ? await TraktService.instance
              .fetchLikedListItemsOrderedOrNull(choice.userList!)
          : await TraktService.instance
              .fetchCustomListItemsOrderedOrNull(_customListRef(choice));
    } catch (_) {
      raw = null;
    }
    if (raw == null) return (items: const <StremioMeta>[], failed: true);
    // The single call already returns the list's order across types; each item
    // carries its own `type`, so transformList resolves movies and shows alike
    // (episodes/people were never requested). Dedup, preserving order.
    final metas = TraktItemTransformer.transformList(raw);
    final seen = <String>{};
    final deduped = <StremioMeta>[];
    for (final m in metas) {
      if (seen.add(m.imdbId ?? m.id)) deduped.add(m);
    }
    return (items: deduped, failed: false);
  }

  /// Own-custom-list reference for the items endpoint — the slug (what Trakt's
  /// examples use) when present, else the Trakt id.
  String _customListRef(TraktListChoice choice) {
    final ids = choice.userList?['ids'];
    if (ids is Map) {
      final slug = ids['slug'];
      if (slug != null && slug.toString().isNotEmpty) return slug.toString();
      final trakt = ids['trakt'];
      if (trakt != null) return trakt.toString();
    }
    return choice.userListId ?? '';
  }

  /// Fetch one content type of a built-in list via [TraktService.fetchListOrNull]
  /// (null on failure). The try/catch guards the one path it doesn't (a throw
  /// while reading the stored token) so a Future.wait sibling is never lost.
  Future<List<dynamic>?> _safeFetch(
      TraktSeeAllList list, String contentType) async {
    try {
      return await TraktService.instance
          .fetchListOrNull(list.apiValue, contentType);
    } catch (_) {
      return null;
    }
  }

  /// Merge the movies + shows payloads into one deduped list. Time-ordered lists
  /// are sorted by their row timestamp (newest first) so the combined timeline is
  /// correct across types; rank-ordered lists are interleaved (movie, show, …) so
  /// each side keeps its API rank and a top show isn't buried beneath every movie.
  List<StremioMeta> _mergeFetched(
      TraktListChoice choice, List<dynamic> movies, List<dynamic> shows) {
    // Only built-in lists reach here (user lists load via a single ordered call).
    final timeOrdered = choice.builtin?.isTimeOrdered ?? false;
    final isHistory = choice.builtin == TraktSeeAllList.history;
    final List<StremioMeta> ordered;
    if (timeOrdered) {
      // History shows are episode-shaped (the show is nested under 'show'); the
      // movies side and every other list is a plain typed item.
      final pairs = <({StremioMeta meta, int key})>[
        ..._pairedByTime(movies, inferredType: 'movie', episodeShaped: false),
        ..._pairedByTime(shows, inferredType: 'show', episodeShaped: isHistory),
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
    // Dedup by IMDB id: a binged show repeats across history rows, and a title
    // could in principle surface on both endpoints. Sorted newest-first first, so
    // the kept copy is the most recent occurrence.
    final seen = <String>{};
    final deduped = <StremioMeta>[];
    for (final m in ordered) {
      if (seen.add(m.imdbId ?? m.id)) deduped.add(m);
    }
    return deduped;
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
          meta = TraktItemTransformer.transformItem({'show': show},
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

  /// Epoch-ms of whichever known Trakt date field a row carries (watched_at,
  /// rated_at, collected_at / last_collected_at, listed_at); 0 when absent so the
  /// item sorts last rather than crashing.
  int _rowTime(Map<String, dynamic> r) {
    const fields = [
      'watched_at',
      'rated_at',
      'collected_at',
      'last_collected_at',
      'listed_at',
      'last_watched_at',
    ];
    for (final f in fields) {
      final v = r[f];
      if (v is String) {
        final t = DateTime.tryParse(v);
        if (t != null) return t.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  // ── TV filter-bar focus wiring ──────────────────────────────────────────────

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      onDown: () => _gridKey.currentState?.focusFirst(),
      onUp: () => _backNode.requestFocus(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final n = _visible.length;
    return Scaffold(
      backgroundColor: kSeeAllBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: 'Trakt',
              subtitle: _loading
                  ? '${_list.label} · Loading…'
                  : '${_list.label} · $n ${n == 1 ? 'title' : 'titles'}',
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              onFilterDown: () => _listNode.requestFocus(),
            ),
            _buildFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleFilterKeys,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            StremioDropdown<TraktListChoice>(
              label: 'List',
              value: _list,
              isTelevision: widget.isTelevision,
              focusNode: _listNode,
              options: [
                for (final l in TraktSeeAllList.values)
                  StremioDropdownOption(TraktListChoice.builtin(l), l.label),
                for (final c in _userLists)
                  StremioDropdownOption(c, c.label),
              ],
              onSelected: _setList,
            ),
            StremioDropdown<String>(
              label: 'Show',
              value: _category,
              isTelevision: widget.isTelevision,
              focusNode: _catNode,
              options: const [
                StremioDropdownOption('all', 'All'),
                StremioDropdownOption('movie', 'Movies'),
                StremioDropdownOption('series', 'Series'),
              ],
              onSelected: (v) => _setFilter(() => _category = v),
            ),
            StremioDropdown<_Sort>(
              label: 'Sort',
              value: _sort,
              isTelevision: widget.isTelevision,
              focusNode: _sortNode,
              options: [
                StremioDropdownOption(
                    _Sort.natural, _isCw ? 'Last Watched' : 'Default'),
                const StremioDropdownOption(_Sort.az, 'A–Z'),
                const StremioDropdownOption(_Sort.za, 'Z–A'),
              ],
              onSelected: (v) => _setFilter(() => _sort = v),
            ),
            if (_showState)
              StremioDropdown<String>(
                label: 'State',
                value: _watch,
                isTelevision: widget.isTelevision,
                focusNode: _watchNode,
                options: const [
                  StremioDropdownOption('all', 'All'),
                  StremioDropdownOption('watched', 'Watched'),
                  StremioDropdownOption('unwatched', 'Unwatched'),
                ],
                onSelected: (v) => _setFilter(() => _watch = v),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            valueColor: AlwaysStoppedAnimation<Color>(kSeeAllAccent),
          ),
        ),
      );
    }
    if (_visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _error ? Icons.cloud_off_rounded : Icons.inbox_rounded,
                size: 44,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              const SizedBox(height: 14),
              Text(
                _emptyMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SeeAllPosterGrid(
      key: _gridKey,
      items: _visible,
      isTelevision: widget.isTelevision,
      loadingMore: false,
      exhausted: true, // finite, in-memory list — no paging
      onOpen: widget.onOpen,
      // Quick-play resolves a resume point from the host's cached CW rows; a
      // fetched-list item isn't in that map, so the button would silently open
      // the detail instead of playing. Only offer it where it works.
      onQuickPlay: _isCw ? widget.onQuickPlay : null,
      progressOf: _progressOf,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _listNode.requestFocus() : null,
    );
  }

  String _emptyMessage() {
    if (_error) return "Couldn't load ${_list.label} from Trakt";
    // Distinguish "the list is empty" from "filters hid everything".
    if (_items.isEmpty) {
      if (_isCw) return 'Nothing to continue yet';
      if (_isPublicList) return 'No ${_list.label} titles right now';
      if (!_list.isBuiltin) return '"${_list.label}" is empty';
      return 'Nothing in your ${_list.label}';
    }
    return 'Nothing matches these filters';
  }
}
