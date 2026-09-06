import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/collection_folder_loader.dart';
import '../../services/collection_catalog_pager.dart';
import '../../services/watched_filter.dart';
import '../../services/main_page_bridge.dart';
import '../../services/home_collections_store.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/home_rail_metrics.dart';
import '../../widgets/collections/folder_hero_band.dart';
import '../../widgets/collections/rail_see_all_pill.dart';
import '../../widgets/home/row_tag_pill.dart';
import '../../widgets/see_all/discover_shelf_scope.dart';
import '../../widgets/see_all/discover_card_settings_scope.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/skeleton_poster.dart';
import '../see_all/catalog_see_all_screen.dart';

/// Full-screen browser for one folder of an imported collection — where a
/// folder tile on the Home board and the collection row's "See All" land.
///
/// Each catalog in a folder is its own list. Two layouts, chosen in
/// Settings › Home Screen › Collections:
///
///  * **Rows** — one horizontal rail per list, each with its own See All
///    into the regular catalog browser; a collection with `showAllTab` also
///    offers an "All" view that pages every list into one merged grid.
///  * **Tabs** — one list at a time as a full poster grid, picked from a
///    List chip (plus "All" when the collection enables it).
///
/// Lists switched off in the Home Rows manager (`collectionlist:` ids in the
/// disabled set) are left out of every view.
///
/// Rails reuse [SeeAllPosterGrid] in shelf mode (under a
/// [DiscoverShelfScope]), so focus walking, paging and card chrome are the
/// Discover stage's own; this screen only adds the vertical DPAD ladder
/// between rails (See-All pill → cards → next rail's pill).
class CollectionFolderScreen extends StatefulWidget {
  final HomeCollection collection;
  final int initialFolderIndex;
  final void Function(StremioMeta item) onOpenItem;
  final void Function(StremioMeta item)? onQuickPlay;
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;

  const CollectionFolderScreen({
    super.key,
    required this.collection,
    required this.onOpenItem,
    this.initialFolderIndex = 0,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
  });

  @override
  State<CollectionFolderScreen> createState() => _CollectionFolderScreenState();
}

/// Rows layout: stacked rails, or the merged grid.
enum _View { lists, all }

/// Tabs layout: the merged grid's value in the List chip.
const int _kAllTab = -1;

/// One catalog list inside the folder: its resolved addon/catalog, the pages
/// loaded so far, and the focus plumbing for its rail.
class _Rail {
  _Rail({
    required this.source,
    required this.addon,
    required this.catalog,
    required StremioService stremio,
  }) {
    pager = CollectionCatalogPager(
      addon: addon,
      catalog: catalog,
      genre: source.genre,
      hides: WatchedFilter.predicate,
      fetch: (a, c, {skip = 0, genre, onRawCount}) {
        final refresh = forceRefresh;
        forceRefresh = false;
        return stremio.fetchCatalog(
          a,
          c,
          skip: skip,
          genre: genre,
          onRawCount: onRawCount,
          forceRefresh: refresh,
        );
      },
    );
  }
  late final CollectionCatalogPager pager;
  bool forceRefresh = false;

  final CollectionCatalogSource source;
  final StremioAddon addon;
  final StremioAddonCatalog catalog;
  final GlobalKey<SeeAllPosterGridState> gridKey = GlobalKey();
  final GlobalKey containerKey = GlobalKey();
  final FocusNode seeAllNode = FocusNode(debugLabel: 'collection_rail_seeall');
  final List<StremioMeta> items = [];
  int get nextSkip => pager.skip;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool get exhausted => pager.exhausted;
  String? get error => pager.error;

  /// "Popular Movies · Action" — the Home row title plus the source's genre.
  String get title {
    final base = CatalogSection.rowTitle(catalog);
    final genre = source.genre;
    return genre == null ? base : '$base · $genre';
  }

  /// Hidden once loaded empty — an empty rail is noise, like on Home.
  bool get visible => loadingInitial || items.isNotEmpty;

  void dispose() => seeAllNode.dispose();
}

class _CollectionFolderScreenState extends State<CollectionFolderScreen> {
  final StremioService _stremio = StremioService.instance;

  static const String _sortDefault = 'default';
  static const String _sortImdbDesc = 'imdbDesc';
  static const String _sortImdbAsc = 'imdbAsc';
  static const String _sortTitle = 'title';
  String _sort = _sortDefault;

  late int _folderIndex;
  CollectionFolderLayout _layout = CollectionFolderLayout.rows;
  _View _view = _View.lists;
  int _tab = 0;
  List<StremioAddon> _addons = const [];
  Set<String> _disabled = const {};
  bool _booted = false;

  List<_Rail> _rails = const [];
  List<String> _unresolved = const [];
  final ScrollController _railsScroll = ScrollController();
  GlobalKey<SeeAllPosterGridState> _tabGridKey = GlobalKey();

  // The All (merged grid) view, shared by both layouts.
  GlobalKey<SeeAllPosterGridState> _allGridKey = GlobalKey();
  CollectionFolderLoader? _loader;
  final List<StremioMeta> _allItems = [];
  bool _allStarted = false;
  bool _allLoadingInitial = false;
  bool _allLoadingMore = false;
  bool _allExhausted = false;

  // Bumped on every folder change so in-flight pages from the previous
  // folder are discarded when they land.
  int _reqToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'collection_back');
  final FocusNode _folderNode = FocusNode(debugLabel: 'collection_folder');
  final FocusNode _viewNode = FocusNode(debugLabel: 'collection_view');
  final FocusNode _listNode = FocusNode(debugLabel: 'collection_list');
  final FocusNode _sortNode = FocusNode(debugLabel: 'collection_sort');
  final FocusNode _retryNode = FocusNode(debugLabel: 'collection_retry');

  late HomeCollection _collection;
  int _configurationToken = 0;
  String? _configurationError;
  String? _configurationSignature;
  bool get _hasFolders => _collection.folders.isNotEmpty;
  HomeCollectionFolder get _folder => _collection.folders[_folderIndex];
  bool get _tabs => _layout == CollectionFolderLayout.tabs;

  /// The folder's lists minus the ones switched off in Home Rows.
  List<CollectionCatalogSource> get _enabledSources => [
    for (final s in _folder.sources)
      if (!_disabled.contains(
        HomeCollectionRowIds.folderList(_collection.id, _folder.id, s),
      ))
        s,
  ];

  bool get _offersAll => _collection.showAllTab && _rails.length > 1;

  /// Whether the merged grid is what's on screen.
  bool get _showingAll => _tabs ? _tab == _kAllTab : _view == _View.all;

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('collection_folder');
    _collection = widget.collection;
    MainPageBridge.addHomeSettingsListener(_onConfigurationChanged);
    _stremio.addAddonsChangedListener(_onConfigurationChanged);
    final count = _collection.folders.length;
    _folderIndex = count == 0
        ? 0
        : widget.initialFolderIndex.clamp(0, count - 1);
    unawaited(_boot());
  }

  void _onConfigurationChanged() => unawaited(_boot(refreshCollection: true));

  Future<void> _boot({bool refreshCollection = false}) async {
    final generation = ++_configurationToken;
    final session = HomeCollectionsStore.captureSession();
    try {
      final addons = await _stremio.getCatalogAddons();
      final disabled = await StorageService.getHomeDisabledSections();
      final layout = await HomeCollectionsStore.instance.getFolderLayout();
      HomeCollection? updated;
      if (refreshCollection) {
        final collections = await HomeCollectionsStore.instance
            .getCollections();
        for (final c in collections) {
          if (c.id == _collection.id && c.enabled) updated = c;
        }
      }
      if (!mounted || generation != _configurationToken) return;
      HomeCollectionsStore.checkSession(session);
      final candidate = refreshCollection
          ? updated ??
                HomeCollection(id: _collection.id, title: _collection.title)
          : _collection;
      final relevantDisabled =
          disabled
              .where(
                (id) => id.startsWith(
                  '${HomeCollectionRowIds.folderListPrefix}${candidate.id}:',
                ),
              )
              .toList()
            ..sort();
      final signature = jsonEncode({
        'collection': candidate.toJson()..remove('importedAt'),
        'addons': [for (final addon in addons) addon.toJson()],
        'disabled': relevantDisabled,
        'layout': layout.name,
      });
      if (_configurationError == null && signature == _configurationSignature) {
        return;
      }
      _configurationSignature = signature;
      final restoreFocus =
          refreshCollection &&
          widget.isTelevision &&
          ModalRoute.of(context)?.isCurrent == true &&
          FocusScope.of(context).hasFocus;
      final folderId = _hasFolders ? _folder.id : null;
      _addons = addons;
      _disabled = disabled;
      _layout = layout;
      if (refreshCollection) {
        _collection =
            updated ??
            HomeCollection(id: _collection.id, title: _collection.title);
        final index = _collection.folders.indexWhere((f) => f.id == folderId);
        _folderIndex = index < 0 ? 0 : index;
      }
      _configurationError = null;
      _booted = true;
      _rebuildFolder(
        autoFocus: !refreshCollection || restoreFocus,
        preserveSelection: refreshCollection,
      );
    } catch (e) {
      if (!mounted || generation != _configurationToken) return;
      setState(() {
        _configurationError =
            'Could not load this collection. Retry to continue.';
        _booted = true;
      });
    }
  }

  @override
  void dispose() {
    MainPageBridge.removeHomeSettingsListener(_onConfigurationChanged);
    _stremio.removeAddonsChangedListener(_onConfigurationChanged);
    for (final r in _rails) {
      r.dispose();
    }
    _railsScroll.dispose();
    _backNode.dispose();
    _folderNode.dispose();
    _viewNode.dispose();
    _listNode.dispose();
    _sortNode.dispose();
    _retryNode.dispose();
    super.dispose();
  }

  // ── Folder (re)build ───────────────────────────────────────────────────

  /// Resolve the current folder's enabled lists into rails and fetch their
  /// first pages. The All view is built lazily on first switch.
  void _rebuildFolder({
    bool autoFocus = false,
    bool preserveSelection = false,
  }) {
    final oldSource = preserveSelection ? _tabRail?.source.key : null;
    final wasAll = preserveSelection && _showingAll;
    final token = ++_reqToken;
    for (final r in _rails) {
      r.dispose();
    }
    final rails = <_Rail>[];
    final unresolved = <String>[];
    final resolved = <String>{};
    if (_hasFolders) {
      for (final s in _enabledSources) {
        final addon = HomeCollectionsStore.resolveAddon(s, _addons);
        final catalog = addon == null
            ? null
            : HomeCollectionsStore.resolveCatalog(s, addon);
        if (addon == null || catalog == null) {
          unresolved.add(
            addon == null
                ? s.addonId
                : '${s.addonId} → ${s.type}/${s.catalogId}',
          );
          continue;
        }
        final resolvedKey = jsonEncode([
          addon.manifestUrl,
          catalog.type,
          catalog.id,
          s.genre,
        ]);
        if (!resolved.add(resolvedKey)) continue;
        rails.add(
          _Rail(source: s, addon: addon, catalog: catalog, stremio: _stremio),
        );
      }
    }
    setState(() {
      _rails = rails;
      _unresolved = unresolved;
      _loader = null;
      _allItems.clear();
      _allStarted = false;
      _allLoadingInitial = false;
      _allLoadingMore = false;
      _allExhausted = false;
      final index = rails.indexWhere((r) => r.source.key == oldSource);
      _tab = wasAll && _collection.showAllTab && rails.length > 1
          ? _kAllTab
          : (index < 0 ? 0 : index);
      _tabGridKey = GlobalKey();
      _allGridKey = GlobalKey();
      if (!_collection.showAllTab || rails.length < 2) _view = _View.lists;
    });
    unawaited(_loadInitialRails(rails, token));
    if (_showingAll) unawaited(_startAll(token));
    if (autoFocus && widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _reqToken) return;
        _folderNode.requestFocus();
      });
    }
  }

  Future<void> _loadInitialRails(List<_Rail> rails, int token) async {
    for (
      var start = 0;
      start < rails.length;
      start += CollectionFolderLoader.maxConcurrent
    ) {
      if (!mounted || token != _reqToken) return;
      await Future.wait(
        rails
            .skip(start)
            .take(CollectionFolderLoader.maxConcurrent)
            .map((rail) => _loadRail(rail, token)),
      );
    }
  }

  Future<void> _loadRail(_Rail r, int token) async {
    final page = await r.pager.nextPage();
    if (!mounted || token != _reqToken) return;
    setState(() {
      r.items.addAll(page);
      r.loadingInitial = false;
    });
  }

  Future<void> _loadMoreRail(_Rail r) async {
    if (r.loadingInitial || r.loadingMore || r.exhausted || r.error != null) {
      return;
    }
    final token = _reqToken;
    setState(() => r.loadingMore = true);
    final page = await r.pager.nextPage();
    if (!mounted || token != _reqToken) return;
    setState(() {
      r.items.addAll(page);
      r.loadingMore = false;
    });
  }

  Future<void> _retryRail(_Rail r) async {
    if (r.loadingInitial || r.loadingMore) return;
    if (r.items.isEmpty && r.exhausted) r.pager.reset();
    r.forceRefresh = true;
    final restoreFocus = _retryNode.hasFocus;
    final token = _reqToken;
    setState(() => r.loadingMore = true);
    final page = await r.pager.nextPage();
    if (!mounted || token != _reqToken) return;
    setState(() {
      r.items.addAll(page);
      r.loadingMore = false;
    });
    _restoreRetryFocus(restoreFocus, token);
  }

  void _restoreRetryFocus(bool restore, int token) {
    if (!restore || !widget.isTelevision) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          token == _reqToken &&
          !_showingEmpty &&
          ModalRoute.of(context)?.isCurrent == true) {
        _enterContent();
      }
    });
  }

  Future<void> _retryRails() async {
    final token = _reqToken;
    final retry = _rails
        .where((r) => r.error != null || r.items.isEmpty)
        .toList();
    for (
      var start = 0;
      start < retry.length;
      start += CollectionFolderLoader.maxConcurrent
    ) {
      if (!mounted || token != _reqToken) return;
      await Future.wait(
        retry
            .skip(start)
            .take(CollectionFolderLoader.maxConcurrent)
            .map(_retryRail),
      );
    }
  }

  void _retryCurrent() {
    if (_configurationError != null || _rails.isEmpty) {
      unawaited(_boot());
      return;
    }
    if (_showingAll) {
      if (_allLoadingInitial || _allLoadingMore) return;
      if (_loader == null || _allExhausted) {
        _allStarted = false;
        _allItems.clear();
        unawaited(_startAll(_reqToken, forceRefresh: true));
      } else {
        unawaited(_loadMoreAll(retry: true));
      }
    } else if (_tabs) {
      final r = _tabRail;
      if (r != null) unawaited(_retryRail(r));
    } else {
      unawaited(_retryRails());
    }
  }

  // ── All (merged grid) ──────────────────────────────────────────────────

  Future<void> _startAll(int token, {bool forceRefresh = false}) async {
    if (_allStarted) return;
    _allStarted = true;
    final restoreFocus = _retryNode.hasFocus;
    final loader = CollectionFolderLoader(
      folder: _folder.copyWith(sources: _enabledSources),
      installedAddons: _addons,
      forceRefresh: forceRefresh,
    );
    setState(() {
      _loader = loader;
      _allLoadingInitial = true;
    });
    try {
      final page = await loader.nextPage();
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allItems.addAll(page);
        _allExhausted = loader.exhausted;
        _allLoadingInitial = false;
      });
      _restoreRetryFocus(restoreFocus, token);
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allLoadingInitial = false;
        _allExhausted = true;
      });
    }
  }

  Future<void> _loadMoreAll({bool retry = false}) async {
    final loader = _loader;
    if (loader == null ||
        _allLoadingInitial ||
        _allLoadingMore ||
        _allExhausted ||
        (!retry && loader.hasErrors)) {
      return;
    }
    final token = _reqToken;
    final restoreFocus = retry && _retryNode.hasFocus;
    setState(() => _allLoadingMore = true);
    try {
      final page = await loader.nextPage();
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allItems.addAll(page);
        _allExhausted = loader.exhausted;
        _allLoadingMore = false;
      });
      _restoreRetryFocus(restoreFocus, token);
    } catch (_) {
      if (!mounted || token != _reqToken) return;
      setState(() {
        _allLoadingMore = false;
        _allExhausted = true;
      });
    }
  }

  /// Client-side sort over whatever is loaded. Default keeps addon order.
  List<StremioMeta> _sorted(List<StremioMeta> items) {
    if (_sort == _sortDefault) return items;
    final sorted = List<StremioMeta>.of(items);
    if (_sort == _sortTitle) {
      sorted.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return sorted;
    }
    final asc = _sort == _sortImdbAsc;
    sorted.sort((a, b) {
      final ra = a.imdbRating, rb = b.imdbRating;
      if (ra == null && rb == null) return 0;
      if (ra == null) return 1;
      if (rb == null) return -1;
      return asc ? ra.compareTo(rb) : rb.compareTo(ra);
    });
    return sorted;
  }

  // ── Handlers ───────────────────────────────────────────────────────────

  void _onFolderChanged(int index) {
    if (index == _folderIndex) return;
    setState(() => _folderIndex = index);
    _rebuildFolder();
  }

  void _onViewChanged(_View view) {
    if (view == _view) return;
    setState(() => _view = view);
    if (view == _View.all) unawaited(_startAll(_reqToken));
  }

  void _onTabChanged(int tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _tabGridKey = GlobalKey();
    });
    if (tab == _kAllTab) unawaited(_startAll(_reqToken));
  }

  void _onSortChanged(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  /// The regular catalog browser on this rail's catalog, seeded with what the
  /// rail already loaded (paging continues rather than restarts) and opened
  /// on the source's genre.
  void _openRailSeeAll(_Rail r) {
    final settings = DiscoverCardSettingsScope.maybeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) {
          final screen = CatalogSeeAllScreen(
            addon: r.addon,
            initialCatalog: r.catalog,
            initialGenre: r.catalog.supportsGenre ? r.source.genre : null,
            seedItems: List<StremioMeta>.of(r.items),
            seedNextSkip: r.nextSkip,
            isTelevision: widget.isTelevision,
            onOpenItem: widget.onOpenItem,
            onQuickPlay: widget.onQuickPlay,
            onItemFocused: widget.onItemFocused,
            isBound: widget.isBound,
          );
          return settings == null
              ? screen
              : DiscoverCardSettingsScope(
                  showTitles: settings.showTitles,
                  showRatings: settings.showRatings,
                  showTypeTags: settings.showTypeTags,
                  child: screen,
                );
        },
      ),
    );
  }

  // ── TV focus ladder ────────────────────────────────────────────────────

  List<_Rail> get _visibleRails => [
    for (final r in _rails)
      if (r.visible) r,
  ];

  _Rail? get _tabRail =>
      _tab >= 0 && _tab < _rails.length ? _rails[_tab] : null;

  List<FocusNode> get _filterNodes => [
    _folderNode,
    if (_tabs) ...[
      if (_rails.isNotEmpty) _listNode,
      _sortNode,
    ] else ...[
      if (_offersAll) _viewNode,
      if (_view == _View.all) _sortNode,
    ],
    if (_hasVisibleLoadError) _retryNode,
  ];

  bool get _showingEmpty {
    if (!_booted) return false;
    if (_showingAll) return !_allLoadingInitial && _allItems.isEmpty;
    if (_tabs) {
      final r = _tabRail;
      return r == null || (!r.loadingInitial && r.items.isEmpty);
    }
    return _visibleRails.isEmpty;
  }

  /// DPAD-down from the filter line: the first rail's See-All pill (Rows) or
  /// the grid on screen (Tabs / All); the Retry button when there's nothing.
  void _enterContent() {
    if (_showingEmpty) {
      _retryNode.requestFocus();
      return;
    }
    if (_showingAll) {
      _allGridKey.currentState?.focusFirst();
      return;
    }
    if (_tabs) {
      _tabGridKey.currentState?.focusFirst();
      return;
    }
    final rails = _visibleRails;
    if (rails.isEmpty) {
      _retryNode.requestFocus();
      return;
    }
    rails.first.seeAllNode.requestFocus();
  }

  /// The chip the grid hands focus back to on DPAD-up.
  FocusNode get _gridExitNode =>
      _tabs && _rails.isNotEmpty ? _listNode : _folderNode;

  void _focusRailAbove(_Rail r) {
    final rails = _visibleRails;
    final i = rails.indexOf(r);
    if (i <= 0) {
      _folderNode.requestFocus();
      return;
    }
    rails[i - 1].gridKey.currentState?.focusFirst();
  }

  void _focusRailBelow(_Rail r) {
    final rails = _visibleRails;
    final i = rails.indexOf(r);
    if (i < 0 || i + 1 >= rails.length) return;
    rails[i + 1].seeAllNode.requestFocus();
  }

  void _ensureRailVisible(_Rail r) {
    final ctx = r.containerKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.15,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      onDown: _enterContent,
      onUp: () => _backNode.requestFocus(),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final subtitle = !_hasFolders
        ? 'No folders'
        : '${_folder.title} · ${_rails.length} '
              'list${_rails.length == 1 ? '' : 's'}';
    return Scaffold(
      backgroundColor: AppThemeScope.of(context).seeAll.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SeeAllHeader(
              title: _collection.title,
              subtitle: subtitle,
              isTelevision: widget.isTelevision,
              backNode: _backNode,
              onFilterDown: () => _folderNode.requestFocus(),
            ),
            if (_hasFolders)
              FolderHeroBand(
                key: ValueKey('folder-hero-${_folder.id}'),
                folder: _folder,
                isTelevision: widget.isTelevision,
              ),
            _buildFilterBar(),
            if (_hasVisibleLoadError)
              Focus(
                canRequestFocus: false,
                onKeyEvent: _handleFilterKeys,
                child: TextButton.icon(
                  focusNode: _retryNode,
                  onPressed: _retryCurrent,
                  icon: const Icon(Icons.refresh),
                  label: Text(_hasVisibleLoadFailure
                      ? 'Some lists could not load · Retry'
                      : 'No new titles loaded · Continue'),
                ),
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _sortChip() => StremioDropdown<String>(
    label: 'Sort',
    value: _sort,
    isTelevision: widget.isTelevision,
    focusNode: _sortNode,
    options: const [
      StremioDropdownOption(_sortDefault, 'Default'),
      StremioDropdownOption(_sortImdbDesc, 'IMDb Rating · High → Low'),
      StremioDropdownOption(_sortImdbAsc, 'IMDb Rating · Low → High'),
      StremioDropdownOption(_sortTitle, 'Title · A → Z'),
    ],
    onSelected: _onSortChanged,
  );

  Widget _buildFilterBar() {
    final folders = _collection.folders;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _handleFilterKeys,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          activeCount: _sort != _sortDefault && (_tabs || _showingAll) ? 1 : 0,
          buildChips: () => [
            StremioDropdown<int>(
              label: 'Folder',
              value: _folderIndex,
              isTelevision: widget.isTelevision,
              focusNode: _folderNode,
              options: [
                for (var i = 0; i < folders.length; i++)
                  StremioDropdownOption(i, folders[i].title),
              ],
              onSelected: _onFolderChanged,
            ),
            if (_tabs) ...[
              if (_rails.isNotEmpty)
                StremioDropdown<int>(
                  label: 'List',
                  value: _tab,
                  isTelevision: widget.isTelevision,
                  focusNode: _listNode,
                  options: [
                    for (var i = 0; i < _rails.length; i++)
                      StremioDropdownOption(i, _rails[i].title),
                    if (_offersAll)
                      const StremioDropdownOption(_kAllTab, 'All'),
                  ],
                  onSelected: _onTabChanged,
                ),
              _sortChip(),
            ] else ...[
              if (_offersAll)
                StremioDropdown<_View>(
                  label: 'View',
                  value: _view,
                  isTelevision: widget.isTelevision,
                  focusNode: _viewNode,
                  options: const [
                    StremioDropdownOption(_View.lists, 'Lists'),
                    StremioDropdownOption(_View.all, 'All'),
                  ],
                  onSelected: _onViewChanged,
                ),
              if (_view == _View.all) _sortChip(),
            ],
          ],
        ),
      ),
    );
  }

  /// Same poster geometry as a Home board rail, so a folder reads as Home
  /// with different lists.
  DiscoverShelfMetrics _railMetrics(BuildContext context) {
    final posterW = homeRailPosterWidth(
      context,
      isTelevision: widget.isTelevision,
    );
    return DiscoverShelfMetrics(cardHeight: posterW * 1.5, hPad: 24);
  }

  bool get _hasVisibleLoadFailure {
    if (_showingAll) return _loader?.hasLoadFailures ?? false;
    if (_tabs) {
      final pager = _tabRail?.pager;
      return pager != null && pager.error != null && !pager.noProgress;
    }
    return _rails.any((r) => r.error != null && !r.pager.noProgress);
  }

  bool get _hasVisibleLoadError {
    if (_configurationError != null) return false;
    if (_showingAll) {
      return _allItems.isNotEmpty && (_loader?.hasErrors ?? false);
    }
    if (_tabs) {
      return (_tabRail?.items.isNotEmpty ?? false) && _tabRail?.error != null;
    }
    return _rails.any((r) => r.items.isNotEmpty) &&
        _rails.any((r) => r.error != null);
  }

  Widget _buildBody() {
    if (!_booted) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_configurationError != null) return _buildEmpty();
    if (_showingAll) return _buildAll();
    if (_tabs) return _buildTab();
    return _buildLists();
  }

  Widget _buildLists() {
    final rails = _visibleRails;
    if (rails.isEmpty) return _buildEmpty();
    final m = _railMetrics(context);
    return ListView.builder(
      controller: _railsScroll,
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: rails.length,
      itemBuilder: (context, i) => _buildRail(rails[i], m),
    );
  }

  Widget _buildRail(_Rail r, DiscoverShelfMetrics m) {
    final app = AppThemeScope.of(context);
    final tv = widget.isTelevision;
    return Column(
      key: r.containerKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(m.hPad, 14, m.hPad, 0),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: app.core.tx,
                    fontSize: tv ? 18 : 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: RowTagPill(r.addon.name)),
              const Spacer(),
              RailSeeAllPill(
                node: r.seeAllNode,
                isTelevision: tv,
                onPressed: () => _openRailSeeAll(r),
                onUp: () => _focusRailAbove(r),
                onDown: () => r.gridKey.currentState?.focusFirst(),
                onFocused: () => _ensureRailVisible(r),
              ),
            ],
          ),
        ),
        SizedBox(
          height: m.columnHeight,
          child: DiscoverShelfScope(
            metrics: m,
            child: r.loadingInitial
                ? SkeletonPosterGrid(isTelevision: tv)
                : SeeAllPosterGrid(
                    key: r.gridKey,
                    items: r.items,
                    isTelevision: tv,
                    loadingMore: r.loadingMore,
                    exhausted: r.exhausted,
                    onOpen: widget.onOpenItem,
                    onQuickPlay: widget.onQuickPlay,
                    onItemFocused: (item) {
                      widget.onItemFocused?.call(item);
                    },
                    isBound: widget.isBound,
                    onLoadMore: () => _loadMoreRail(r),
                    onExitTop: tv ? () => r.seeAllNode.requestFocus() : null,
                    onExitBottom: tv ? () => _focusRailBelow(r) : null,
                  ),
          ),
        ),
      ],
    );
  }

  /// Tabs layout: the selected list as a full poster grid.
  Widget _buildTab() {
    final r = _tabRail;
    if (r == null) return _buildEmpty();
    if (r.loadingInitial) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (r.items.isEmpty) return _buildEmpty();
    return SeeAllPosterGrid(
      // Keyed per list so switching tabs remounts the grid (fresh scroll and
      // focus memory) instead of morphing one list into another.
      key: _tabGridKey,
      items: _sorted(r.items),
      isTelevision: widget.isTelevision,
      loadingMore: r.loadingMore,
      exhausted: r.exhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: () => _loadMoreRail(r),
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
    );
  }

  Widget _buildAll() {
    if (_allLoadingInitial || (!_allStarted && _rails.isNotEmpty)) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_allItems.isEmpty) return _buildEmpty();
    return SeeAllPosterGrid(
      key: _allGridKey,
      items: _sorted(_allItems),
      isTelevision: widget.isTelevision,
      loadingMore: _allLoadingMore,
      exhausted: _allExhausted,
      onOpen: widget.onOpenItem,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: _loadMoreAll,
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
    );
  }

  Widget _buildEmpty() {
    final app = AppThemeScope.of(context);
    final String title;
    final String detail;
    if (_configurationError != null) {
      title = 'Could not load collection';
      detail = _configurationError!;
    } else if (!_hasFolders) {
      title = 'This collection has no folders';
      detail = 'Import a file that lists folders with catalog sources.';
    } else if (_folder.sources.isEmpty) {
      title = 'This folder lists no catalogs';
      detail = 'Nothing to browse here.';
    } else if (_enabledSources.isEmpty) {
      title = 'Every list in this folder is switched off';
      detail =
          'Turn its lists back on under Settings › Home Screen › Home Rows.';
    } else if (_rails.isEmpty) {
      title = 'No matching addon installed';
      detail =
          'This folder needs an addon that isn\'t installed:\n'
          '${_unresolved.toSet().join('\n')}\n\n'
          'Install it under Addons, then come back.';
    } else if (_tabs && !_showingAll) {
      title = 'Nothing in this list';
      detail = 'The catalog may be empty, or the addon failed to respond.';
    } else {
      title = 'Nothing in this folder';
      detail = _unresolved.isNotEmpty
          ? 'The installed catalogs returned nothing. Some lists are '
                'missing an addon:\n${_unresolved.toSet().join('\n')}'
          : 'The catalogs may be empty, or the addon failed to respond.';
    }
    return SingleChildScrollView(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 44,
                  color: app.fade(app.core.tx, 0.25),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.7),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.4),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Focus(
                  onKeyEvent: (_, event) {
                    if (widget.isTelevision &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _gridExitNode.requestFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: OutlinedButton.icon(
                    focusNode: _retryNode,
                    onPressed: _retryCurrent,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: app.core.tx,
                      side: BorderSide(color: app.seeAll.accentBorder),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: app.shape.br(11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
