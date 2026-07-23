import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/simkl/simkl_list_source.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Sort orders for the grid. [natural] keeps the API's own rank/interleave
/// order.
enum _Sort { natural, az, za, imdbDesc, imdbAsc }

/// Full-screen "See All" for the Simkl source. Opens on Trending (public, no
/// auth wall, always populated) and lets the user switch — via the "List"
/// dropdown — to any of the five watchlist states (Plan to Watch / Watching /
/// On Hold / Completed / Dropped), Ratings, or the other two discovery lists
/// (Top Rated, New & Upcoming).
///
/// Deliberately simpler than [TraktSeeAllScreen]: no Continue Watching (Simkl
/// has no playback data yet — that's the scrobble step, not this one) and no
/// custom/liked-list group dropdown (Simkl's Custom Lists aren't exposed via
/// API yet). Every list is fetched via [SimklListSource], then filtered by
/// category/sort in memory — same shape as Trakt's screen otherwise, so it
/// slots into the Discover tab's dispatch the same way.
class SimklSeeAllScreen extends StatefulWidget {
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

  const SimklSeeAllScreen({
    super.key,
    required this.onOpen,
    this.onQuickPlay,
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

  SimklSeeAllList _list = SimklSeeAllList.trending;

  List<StremioMeta> _items = const [];
  List<StremioMeta> _visible = const [];

  String _category = 'all'; // all | movie | series
  _Sort _sort = _Sort.natural;

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
    _fetchList(_list);
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
    Iterable<StremioMeta> it = _items;
    if (_category == 'movie') {
      it = it.where((m) => m.type != 'series');
    } else if (_category == 'series') {
      it = it.where((m) => m.type == 'series');
    }
    final list = it.toList();
    switch (_sort) {
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
    }
    _visible = list;
  }

  void _setFilter(VoidCallback change) {
    setState(() {
      change();
      _recompute();
    });
  }

  /// Quick-play a random title from the filtered view — the whole list is in
  /// memory (no paging), so a plain in-list pick is uniform.
  void _playRandom() {
    final play = widget.onQuickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground(
        'discover_random_play', {'source': 'simkl'});
    play(_visible[_random.nextInt(_visible.length)]);
  }

  // ── List selection ───────────────────────────────────────────────────────

  void _onPrimary(SimklSeeAllList list) {
    if (list == _list) return;
    setState(() {
      _list = list;
      _category = 'all';
      _sort = _Sort.natural;
    });
    _fetchList(list);
  }

  Future<void> _fetchList(SimklSeeAllList list) async {
    final token = ++_fetchToken;
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
    if (_sort != _Sort.natural) n++;
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
              value: _sort,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _sortNode,
              options: const [
                StremioDropdownOption(_Sort.natural, 'Default'),
                StremioDropdownOption(_Sort.az, 'A–Z'),
                StremioDropdownOption(_Sort.za, 'Z–A'),
                StremioDropdownOption(
                    _Sort.imdbDesc, 'IMDb Rating · High → Low'),
                StremioDropdownOption(
                    _Sort.imdbAsc, 'IMDb Rating · Low → High'),
              ],
              onSelected: (v) => _setFilter(() => _sort = v),
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
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
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
      if (_list.isPublic) return 'No ${_list.label} titles right now';
      return 'Nothing in your ${_list.label}';
    }
    return 'Nothing matches these filters';
  }
}
