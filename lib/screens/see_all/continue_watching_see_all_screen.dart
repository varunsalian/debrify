import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/app_route_observer.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Sort orders for the Continue Watching grid.
enum _CwSort { lastWatched, az, za }

/// Full-screen "See All" grid for Continue Watching — both the local and the
/// Trakt sources use this same screen (they differ only in the [items] +
/// [progressOf] the host passes in). It's a client-side view over an already-
/// loaded list: category (All / Movies / Series), sort (Last Watched / A–Z /
/// Z–A) and watched-state (All / Watched / Unwatched) all filter/sort in memory,
/// so there's no paging.
///
/// [items] must arrive in last-watched order (newest first) — that's the
/// "Last Watched" sort, restored by leaving the order untouched.
///
/// Opening an item (detail or quick-play) can change the underlying data
/// (progress advances, a finished title drops out), so the screen re-fetches via
/// [onReload] whenever a route pushed on top of it pops back (tracked with
/// [RouteAware]) — otherwise the grid would show a stale snapshot.
class ContinueWatchingSeeAllScreen extends StatefulWidget {
  final String title;
  final List<StremioMeta> items;
  final double? Function(StremioMeta item) progressOf;

  /// Pre-selected category ('all' / 'movie' / 'series') — usually the type of
  /// the row the user opened See-All from.
  final String initialCategory;

  /// Opens the detail/playback for an item.
  final void Function(StremioMeta item) onOpen;

  /// Re-fetches the freshly-reloaded list; called after a pushed route pops
  /// back. Null keeps the initial snapshot.
  final Future<List<StremioMeta>> Function()? onReload;

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

  const ContinueWatchingSeeAllScreen({
    super.key,
    required this.title,
    required this.items,
    required this.progressOf,
    required this.onOpen,
    this.initialCategory = 'all',
    this.onReload,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
    this.embedded = false,
    this.leading,
    this.leadingNode,
  });

  @override
  State<ContinueWatchingSeeAllScreen> createState() =>
      _ContinueWatchingSeeAllScreenState();
}

class _ContinueWatchingSeeAllScreenState
    extends State<ContinueWatchingSeeAllScreen> with RouteAware {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  // Live source list (refreshed after each open) + the derived, cached view.
  late List<StremioMeta> _items;
  List<StremioMeta> _visible = const [];

  late String _category; // all | movie | series
  _CwSort _sort = _CwSort.lastWatched;
  String _watch = 'all'; // all | watched | unwatched

  // A title is "watched" once past this fraction, matching the app's
  // quick-play/continue-watching threshold.
  static const double _watchedAt = 0.9;

  final FocusNode _backNode = FocusNode(debugLabel: 'cwsa_back');
  final FocusNode _catNode = FocusNode(debugLabel: 'cwsa_category');
  final FocusNode _sortNode = FocusNode(debugLabel: 'cwsa_sort');
  final FocusNode _watchNode = FocusNode(debugLabel: 'cwsa_watch');
  final FocusNode _randomNode = FocusNode(debugLabel: 'cwsa_random');

  final Random _random = Random();

  /// The Random button is a Discover affordance: only the embedded host wires
  /// Quick Play (and hides it in PikPak-only mode by passing null).
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('continue_watching_see_all');
    MainPageBridge.addPlaybackReturnListener(_onPlaybackReturned);
    _items = widget.items;
    _category = widget.initialCategory;
    // Discover only: reopen on the order the user last picked for this source.
    // Read before the first _recompute so the grid paints already sorted.
    if (widget.embedded) {
      final saved = DiscoverPrefs.enumSortFor(DiscoverPrefs.cw, _CwSort.values);
      if (saved != null) _sort = saved;
    }
    _recompute();
    // Embedded (Discover): the host focuses the Source dropdown on entry, and a
    // source swap re-mounts this panel — so don't yank focus into the grid here,
    // it would steal the DPAD ring off the Source dropdown on every swap.
    if (widget.isTelevision && !widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
    }
  }

  /// Land DPAD focus somewhere usable: the first grid tile, or — when the grid
  /// is empty (its non-focusable empty-state is shown) — the back button, so the
  /// remote is never stranded.
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void didUpdateWidget(covariant ContinueWatchingSeeAllScreen old) {
    super.didUpdateWidget(old);
    // Embedded in Discover, the rows load async after mount, so re-sync when the
    // host hands us a fresh list (identity change) rather than staying on the
    // initial empty snapshot.
    if (!identical(widget.items, old.items)) {
      _items = widget.items;
      _recompute();
      // If the reload drained the grid to empty on TV, its tiles' focus nodes are
      // gone — move focus to the leading Source dropdown so the remote isn't
      // stranded on the non-focusable empty state. But only when focus was on the
      // grid: a background reload shouldn't yank the user off a filter dropdown.
      if (widget.embedded && widget.isTelevision && _visible.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _visible.isNotEmpty) return;
          if ((widget.leadingNode?.hasFocus ?? false) ||
              _catNode.hasFocus ||
              _sortNode.hasFocus ||
              _watchNode.hasFocus ||
              _randomNode.hasFocus) {
            return;
          }
          (widget.leadingNode ?? _catNode).requestFocus();
        });
      }
    }
  }

  // A detail or in-app player route pushed from a grid tile just popped back
  // onto us — re-fetch so finished titles drop out and progress/order stay
  // fresh.
  @override
  void didPopNext() => _refresh();

  // Native-TV / DeoVR / external playback pushes no Flutter route, so
  // [didPopNext] can't fire for it — a title watched to the end would stay in
  // the grid at its old progress. See [MainPageBridge.notifyPlaybackReturned].
  // Gated on being current so a grid buried under a detail route leaves the
  // refresh to that route (this one re-reads via didPopNext when it pops).
  void _onPlaybackReturned() {
    if (!mounted) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _refresh();
  }

  Future<void> _refresh() async {
    final reload = widget.onReload;
    if (reload == null) return;
    final fresh = await reload();
    if (!mounted) return;
    setState(() {
      _items = fresh;
      _recompute();
    });
    // The reload may have emptied the grid (last title finished) — its focus
    // nodes are gone, so move focus to the back button on TV.
    if (widget.isTelevision && _visible.isEmpty) _backNode.requestFocus();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    MainPageBridge.removePlaybackReturnListener(_onPlaybackReturned);
    _backNode.dispose();
    _catNode.dispose();
    _sortNode.dispose();
    _watchNode.dispose();
    _randomNode.dispose();
    super.dispose();
  }

  // ── Derived list (memoized; recomputed only on data/filter change) ──────────

  bool _isWatched(StremioMeta m) => (widget.progressOf(m) ?? 0) >= _watchedAt;

  void _recompute() {
    Iterable<StremioMeta> it = _items;
    if (_category == 'movie') {
      it = it.where((m) => m.type != 'series');
    } else if (_category == 'series') {
      it = it.where((m) => m.type == 'series');
    }
    if (_watch == 'watched') {
      it = it.where(_isWatched);
    } else if (_watch == 'unwatched') {
      it = it.where((m) => !_isWatched(m));
    }
    final list = it.toList();
    switch (_sort) {
      case _CwSort.lastWatched:
        break; // items already arrive newest-first
      case _CwSort.az:
        list.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _CwSort.za:
        list.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
    }
    _visible = list;
  }

  /// Sort picks are remembered (Discover only) so the next launch — and the next
  /// swap back to this source — opens on the same order. Only an explicit pick
  /// is stored; nothing else in this screen resets the sort.
  void _setSort(_CwSort v) {
    _setFilter(() => _sort = v);
    if (widget.embedded) {
      unawaited(DiscoverPrefs.setEnumSort(DiscoverPrefs.cw, v));
    }
  }

  void _setFilter(VoidCallback change) {
    setState(() {
      change();
      _recompute();
    });
  }

  /// Quick-play a random title from the filtered view. [_visible] already has
  /// the Show/State dropdowns applied, and the whole list is in memory — no
  /// paging — so a plain in-list pick is uniform.
  void _playRandom() {
    final play = widget.onQuickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground(
        'discover_random_play', {'source': 'continue_watching'});
    play(_visible[_random.nextInt(_visible.length)]);
  }

  // ── TV filter-bar focus wiring ──────────────────────────────────────────────

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      [
        if (widget.leadingNode != null) widget.leadingNode!,
        _catNode,
        _sortNode,
        _watchNode,
        if (_showRandom) _randomNode,
      ],
      onDown: () => _gridKey.currentState?.focusFirst(),
      // Embedded (Discover tab) has no back button above the bar, so
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
              title: widget.title,
              // Reflect what the grid actually shows, so a filter doesn't leave
              // the header disagreeing with the body.
              subtitle: '${_visible.length}'
                  ' ${_visible.length == 1 ? 'title' : 'titles'}',
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              onFilterDown: () => _catNode.requestFocus(),
            ),
            _buildFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  /// Non-default filters, for the collapsed Filters button badge.
  int get _activeFilterCount {
    var n = 0;
    // Compare against how the screen opened, not a hardcoded 'all': a seeded
    // rail can start _category on 'movie'/'series', which isn't a user filter.
    if (_category != widget.initialCategory) n++;
    if (_sort != _CwSort.lastWatched) n++;
    if (_watch != 'all') n++;
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
          trailing: _showRandom
              ? SeeAllRandomButton(
                  quiet: _quiet,
                  enabled: _visible.isNotEmpty,
                  focusNode: _randomNode,
                  onPressed: _playRandom,
                )
              : null,
          buildChips: () => [
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
            StremioDropdown<_CwSort>(
              label: 'Sort',
              value: _sort,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _sortNode,
              options: const [
                StremioDropdownOption(_CwSort.lastWatched, 'Last Watched'),
                StremioDropdownOption(_CwSort.az, 'A–Z'),
                StremioDropdownOption(_CwSort.za, 'Z–A'),
              ],
              onSelected: _setSort,
            ),
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
    if (_visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history_rounded,
                  size: 44, color: Colors.white.withValues(alpha: 0.25)),
              const SizedBox(height: 14),
              Text(
                _items.isEmpty
                    ? 'Nothing to continue yet'
                    : 'Nothing matches these filters',
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
      // Discover on TV has the detail rail naming the type and carrying the
      // rating — drop both badges there.
      showTypeBadge: !_quiet,
      showRatingBadge: !_quiet,
      progressOf: widget.progressOf,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _catNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded ? () => MainPageBridge.focusTvSidebar?.call() : null,
    );
  }
}
