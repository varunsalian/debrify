import '../../widgets/see_all/see_all_header.dart';
import '../../services/storage_service.dart';
import '../../widgets/collections/tv_collection_titles.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/home_collection.dart';
import '../../widgets/collections/collection_list_gallery.dart';
import '../../widgets/collections/collection_browser_hero.dart';
import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/collection_folder_loader.dart';
import '../../services/collection_catalog_pager.dart';
import '../../services/watched_filter.dart';
import '../../services/main_page_bridge.dart';
import '../../services/home_collections_store.dart';
import '../../services/stremio_service.dart';
import '../../theme/app_theme_scope.dart';
import '../../services/collection_native_source_service.dart';
import '../../widgets/see_all/discover_card_settings_scope.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/skeleton_poster.dart';

/// Collection folders open as artwork galleries; each list opens a full grid.
/// Existing tabbed and merged views retain their paging and filter semantics.
class CollectionFolderScreen extends StatefulWidget {
  final HomeCollection collection;
  final int initialFolderIndex;
  final void Function(StremioMeta item) onOpenItem;
  final void Function(StremioMeta item)? onQuickPlay;
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;
  final CollectionNativeSourceService? nativeSources;
  final String? sourceKey;

  const CollectionFolderScreen({
    super.key,
    required this.collection,
    required this.onOpenItem,
    this.initialFolderIndex = 0,
    this.onQuickPlay,
    this.onItemFocused,
    this.isBound,
    this.isTelevision = false,
    this.nativeSources,
    this.sourceKey,
  });

  @override
  State<CollectionFolderScreen> createState() => _CollectionFolderScreenState();
}

/// Gallery layout: list cards, or the merged title grid.
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
    required CollectionNativeSourceService native,
  }) {
    if (source.isNative) {
      pager = NativeCollectionPager(
        fetch: (page) => native.fetchPreview(source, page),
        hides: WatchedFilter.predicate,
      );
      return;
    }
    pager = CollectionCatalogPager(
      addon: addon!,
      catalog: catalog!,
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
  late final CollectionPager pager;
  bool forceRefresh = false;

  final CollectionCatalogSource source;
  final StremioAddon? addon;
  final StremioAddonCatalog? catalog;
  final List<StremioMeta> items = [];
  bool loadingInitial = true;
  bool loadingMore = false;
  bool get exhausted => pager.exhausted;
  String? get error => pager.error;

  /// "Popular Movies · Action" — the Home row title plus the source's genre.
  String get title {
    final base =
        source.title ??
        (catalog == null ? source.label : CatalogSection.rowTitle(catalog!));
    final genre = source.genre;
    return genre == null ? base : '$base · $genre';
  }
}

class _CollectionFolderScreenState extends State<CollectionFolderScreen> {
  CollectionNativeSourceService get _native =>
      widget.nativeSources ?? CollectionNativeSourceService.instance;

  void _identitiesChanged() {
    if (mounted) setState(() {});
  }

  final _emptyPageContinuations = <Object>{};

  void _continueEmptyPage(
    Object owner,
    bool Function() isCurrent,
    Future<void> Function() load,
  ) {
    if (!_emptyPageContinuations.add(owner)) return;
    final token = _reqToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _emptyPageContinuations.remove(owner);
      if (mounted && token == _reqToken && isCurrent()) {
        unawaited(load());
      }
    });
  }

  bool _railCanContinue(_Rail rail) => !rail.exhausted && rail.error == null;
  bool get _allCanContinue =>
      _loader != null && !_allExhausted && !_loader!.hasErrors;

  List<StremioMeta> _displayItems(List<StremioMeta> items) {
    _native.prefetchIdentities(items);
    final seen = <String>{};
    return [
      for (final item in items.map(_native.withCachedIdentity))
        if (!WatchedFilter.hides(item) &&
            seen.add('${item.type}:${item.effectiveImdbId ?? item.id}'))
          item,
    ];
  }

  @override
  void didUpdateWidget(covariant CollectionFolderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous =
        oldWidget.nativeSources ?? CollectionNativeSourceService.instance;
    if (previous != _native) {
      previous.identityChanges.removeListener(_identitiesChanged);
      _native.identityChanges.addListener(_identitiesChanged);
    }
  }

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
  bool _booted = false;
  String _tvListStyle = 'grid';
  GlobalKey<TvCollectionTitlesState> _tvTitlesKey = GlobalKey();
  bool get _styledTvList => widget.isTelevision && _tvListStyle != 'grid';

  List<_Rail> _rails = const [];
  List<String> _unresolved = const [];
  GlobalKey<CollectionListGalleryState> _galleryKey = GlobalKey();
  bool _initialGridFocus = false;
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
  final FocusNode _detailsNode = FocusNode(debugLabel: 'collection_details');
  final FocusNode _issuesNode = FocusNode(debugLabel: 'collection_issues');

  late HomeCollection _collection;
  int _configurationToken = 0;
  String? _configurationError;
  String? _configurationSignature;
  bool get _hasFolders => _collection.folders.isNotEmpty;
  HomeCollectionFolder get _folder => _collection.folders[_folderIndex];
  bool get _tabs =>
      widget.sourceKey != null || _layout == CollectionFolderLayout.tabs;

  /// The folder's lists, narrowed to the selected source when opening a list.
  List<CollectionCatalogSource> get _enabledSources => [
    for (final s in _folder.sources)
      if (widget.sourceKey == null || s.key == widget.sourceKey) s,
  ];

  Set<String> get _sourceIssues => {
    ..._unresolved,
    for (final r in _rails)
      if (r.error != null) '${r.title}: ${r.error}',
    if (_showingAll) ...?_loader?.errors,
  };

  bool get _offersAll => _collection.showAllTab && _rails.length > 1;

  /// Whether the merged grid is what's on screen.
  bool get _showingAll => _tabs ? _tab == _kAllTab : _view == _View.all;

  @override
  void initState() {
    super.initState();
    _native.identityChanges.addListener(_identitiesChanged);
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
      final tvStyle = widget.isTelevision
          ? await StorageService.getTvCollectionListStyle()
          : 'grid';
      final addons = await _stremio.getAddons();
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
      final signature = jsonEncode({
        'collection': candidate.toJson()..remove('importedAt'),
        'addons': [for (final addon in addons) addon.toJson()],
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
      _layout = widget.sourceKey != null
          ? CollectionFolderLayout.tabs
          : switch (candidate.viewMode?.toUpperCase()) {
              'TABBED_GRID' => CollectionFolderLayout.tabs,
              'FOLLOW_LAYOUT' || 'ROWS' => CollectionFolderLayout.rows,
              _ => layout,
            };
      if (refreshCollection) {
        _collection =
            updated ??
            HomeCollection(id: _collection.id, title: _collection.title);
        final index = _collection.folders.indexWhere((f) => f.id == folderId);
        _folderIndex = index < 0 ? 0 : index;
      }
      _tvListStyle = tvStyle;
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
    _native.identityChanges.removeListener(_identitiesChanged);
    MainPageBridge.removeHomeSettingsListener(_onConfigurationChanged);
    _stremio.removeAddonsChangedListener(_onConfigurationChanged);
    _backNode.dispose();
    _folderNode.dispose();
    _viewNode.dispose();
    _listNode.dispose();
    _sortNode.dispose();
    _retryNode.dispose();
    _issuesNode.dispose();
    _detailsNode.dispose();
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
    _openRequest++;
    _openingTitle = null;
    final rails = <_Rail>[];
    final unresolved = <String>[];
    final resolved = <String>{};
    if (_hasFolders) {
      for (final s in _enabledSources) {
        final addon = HomeCollectionsStore.resolveAddon(s, _addons);
        final catalog = addon == null
            ? null
            : HomeCollectionsStore.resolveCatalog(s, addon);
        if (!s.isNative && (addon == null || catalog == null)) {
          unresolved.add(
            HomeCollectionsStore.sourceIssue(s, _addons) ?? s.label,
          );
          continue;
        }
        final resolvedKey = s.isNative
            ? s.key
            : jsonEncode([
                addon!.manifestUrl,
                catalog!.type,
                catalog.id,
                s.genre,
              ]);
        if (!resolved.add(resolvedKey)) continue;
        rails.add(
          _Rail(
            source: s,
            addon: addon,
            catalog: catalog,
            stremio: _stremio,
            native:
                widget.nativeSources ?? CollectionNativeSourceService.instance,
          ),
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
      _tvTitlesKey = GlobalKey();
      _galleryKey = GlobalKey();
      _allGridKey = GlobalKey();
      if (!_collection.showAllTab || rails.length < 2) _view = _View.lists;
    });
    unawaited(_loadInitialRails(rails, token));
    if (_showingAll) unawaited(_startAll(token));
    if (autoFocus && widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _reqToken) return;
        if (widget.sourceKey == null) {
          _folderNode.requestFocus();
        } else {
          _sortNode.requestFocus();
          _focusLoadedGrid();
        }
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
    _focusLoadedGrid();
  }

  void _focusLoadedGrid() {
    if (widget.sourceKey == null || !widget.isTelevision || _initialGridFocus) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _initialGridFocus ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      if (_styledTvList &&
          _tvTitlesKey.currentState != null &&
          _sortNode.hasFocus) {
        _initialGridFocus = true;
        _tvTitlesKey.currentState!.focusFirst();
        return;
      }
      final grid = _tabGridKey.currentState;
      if (grid != null && _sortNode.hasFocus) {
        _initialGridFocus = true;
        grid.focusFirst();
      }
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
      previews: true,
      native: widget.nativeSources,
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

  int _openRequest = 0;
  String? _openingTitle;

  void _openItem(StremioMeta item) => _dispatchItem(item, widget.onOpenItem);

  void _quickPlay(StremioMeta item) {
    final callback = widget.onQuickPlay;
    if (callback != null) _dispatchItem(item, callback);
  }

  Future<void> _dispatchItem(
    StremioMeta item,
    void Function(StremioMeta) callback,
  ) async {
    final request = ++_openRequest;
    final native =
        widget.nativeSources ?? CollectionNativeSourceService.instance;
    if (!item.id.startsWith('tmdb:') || !native.resolveIds) {
      setState(() => _openingTitle = null);
      callback(item);
      return;
    }
    setState(() => _openingTitle = item.name);
    final session = HomeCollectionsStore.captureSession();
    try {
      final resolved = await native
          .resolveIdentity(item)
          .timeout(const Duration(seconds: 4), onTimeout: () => item);
      if (mounted &&
          request == _openRequest &&
          session == HomeCollectionsStore.captureSession() &&
          ModalRoute.of(context)?.isCurrent == true) {
        callback(resolved);
      }
    } finally {
      if (mounted && request == _openRequest) {
        setState(() => _openingTitle = null);
      }
    }
  }

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
      _tvTitlesKey = GlobalKey();
    });
    if (tab == _kAllTab) unawaited(_startAll(_reqToken));
  }

  void _onSortChanged(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
  }

  Future<void> _openList(_Rail r, int index) async {
    final token = _reqToken;
    final settings = DiscoverCardSettingsScope.maybeOf(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) {
          final screen = CollectionFolderScreen(
            collection: _collection,
            initialFolderIndex: _folderIndex,
            sourceKey: r.source.key,
            nativeSources: widget.nativeSources,
            isTelevision: widget.isTelevision,
            onOpenItem: widget.onOpenItem,
            onQuickPlay: widget.onQuickPlay,
            onItemFocused: widget.onItemFocused,
            isBound: widget.isBound,
          );
          return DiscoverCardSettingsScope(
            showTitles: settings?.showTitles ?? true,
            showRatings: settings?.showRatings ?? true,
            showTypeTags: settings?.showTypeTags ?? true,
            child: screen,
          );
        },
      ),
    );
    if (mounted && token == _reqToken) {
      _galleryKey.currentState?.focusIndex(index);
    }
  }

  // ── TV focus ladder ────────────────────────────────────────────────────

  List<_Rail> get _visibleRails => _rails;

  _Rail? get _tabRail =>
      _tab >= 0 && _tab < _rails.length ? _rails[_tab] : null;

  List<FocusNode> get _filterNodes => [
    if (widget.sourceKey == null) _folderNode,
    if (_tabs) ...[
      if (_rails.isNotEmpty && widget.sourceKey == null) _listNode,
      _sortNode,
    ] else ...[
      if (_offersAll) _viewNode,
      if (_view == _View.all) _sortNode,
    ],
  ];

  bool get _showingEmpty {
    if (!_booted) return false;
    if (_showingAll) {
      return !_allLoadingInitial &&
          !_allCanContinue &&
          _displayItems(_allItems).isEmpty;
    }
    if (_tabs) {
      final r = _tabRail;
      return r == null ||
          (!r.loadingInitial &&
              !_railCanContinue(r) &&
              _displayItems(r.items).isEmpty);
    }
    return _visibleRails.isEmpty;
  }

  /// Down from filters returns to the selected gallery card or title grid;
  /// empty pages offer Retry.
  void _enterContent() {
    if (_showingEmpty) {
      (_hasEmptyLoadError ? _detailsNode : _retryNode).requestFocus();
      return;
    }
    if (_showingAll) {
      if (_styledTvList) {
        _tvTitlesKey.currentState?.focusFirst();
      } else {
        _allGridKey.currentState?.focusFirst();
      }
      return;
    }
    if (_tabs) {
      if (_styledTvList) {
        _tvTitlesKey.currentState?.focusFirst();
      } else {
        _tabGridKey.currentState?.focusFirst();
      }
      return;
    }
    final rails = _visibleRails;
    if (rails.isEmpty) {
      _retryNode.requestFocus();
      return;
    }
    _galleryKey.currentState?.focusFirst();
  }

  /// The chip the grid hands focus back to on DPAD-up.
  FocusNode get _gridExitNode => widget.sourceKey != null
      ? _sortNode
      : _tabs && _rails.isNotEmpty
      ? _listNode
      : _folderNode;

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
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
    return Scaffold(
      backgroundColor: AppThemeScope.of(context).seeAll.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_styledTvList && (_tabs || _showingAll))
              Row(
                children: [
                  Expanded(
                    child: SeeAllHeader(
                      title: _showingAll
                          ? 'All titles'
                          : (_tabRail?.title ?? _collection.title),
                      subtitle:
                          '${_collection.title} / ${_hasFolders ? _folder.title : ""}',
                      isTelevision: true,
                      backNode: _backNode,
                      onFilterDown: () => _filterNodes.first.requestFocus(),
                    ),
                  ),
                  if (_hasHeaderIssue) _buildIssueAction(),
                ],
              )
            else
              CollectionBrowserHero(
                collectionTitle: _collection.title,
                folder: _hasFolders ? _folder : null,
                listTitle: widget.sourceKey != null ? _tabRail?.title : null,
                source: widget.sourceKey != null
                    ? _tabRail?.source.provider.toUpperCase()
                    : null,
                listCount: _rails.length,
                backdrop: _collection.backdropImageUrl,
                item:
                    widget.sourceKey != null &&
                        (_tabRail?.items.isNotEmpty ?? false)
                    ? _tabRail!.items.first
                    : null,
                backNode: _backNode,
                action: _hasHeaderIssue ? _buildIssueAction() : null,
                onRight: _hasHeaderIssue ? _issuesNode.requestFocus : null,
                onDown: () => _filterNodes.first.requestFocus(),
              ),
            _buildFilterBar(),
            if (_openingTitle != null)
              Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Opening $_openingTitle…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _openRequest++;
                      _openingTitle = null;
                    }),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  bool get _hasHeaderIssue => _hasVisibleLoadError || _sourceIssues.isNotEmpty;

  Future<void> _showIssueDetails(String detail, {bool retry = false}) async {
    final shouldRetry = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Collection details'),
        content: Text(detail),
        actions: [
          TextButton(
            autofocus: !retry,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Close'),
          ),
          if (retry)
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                _hasVisibleLoadError && !_hasVisibleLoadFailure
                    ? 'Continue'
                    : 'Retry',
              ),
            ),
        ],
      ),
    );
    if (mounted && shouldRetry == true) _retryCurrent();
  }

  Widget _buildIssueAction() => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _backNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          _filterNodes.first.requestFocus();
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    },
    child: IconButton(
      focusNode: _issuesNode,
      tooltip: 'Collection needs attention',
      icon: const Icon(Icons.info_outline),
      onPressed: () => _showIssueDetails(
        _sourceIssues.isNotEmpty
            ? _sourceIssues.join('\n\n')
            : 'No new titles loaded. Continue to try again.',
        retry: _hasVisibleLoadError,
      ),
    ),
  );

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
            if (widget.sourceKey == null)
              StremioDropdown<int>(
                label: 'Folder',
                value: _folderIndex,
                isTelevision: widget.isTelevision,
                focusNode: _folderNode,
                options: [
                  for (var i = 0; i < folders.length; i++)
                    if (widget.sourceKey == null || i == _folderIndex)
                      StremioDropdownOption(i, folders[i].title),
                ],
                onSelected: _onFolderChanged,
              ),
            if (_tabs) ...[
              if (_rails.isNotEmpty && widget.sourceKey == null)
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
                    StremioDropdownOption(_View.lists, 'Gallery'),
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
    return CollectionListGallery(
      key: _galleryKey,
      lists: [
        for (final r in rails)
          CollectionListPreview(
            id: r.source.key,
            title: r.title,
            source: r.addon?.name ?? r.source.provider.toUpperCase(),
            items: _displayItems(r.items),
            loading: r.loadingInitial,
            failed: r.error != null,
          ),
      ],
      onOpen: (index) => _openList(rails[index], index),
      onExitTop: () => _folderNode.requestFocus(),
    );
  }

  /// Tabs layout: the selected list as a full poster grid.
  Widget _buildTab() {
    final r = _tabRail;
    if (r == null) return _buildEmpty();
    if (r.loadingInitial) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    final items = _displayItems(r.items);
    if (items.isEmpty) {
      if (!_railCanContinue(r)) return _buildEmpty();
      if (!r.loadingMore) {
        _continueEmptyPage(
          r,
          () => !_showingAll && identical(_tabRail, r),
          () => _loadMoreRail(r),
        );
      }
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_styledTvList) {
      return _styledTitles(
        items,
        loadingMore: r.loadingMore,
        exhausted: r.exhausted,
        loadMore: () => _loadMoreRail(r),
      );
    }
    return SeeAllPosterGrid(
      // Keyed per list so switching tabs remounts the grid (fresh scroll and
      // focus memory) instead of morphing one list into another.
      key: _tabGridKey,
      items: _sorted(items),
      isTelevision: widget.isTelevision,
      loadingMore: r.loadingMore,
      exhausted: r.exhausted,
      onOpen: _openItem,
      onQuickPlay: widget.onQuickPlay == null ? null : _quickPlay,
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
    final items = _displayItems(_allItems);
    if (items.isEmpty) {
      if (!_allCanContinue) return _buildEmpty();
      final loader = _loader!;
      if (!_allLoadingMore) {
        _continueEmptyPage(
          loader,
          () => _showingAll && identical(_loader, loader),
          _loadMoreAll,
        );
      }
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (_styledTvList) {
      return _styledTitles(
        items,
        loadingMore: _allLoadingMore,
        exhausted: _allExhausted,
        loadMore: _loadMoreAll,
      );
    }
    return SeeAllPosterGrid(
      key: _allGridKey,
      items: _sorted(items),
      isTelevision: widget.isTelevision,
      loadingMore: _allLoadingMore,
      exhausted: _allExhausted,
      onOpen: _openItem,
      onQuickPlay: widget.onQuickPlay == null ? null : _quickPlay,
      onItemFocused: widget.onItemFocused,
      isBound: widget.isBound,
      onLoadMore: _loadMoreAll,
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
    );
  }

  Widget _styledTitles(
    List<StremioMeta> items, {
    required bool loadingMore,
    required bool exhausted,
    required VoidCallback loadMore,
  }) => TvCollectionTitles(
    key: _tvTitlesKey,
    style: _tvListStyle,
    items: _sorted(items),
    loadingMore: loadingMore,
    exhausted: exhausted,
    onLoadMore: loadMore,
    onOpen: _openItem,
    onQuickPlay: widget.onQuickPlay == null ? null : _quickPlay,
    onItemFocused: widget.onItemFocused,
    isBound: widget.isBound,
    onExitTop: () => _gridExitNode.requestFocus(),
  );

  bool get _hasEmptyLoadError {
    if (_configurationError != null) return true;
    if (!_hasFolders || _folder.sources.isEmpty || _enabledSources.isEmpty) {
      return false;
    }
    if (_rails.isEmpty) return _unresolved.isNotEmpty;
    if (_showingAll) return _loader?.hasErrors ?? false;
    if (_tabs) return _tabRail?.error != null;
    return _sourceIssues.isNotEmpty;
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
      detail =
          'Add a folder in the collection editor or import a collection file.';
    } else if (_folder.sources.isEmpty) {
      title = 'This folder has no sources';
      detail = 'Add an addon, TMDB, or Trakt source in the collection editor.';
    } else if (_enabledSources.isEmpty) {
      title = 'This list is unavailable';
      detail = 'The selected list is no longer in this folder.';
    } else if (_rails.isEmpty) {
      title = 'Some collection sources need attention';
      detail = _unresolved.toSet().join('\n\n');
    } else if (_showingAll && (_loader?.hasErrors ?? false)) {
      title = 'Could not load all lists';
      detail = _loader!.errors.toSet().join('\n');
    } else if (_tabs && !_showingAll) {
      title = _tabRail?.error == null
          ? 'Nothing in this list'
          : 'Could not load this list';
      detail =
          _tabRail?.error ??
          'This list is empty or its titles are hidden by your watched filter.';
    } else {
      title = 'Nothing in this folder';
      detail = _unresolved.isNotEmpty
          ? 'The installed catalogs returned nothing. Some lists are '
                'unavailable:\n${_unresolved.toSet().join('\n')}'
          : _rails
                .map((r) => r.error)
                .whereType<String>()
                .toSet()
                .join('\n')
                .isNotEmpty
          ? _rails.map((r) => r.error).whereType<String>().toSet().join('\n')
          : 'The lists are empty or their titles are hidden by your watched filter.';
    }
    final hasError = _hasEmptyLoadError;
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
                  hasError ? 'Couldn’t load this collection' : title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.7),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasError ? 'Please try again.' : detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: app.fade(app.core.tx, 0.4),
                    fontSize: 13,
                  ),
                ),
                if (hasError)
                  Focus(
                    canRequestFocus: false,
                    onKeyEvent: (_, event) {
                      if (widget.isTelevision && event is KeyDownEvent) {
                        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                          _gridExitNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _retryNode.requestFocus();
                          return KeyEventResult.handled;
                        }
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextButton(
                      focusNode: _detailsNode,
                      onPressed: () => _showIssueDetails(detail),
                      child: const Text('View details'),
                    ),
                  ),
                const SizedBox(height: 18),
                Focus(
                  onKeyEvent: (_, event) {
                    if (widget.isTelevision &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      (hasError ? _detailsNode : _gridExitNode).requestFocus();
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
