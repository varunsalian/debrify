import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/trakt/trakt_list_source.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Sort orders for the grid. [natural] keeps the list's incoming order —
/// last-watched for Continue Watching, the API's own rank for fetched lists.
enum _Sort { natural, az, za, imdbDesc, imdbAsc }

/// Full-screen "See All" for the Trakt source. Opens on Continue Watching (the
/// row the user came from, handed in already-loaded via [cwItems]) and lets them
/// switch — via the "List" dropdown — to any built-in Trakt list (Watchlist,
/// History, Collection, Ratings, Recommendations, Trending, Popular,
/// Anticipated).
///
/// The user's own custom lists and liked lists are grouped: the "List" dropdown
/// gets "Custom Lists" / "Liked Lists" entries (only when the user has any), and
/// picking one reveals a second dropdown listing that group's specific lists —
/// so hundreds of lists never clog the primary dropdown.
///
/// Continue Watching is a client-side view over the cached rows (with the
/// progress/watched filters the local grid has). Every other list is fetched via
/// [TraktListSource], then filtered by category/sort in memory. Progress-based
/// controls (Sort "Last Watched", the Watched/Unwatched filter) only appear for
/// Continue Watching.
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

  /// Fires when a grid tile gains focus — drives the Discover detail rail.
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;

  /// Embedded mode (e.g. inside the Discover tab): drops the Scaffold + back
  /// header so the host provides the chrome, and prepends [leading] (a Source
  /// dropdown) to the filter bar with [leadingNode] in the DPAD focus row.
  final bool embedded;
  final Widget? leading;
  final FocusNode? leadingNode;

  const TraktSeeAllScreen({
    super.key,
    required this.cwItems,
    required this.cwProgress,
    required this.onOpen,
    this.initialCategory = 'all',
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
    this.embedded = false,
    this.leading,
    this.leadingNode,
  });

  @override
  State<TraktSeeAllScreen> createState() => _TraktSeeAllScreenState();
}

class _TraktSeeAllScreenState extends State<TraktSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  TraktListChoice _list =
      const TraktListChoice.builtin(TraktSeeAllList.continueWatching);

  // The user's own custom + liked lists, loaded lazily and offered under the
  // "Custom Lists" / "Liked Lists" groups (a secondary dropdown), so they never
  // flood the primary list dropdown.
  List<TraktListChoice> _customLists = const [];
  List<TraktListChoice> _likedLists = const [];

  // Active user-list group: null (a built-in is selected), 'custom' or 'liked'.
  String? _group;

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
  final FocusNode _groupNode = FocusNode(debugLabel: 'tsa_group');
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

  List<TraktListChoice> get _groupLists =>
      _group == 'custom' ? _customLists : _likedLists;

  /// Filter-bar focus order, recomputed because the group + State controls come
  /// and go with the selected list.
  List<FocusNode> get _filterNodes => [
        if (widget.leadingNode != null) widget.leadingNode!,
        _listNode,
        if (_group != null) _groupNode,
        _catNode,
        _sortNode,
        if (_showState) _watchNode,
      ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('trakt_see_all');
    _items = widget.cwItems;
    _category = widget.initialCategory;
    _recompute();
    // Embedded (Discover): the host focuses the Source dropdown on entry, and a
    // source swap re-mounts this panel — so don't yank focus into the grid here,
    // it would steal the DPAD ring off the Source dropdown on every swap.
    if (widget.isTelevision && !widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
    }
    _loadUserLists();
  }

  @override
  void didUpdateWidget(covariant TraktSeeAllScreen old) {
    super.didUpdateWidget(old);
    // Embedded in Discover, the cached Continue Watching rows load async after
    // mount — re-sync while actually showing CW so a fetched list isn't clobbered.
    if (_isCw && !identical(widget.cwItems, old.cwItems)) {
      _items = widget.cwItems;
      _recompute();
      // If the reload drained the grid to empty on TV, move focus off the
      // vanished tiles to the leading Source dropdown so the remote isn't stranded
      // — but only when focus was on the grid, not if the user is mid-way through
      // a filter dropdown (a background reload shouldn't yank them off it).
      if (widget.embedded && widget.isTelevision && _visible.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _visible.isNotEmpty) return;
          if (_filterNodes.any((n) => n.hasFocus)) return;
          (widget.leadingNode ?? _listNode).requestFocus();
        });
      }
    }
  }

  /// Load the user's custom + liked lists in the background and split them into
  /// the two groups. Returns [] when Trakt isn't connected or on error, so the
  /// dropdown simply keeps only the built-in entries.
  Future<void> _loadUserLists() async {
    final lists = await TraktListSource.instance.loadUserLists();
    if (!mounted || lists.isEmpty) return;
    setState(() {
      _customLists = [for (final c in lists) if (!c.liked) c];
      _likedLists = [for (final c in lists) if (c.liked) c];
    });
  }

  /// Land DPAD focus somewhere usable: the first grid tile, or — when the grid
  /// is empty — the back button, so the remote is never stranded.
  void _focusEntry() {
    if (!mounted) return;
    // Only invoked standalone (initState gates on !embedded); embedded empty-grid
    // focus recovery lives in didUpdateWidget instead.
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
    _groupNode.dispose();
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
      case _Sort.imdbDesc:
      case _Sort.imdbAsc:
        // Unrated items sink to the end in BOTH directions so they never bury
        // rated ones; rating ties fall back to A–Z so the order is stable.
        final asc = _sort == _Sort.imdbAsc;
        list.sort((a, b) {
          final ra = a.imdbRating, rb = b.imdbRating;
          if (ra == null && rb == null) {
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          }
          if (ra == null) return 1;
          if (rb == null) return -1;
          final byRating = asc ? ra.compareTo(rb) : rb.compareTo(ra);
          if (byRating != 0) return byRating;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
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

  // ── List selection (primary dropdown + group dropdown) ──────────────────────

  static const String _customGroupKey = 'grp_custom';
  static const String _likedGroupKey = 'grp_liked';

  String _builtinKey(TraktSeeAllList l) => 'b${l.index}';

  /// Value for the primary dropdown: a group key when a user list is active,
  /// else the current built-in's key.
  String get _primaryKey {
    if (_group == 'custom') return _customGroupKey;
    if (_group == 'liked') return _likedGroupKey;
    return _builtinKey(_list.builtin ?? TraktSeeAllList.continueWatching);
  }

  /// Primary dropdown picked: a built-in list, or a group (which reveals the
  /// secondary dropdown and lands on that group's first list).
  void _onPrimary(String key) {
    if (key == _customGroupKey || key == _likedGroupKey) {
      final group = key == _customGroupKey ? 'custom' : 'liked';
      // Already in this group — keep the sub-list the user is viewing rather than
      // snapping back to the first (re-picking the header must not lose their spot).
      if (group == _group) return;
      final lists = group == 'custom' ? _customLists : _likedLists;
      if (lists.isEmpty) return;
      setState(() => _group = group);
      _setList(lists.first);
      return;
    }
    final idx = int.tryParse(key.substring(1));
    if (idx == null || idx < 0 || idx >= TraktSeeAllList.values.length) return;
    setState(() => _group = null);
    _setList(TraktListChoice.builtin(TraktSeeAllList.values[idx]));
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

  /// Fetch and display a non-CW list via [TraktListSource]. Surfaces the error
  /// state only when nothing loaded AND the fetch actually failed (a partial
  /// built-in success still shows what loaded); a genuinely empty list reads as
  /// empty, not error.
  Future<void> _fetchList(TraktListChoice choice) async {
    final token = ++_fetchToken;
    setState(() {
      _loading = true;
      _error = false;
      _visible = const [];
    });
    final loaded = await TraktListSource.instance.loadList(choice);
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

  // ── TV filter-bar focus wiring ──────────────────────────────────────────────

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      onDown: () => _gridKey.currentState?.focusFirst(),
      // Embedded (Discover tab) has no back button above the filter bar, so
      // up-from-filters stays put; the standalone screen returns to it.
      onUp: () {
        if (!widget.embedded) _backNode.requestFocus();
      },
      // Embedded: Left off the leading Source dropdown escapes to the TV sidebar.
      onLeftEdge: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final n = _visible.length;
    // Embedded (Discover tab): the host supplies the Scaffold + chrome, so render
    // just the filter bar (with the leading Source dropdown) over the grid.
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFilterBar(),
          Expanded(child: _buildBody()),
        ],
      );
    }
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

  /// Non-default secondary filters, for the collapsed Filters button badge. The
  /// List selector isn't counted (it's the primary source, like Discover's).
  int get _activeFilterCount {
    var n = 0;
    // Compare against how the screen opened, not a hardcoded 'all': a seeded
    // rail can start _category on 'movie'/'series', which isn't a user filter.
    if (_category != widget.initialCategory) n++;
    if (_sort != _Sort.natural) n++;
    if (_showState && _watch != 'all') n++;
    return n;
  }

  /// Discover TV styling: quiet text-segment filters on the glass stage, no
  /// per-poster rating chips (the detail rail carries that information).
  bool get _quiet => widget.embedded && widget.isTelevision;

  Widget _buildFilterBar() {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleFilterKeys,
      child: Padding(
        padding: _quiet
            ? const EdgeInsets.fromLTRB(24, 16, 24, 10)
            : const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          leading: widget.leading,
          quiet: _quiet,
          activeCount: _activeFilterCount,
          buildChips: () => [
            StremioDropdown<String>(
              label: 'List',
              value: _primaryKey,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _listNode,
              options: [
                for (final l in TraktSeeAllList.values)
                  StremioDropdownOption(_builtinKey(l), l.label),
                if (_customLists.isNotEmpty)
                  const StremioDropdownOption(_customGroupKey, 'Custom Lists'),
                if (_likedLists.isNotEmpty)
                  const StremioDropdownOption(_likedGroupKey, 'Liked Lists'),
              ],
              onSelected: _onPrimary,
            ),
            if (_group != null)
              StremioDropdown<TraktListChoice>(
                label: _group == 'custom' ? 'Custom' : 'Liked',
                value: _list,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _groupNode,
                options: [
                  for (final c in _groupLists) StremioDropdownOption(c, c.label),
                ],
                onSelected: _setList,
              ),
            StremioDropdown<String>(
              label: 'Show',
              value: _category,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
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
              quiet: _quiet,
              focusNode: _sortNode,
              options: [
                StremioDropdownOption(
                    _Sort.natural, _isCw ? 'Last Watched' : 'Default'),
                const StremioDropdownOption(_Sort.az, 'A–Z'),
                const StremioDropdownOption(_Sort.za, 'Z–A'),
                const StremioDropdownOption(
                    _Sort.imdbDesc, 'IMDb Rating · High → Low'),
                const StremioDropdownOption(
                    _Sort.imdbAsc, 'IMDb Rating · Low → High'),
              ],
              onSelected: (v) => _setFilter(() => _sort = v),
            ),
            if (_showState)
              StremioDropdown<String>(
                label: 'State',
                value: _watch,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
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
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
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
      onItemFocused: widget.onItemFocused,
      // Discover on TV has the detail rail naming the type — drop the badge there.
      showTypeBadge: !_quiet,
      showRatingBadge: !_quiet,
      progressOf: _progressOf,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _listNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
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
