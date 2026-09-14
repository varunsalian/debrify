import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/stremio_addon.dart';
import '../../services/analytics_service.dart';
import '../../services/discover_prefs.dart';
import '../../services/main_page_bridge.dart';
import '../../services/mdblist/mdblist_discover_models.dart';
import '../../services/mdblist/mdblist_discover_source.dart';
import '../../services/mdblist/mdblist_list_source.dart';
import '../../services/mdblist/mdblist_models.dart';
import '../../services/watched_filter.dart';
import '../../theme/app_theme_scope.dart';
import '../../widgets/see_all/mdblist_save_button.dart';
import '../../widgets/see_all/see_all_filter_bar.dart';
import '../../widgets/see_all/see_all_filter_focus.dart';
import '../../widgets/see_all/see_all_header.dart';
import '../../widgets/see_all/see_all_poster_grid.dart';
import '../../widgets/see_all/see_all_random_button.dart';
import '../../widgets/see_all/stremio_dropdown.dart';
import '../../widgets/skeleton_poster.dart';

enum _Sort { natural, az, za, newest, oldest }

/// Full-screen / embedded MDBList tracker and discovery browser.
///
/// Unlike the old list-only panel, this surface keeps the API's distinct
/// library, recommendation, list-directory, and quota-limited catalog
/// contracts separate while presenting them through one stable filter line.
class MdblistSeeAllScreen extends StatefulWidget {
  final void Function(StremioMeta item) onOpen;
  final void Function(StremioMeta item)? onQuickPlay;
  final void Function(StremioMeta item)? onItemFocused;
  final bool Function(StremioMeta item)? isBound;
  final bool isTelevision;
  final bool embedded;
  final Widget? leading;
  final FocusNode? leadingNode;
  final MdblistListChoice? initialList;

  /// Preserve the source directory when opening a Home list directly.
  final bool? initialListIsPublic;

  /// Injection seams used by contract/widget tests. Production callers leave
  /// both null and use the account-bound singletons.
  final MdblistDiscoverSource? source;
  final Future<bool> Function()? isAuthenticated;

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
    this.initialListIsPublic,
    this.source,
    this.isAuthenticated,
  });

  @override
  State<MdblistSeeAllScreen> createState() => _MdblistSeeAllScreenState();
}

class _MdblistSeeAllScreenState extends State<MdblistSeeAllScreen> {
  final GlobalKey<SeeAllPosterGridState> _gridKey = GlobalKey();
  final Random _random = Random();

  MdblistDiscoverSource get _source =>
      widget.source ?? MdblistDiscoverSource.instance;

  bool _connected = false;
  MdblistDiscoverGroup _group = MdblistDiscoverGroup.library;
  MdblistLibraryView _libraryView = MdblistLibraryView.continueWatching;
  MdblistListDirectory _directory = MdblistListDirectory.mine;
  List<MdblistDiscoverChoice> _choices = const [];
  MdblistDiscoverChoice? _selected;
  MdblistDiscoverChoice? _searchResult;
  bool _searchResultIsPublic = false;
  bool _selectedLiked = false;

  MdblistDiscoverPage _page = const MdblistDiscoverPage();
  List<StremioMeta> _visible = const [];
  String _show = 'all';
  _Sort _sort = _Sort.natural;
  MdblistCatalogQuery _catalogDraft = const MdblistCatalogQuery();
  bool _catalogApplied = false;

  bool _menuLoading = true;
  bool _itemsLoading = false;
  bool _loadingMore = false;
  bool _saveBusy = false;
  bool _cloneBusy = false;
  bool _menuPartial = false;
  MdblistResultKind? _errorKind;
  int _fetchToken = 0;

  final FocusNode _backNode = FocusNode(debugLabel: 'msa_back');
  final FocusNode _categoryNode = FocusNode(debugLabel: 'msa_category');
  final FocusNode _viewNode = FocusNode(debugLabel: 'msa_view');
  final FocusNode _listNode = FocusNode(debugLabel: 'msa_list');
  final FocusNode _showNode = FocusNode(debugLabel: 'msa_show');
  final FocusNode _sortNode = FocusNode(debugLabel: 'msa_sort');
  final FocusNode _orderNode = FocusNode(debugLabel: 'msa_order');
  final FocusNode _filtersNode = FocusNode(debugLabel: 'msa_filters');
  final FocusNode _applyNode = FocusNode(debugLabel: 'msa_apply');
  final FocusNode _moreNode = FocusNode(debugLabel: 'msa_more');
  final FocusNode _saveNode = FocusNode(debugLabel: 'msa_save');
  final FocusNode _cloneNode = FocusNode(debugLabel: 'msa_clone');
  final FocusNode _randomNode = FocusNode(debugLabel: 'msa_random');

  bool get _quiet => widget.embedded && widget.isTelevision;
  bool get _showRandom => widget.embedded && widget.onQuickPlay != null;
  bool get _isCatalog => _group == MdblistDiscoverGroup.catalog;
  bool get _catalogCanApply =>
      !_itemsLoading &&
      (_source.catalogQuota?.exhausted != true ||
          _source.hasCachedCatalog(_catalogDraft));
  bool get _catalogCanLoadMore =>
      !_loadingMore && _source.catalogQuota?.exhausted != true;
  bool get _showListPicker =>
      (_group == MdblistDiscoverGroup.discover ||
          _group == MdblistDiscoverGroup.lists) &&
      _selected != null;
  bool get _canLike {
    final selected = _selected;
    if (selected?.kind != MdblistDiscoverChoiceKind.regularList ||
        selected?.numericId == null) {
      return false;
    }
    return _directory == MdblistListDirectory.top ||
        _directory == MdblistListDirectory.curated ||
        _directory == MdblistListDirectory.liked ||
        _directory == MdblistListDirectory.searchResult;
  }

  bool get _canClone =>
      _selected?.kind == MdblistDiscoverChoiceKind.regularList &&
      _selected?.numericId != null &&
      _directory != MdblistListDirectory.mine;

  List<FocusNode> get _filterNodes => [
    if (widget.leadingNode != null) widget.leadingNode!,
    if (_connected) _categoryNode,
    if (_connected &&
        !_isCatalog &&
        !(_group == MdblistDiscoverGroup.forYou && _selected == null))
      _viewNode,
    if (_showListPicker) _listNode,
    if (_connected) _showNode,
    if (_connected) _sortNode,
    if (_isCatalog) _orderNode,
    if (_isCatalog) _filtersNode,
    if (_isCatalog) _applyNode,
    if (_isCatalog && !_page.exhausted) _moreNode,
    if (_canLike) _saveNode,
    if (_canClone) _cloneNode,
    if (_showRandom && _page.items.isNotEmpty) _randomNode,
  ];

  FocusNode get _gridExitNode {
    if (_isCatalog) return _applyNode;
    if (_showListPicker) return _listNode;
    return _viewNode;
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('mdblist_see_all');
    if (widget.embedded) {
      final saved = DiscoverPrefs.enumSortFor(
        DiscoverPrefs.mdblist,
        _Sort.values,
      );
      if (saved != null) _sort = saved;
    }
    _init();
    if (widget.isTelevision && !widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusEntry());
    }
  }

  Future<void> _init() async {
    final connected =
        await (widget.isAuthenticated?.call() ??
            _source.service.isAuthenticated());
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _connected = false;
        _menuLoading = false;
      });
      return;
    }
    _connected = true;
    final initial = widget.initialList;
    if (initial != null) {
      final choice = MdblistDiscoverChoice(
        id: initial.id.toString(),
        label: initial.name,
        kind: MdblistDiscoverChoiceKind.regularList,
        numericId: initial.id,
        ownerName: initial.ownerName,
        itemCount: initial.itemCount,
        liked: initial.liked,
        likes: initial.likes,
      );
      setState(() {
        _group = MdblistDiscoverGroup.lists;
        _directory = MdblistListDirectory.searchResult;
        _searchResult = choice;
        _searchResultIsPublic =
            widget.initialListIsPublic ??
            (initial.ownerName != null && !initial.liked);
        _choices = [choice];
        _selected = choice;
        _selectedLiked = choice.liked;
        _menuLoading = false;
      });
      await _loadChoice(choice);
      return;
    }
    setState(() => _menuLoading = false);
    await _loadLibrary();
  }

  @override
  void dispose() {
    for (final node in [
      _backNode,
      _categoryNode,
      _viewNode,
      _listNode,
      _showNode,
      _sortNode,
      _orderNode,
      _filtersNode,
      _applyNode,
      _moreNode,
      _saveNode,
      _cloneNode,
      _randomNode,
    ]) {
      node.dispose();
    }
    super.dispose();
  }

  bool get _canContinueEmpty =>
      !_isCatalog &&
      _group != MdblistDiscoverGroup.library &&
      _selected != null &&
      _visible.isEmpty &&
      !_page.exhausted;

  void _focusEntry() {
    if (!mounted) return;
    if (_canContinueEmpty) {
      _moreNode.requestFocus();
    } else if (_visible.isEmpty) {
      _backNode.requestFocus();
    } else {
      _gridKey.currentState?.focusFirst();
    }
  }

  Future<void> _switchGroup(MdblistDiscoverGroup group) async {
    if (group == _group) return;
    setState(() {
      _fetchToken++;
      _group = group;
      _show = group == MdblistDiscoverGroup.catalog
          ? (_catalogDraft.mediaType == 'show' ? 'series' : 'movie')
          : 'all';
      _sort = _Sort.natural;
      _choices = const [];
      _selected = null;
      _page = const MdblistDiscoverPage();
      _visible = const [];
      _errorKind = null;
      _menuPartial = false;
      _itemsLoading = false;
      _loadingMore = false;
      _menuLoading =
          group == MdblistDiscoverGroup.forYou ||
          group == MdblistDiscoverGroup.discover ||
          group == MdblistDiscoverGroup.lists;
      _catalogApplied = false;
      if (group == MdblistDiscoverGroup.discover) {
        _directory = MdblistListDirectory.official;
      } else if (group == MdblistDiscoverGroup.lists) {
        _directory = _searchResult == null
            ? MdblistListDirectory.mine
            : MdblistListDirectory.searchResult;
      }
    });
    switch (group) {
      case MdblistDiscoverGroup.library:
        await _loadLibrary();
      case MdblistDiscoverGroup.forYou:
        await _loadRecommendations();
      case MdblistDiscoverGroup.discover:
      case MdblistDiscoverGroup.lists:
        await _loadDirectory();
      case MdblistDiscoverGroup.catalog:
        break;
    }
  }

  Future<void> _selectLibrary(MdblistLibraryView view) async {
    if (view == _libraryView) return;
    setState(() {
      _libraryView = view;
      _show = 'all';
      _sort = _Sort.natural;
    });
    await _loadLibrary();
  }

  Future<void> _loadLibrary({bool force = false}) async {
    final token = ++_fetchToken;
    setState(() {
      _itemsLoading = true;
      _errorKind = null;
      _page = const MdblistDiscoverPage();
      _visible = const [];
    });
    final page = await _source.loadLibrary(_libraryView, force: force);
    if (!mounted || token != _fetchToken) return;
    _acceptPage(page);
  }

  Future<void> _loadRecommendations({bool force = false}) async {
    final token = ++_fetchToken;
    setState(() {
      _menuLoading = true;
      _itemsLoading = false;
      _errorKind = null;
      _menuPartial = false;
      _page = const MdblistDiscoverPage();
      _visible = const [];
    });
    final result = await _source.loadRecommendationChoices(force: force);
    if (!mounted || token != _fetchToken) return;
    if (!result.isUsable) {
      setState(() {
        _menuLoading = false;
        _errorKind = result.kind;
      });
      return;
    }
    final selected = result.choices.isEmpty ? null : result.choices.first;
    setState(() {
      _menuLoading = false;
      _choices = result.choices;
      _selected = selected;
      _menuPartial = result.kind == MdblistResultKind.partial;
    });
    if (selected != null) await _loadChoice(selected);
  }

  Future<void> _switchDirectory(MdblistListDirectory directory) async {
    if (directory == _directory) return;
    setState(() {
      _directory = directory;
      _show = 'all';
      _sort = _Sort.natural;
    });
    await _loadDirectory();
  }

  Future<void> _loadDirectory({bool force = false}) async {
    if (_directory == MdblistListDirectory.searchResult) {
      final found = _searchResult;
      setState(() {
        _menuLoading = false;
        _choices = found == null ? const [] : [found];
        _selected = found;
        _selectedLiked = found?.liked ?? false;
      });
      if (found != null) await _loadChoice(found);
      return;
    }
    final token = ++_fetchToken;
    setState(() {
      _menuLoading = true;
      _itemsLoading = false;
      _errorKind = null;
      _menuPartial = false;
      _choices = const [];
      _selected = null;
      _page = const MdblistDiscoverPage();
      _visible = const [];
    });
    final result = await _source.loadDirectory(_directory, force: force);
    if (!mounted || token != _fetchToken) return;
    if (!result.isUsable) {
      setState(() {
        _menuLoading = false;
        _errorKind = result.kind;
      });
      return;
    }
    final selected = result.choices.isEmpty ? null : result.choices.first;
    setState(() {
      _menuLoading = false;
      _choices = result.choices;
      _selected = selected;
      _selectedLiked = selected?.liked ?? false;
      _menuPartial = result.kind == MdblistResultKind.partial;
    });
    if (selected != null) await _loadChoice(selected);
  }

  Future<void> _selectChoice(MdblistDiscoverChoice choice) async {
    if (choice == _selected) return;
    setState(() {
      _selected = choice;
      _selectedLiked = choice.liked;
      _show = 'all';
      _sort = _Sort.natural;
    });
    await _loadChoice(choice);
  }

  Future<void> _loadChoice(MdblistDiscoverChoice choice) async {
    final token = ++_fetchToken;
    setState(() {
      _itemsLoading = true;
      _loadingMore = false;
      _errorKind = null;
      _page = const MdblistDiscoverPage();
      _visible = const [];
    });
    final page = await _source.loadChoice(choice);
    if (!mounted || token != _fetchToken || choice != _selected) return;
    _acceptPage(page);
  }

  Future<void> _loadMoreChoice() async {
    final choice = _selected;
    final cursor = _page.nextCursor;
    if (choice == null || cursor == null || _loadingMore) return;
    final token = _fetchToken;
    final restoreFocus = _moreNode.hasFocus;
    setState(() => _loadingMore = true);
    final next = await _source.loadChoice(choice, cursor: cursor);
    if (!mounted || choice != _selected || token != _fetchToken) return;
    if (!next.isUsable) {
      setState(() {
        _loadingMore = false;
        _page = _page.copyWith(kind: MdblistResultKind.partial);
      });
      return;
    }
    final merged = _dedup([..._page.items, ...next.items]);
    setState(() {
      _loadingMore = false;
      _page = MdblistDiscoverPage(
        items: merged,
        progressByImdb: {..._page.progressByImdb, ...next.progressByImdb},
        kind: next.kind,
        nextCursor: next.nextCursor,
      );
      _recompute();
    });
    if (restoreFocus && widget.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || token != _fetchToken) return;
        if (_visible.isNotEmpty) {
          _gridKey.currentState?.focusFirst();
        } else if (_canContinueEmpty) {
          _moreNode.requestFocus();
        } else {
          _gridExitNode.requestFocus();
        }
      });
    }
  }

  void _acceptPage(MdblistDiscoverPage page) {
    setState(() {
      _itemsLoading = false;
      _page = page;
      _errorKind = page.isUsable ? null : page.kind;
      _recompute();
    });
    if (widget.isTelevision && _visible.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        (_canContinueEmpty ? _moreNode : _gridExitNode).requestFocus();
      });
    }
  }

  bool get _hidesWatched {
    if (_isCatalog || _group == MdblistDiscoverGroup.forYou) return true;
    if (_group == MdblistDiscoverGroup.library || _selectedLiked) return false;
    return switch (_directory) {
      MdblistListDirectory.mine || MdblistListDirectory.liked => false,
      MdblistListDirectory.searchResult => _searchResultIsPublic,
      _ => true,
    };
  }

  void _recompute() {
    Iterable<StremioMeta> items = _page.items;
    if (_hidesWatched) items = items.where((m) => !WatchedFilter.hides(m));
    if (!_isCatalog) {
      if (_show == 'movie') {
        items = items.where((item) => item.type != 'series');
      } else if (_show == 'series') {
        items = items.where((item) => item.type == 'series');
      }
    }
    final visible = items.toList();
    switch (_sort) {
      case _Sort.natural:
        break;
      case _Sort.az:
        visible.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.za:
        visible.sort(
          (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()),
        );
      case _Sort.newest:
        visible.sort((a, b) => (b.addedAtMs ?? 0).compareTo(a.addedAtMs ?? 0));
      case _Sort.oldest:
        visible.sort((a, b) => (a.addedAtMs ?? 0).compareTo(b.addedAtMs ?? 0));
    }
    _visible = visible;
  }

  void _setShow(String value) {
    setState(() {
      _show = value;
      if (_isCatalog) {
        _fetchToken++;
        _loadingMore = false;
        _catalogDraft = _catalogDraft.copyWith(
          mediaType: value == 'series' ? 'show' : 'movie',
        );
        _catalogApplied = false;
        _page = const MdblistDiscoverPage();
        _visible = const [];
        _errorKind = null;
      } else {
        _recompute();
      }
    });
  }

  void _setSort(_Sort value) {
    setState(() {
      _sort = value;
      _recompute();
    });
    if (widget.embedded) {
      unawaited(DiscoverPrefs.setEnumSort(DiscoverPrefs.mdblist, value));
    }
  }

  void _setCatalogSort(String value) {
    setState(() {
      _fetchToken++;
      _loadingMore = false;
      _catalogDraft = _catalogDraft.copyWith(sort: value);
      _catalogApplied = false;
      _page = const MdblistDiscoverPage();
      _visible = const [];
      _errorKind = null;
    });
  }

  void _setCatalogOrder(String value) {
    setState(() {
      _fetchToken++;
      _loadingMore = false;
      _catalogDraft = _catalogDraft.copyWith(sortOrder: value);
      _catalogApplied = false;
      _page = const MdblistDiscoverPage();
      _visible = const [];
      _errorKind = null;
    });
  }

  Future<void> _applyCatalog() async {
    if (_itemsLoading) return;
    final validationError = _catalogDraft.validationError;
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationError),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }
    final query = _catalogDraft.normalized;
    final token = ++_fetchToken;
    setState(() {
      _catalogDraft = query;
      _itemsLoading = true;
      _errorKind = null;
      _page = const MdblistDiscoverPage();
      _visible = const [];
    });
    final page = await _source.applyCatalog(query);
    if (!mounted || token != _fetchToken) return;
    setState(() => _catalogApplied = true);
    _acceptPage(page);
  }

  Future<void> _loadMoreCatalog() async {
    if (_loadingMore || _page.exhausted) return;
    final token = _fetchToken;
    final query = _catalogDraft.normalized;
    setState(() => _loadingMore = true);
    final page = await _source.loadMoreCatalog(query, _page);
    if (!mounted ||
        token != _fetchToken ||
        !_isCatalog ||
        query.cacheKey != _catalogDraft.normalized.cacheKey) {
      return;
    }
    setState(() {
      _loadingMore = false;
      _page = page;
      _recompute();
    });
  }

  Future<void> _openCatalogFilters() async {
    var draft = _catalogDraft;
    final genre = TextEditingController(text: draft.genre ?? '');
    final country = TextEditingController(text: draft.country ?? '');
    final language = TextEditingController(text: draft.language ?? '');
    final scoreMin = TextEditingController(
      text: draft.scoreMin?.toString() ?? '',
    );
    final scoreMax = TextEditingController(
      text: draft.scoreMax?.toString() ?? '',
    );
    final yearMin = TextEditingController(
      text: draft.yearMin?.toString() ?? '',
    );
    final yearMax = TextEditingController(
      text: draft.yearMax?.toString() ?? '',
    );
    final releasedFrom = TextEditingController(text: draft.releasedFrom ?? '');
    final releasedTo = TextEditingController(text: draft.releasedTo ?? '');
    final runtimeMax = TextEditingController(
      text: draft.runtimeMax?.toString() ?? '',
    );
    final runtimeMin = TextEditingController(
      text: draft.runtimeMin?.toString() ?? '',
    );
    final result = await showDialog<MdblistCatalogQuery>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('MDBList Catalog Filters'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: draft.mediaType,
                    decoration: const InputDecoration(labelText: 'Media type'),
                    items: const [
                      DropdownMenuItem(value: 'movie', child: Text('Movies')),
                      DropdownMenuItem(value: 'show', child: Text('Series')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(
                          () => draft = draft.copyWith(mediaType: value),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: genre,
                    decoration: const InputDecoration(
                      labelText: 'Genre',
                      hintText: 'e.g. Horror',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: releasedFrom,
                          decoration: const InputDecoration(
                            labelText: 'Released from',
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: releasedTo,
                          decoration: const InputDecoration(
                            labelText: 'Released to',
                            hintText: 'YYYY-MM-DD',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: country,
                          decoration: const InputDecoration(
                            labelText: 'Country code',
                            hintText: 'US',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: language,
                          decoration: const InputDecoration(
                            labelText: 'Language code',
                            hintText: 'en',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: yearMin,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Year from',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: yearMax,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Year to',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: scoreMin,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum score (0–100)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: scoreMax,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Maximum score (0–100)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: runtimeMin,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Minimum runtime',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: runtimeMax,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Maximum runtime',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                MdblistCatalogQuery(
                  mediaType: draft.mediaType,
                  sort: draft.sort,
                  sortOrder: draft.sortOrder,
                ),
              ),
              child: const Text('Reset'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                context,
                MdblistCatalogQuery(
                  mediaType: draft.mediaType,
                  genre: genre.text,
                  country: country.text,
                  language: language.text,
                  scoreMin: int.tryParse(scoreMin.text),
                  scoreMax: int.tryParse(scoreMax.text),
                  yearMin: int.tryParse(yearMin.text),
                  yearMax: int.tryParse(yearMax.text),
                  releasedFrom: releasedFrom.text,
                  releasedTo: releasedTo.text,
                  runtimeMin: int.tryParse(runtimeMin.text),
                  runtimeMax: int.tryParse(runtimeMax.text),
                  sort: draft.sort,
                  sortOrder: draft.sortOrder,
                ),
              ),
              child: const Text('Use Filters'),
            ),
          ],
        ),
      ),
    );
    genre.dispose();
    country.dispose();
    language.dispose();
    scoreMin.dispose();
    scoreMax.dispose();
    yearMin.dispose();
    yearMax.dispose();
    releasedFrom.dispose();
    releasedTo.dispose();
    runtimeMax.dispose();
    runtimeMin.dispose();
    if (!mounted || result == null) return;
    setState(() {
      _fetchToken++;
      _loadingMore = false;
      _catalogDraft = result;
      _show = result.mediaType == 'show' ? 'series' : 'movie';
      _catalogApplied = false;
      _page = const MdblistDiscoverPage();
      _visible = const [];
      _errorKind = null;
    });
  }

  Future<void> _toggleLike() async {
    final id = _selected?.numericId;
    if (id == null || _saveBusy) return;
    final wasLiked = _selectedLiked;
    setState(() => _saveBusy = true);
    final ok = wasLiked
        ? await _source.service.unlikeList(id)
        : await _source.service.likeList(id);
    if (!mounted) return;
    setState(() {
      _saveBusy = false;
      if (ok) _selectedLiked = !wasLiked;
    });
    if (ok) _source.invalidateListDirectories();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (wasLiked ? 'Removed from Liked Lists' : 'Added to Liked Lists')
              : "Couldn't update Liked Lists",
        ),
        backgroundColor: ok ? null : Colors.red.shade700,
      ),
    );
  }

  Future<void> _cloneList() async {
    final selected = _selected;
    if (selected?.numericId == null || _cloneBusy) return;
    setState(() => _cloneBusy = true);
    final id = await _source.service.saveListAsClone(
      sourceListId: selected!.numericId!,
      name: selected.label,
    );
    if (!mounted) return;
    setState(() => _cloneBusy = false);
    if (id != null) _source.invalidateListDirectories();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          id == null
              ? "Couldn't clone the list"
              : 'Cloned "${selected.label}" to My Lists',
        ),
        backgroundColor: id == null ? Colors.red.shade700 : null,
      ),
    );
  }

  void _playRandom() {
    final play = widget.onQuickPlay;
    if (play == null || _visible.isEmpty) return;
    AnalyticsService.trackInBackground('discover_random_play', {
      'source': 'mdblist',
    });
    play(_visible[_random.nextInt(_visible.length)]);
  }

  KeyEventResult _handleFilterKeys(FocusNode _, KeyEvent event) {
    if (!widget.isTelevision) return KeyEventResult.ignored;
    return handleSeeAllFilterArrows(
      event,
      _filterNodes,
      onDown: () => _canContinueEmpty
          ? _moreNode.requestFocus()
          : _gridKey.currentState?.focusFirst(),
      onUp: () {
        if (!widget.embedded) _backNode.requestFocus();
      },
      onLeftEdge: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
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
              title: 'MDBList',
              subtitle: _subtitle(),
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

  String _subtitle() {
    if (_itemsLoading) return '${_activeLabel()} · Loading…';
    final count = _visible.length;
    return '${_activeLabel()} · $count ${count == 1 ? 'title' : 'titles'}';
  }

  String _activeLabel() {
    if (_isCatalog) return 'Catalog';
    if (_group == MdblistDiscoverGroup.library) return _libraryView.label;
    return _selected?.label ?? _group.label;
  }

  Widget _buildFilterBar() => Focus(
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
        trailing: _buildTrailing(),
        buildChips: () => [
          if (_connected) ...[
            StremioDropdown<MdblistDiscoverGroup>(
              label: 'Category',
              value: _group,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _categoryNode,
              options: [
                for (final group in MdblistDiscoverGroup.values)
                  StremioDropdownOption(group, group.label),
              ],
              onSelected: _switchGroup,
            ),
            ..._buildViewControls(),
            StremioDropdown<String>(
              label: 'Show',
              value: _show,
              isTelevision: widget.isTelevision,
              quiet: _quiet,
              focusNode: _showNode,
              options: _isCatalog
                  ? const [
                      StremioDropdownOption('movie', 'Movies'),
                      StremioDropdownOption('series', 'Series'),
                    ]
                  : const [
                      StremioDropdownOption('all', 'All'),
                      StremioDropdownOption('movie', 'Movies'),
                      StremioDropdownOption('series', 'Series'),
                    ],
              onSelected: _setShow,
            ),
            if (_isCatalog)
              StremioDropdown<String>(
                label: 'Sort',
                value: _catalogDraft.sort,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _sortNode,
                options: const [
                  StremioDropdownOption('score', 'MDBList Score'),
                  StremioDropdownOption('imdbpopular', 'IMDb Popular'),
                  StremioDropdownOption('imdbrating', 'IMDb Rating'),
                  StremioDropdownOption('imdbvotes', 'IMDb Votes'),
                  StremioDropdownOption('letterrating', 'Letterboxd Rating'),
                  StremioDropdownOption('metacritic', 'Metacritic'),
                  StremioDropdownOption('rtaudience', 'RT Audience'),
                  StremioDropdownOption('rtomatoes', 'RT Critics'),
                  StremioDropdownOption('tmdbpopular', 'TMDB Popular'),
                  StremioDropdownOption('released', 'Release Date'),
                  StremioDropdownOption('releasedigital', 'Digital Release'),
                  StremioDropdownOption('score_average', 'Average Score'),
                  StremioDropdownOption('title', 'Title'),
                ],
                onSelected: _setCatalogSort,
              )
            else
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
                  StremioDropdownOption(_Sort.newest, 'Newest Activity'),
                  StremioDropdownOption(_Sort.oldest, 'Oldest Activity'),
                ],
                onSelected: _setSort,
              ),
            if (_isCatalog)
              StremioDropdown<String>(
                label: 'Order',
                value: _catalogDraft.sortOrder,
                isTelevision: widget.isTelevision,
                quiet: _quiet,
                focusNode: _orderNode,
                options: const [
                  StremioDropdownOption('desc', 'Descending'),
                  StremioDropdownOption('asc', 'Ascending'),
                ],
                onSelected: _setCatalogOrder,
              ),
          ],
        ],
      ),
    ),
  );

  List<Widget> _buildViewControls() {
    if (_group == MdblistDiscoverGroup.library) {
      return [
        StremioDropdown<MdblistLibraryView>(
          label: 'View',
          value: _libraryView,
          isTelevision: widget.isTelevision,
          quiet: _quiet,
          focusNode: _viewNode,
          options: [
            for (final view in MdblistLibraryView.values)
              StremioDropdownOption(view, view.label),
          ],
          onSelected: _selectLibrary,
        ),
      ];
    }
    if (_group == MdblistDiscoverGroup.forYou) {
      if (_selected == null) return const [];
      return [
        StremioDropdown<MdblistDiscoverChoice>(
          label: 'View',
          value: _selected!,
          isTelevision: widget.isTelevision,
          quiet: _quiet,
          focusNode: _viewNode,
          options: [
            for (final choice in _choices)
              StremioDropdownOption(choice, choice.displayLabel),
          ],
          onSelected: _selectChoice,
        ),
      ];
    }
    if (_group == MdblistDiscoverGroup.discover ||
        _group == MdblistDiscoverGroup.lists) {
      final directories = _group == MdblistDiscoverGroup.discover
          ? const [
              MdblistListDirectory.official,
              MdblistListDirectory.curated,
              MdblistListDirectory.top,
            ]
          : [
              MdblistListDirectory.mine,
              MdblistListDirectory.liked,
              MdblistListDirectory.external,
              if (_searchResult != null) MdblistListDirectory.searchResult,
            ];
      return [
        StremioDropdown<MdblistListDirectory>(
          label: 'View',
          value: _directory,
          isTelevision: widget.isTelevision,
          quiet: _quiet,
          focusNode: _viewNode,
          options: [
            for (final directory in directories)
              StremioDropdownOption(directory, directory.label),
          ],
          onSelected: _switchDirectory,
        ),
        if (_selected != null)
          StremioDropdown<MdblistDiscoverChoice>(
            label: 'List',
            value: _selected!,
            isTelevision: widget.isTelevision,
            quiet: _quiet,
            focusNode: _listNode,
            options: [
              for (final choice in _choices)
                StremioDropdownOption(choice, choice.displayLabel),
            ],
            onSelected: _selectChoice,
          ),
      ];
    }
    return const [];
  }

  int get _activeFilterCount {
    var count = 0;
    if (_show != (_isCatalog ? 'movie' : 'all')) count++;
    if (_sort != _Sort.natural ||
        (_isCatalog &&
            (_catalogDraft.sort != 'score' ||
                _catalogDraft.sortOrder != 'desc'))) {
      count++;
    }
    if (_isCatalog && _hasCatalogFilters) count++;
    return count;
  }

  bool get _hasCatalogFilters =>
      _catalogDraft.genre?.trim().isNotEmpty == true ||
      _catalogDraft.country?.trim().isNotEmpty == true ||
      _catalogDraft.language?.trim().isNotEmpty == true ||
      _catalogDraft.scoreMin != null ||
      _catalogDraft.scoreMax != null ||
      _catalogDraft.yearMin != null ||
      _catalogDraft.yearMax != null ||
      _catalogDraft.releasedFrom != null ||
      _catalogDraft.releasedTo != null ||
      _catalogDraft.runtimeMin != null ||
      _catalogDraft.runtimeMax != null;

  Widget? _buildTrailing() {
    final actions = <Widget>[
      if (_isCatalog)
        OutlinedButton.icon(
          focusNode: _filtersNode,
          onPressed: _openCatalogFilters,
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: const Text('Filters'),
        ),
      if (_isCatalog)
        FilledButton.icon(
          focusNode: _applyNode,
          onPressed: _catalogCanApply ? _applyCatalog : null,
          icon: _itemsLoading
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search_rounded, size: 16),
          label: Text(_catalogApplied ? 'Reapply' : 'Apply'),
        ),
      if (_isCatalog && !_page.exhausted)
        OutlinedButton.icon(
          focusNode: _moreNode,
          onPressed: _catalogCanLoadMore ? _loadMoreCatalog : null,
          icon: _loadingMore
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.expand_more_rounded, size: 16),
          label: const Text('More'),
        ),
      if (_canLike)
        MdblistSaveButton(
          quiet: _quiet,
          saved: _selectedLiked,
          busy: _saveBusy,
          focusNode: _saveNode,
          onPressed: _toggleLike,
        ),
      if (_canClone)
        OutlinedButton.icon(
          focusNode: _cloneNode,
          onPressed: _cloneBusy ? null : _cloneList,
          icon: _cloneBusy
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Clone'),
        ),
      if (_showRandom && _page.items.isNotEmpty)
        SeeAllRandomButton(
          quiet: _quiet,
          enabled: _visible.isNotEmpty,
          focusNode: _randomNode,
          onPressed: _playRandom,
        ),
    ];
    if (actions.isEmpty) return null;
    if (actions.length == 1) return actions.single;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          if (index > 0) SizedBox(width: _quiet ? 6 : 8),
          actions[index],
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_menuLoading || _itemsLoading) {
      return SkeletonPosterGrid(isTelevision: widget.isTelevision);
    }
    if (!_connected) return _buildEmpty();
    if (_visible.isEmpty) {
      final status = <String>[
        if (_menuPartial) 'Some MDBList menu results could not be refreshed',
        if (_page.kind == MdblistResultKind.partial)
          'Showing retained or partial MDBList results',
      ];
      if (status.isEmpty && !_canContinueEmpty) return _buildEmpty();
      return Column(
        children: [
          for (final message in status) _statusStrip(message),
          Expanded(child: _buildEmpty()),
          if (_canContinueEmpty)
            SafeArea(
              top: false,
              child: Focus(
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowUp) {
                    _gridExitNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextButton(
                  focusNode: _moreNode,
                  onPressed: _loadingMore ? null : _loadMoreChoice,
                  child: Text(_loadingMore ? 'Loading…' : 'Continue loading'),
                ),
              ),
            ),
        ],
      );
    }
    final grid = SeeAllPosterGrid(
      key: _gridKey,
      items: _visible,
      isTelevision: widget.isTelevision,
      loadingMore: _loadingMore,
      exhausted: _isCatalog ? true : _page.exhausted,
      onOpen: widget.onOpen,
      onQuickPlay: widget.onQuickPlay,
      onItemFocused: widget.onItemFocused,
      progressOf: (item) => _page.progressByImdb[item.imdbId],
      isBound: widget.isBound,
      onLoadMore: _isCatalog ? () {} : _loadMoreChoice,
      onExitTop: widget.isTelevision
          ? () => _gridExitNode.requestFocus()
          : null,
      onExitLeft: widget.embedded
          ? () => MainPageBridge.focusTvSidebar?.call()
          : null,
    );
    final status = <String>[
      if (_menuPartial) 'Some MDBList menu results could not be refreshed',
      if (_page.kind == MdblistResultKind.partial)
        'Showing retained or partial MDBList results',
      if (_isCatalog) _quotaLabel(),
    ];
    if (status.isEmpty) return grid;
    return Column(
      children: [
        for (final message in status) _statusStrip(message),
        Expanded(child: grid),
      ],
    );
  }

  Widget _buildEmpty() {
    final app = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _errorKind == null
                  ? Icons.inbox_rounded
                  : Icons.cloud_off_rounded,
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
            if (_isCatalog) ...[
              const SizedBox(height: 8),
              Text(
                _quotaLabel(),
                style: TextStyle(
                  color: app.fade(app.core.tx, 0.5),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusStrip(String text) {
    final app = AppThemeScope.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      color: app.fade(app.seeAll.accent, 0.12),
      child: Text(
        text,
        style: TextStyle(
          color: app.fade(app.core.tx, 0.72),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _emptyMessage() {
    if (!_connected) return 'Connect MDBList in Settings to browse it';
    final error = _errorKind;
    if (error != null) {
      return switch (error) {
        MdblistResultKind.denied =>
          'This MDBList view is not available on your current plan',
        MdblistResultKind.rateLimited =>
          _isCatalog
              ? 'MDBList Catalog query quota is exhausted'
              : 'MDBList rate limit reached — try again later',
        MdblistResultKind.unauthenticated => 'Reconnect MDBList in Settings',
        _ => "Couldn't load ${_activeLabel()} from MDBList",
      };
    }
    if (_isCatalog && !_catalogApplied) {
      return 'Choose filters and press Apply — Catalog never runs automatically';
    }
    if (_page.items.isNotEmpty) return 'Nothing matches these filters';
    if (_group == MdblistDiscoverGroup.forYou && _selected == null) {
      return 'No recommendation sections are available for this account';
    }
    if ((_group == MdblistDiscoverGroup.discover ||
            _group == MdblistDiscoverGroup.lists) &&
        _selected == null) {
      return 'No ${_directory.label.toLowerCase()} available';
    }
    if (_group == MdblistDiscoverGroup.library &&
        _libraryView == MdblistLibraryView.continueWatching) {
      return 'Nothing to continue yet';
    }
    return 'Nothing in ${_activeLabel()}';
  }

  String _quotaLabel() {
    final quota = _page.quota ?? _source.catalogQuota;
    final remaining = quota?.remaining;
    if (remaining == null) return 'Catalog quota appears after the first Apply';
    final expiry = quota?.firstExpiresAt;
    final reset = expiry == null
        ? ''
        : ' · next slot ${expiry.toLocal().toString().split('.').first}';
    return '$remaining catalog ${remaining == 1 ? 'query' : 'queries'} remaining$reset';
  }

  List<StremioMeta> _dedup(Iterable<StremioMeta> items) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (seen.add((item.imdbId ?? item.id).toLowerCase())) item,
    ];
  }
}
