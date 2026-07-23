import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/mdblist/mdblist_service.dart';
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
/// Step 2 scope: browse the user's OWN lists. A single "List" dropdown switches
/// between them (all shown — no grouping), and each list's movies + shows are
/// merged into one grid. There is intentionally no movie/show toggle yet
/// (deferred), and no built-in/public lists (a later step).
///
/// Mirrors [TraktSeeAllScreen]'s structure but far simpler: no Continue
/// Watching, no per-item progress, no State filter.
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
  });

  @override
  State<MdblistSeeAllScreen> createState() => _MdblistSeeAllScreenState();
}

class _MdblistSeeAllScreenState extends State<MdblistSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();

  bool _connected = false;
  bool _listsLoading = true;
  List<MdblistListChoice> _lists = const [];
  MdblistListChoice? _selected;

  List<StremioMeta> _items = const [];
  List<StremioMeta> _visible = const [];

  _Sort _sort = _Sort.natural;

  bool _itemsLoading = false;
  bool _error = false;

  // Guards against a slow fetch landing after the user moved to another list.
  int _fetchToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'msa_back');
  final FocusNode _listNode = FocusNode(debugLabel: 'msa_list');
  final FocusNode _sortNode = FocusNode(debugLabel: 'msa_sort');
  final FocusNode _randomNode = FocusNode(debugLabel: 'msa_random');

  final Random _random = Random();

  /// The Random button is a Discover affordance: only the embedded host wires
  /// Quick Play (and hides it in PikPak-only mode by passing null).
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;

  bool get _quiet => widget.embedded && widget.isTelevision;

  /// Filter-bar focus order. The List/Sort/Random controls only exist once a
  /// list is selected; before that the row is just the leading Source dropdown.
  List<FocusNode> get _filterNodes => [
    if (widget.leadingNode != null) widget.leadingNode!,
    if (_selected != null) _listNode,
    if (_selected != null) _sortNode,
    if (_selected != null && _showRandom) _randomNode,
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
    final lists = await MdblistListSource.instance.loadUserLists();
    if (!mounted) return;
    if (lists.isEmpty) {
      setState(() {
        _connected = true;
        _lists = const [];
        _listsLoading = false;
      });
      return;
    }
    setState(() {
      _connected = true;
      _lists = lists;
      _selected = lists.first;
      _listsLoading = false;
    });
    _fetchItems(lists.first);
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
    _listNode.dispose();
    _sortNode.dispose();
    _randomNode.dispose();
    super.dispose();
  }

  // ── Derived list ────────────────────────────────────────────────────────────

  void _recompute() {
    final list = _items.toList();
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
                  (_selected != null ? _listNode : _backNode).requestFocus(),
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
          activeCount: _sort != _Sort.natural ? 1 : 0,
          trailing: (_showRandom && _selected != null)
              ? SeeAllRandomButton(
                  quiet: _quiet,
                  enabled: _visible.isNotEmpty,
                  focusNode: _randomNode,
                  onPressed: _playRandom,
                )
              : null,
          buildChips: () => [
            if (_selected != null) ...[
              StremioDropdown<MdblistListChoice>(
                label: 'List',
                value: _selected!,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _listNode,
                options: [
                  for (final l in _lists) StremioDropdownOption(l, l.label),
                ],
                onSelected: _selectList,
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
        ),
      ),
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
    if (_lists.isEmpty) return 'You have no MDBList lists yet';
    return '"${_selected?.label ?? ''}" is empty';
  }
}
