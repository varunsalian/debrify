import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/simkl/simkl_list_source.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/see_all_sort.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Sort orders for the grid. [natural] keeps the API's own rank/interleave
/// order.
enum _Sort { natural, az, za, imdbDesc, imdbAsc, addedNewest, addedOldest }

/// Full-screen "See All" for the Simkl source. Opens on Continue Watching when
/// the host provides some (else Trending — public, no auth wall, always
/// populated) and lets the user switch — via the "List" dropdown — to Continue
/// Watching, any of the five watchlist states (Plan to Watch / Watching / On
/// Hold / Completed / Dropped), Ratings, or the two discovery lists (Top Rated,
/// New & Upcoming).
///
/// Continue Watching mirrors [TraktSeeAllScreen]: the host hands its items in
/// already-loaded ([cwItems]/[cwProgress]) rather than fetching via
/// [SimklListSource], and only that list shows progress bars. Still simpler than
/// Trakt in one way: no custom/liked-list group dropdown (Simkl's Custom Lists
/// aren't exposed via API yet). Every non-CW list is fetched via
/// [SimklListSource], then filtered by category/sort in memory.
class SimklSeeAllScreen extends StatefulWidget {
  /// Open / quick-play for a NON-CW list (Trending, watchlist states, …) — a
  /// plain catalog open/play, no resume.
  final void Function(StremioMeta item) onOpen;
  final void Function(StremioMeta item)? onQuickPlay;

  /// The user's Continue Watching titles (paused + up-next), already loaded by
  /// the host — the [SimklSeeAllList.continueWatching] list renders these
  /// directly (no fetch). Empty when the host has none / isn't connected, in
  /// which case the screen opens on Trending instead. Progress bars for these
  /// come from [cwProgress] (imdbId → 0..1); other lists show no progress.
  final List<StremioMeta> cwItems;
  final Map<String, double> cwProgress;

  /// Open / quick-play used ONLY while the Continue Watching list is showing —
  /// these resume at the paused / up-next episode. Kept separate from [onOpen]/
  /// [onQuickPlay] so a title that's browsed from another list (Trending, etc.)
  /// but also happens to be in CW opens fresh, not mid-episode. Fall back to the
  /// plain handlers when not provided.
  final void Function(StremioMeta item)? cwOnOpen;
  final void Function(StremioMeta item)? cwOnQuickPlay;

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

  const SimklSeeAllScreen({
    super.key,
    required this.onOpen,
    this.onQuickPlay,
    this.cwItems = const [],
    this.cwProgress = const {},
    this.cwOnOpen,
    this.cwOnQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
    this.embedded = false,
    this.leading,
    this.leadingNode,
  });

  @override
  State<SimklSeeAllScreen> createState() => _SimklSeeAllScreenState();
}

class _SimklSeeAllScreenState extends State<SimklSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  late SimklSeeAllList _list;

  /// True while [_list] is still the initState auto-pick (not user-chosen) — so
  /// a CW list that loads AFTER we fell back to Trending can promote itself.
  bool _autoList = true;

  bool get _isCw => _list == SimklSeeAllList.continueWatching;

  /// Grid handlers: the CW list resumes (cwOnOpen/cwOnQuickPlay); every other
  /// list opens/plays plainly, so a title browsed fresh from Trending etc. never
  /// resumes just because it also sits in Continue Watching.
  void Function(StremioMeta) get _open =>
      _isCw ? (widget.cwOnOpen ?? widget.onOpen) : widget.onOpen;
  void Function(StremioMeta)? get _quickPlay =>
      _isCw ? (widget.cwOnQuickPlay ?? widget.onQuickPlay) : widget.onQuickPlay;

  List<StremioMeta> _items = const [];
  List<StremioMeta> _visible = const [];

  String _category = 'all'; // all | movie | series
  _Sort _sort = _Sort.natural;

  /// A remembered date sort waiting for a list that can honour it. Resolved by
  /// [_recompute] the first time dated rows load, and dropped the moment the
  /// user picks any sort themselves — a stored preference should re-apply once,
  /// not keep overriding the choice they just made.
  _Sort? _deferredSort;

  bool _loading = false;
  bool _error = false;

  // Guards against a slow fetch landing after the user has moved on to
  // another list (or left the screen).
  int _fetchToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'ssa_back');
  final FocusNode _listNode = FocusNode(debugLabel: 'ssa_list');
  final FocusNode _catNode = FocusNode(debugLabel: 'ssa_category');
  final FocusNode _sortNode = FocusNode(debugLabel: 'ssa_sort');
  final FocusNode _randomNode = FocusNode(debugLabel: 'ssa_random');

  final Random _random = Random();

  /// The Random button is a Discover affordance: only the embedded host
  /// wires Quick Play (and hides it in PikPak-only mode by passing null).
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  /// "Date Added" is offered only where the rows carry a date — Simkl stamps
  /// `added_to_watchlist_at` on the watchlist statuses (Plan to Watch,
  /// Watching, Completed, …) but the best/premieres/trending lists are public
  /// catalogue rows with none. Asked of the LOADED items, so nothing has to
  /// enumerate which Simkl list is which.
  bool get _showAdded => hasAddedDates(_items);

  /// What the date on THIS list's rows actually means. The watchlist statuses
  /// carry `added_to_watchlist_at`, but Ratings comes from `/sync/ratings`,
  /// where the date is `user_rated_at` — calling that "Date Added" would tell
  /// the user the list is ordered by when they saved a title when it is
  /// ordered by when they rated it.
  String get _addedLabel =>
      _list == SimklSeeAllList.ratings ? 'Date Rated' : 'Date Added';

  /// The sort actually applied. A remembered "Date Added" pick can outlive the
  /// list it was made on (swap Plan to Watch → Trending, or relaunch), and the
  /// dropdown must not be handed a value absent from its options.
  _Sort get _effectiveSort =>
      (!_showAdded &&
              (_sort == _Sort.addedNewest || _sort == _Sort.addedOldest))
          ? _Sort.natural
          : _sort;

  List<FocusNode> get _filterNodes => [
        if (widget.leadingNode != null) widget.leadingNode!,
        _listNode,
        _catNode,
        _sortNode,
        if (_showRandom) _randomNode,
      ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('simkl_see_all');
    // Land on Continue Watching when the host handed us some (the natural
    // "continue" context); otherwise Trending (public, always populated).
    _list = widget.cwItems.isNotEmpty
        ? SimklSeeAllList.continueWatching
        : SimklSeeAllList.trending;
    // Discover only: reopen on the order the user last picked for this source.
    // Read before the fetch so the arriving grid is sorted on its first paint.
    if (widget.embedded) {
      final saved =
          DiscoverPrefs.enumSortFor(DiscoverPrefs.simkl, _Sort.values);
      if (saved != null) {
        _sort = saved;
        // A remembered DATE sort can't take effect here: Simkl opens on
        // Continue Watching or Trending, both undated, and the list switch that
        // finally reaches a dated list resets _sort. Held aside so it can be
        // claimed when dated rows actually arrive — otherwise the preference
        // would be stored and never once applied.
        if (saved == _Sort.addedNewest || saved == _Sort.addedOldest) {
          _deferredSort = saved;
        }
      }
    }
    _fetchList(_list);
  }

  @override
  void didUpdateWidget(SimklSeeAllScreen old) {
    super.didUpdateWidget(old);
    if (identical(widget.cwItems, old.cwItems)) return;
    // No setState needed — didUpdateWidget is followed by build (matches
    // TraktSeeAllScreen).
    if (_isCw) {
      // A background CW refresh (progress moved, a title finished) — re-mirror.
      _items = widget.cwItems;
      _recompute();
    } else if (_autoList &&
        old.cwItems.isEmpty &&
        widget.cwItems.isNotEmpty) {
      // We auto-fell-back to Trending because CW hadn't loaded yet; it just
      // arrived and the user hasn't picked a list — promote to Continue
      // Watching (the intended landing). Bump the token so a Trending fetch
      // that's still in flight can't overwrite this promoted CW grid.
      _fetchToken++;
      _list = SimklSeeAllList.continueWatching;
      _loading = false;
      _error = false;
      _items = widget.cwItems;
      _recompute();
    }
  }

  @override
  void dispose() {
    _backNode.dispose();
    _listNode.dispose();
    _catNode.dispose();
    _sortNode.dispose();
    _randomNode.dispose();
    super.dispose();
  }

  // ── Derived list (memoized; recomputed only on data/filter change) ──────────

  void _recompute() {
    // Dated rows have arrived: settle the remembered date sort. Claimed only
    // over `natural`, so the list switch that got us here (which resets the
    // sort) is honoured while an explicit pick made since is not overridden.
    final settled = settleDeferredSort(
      deferred: _deferredSort,
      current: _sort,
      natural: _Sort.natural,
      listHasDates: hasAddedDates(_items),
    );
    _sort = settled.sort;
    _deferredSort = settled.deferred;
    Iterable<StremioMeta> it = _items;
    if (_category == 'movie') {
      it = it.where((m) => m.type != 'series');
    } else if (_category == 'series') {
      it = it.where((m) => m.type == 'series');
    }
    final list = it.toList();
    switch (_effectiveSort) {
      case _Sort.natural:
        break; // items already arrive in the list's natural (rank) order
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
        // Unrated items sink to the end in BOTH directions so they never
        // bury rated ones; rating ties fall back to A–Z for stability.
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
      case _Sort.addedNewest:
      case _Sort.addedOldest:
        list.sort(byAddedDate(newest: _sort == _Sort.addedNewest));
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

  /// Sort picks are remembered (Discover only) so the next launch — and the next
  /// swap back to this source — opens on the same order. Only an explicit pick
  /// is stored: switching lists resets the sort in-session, and that reset must
  /// not erase the user's standing choice.
  void _setSort(_Sort v) {
    // An explicit pick supersedes anything still waiting to be restored.
    _deferredSort = null;
    _setFilter(() => _sort = v);
    if (widget.embedded) {
      unawaited(DiscoverPrefs.setEnumSort(DiscoverPrefs.simkl, v));
    }
  }

  /// Quick-play a random title from the filtered view — the whole list is in
  /// memory (no paging), so a plain in-list pick is uniform. Uses the list-aware
  /// handler so a random CW pick resumes.
  void _playRandom() {
    final play = _quickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground(
        'discover_random_play', {'source': 'simkl'});
    play(_visible[_random.nextInt(_visible.length)]);
  }

  // ── List selection ───────────────────────────────────────────────────────

  void _onPrimary(SimklSeeAllList list) {
    if (list == _list) return;
    setState(() {
      _autoList = false; // user chose this list — stop auto-promoting to CW
      _list = list;
      _category = 'all';
      _sort = _Sort.natural;
    });
    _fetchList(list);
  }

  /// Progress bar value (0..1) for a tile — only for Continue Watching titles
  /// (other lists show no progress). Up-next entries have no [cwProgress] entry,
  /// so they correctly render without a bar.
  double? _progressOf(StremioMeta m) =>
      _isCw ? widget.cwProgress[m.imdbId] : null;

  Future<void> _fetchList(SimklSeeAllList list) async {
    // Bump the token FIRST so any in-flight network fetch is invalidated —
    // including when switching TO Continue Watching (else its late response
    // would overwrite the CW grid).
    final token = ++_fetchToken;
    // Continue Watching is host-provided — no network fetch, just mirror it.
    if (list == SimklSeeAllList.continueWatching) {
      setState(() {
        _loading = false;
        _error = false;
        _items = widget.cwItems;
        _recompute();
      });
      if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
      _visible = const [];
    });
    final loaded = await SimklListSource.instance.loadList(list);
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
      onUp: () {
        if (!widget.embedded) _backNode.requestFocus();
      },
      onLeftEdge:
          widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final n = _visible.length;
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
              title: 'Simkl',
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

  int get _activeFilterCount {
    var n = 0;
    if (_category != 'all') n++;
    if (_effectiveSort != _Sort.natural) n++;
    return n;
  }

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
          trailing: _showRandom
              ? SeeAllRandomButton(
                  quiet: _quiet,
                  enabled: _visible.isNotEmpty,
                  focusNode: _randomNode,
                  onPressed: _playRandom,
                )
              : null,
          buildChips: () => [
            StremioDropdown<SimklSeeAllList>(
              label: 'List',
              value: _list,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _listNode,
              options: [
                for (final l in SimklSeeAllList.values)
                  StremioDropdownOption(l, l.label),
              ],
              onSelected: _onPrimary,
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
              value: _effectiveSort,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _sortNode,
              options: [
                const StremioDropdownOption(_Sort.natural, 'Default'),
                const StremioDropdownOption(_Sort.az, 'A–Z'),
                const StremioDropdownOption(_Sort.za, 'Z–A'),
                const StremioDropdownOption(
                    _Sort.imdbDesc, 'IMDb Rating · High → Low'),
                const StremioDropdownOption(
                    _Sort.imdbAsc, 'IMDb Rating · Low → High'),
                if (_showAdded) ...[
                  StremioDropdownOption(
                      _Sort.addedNewest, '$_addedLabel · Newest'),
                  StremioDropdownOption(
                      _Sort.addedOldest, '$_addedLabel · Oldest'),
                ],
              ],
              onSelected: _setSort,
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
      onOpen: _open,
      onQuickPlay: _quickPlay,
      onItemFocused: widget.onItemFocused,
      progressOf: _progressOf,
      showTypeBadge: !_quiet,
      showRatingBadge: !_quiet,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _listNode.requestFocus() : null,
      onExitLeft:
          widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }

  String _emptyMessage() {
    if (_error) return "Couldn't load ${_list.label} from Simkl";
    if (_items.isEmpty) {
      if (_isCw) return 'Nothing to continue yet';
      if (_list.isPublic) return 'No ${_list.label} titles right now';
      return 'Nothing in your ${_list.label}';
    }
    return 'Nothing matches these filters';
  }
}
