import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/skeleton_poster.dart';
import '../../services/trakt/trakt_list_source.dart';
import '../../services/watched_filter.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/see_all/see_all_sort.dart';
import '../../widgets/see_all/stremio_dropdown.dart';

/// Sort orders for the grid. [natural] keeps the list's incoming order —
/// last-watched for Continue Watching, the API's own rank for fetched lists.
enum _Sort { natural, az, za, imdbDesc, imdbAsc, addedNewest, addedOldest }

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

  /// Open directly on this list instead of Continue Watching (a Home list
  /// row's See-All). A custom/liked choice must carry its full account
  /// payload (ids + owner) — the screen seeds its group dropdown from it so
  /// the selection is representable before (or without) the async user-lists
  /// refresh. Null keeps today's behavior exactly.
  final TraktListChoice? initialList;

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
    this.initialList,
  });

  @override
  State<TraktSeeAllScreen> createState() => _TraktSeeAllScreenState();
}

class _TraktSeeAllScreenState extends State<TraktSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  TraktListChoice _list = const TraktListChoice.builtin(
    TraktSeeAllList.continueWatching,
  );

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

  /// A remembered date sort waiting for a list that can honour it. Resolved by
  /// [_recompute] the first time dated rows load, and dropped the moment the
  /// user picks any sort themselves — a stored preference should re-apply once,
  /// not keep overriding the choice they just made.
  _Sort? _deferredSort;

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
  final FocusNode _randomNode = FocusNode(debugLabel: 'tsa_random');

  final Random _random = Random();

  bool get _isCw => _list.isContinueWatching;

  /// The Random button is a Discover affordance: only the embedded host wires
  /// Quick Play (and hides it in PikPak-only mode by passing null). Works on
  /// every list — the host resolves CW items to their resume point and plays
  /// fetched-list items like catalog titles.
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  /// The State (Watched/Unwatched) filter only makes sense where we have
  /// per-item progress — i.e. Continue Watching.
  bool get _showState => _isCw;

  /// "Date Added" is offered only where the rows actually carry a date —
  /// Watchlist, Collection, Ratings, History and user lists do; Trending,
  /// Popular and Anticipated are public rows with no per-user date. Asked of
  /// the LOADED items rather than the list identity, so custom and liked lists
  /// are covered without enumerating them, and a Trakt response that stops
  /// sending dates hides the option instead of offering a no-op that silently
  /// degrades to A–Z.
  bool get _showAdded => hasAddedDates(_items);

  /// What the date on THIS list's rows actually means. Trakt names the field
  /// after the list, so one label would be a lie on two of them: History sorts
  /// by `watched_at` and Ratings by `rated_at`. Watchlist, Collection and user
  /// lists all genuinely mean "added".
  String get _addedLabel {
    switch (_list.builtin) {
      case TraktSeeAllList.history:
        return 'Date Watched';
      case TraktSeeAllList.ratings:
        return 'Date Rated';
      default:
        return 'Date Added';
    }
  }

  /// The sort actually applied. A remembered — or carried-over — "Date Added"
  /// pick can outlive the list it was made on (swap Watchlist → Trending, or
  /// relaunch), and both the dropdown and the sort must agree about that:
  /// leaving `_sort` set would hand StremioDropdown a value absent from its
  /// options and silently sort by name instead. The stored pick is left
  /// untouched so it comes back when the user returns to a dated list.
  _Sort get _effectiveSort =>
      (!_showAdded &&
          (_sort == _Sort.addedNewest || _sort == _Sort.addedOldest))
      ? _Sort.natural
      : _sort;

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
    if (_showRandom) _randomNode,
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('trakt_see_all');
    _items = widget.cwItems;
    _category = widget.initialCategory;
    // Discover only: reopen on the order the user last picked for this source.
    // Read before the first _recompute so the grid paints already sorted.
    if (widget.embedded) {
      final saved = DiscoverPrefs.enumSortFor(
        DiscoverPrefs.trakt,
        _Sort.values,
      );
      if (saved != null) {
        _sort = saved;
        // A remembered DATE sort can't take effect here: Discover always opens
        // Trakt on Continue Watching, whose rows carry no dates, and the list
        // switch that finally reaches a dated list resets _sort. Held aside so
        // it can be claimed when dated rows actually arrive — otherwise the
        // preference would be stored and never once applied.
        if (saved == _Sort.addedNewest || saved == _Sort.addedOldest) {
          _deferredSort = saved;
        }
      }
    }
    // A Home list row's See-All: open on that list, not Continue Watching.
    // Custom/liked choices SEED their group array so both dropdowns can
    // represent the selection immediately — _loadUserLists() fills the rest
    // async and must not be a prerequisite (or a Trakt hiccup would render a
    // blank dropdown over a grid that fetched fine).
    final initial = widget.initialList;
    if (initial != null && !initial.isContinueWatching) {
      _list = initial;
      if (!initial.isBuiltin) {
        if (initial.liked) {
          _group = 'liked';
          _likedLists = [initial];
        } else {
          _group = 'custom';
          _customLists = [initial];
        }
      }
    }
    _recompute();
    // Embedded (Discover): the host focuses the Source dropdown on entry, and a
    // source swap re-mounts this panel — so don't yank focus into the grid here,
    // it would steal the DPAD ring off the Source dropdown on every swap.
    //
    // Opening on a fetched list: the grid is empty until the fetch lands, so
    // an immediate _focusEntry would park focus on the back button for the
    // whole visit. Defer it to the fetch's completion instead (and only if
    // nothing real took focus meanwhile).
    if (initial != null && !initial.isContinueWatching) {
      unawaited(
        _fetchList(_list).then((_) {
          if (!mounted || !widget.isTelevision || widget.embedded) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final primary = FocusManager.instance.primaryFocus;
            if (primary != null && primary is! FocusScopeNode) return;
            _focusEntry();
          });
        }),
      );
    } else if (widget.isTelevision && !widget.embedded) {
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
  /// dropdown simply keeps only the built-in entries — and, when the screen was
  /// opened on a seeded [TraktSeeAllScreen.initialList], that seed (the early
  /// return keeps the seeded single-entry arrays intact).
  Future<void> _loadUserLists() async {
    final lists = await TraktListSource.instance.loadUserLists();
    if (!mounted || lists.isEmpty) return;
    setState(() {
      _customLists = [
        for (final c in lists)
          if (!c.liked) c,
      ];
      _likedLists = [
        for (final c in lists)
          if (c.liked) c,
      ];
      // The active selection must stay representable: if the refresh no
      // longer contains the seeded initial list (deleted/unliked upstream,
      // or a partial response), keep it as a leading entry rather than
      // handing the group dropdown a value absent from its options.
      if (_group == 'custom' &&
          !_list.isBuiltin &&
          !_customLists.contains(_list)) {
        _customLists = [_list, ..._customLists];
      } else if (_group == 'liked' &&
          !_list.isBuiltin &&
          !_likedLists.contains(_list)) {
        _likedLists = [_list, ..._likedLists];
      }
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
    _randomNode.dispose();
    super.dispose();
  }

  // ── Derived list (memoized; recomputed only on data/filter change) ──────────

  double? _progressOf(StremioMeta m) =>
      _isCw ? widget.cwProgress[m.imdbId] : null;

  bool _isWatched(StremioMeta m) => (_progressOf(m) ?? 0) >= _watchedAt;

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
    if (_showState && _watch == 'watched') {
      it = it.where(_isWatched);
    } else if (_showState && _watch == 'unwatched') {
      it = it.where((m) => !_isWatched(m));
    }
    // Discovery lists only; the account's own lists stay complete.
    if (_list.builtin?.hidesWatched ?? false) {
      it = it.where((m) => !WatchedFilter.hides(m));
    }
    final list = it.toList();
    switch (_effectiveSort) {
      case _Sort.natural:
        break; // items already arrive in the list's natural order
      case _Sort.az:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case _Sort.za:
        list.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
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
  /// is stored: switching lists resets the sort in-session (it's progress-
  /// specific to CW) and that reset must not erase the user's standing choice.
  void _setSort(_Sort v) {
    // An explicit pick supersedes anything still waiting to be restored.
    _deferredSort = null;
    _setFilter(() => _sort = v);
    if (widget.embedded) {
      unawaited(DiscoverPrefs.setEnumSort(DiscoverPrefs.trakt, v));
    }
  }

  /// Quick-play a random title from the filtered view. [_visible] already has
  /// the Show/State dropdowns applied, and the whole list is in memory — no
  /// paging — so a plain in-list pick is uniform.
  void _playRandom() {
    final play = widget.onQuickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground('discover_random_play', {
      'source': 'trakt_cw',
    });
    play(_visible[_random.nextInt(_visible.length)]);
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
      onLeftEdge: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
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
      backgroundColor: AppThemeScope.of(context).seeAll.bg,
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
    if (_effectiveSort != _Sort.natural) n++;
    if (_showState && _watch != 'all') n++;
    return n;
  }

  /// Discover TV styling: quiet text-segment filters on the glass stage.
  /// Poster details are governed independently by the Discover card scope.
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
                  for (final c in _groupLists)
                    StremioDropdownOption(c, c.label),
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
              value: _effectiveSort,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _sortNode,
              options: [
                StremioDropdownOption(
                  _Sort.natural,
                  _isCw ? 'Last Watched' : 'Default',
                ),
                const StremioDropdownOption(_Sort.az, 'A–Z'),
                const StremioDropdownOption(_Sort.za, 'Z–A'),
                const StremioDropdownOption(
                  _Sort.imdbDesc,
                  'IMDb Rating · High → Low',
                ),
                const StremioDropdownOption(
                  _Sort.imdbAsc,
                  'IMDb Rating · Low → High',
                ),
                if (_showAdded) ...[
                  StremioDropdownOption(
                    _Sort.addedNewest,
                    '$_addedLabel · Newest',
                  ),
                  StremioDropdownOption(
                    _Sort.addedOldest,
                    '$_addedLabel · Oldest',
                  ),
                ],
              ],
              onSelected: _setSort,
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
      final app = AppThemeScope.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _error ? Icons.cloud_off_rounded : Icons.inbox_rounded,
                size: 44,
                color: app.fade(app.core.tx, 0.25),
              ),
              const SizedBox(height: 14),
              Text(
                _emptyMessage(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.7),
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
      // Quick-play works on every list: the host resolves CW items to their
      // resume point and plays fetched-list items like catalog titles.
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      progressOf: _progressOf,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _listNode.requestFocus() : null,
      // Embedded: Left at grid column 0 escapes to the TV sidebar.
      onExitLeft: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
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
