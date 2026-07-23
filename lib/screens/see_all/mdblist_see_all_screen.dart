import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/mdblist/mdblist_service.dart';
import '../../widgets/see_all/mdblist_like_button.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/see_all_theme.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/skeleton_poster.dart';

/// Sort orders for the grid. [natural] keeps the list's own MDBList order.
/// (No IMDb sort — MDBList list items carry no rating.)
enum _Sort { natural, az, za }

/// Full-screen / embedded "See All" for the MDBList source.
///
/// A "Category" dropdown switches between the user's OWN lists ('mine'), the
/// lists they've LIKED on MDBList ('liked'), and MDBList's top/public lists
/// ('top'); a second "List" dropdown then picks a specific list within that
/// category. Each list's movies + shows are merged into one grid. Own lists
/// load on entry; the other categories load lazily the first time the user
/// switches to them, then are cached.
///
/// There is intentionally no movie/show toggle (deferred) and no list search
/// (a later step). Mirrors [TraktSeeAllScreen]'s structure but simpler: no
/// Continue Watching, no per-item progress, no State filter.
class MdblistSeeAllScreen extends StatefulWidget {
  final void Function(StremioMeta item) onOpen;
  final void Function(StremioMeta item)? onQuickPlay;

  /// Fires when a grid tile gains focus — drives the Discover detail rail.
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;

  /// Embedded mode (inside the Discover tab): drops the Scaffold + back header
  /// so the host provides the chrome, and prepends [leading] (the Source
  /// dropdown) to the filter bar with [leadingNode] in the DPAD focus row.
  final bool embedded;
  final Widget? leading;
  final FocusNode? leadingNode;

  /// A list handed off from the Search tab's Lists search. When set, the
  /// screen opens focused on it (a "Search Result" pseudo-category) and shows
  /// the ♥ like toggle — the only path that gets the heart.
  final MdblistListChoice? initialList;

  const MdblistSeeAllScreen({
    super.key,
    required this.onOpen,
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
  State<MdblistSeeAllScreen> createState() => _MdblistSeeAllScreenState();
}

class _MdblistSeeAllScreenState extends State<MdblistSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  bool _connected = false;

  // Category: 'mine' (the user's own lists), 'liked' (lists they liked on
  // MDBList), 'top' (public/top lists), or 'found' (a single list handed off
  // from the Search tab — only present when [widget.initialList] is set).
  // Each fetched category's lists are loaded once and cached (flags below);
  // 'found' is in-memory from the start.
  String _category = 'mine';
  List<MdblistListChoice> _myLists = const [];
  bool _myLoaded = false;
  List<MdblistListChoice> _likedLists = const [];
  bool _likedLoaded = false;
  List<MdblistListChoice> _topLists = const [];
  bool _topLoaded = false;
  List<MdblistListChoice> _foundLists = const [];

  // ♥ state for the found list (the heart only shows on that path). Kept
  // as local state because MdblistListChoice is immutable.
  bool _foundLiked = false;
  bool _likeBusy = false;

  MdblistListChoice? _selected;

  List<StremioMeta> _items = const [];
  List<StremioMeta> _visible = const [];

  String _show = 'all'; // all | movie | series
  _Sort _sort = _Sort.natural;

  bool _listsLoading = true;
  bool _itemsLoading = false;
  bool _error = false;

  // Guards against a slow items fetch landing after the user moved on.
  int _fetchToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'msa_back');
  final FocusNode _categoryNode = FocusNode(debugLabel: 'msa_category');
  final FocusNode _listNode = FocusNode(debugLabel: 'msa_list');
  final FocusNode _showNode = FocusNode(debugLabel: 'msa_show');
  final FocusNode _sortNode = FocusNode(debugLabel: 'msa_sort');
  final FocusNode _likeNode = FocusNode(debugLabel: 'msa_like');
  final FocusNode _randomNode = FocusNode(debugLabel: 'msa_random');

  final Random _random = Random();

  /// The Random button is a Discover affordance: only the embedded host wires
  /// Quick Play (and hides it in PikPak-only mode by passing null).
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  bool get _quiet => widget.embedded && widget.isTelevision;

  List<MdblistListChoice> get _categoryLists => _category == 'top'
      ? _topLists
      : _category == 'liked'
      ? _likedLists
      : _category == 'found'
      ? _foundLists
      : _myLists;

  /// The ♥ toggle only exists on the search-handoff path (the found list).
  bool get _showLike => _category == 'found' && _selected != null;

  /// Filter-bar focus order. Category is present whenever connected; List/Sort/
  /// Like/Random only once a list is selected.
  List<FocusNode> get _filterNodes => [
    if (widget.leadingNode != null) widget.leadingNode!,
    if (_connected) _categoryNode,
    if (_connected && _selected != null) _listNode,
    if (_connected && _selected != null) _showNode,
    if (_connected && _selected != null) _sortNode,
    if (_showLike) _likeNode,
    if (_connected && _selected != null && _showRandom) _randomNode,
  ];

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('mdblist_see_all');
    _init();
    // Embedded (Discover): the host focuses the Source dropdown on entry, and a
    // source swap re-mounts this panel — so don't yank focus into the grid.
    if (widget.isTelevision && !widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
    }
  }

  Future<void> _init() async {
    final connected = await MdblistService.instance.isAuthenticated();
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _connected = false;
        _listsLoading = false;
      });
      return;
    }
    setState(() => _connected = true);
    // A list handed off from the Search tab: open focused on it instead of the
    // default My Lists category. It stays available in the Category dropdown
    // ("Search Result") for the rest of this screen's life.
    final found = widget.initialList;
    if (found != null) {
      setState(() {
        _foundLists = [found];
        _foundLiked = found.liked;
        _category = 'found';
        _selected = found;
        _listsLoading = false;
      });
      _fetchItems(found);
      return;
    }
    await _loadCategory('mine');
  }

  /// Load [cat]'s lists (fetching once, then cached), then select its first
  /// list and fetch its items. Safe against rapid category switches: every
  /// await re-checks that [cat] is still the active category.
  Future<void> _loadCategory(String cat) async {
    final alreadyLoaded = cat == 'top'
        ? _topLoaded
        : cat == 'liked'
        ? _likedLoaded
        : cat == 'found'
        // The found list is in-memory from the handoff — never fetched here.
        ? true
        : _myLoaded;
    setState(() {
      // Cancel any in-flight items fetch from the previous category (else its
      // result could land under the new category) and clear its loading flag —
      // otherwise switching into an empty category would strand the skeleton.
      _fetchToken++;
      _itemsLoading = false;
      _listsLoading = !alreadyLoaded;
      _selected = null;
      _items = const [];
      _visible = const [];
      _error = false;
    });

    if (!alreadyLoaded) {
      final lists = cat == 'top'
          ? await MdblistListSource.instance.loadTopLists()
          : cat == 'liked'
          ? await MdblistListSource.instance.loadLikedLists()
          : await MdblistListSource.instance.loadUserLists();
      if (!mounted || _category != cat) return;
      setState(() {
        // Cache only a non-empty result. The loaders return [] on network
        // failure too (indistinguishable from genuinely empty), so NOT caching
        // an empty result lets a transient failure retry on the next switch
        // instead of being stuck on the empty state.
        if (cat == 'top') {
          _topLists = lists;
          _topLoaded = lists.isNotEmpty;
        } else if (cat == 'liked') {
          _likedLists = lists;
          _likedLoaded = lists.isNotEmpty;
        } else {
          _myLists = lists;
          _myLoaded = lists.isNotEmpty;
        }
        _listsLoading = false;
      });
    }

    if (!mounted || _category != cat) return;
    final lists = _categoryLists;
    if (lists.isEmpty) {
      setState(() => _selected = null);
      if (widget.isTelevision) _categoryNode.requestFocus();
      return;
    }
    setState(() => _selected = lists.first);
    _fetchItems(lists.first);
  }

  void _switchCategory(String cat) {
    if (cat == _category) return;
    setState(() {
      _category = cat;
      _show = 'all';
      _sort = _Sort.natural;
    });
    _loadCategory(cat);
  }

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
    _categoryNode.dispose();
    _listNode.dispose();
    _showNode.dispose();
    _sortNode.dispose();
    _likeNode.dispose();
    _randomNode.dispose();
    super.dispose();
  }

  // ── Derived list ────────────────────────────────────────────────────────────

  void _recompute() {
    Iterable<StremioMeta> it = _items;
    if (_show == 'movie') {
      it = it.where((m) => m.type != 'series');
    } else if (_show == 'series') {
      it = it.where((m) => m.type == 'series');
    }
    final list = it.toList();
    switch (_sort) {
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
    }
    _visible = list;
  }

  void _setShow(String v) {
    setState(() {
      _show = v;
      _recompute();
    });
  }

  void _setSort(_Sort v) {
    setState(() {
      _sort = v;
      _recompute();
    });
  }

  void _selectList(MdblistListChoice choice) {
    if (choice == _selected) return;
    setState(() {
      _selected = choice;
      _show = 'all';
      _sort = _Sort.natural;
    });
    _fetchItems(choice);
  }

  Future<void> _fetchItems(MdblistListChoice choice) async {
    final token = ++_fetchToken;
    setState(() {
      _itemsLoading = true;
      _error = false;
      _items = const [];
      _visible = const [];
    });
    final loaded = await MdblistListSource.instance.loadListItems(choice);
    if (!mounted || token != _fetchToken) return;
    if (loaded.items.isEmpty && loaded.failed) {
      setState(() {
        _itemsLoading = false;
        _error = true;
      });
      if (widget.isTelevision) _listNode.requestFocus();
      return;
    }
    setState(() {
      _items = loaded.items;
      _itemsLoading = false;
      _recompute();
    });
    if (widget.isTelevision && _visible.isEmpty) _listNode.requestFocus();
  }

  /// Quick-play a random title from the current list.
  void _playRandom() {
    final play = widget.onQuickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground('discover_random_play', {
      'source': 'mdblist',
    });
    play(_visible[_random.nextInt(_visible.length)]);
  }

  /// Toggle ♥ on the found list (the search-handoff path). The heart reflects
  /// the list's per-user `liked` flag, which the API flips immediately; the
  /// "Liked Lists" category may lag a little behind (server-side index).
  Future<void> _toggleLike() async {
    final list = _foundLists.isNotEmpty ? _foundLists.first : null;
    if (list == null || _likeBusy) return;
    final want = !_foundLiked;
    setState(() => _likeBusy = true);
    final ok = await MdblistService.instance.setListLiked(list.id, like: want);
    if (!mounted) return;
    setState(() {
      _likeBusy = false;
      if (ok) _foundLiked = want;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            want ? "Couldn't like the list" : "Couldn't unlike the list",
          ),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    AnalyticsService.trackInBackground('mdblist_list_like', {'liked': want});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          want ? 'Liked "${list.name}" on MDBList' : 'Unliked "${list.name}"',
        ),
      ),
    );
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
      onLeftEdge: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildFilterBar(), Expanded(child: _buildBody())],
      );
    }
    final n = _visible.length;
    return Scaffold(
      backgroundColor: kSeeAllBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: 'MDBList',
              subtitle: _itemsLoading
                  ? '${_selected?.label ?? ''} · Loading…'
                  : '${_selected?.label ?? ''} · $n ${n == 1 ? 'title' : 'titles'}',
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              onFilterDown: () =>
                  (_connected ? _categoryNode : _backNode).requestFocus(),
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
        padding: _quiet
            ? const EdgeInsets.fromLTRB(24, 16, 24, 10)
            : const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          leading: widget.leading,
          quiet: _quiet,
          activeCount:
              (_sort != _Sort.natural ? 1 : 0) + (_show != 'all' ? 1 : 0),
          trailing: _buildTrailing(),
          buildChips: () => [
            if (_connected) ...[
              StremioDropdown<String>(
                label: 'Category',
                value: _category,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _categoryNode,
                options: [
                  const StremioDropdownOption('mine', 'My Lists'),
                  const StremioDropdownOption('liked', 'Liked Lists'),
                  const StremioDropdownOption('top', 'Top Lists'),
                  // Only exists while a search-handoff list is held.
                  if (_foundLists.isNotEmpty)
                    const StremioDropdownOption('found', 'Search Result'),
                ],
                onSelected: _switchCategory,
              ),
              if (_selected != null) ...[
                StremioDropdown<MdblistListChoice>(
                  label: 'List',
                  value: _selected!,
                  isTelevision: widget.isTelevision,
                  quiet: _quiet,
                  focusNode: _listNode,
                  options: [
                    for (final l in _categoryLists)
                      StremioDropdownOption(
                        l,
                        // Liked/top lists belong to other users — show the owner.
                        (_category != 'mine' && l.ownerName != null)
                            ? '${l.name} · ${l.ownerName}'
                            : l.label,
                      ),
                  ],
                  onSelected: _selectList,
                ),
                StremioDropdown<String>(
                  label: 'Show',
                  value: _show,
                  isTelevision: widget.isTelevision,
                  quiet: _quiet,
                  focusNode: _showNode,
                  options: const [
                    StremioDropdownOption('all', 'All'),
                    StremioDropdownOption('movie', 'Movies'),
                    StremioDropdownOption('series', 'Series'),
                  ],
                  onSelected: _setShow,
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
                  ],
                  onSelected: _setSort,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Trailing filter-bar actions: the ♥ toggle (search-handoff path only) and
  /// the Random button. Order matches [_filterNodes] so DPAD left/right walks
  /// them in visual order.
  Widget? _buildTrailing() {
    final like = _showLike
        ? MdblistLikeButton(
            quiet: _quiet,
            liked: _foundLiked,
            busy: _likeBusy,
            focusNode: _likeNode,
            onPressed: _toggleLike,
          )
        : null;
    final random = (_showRandom && _selected != null)
        ? SeeAllRandomButton(
            quiet: _quiet,
            enabled: _visible.isNotEmpty,
            focusNode: _randomNode,
            onPressed: _playRandom,
          )
        : null;
    if (like == null && random == null) return null;
    if (like == null) return random;
    if (random == null) return like;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [like, SizedBox(width: _quiet ? 6 : 8), random],
    );
  }

  Widget _buildBody() {
    if (_listsLoading || _itemsLoading) {
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
                _error
                    ? Icons.cloud_off_rounded
                    : (!_connected
                          ? Icons.link_off_rounded
                          : Icons.inbox_rounded),
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
      // Discover on TV has the detail rail naming the type — drop the badges there.
      showTypeBadge: !_quiet,
      showRatingBadge: !_quiet,
      isBound: widget.isBound,
      onLoadMore: () {},
      onExitTop: widget.isTelevision ? () => _listNode.requestFocus() : null,
      onExitLeft: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
  }

  String _emptyMessage() {
    if (!_connected) return 'Connect MDBList in Settings to browse your lists';
    if (_error) return "Couldn't load \"${_selected?.label ?? ''}\" from MDBList";
    if (_selected == null) {
      if (_category == 'top') return 'No top lists available right now';
      if (_category == 'liked') return "You haven't liked any lists yet";
      return 'You have no MDBList lists yet';
    }
    // The list has items but the Show filter hid them all.
    if (_items.isNotEmpty) return 'Nothing matches these filters';
    return '"${_selected?.label ?? ''}" is empty';
  }
}
