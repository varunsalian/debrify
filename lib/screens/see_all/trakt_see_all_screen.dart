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

/// Sort orders for the grid. [natural] keeps the list's incoming order —
/// last-watched for Continue Watching, the API's own rank for fetched lists.
enum _Sort { natural, az, za }

/// Full-screen "See All" for the Trakt source. Opens on Continue Watching (the
/// row the user came from, handed in already-loaded via [cwItems]) and lets them
/// switch to any standard Trakt list — Watchlist, History, Collection, Ratings,
/// Recommendations, Trending, Popular, Anticipated — via the "List" dropdown.
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

  TraktSeeAllList _list = TraktSeeAllList.continueWatching;

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

  bool get _isCw => _list == TraktSeeAllList.continueWatching;

  /// The State (Watched/Unwatched) filter only makes sense where we have
  /// per-item progress — i.e. Continue Watching.
  bool get _showState => _isCw;

  /// Global (non-personal) lists — used to phrase the empty state correctly
  /// ("No Trending titles" vs "Nothing in your Watchlist").
  bool get _isPublicList => _list.isPublic;

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
  void _setList(TraktSeeAllList list) {
    if (list == _list) return;
    setState(() {
      _list = list;
      // The rail's category ('movie'/'series') that seeded the screen must not
      // silently truncate an unrelated fetched list, so reset it to 'all' — but
      // restore it when returning to Continue Watching so CW matches the rail the
      // user opened from. State/Sort are progress-specific to CW, so reset them.
      _category = list == TraktSeeAllList.continueWatching
          ? widget.initialCategory
          : 'all';
      _watch = 'all';
      _sort = _Sort.natural;
    });
    if (list == TraktSeeAllList.continueWatching) {
      setState(() {
        _fetchToken++; // cancel any in-flight fetch
        _items = widget.cwItems;
        _loading = false;
        _error = false;
        _recompute();
      });
      if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
    } else {
      _fetchList(list);
    }
  }

  /// Fetch a standard Trakt list from both the movies and shows endpoints
  /// concurrently, merge (see [_mergeFetched]) + dedup, then filter/sort in
  /// memory like the cached list.
  ///
  /// A `null` result means that endpoint failed (vs `[]` = genuinely empty). We
  /// surface the error state only when nothing loaded AND at least one side
  /// failed — so a real outage on one side that leaves the grid empty reads as
  /// an error, not as a (misleading) empty list, while a partial success still
  /// shows whatever loaded.
  Future<void> _fetchList(TraktSeeAllList list) async {
    final token = ++_fetchToken;
    setState(() {
      _loading = true;
      _error = false;
      _visible = const [];
    });
    // Fetch each endpoint independently so one throwing/failing can't discard
    // the other's result.
    final results = await Future.wait([
      _safeFetch(list, 'movies'),
      _safeFetch(list, 'shows'),
    ]);
    if (!mounted || token != _fetchToken) return;
    final movies = results[0];
    final shows = results[1];

    final deduped = _mergeFetched(list, movies ?? const [], shows ?? const []);
    final anyFailed = movies == null || shows == null;
    if (deduped.isEmpty && anyFailed) {
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
      _items = deduped;
      _loading = false;
      _recompute();
    });
    if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
  }

  /// [TraktService.fetchListOrNull] already returns null on every failure it
  /// catches; this guards the one path it doesn't (a throw while reading the
  /// stored token) so a Future.wait sibling is never lost to it.
  Future<List<dynamic>?> _safeFetch(TraktSeeAllList list, String contentType) async {
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
      TraktSeeAllList list, List<dynamic> movies, List<dynamic> shows) {
    final List<StremioMeta> ordered;
    if (list.isTimeOrdered) {
      // History shows are episode-shaped (the show is nested under 'show'); the
      // movies side and every other list is a plain typed item.
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
            StremioDropdown<TraktSeeAllList>(
              label: 'List',
              value: _list,
              isTelevision: widget.isTelevision,
              focusNode: _listNode,
              options: [
                for (final l in TraktSeeAllList.values)
                  StremioDropdownOption(l, l.label),
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
      return 'Nothing in your ${_list.label}';
    }
    return 'Nothing matches these filters';
  }
}
