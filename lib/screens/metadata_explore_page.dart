import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/metadata_preferences.dart';
import '../models/stremio_addon.dart';
import '../services/collection_native_source_service.dart';
import '../services/metadata_details_service.dart';
import '../services/metadata_explore_service.dart';
import '../services/metadata_preferences_service.dart';
import '../services/main_page_bridge.dart';
import '../services/profiles/profile_runtime.dart';
import '../widgets/catalog_item_tile.dart';
import '../widgets/metadata_explore_spotlight.dart';
import '../widgets/metadata_title_navigation.dart';
import '../widgets/see_all/see_all_filter_bar.dart';
import '../widgets/see_all/see_all_filter_focus.dart';
import '../widgets/see_all/see_all_poster_grid.dart';
import '../widgets/see_all/stremio_dropdown.dart';

/// Original-language filters shared by standalone and embedded TMDB browsing.
const _metadataBrowseLanguages = <StremioDropdownOption<String>>[
  StremioDropdownOption('', 'All languages'),
  StremioDropdownOption('ar', 'Arabic'),
  StremioDropdownOption('as', 'Assamese'),
  StremioDropdownOption('bn', 'Bengali'),
  StremioDropdownOption('bg', 'Bulgarian'),
  StremioDropdownOption('my', 'Burmese'),
  StremioDropdownOption('ca', 'Catalan'),
  StremioDropdownOption('zh', 'Chinese'),
  StremioDropdownOption('hr', 'Croatian'),
  StremioDropdownOption('cs', 'Czech'),
  StremioDropdownOption('da', 'Danish'),
  StremioDropdownOption('nl', 'Dutch'),
  StremioDropdownOption('en', 'English'),
  StremioDropdownOption('fi', 'Finnish'),
  StremioDropdownOption('fr', 'French'),
  StremioDropdownOption('de', 'German'),
  StremioDropdownOption('el', 'Greek'),
  StremioDropdownOption('gu', 'Gujarati'),
  StremioDropdownOption('he', 'Hebrew'),
  StremioDropdownOption('hi', 'Hindi'),
  StremioDropdownOption('hu', 'Hungarian'),
  StremioDropdownOption('is', 'Icelandic'),
  StremioDropdownOption('id', 'Indonesian'),
  StremioDropdownOption('it', 'Italian'),
  StremioDropdownOption('ja', 'Japanese'),
  StremioDropdownOption('kn', 'Kannada'),
  StremioDropdownOption('ko', 'Korean'),
  StremioDropdownOption('ms', 'Malay'),
  StremioDropdownOption('ml', 'Malayalam'),
  StremioDropdownOption('mr', 'Marathi'),
  StremioDropdownOption('ne', 'Nepali'),
  StremioDropdownOption('no', 'Norwegian'),
  StremioDropdownOption('or', 'Odia'),
  StremioDropdownOption('fa', 'Persian'),
  StremioDropdownOption('pl', 'Polish'),
  StremioDropdownOption('pt', 'Portuguese'),
  StremioDropdownOption('pa', 'Punjabi'),
  StremioDropdownOption('ro', 'Romanian'),
  StremioDropdownOption('ru', 'Russian'),
  StremioDropdownOption('sr', 'Serbian'),
  StremioDropdownOption('si', 'Sinhala'),
  StremioDropdownOption('sk', 'Slovak'),
  StremioDropdownOption('sl', 'Slovenian'),
  StremioDropdownOption('es', 'Spanish'),
  StremioDropdownOption('sv', 'Swedish'),
  StremioDropdownOption('tl', 'Tagalog'),
  StremioDropdownOption('ta', 'Tamil'),
  StremioDropdownOption('te', 'Telugu'),
  StremioDropdownOption('th', 'Thai'),
  StremioDropdownOption('tr', 'Turkish'),
  StremioDropdownOption('uk', 'Ukrainian'),
  StremioDropdownOption('ur', 'Urdu'),
  StremioDropdownOption('vi', 'Vietnamese'),
];

/// Optional detail destination, using the host's existing title-open action.
class MetadataExplorePage extends StatefulWidget {
  const MetadataExplorePage({
    super.key,
    required this.item,
    required this.preferences,
    required this.onOpen,
    this.isTelevision = false,
    this.service,
  });
  final MetadataExploreService? service;
  final StremioMeta item;
  final MetadataPreferences preferences;
  final ValueChanged<StremioMeta> onOpen;
  final bool isTelevision;
  @override
  State<MetadataExplorePage> createState() => _MetadataExplorePageState();
}

class _MetadataExplorePageState extends State<MetadataExplorePage> {
  MetadataExploreData? _data;
  Timer? _retryTimer;
  int _loadGeneration = 0;
  bool _loading = true;
  bool _failed = false;

  void _cancelLoad() {
    ++_loadGeneration;
    _retryTimer?.cancel();
    _retryTimer = null;
  }
  late MetadataPreferences _preferences;
  final _scope = ProfileRuntime.scope.value;
  int _policyGeneration = 0;
  bool _profileChanged = false;

  Future<void> _policyChanged() async {
    final generation = ++_policyGeneration;
    _cancelLoad();
    setState(() {
      _data = null;
      _loading = true;
      _failed = false;
    });
    if (_scope != ProfileRuntime.scope.value) {
      setState(() => _profileChanged = true);
      return;
    }
    try {
      final preferences = await MetadataPreferencesService.load();
      if (!mounted || generation != _policyGeneration) return;
      setState(() {
        _preferences = preferences;
        _reload();
      });
    } catch (_) {
      if (mounted && generation == _policyGeneration) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _cancelLoad();
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    ProfileRuntime.scope.removeListener(_policyChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences;
    MetadataPreferencesService.revision.addListener(_policyChanged);
    ProfileRuntime.scope.addListener(_policyChanged);
    _reload();
  }

  void _reload() {
    _cancelLoad();
    _loading = true;
    _failed = false;
    _attemptLoad(_loadGeneration, 0);
  }

  Future<void> _attemptLoad(int generation, int attempt) async {
    bool current() => mounted && !_profileChanged &&
        _scope == ProfileRuntime.scope.value && generation == _loadGeneration;
    if (!current()) return;
    try {
      final data = await (widget.service ?? MetadataExploreService.instance)
          .details(widget.item, _preferences);
      if (!current()) return;
      setState(() => _data = data);
      if (data.unavailable.isEmpty) {
        setState(() => _loading = false);
        return;
      }
    } catch (_) {
      if (!current()) return;
    }
    if (attempt < 2) {
      _retryTimer = Timer(Duration(seconds: 1 << attempt), () {
        _retryTimer = null;
        if (current()) _attemptLoad(generation, attempt + 1);
      });
    } else {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _entity(String kind, Map<String, dynamic> row) {
    if (!mounted || _profileChanged || _scope != ProfileRuntime.scope.value) return;
    final id = MetadataDetailsService.positiveId(row['id']);
    if (id == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MetadataBrowsePage(
          title: MetadataDetailsService.text(row['name']) ?? 'Browse',
          kind: kind,
          id: id,
          preferences: _preferences,
          onOpen: widget.onOpen,
          isTelevision: widget.isTelevision,
          type: widget.item.type == 'series' ? 'tv' : 'movie',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_profileChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('Explore')),
        body: const Center(child: Text(
          'Profile changed. Go back to browse your current profile.',
        )),
      );
    }
    return MetadataExploreSpotlight(
      item: widget.item,
      preferences: _preferences,
      data: _data,
      loading: _loading,
      failed: _failed,
      isTelevision: widget.isTelevision,
      onRetry: () => setState(_reload),
      onEntity: _entity,
      titleBuilder: (item, focusNode) => _MetadataTitleTile(
        focusNode: focusNode,
        item: item, onOpen: widget.onOpen, isTelevision: widget.isTelevision,
      ),
      onDiscover: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MetadataBrowsePage(
          title: 'Discover', kind: 'discover', preferences: _preferences,
          onOpen: widget.onOpen, isTelevision: widget.isTelevision,
        ),
      )),
    );
  }
}

class MetadataBrowsePage extends StatefulWidget {
  const MetadataBrowsePage({
    super.key,
    required this.title,
    required this.kind,
    required this.preferences,
    required this.onOpen,
    this.id,
    this.type = 'movie',
    this.isTelevision = false,
    this.service,
    this.embedded = false,
    this.leading,
    this.leadingNode,
    this.onItemFocused,
    this.isBound,
  });
  final MetadataExploreService? service;
  final String title, kind, type;

  /// Discover supplies the Source dropdown and owns the surrounding page.
  final bool embedded;
  final Widget? leading;
  final FocusNode? leadingNode;
  final ValueChanged<StremioMeta>? onItemFocused;
  final bool Function(StremioMeta)? isBound;
  final int? id;
  final MetadataPreferences preferences;
  final ValueChanged<StremioMeta> onOpen;
  final bool isTelevision;
  @override
  State<MetadataBrowsePage> createState() => _MetadataBrowsePageState();
}

class _MetadataBrowsePageState extends State<MetadataBrowsePage> {
  final _gridKey = GlobalKey<SeeAllPosterGridState>();
  final _typeNode = FocusNode(debugLabel: 'tmdb_type');
  final _runtimeNode = FocusNode(debugLabel: 'tmdb_runtime');
  final _languageNode = FocusNode(debugLabel: 'tmdb_language');
  final _retryNode = FocusNode(debugLabel: 'tmdb_retry');
  bool _opening = false;
  final _items = <StremioMeta>[];
  final _scroll = ScrollController();
  Timer? _retryTimer;
  int _retryCount = 0;

  void _nearEnd() {
    if (!mounted ||
        _profileChanged ||
        _busy ||
        !_more ||
        _error != null ||
        _retryTimer != null ||
        !_scroll.hasClients) {
      return;
    }
    if (_scroll.position.extentAfter < _scroll.position.viewportDimension) {
      _load();
    }
  }

  void _focused(int index) {
    if (index >= _items.length - 8 &&
        !_busy &&
        _more &&
        _error == null &&
        _retryTimer == null) {
      _load();
    }
  }

  int _page = 0, _generation = 0;
  bool _busy = false, _more = true;
  String? _error, _description;
  late String _type;
  bool _short = false;
  String _language = '';
  late MetadataPreferences _preferences;
  final _scope = ProfileRuntime.scope.value;
  bool _profileChanged = false;
  int _policyGeneration = 0;

  Future<void> _policyChanged() async {
    final generation = ++_policyGeneration;
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (_scope != ProfileRuntime.scope.value) {
      setState(() {
        _profileChanged = true;
        _items.clear();
      });
      return;
    }
    setState(() {
      _items.clear();
      _busy = true;
    });
    try {
      final prefs = await MetadataPreferencesService.load();
      if (!mounted || generation != _policyGeneration) return;
      _preferences = prefs;
      await _load(reset: true);
    } catch (_) {
      if (mounted && generation == _policyGeneration) {
        setState(() {
          _busy = false;
          _error = 'Could not load preferences. Go back and retry.';
        });
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _scroll.dispose();
    _typeNode.dispose();
    _runtimeNode.dispose();
    _languageNode.dispose();
    _retryNode.dispose();
    MetadataPreferencesService.revision.removeListener(_policyChanged);
    ProfileRuntime.scope.removeListener(_policyChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_nearEnd);
    _type = widget.type;
    _preferences = widget.preferences;
    MetadataPreferencesService.revision.addListener(_policyChanged);
    ProfileRuntime.scope.addListener(_policyChanged);
    _load();
  }

  Future<void> _load({bool reset = false, bool retry = false}) async {
    if (_profileChanged || (_busy && !reset)) return;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!retry) _retryCount = 0;
    if (reset) {
      _items.clear();
      _description = null;
      _page = 0;
      _more = true;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await (widget.service ?? MetadataExploreService.instance)
          .browse(
            kind: widget.kind,
            id: widget.id,
            preferences: _preferences,
            type: _type,
            page: _page + 1,
            filters: {
              if (_short) 'with_runtime.lte': '120',
              if (_language.isNotEmpty) 'with_original_language': _language,
            },
          );
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = _items.map((i) => '${i.type}:${i.id}').toSet();
        _items.addAll(result.items.where((i) => seen.add('${i.type}:${i.id}')));
        _page++;
        _more = result.hasMore;
        _description = result.description;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        if (_retryCount < 2) {
          final delay = Duration(seconds: 1 << _retryCount++);
          _retryTimer = Timer(delay, () {
            _retryTimer = null;
            if (mounted && generation == _generation && !_profileChanged) {
              _load(retry: true);
            }
          });
        } else {
          setState(() => _error = 'Could not load titles. Retry');
        }
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
        if (_retryTimer == null && _error == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || generation != _generation) return;
            if (widget.embedded && _items.isEmpty && _more) {
              _load();
            } else {
              _nearEnd();
            }
          });
        }
      }
    }
  }

  Future<void> _openEmbeddedTitle(StremioMeta item) async {
    if (_opening || _profileChanged || _scope != ProfileRuntime.scope.value) {
      return;
    }
    _opening = true;
    try {
      await openMetadataTitle(context, item, widget.onOpen);
    } finally {
      _opening = false;
    }
  }

  void _focusResults() {
    if (_items.isEmpty && _error != null) {
      _retryNode.requestFocus();
    } else {
      _gridKey.currentState?.focusFirst();
    }
  }

  Widget _buildLanguageDropdown({bool quiet = false}) => StremioDropdown<String>(
    label: 'Language',
    value: _language,
    quiet: quiet,
    isTelevision: widget.isTelevision,
    focusNode: _languageNode,
    options: _metadataBrowseLanguages,
    onSelected: (value) {
      _language = value;
      _load(reset: true);
    },
  );

  Widget _buildEmbedded() {
    final quiet = widget.isTelevision;
    final filters = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => !widget.isTelevision
          ? KeyEventResult.ignored
          : handleSeeAllFilterArrows(
              event,
              [
                if (widget.leadingNode != null) widget.leadingNode!,
                _typeNode,
                _runtimeNode,
                _languageNode,
              ],
              onDown: _focusResults,
              onUp: () {},
              onLeftEdge: () => MainPageBridge.focusTvSidebar?.call(),
            ),
      child: Padding(
        padding: quiet
            ? const EdgeInsets.fromLTRB(24, 16, 24, 10)
            : const EdgeInsets.fromLTRB(24, 10, 24, 12),
        child: SeeAllFilterBar(
          isTelevision: widget.isTelevision,
          quiet: quiet,
          leading: widget.leading,
          activeCount:
              (_type == 'tv' ? 1 : 0) +
              (_short ? 1 : 0) +
              (_language.isNotEmpty ? 1 : 0),
          buildChips: () => [
            StremioDropdown<String>(
              label: 'Type',
              value: _type,
              quiet: quiet,
              isTelevision: widget.isTelevision,
              focusNode: _typeNode,
              options: const [
                StremioDropdownOption('movie', 'Movies'),
                StremioDropdownOption('tv', 'TV shows'),
              ],
              onSelected: (value) {
                _type = value;
                _load(reset: true);
              },
            ),
            StremioDropdown<bool>(
              label: 'Runtime',
              value: _short,
              quiet: quiet,
              isTelevision: widget.isTelevision,
              focusNode: _runtimeNode,
              options: const [
                StremioDropdownOption(false, 'Any runtime'),
                StremioDropdownOption(true, 'Under two hours'),
              ],
              onSelected: (value) {
                _short = value;
                _load(reset: true);
              },
            ),
            _buildLanguageDropdown(quiet: quiet),
          ],
        ),
      ),
    );
    final retry = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (widget.isTelevision &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_items.isEmpty) {
            (widget.leadingNode ?? _typeNode).requestFocus();
          } else {
            _gridKey.currentState?.focusFirst();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: TextButton(
        focusNode: _retryNode,
        onPressed: () {
          // Retry disappears while loading. Keep TV focus on a mounted control.
          if (widget.isTelevision && _retryNode.hasFocus) {
            (widget.leadingNode ?? _typeNode).requestFocus();
          }
          _load();
        },
        child: Text(_error ?? 'Retry'),
      ),
    );
    final waiting = _busy || _retryTimer != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        filters,
        Expanded(
          child: _profileChanged
              ? const Center(
                  child: Text('Profile changed. Reopen Discover to continue.'),
                )
              : _items.isEmpty
              ? Center(
                  child: waiting
                      ? const CircularProgressIndicator()
                      : _error != null
                      ? retry
                      : const Text('No matching titles'),
                )
              : Stack(
                  children: [
                    Positioned.fill(
                      child: SeeAllPosterGrid(
                        key: _gridKey,
                        items: List.of(_items),
                        isTelevision: widget.isTelevision,
                        loadingMore: waiting,
                        exhausted: !_more || _error != null,
                        onOpen: _openEmbeddedTitle,
                        onItemFocused: widget.onItemFocused,
                        isBound: widget.isBound,
                        onLoadMore: () {
                          if (_more && !waiting && _error == null) _load();
                        },
                        onExitTop: () =>
                            (widget.leadingNode ?? _typeNode).requestFocus(),
                        onExitLeft: () => MainPageBridge.focusTvSidebar?.call(),
                        onExitBottom: _error != null
                            ? _retryNode.requestFocus
                            : null,
                      ),
                    ),
                    if (_error != null)
                      Align(alignment: Alignment.bottomCenter, child: retry),
                  ],
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.embedded ? _buildEmbedded() : _buildStandalone();

  Widget _buildStandalone() => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: _profileChanged
        ? const Center(
            child: Text(
              'Profile changed. Go back to browse your current profile.',
            ),
          )
        : CustomScrollView(
            controller: _scroll,
            slivers: [
              if (_description?.isNotEmpty == true)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_description!),
                  ),
                ),
              if (widget.kind == 'discover')
                SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 12,
                    children: [
                      DropdownButton<String>(
                        value: _type,
                        items: const [
                          DropdownMenuItem(
                            value: 'movie',
                            child: Text('Movies'),
                          ),
                          DropdownMenuItem(
                            value: 'tv',
                            child: Text('TV shows'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          _type = v;
                          _load(reset: true);
                        },
                      ),
                      FilterChip(
                        label: const Text('Under two hours'),
                        selected: _short,
                        onSelected: (v) {
                          _short = v;
                          _load(reset: true);
                        },
                      ),
                      _buildLanguageDropdown(),
                    ],
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 2 / 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _MetadataTitleTile(
                      item: _items[i],
                      onFocused: () => _focused(i),
                      onOpen: widget.onOpen,
                      isTelevision: widget.isTelevision,
                    ),
                    childCount: _items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: _busy || _retryTimer != null
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        )
                      : _error != null
                      ? TextButton(onPressed: _load, child: Text(_error!))
                      : _more
                      ? const SizedBox(height: 40)
                      : _items.isEmpty
                      ? const Text('No matching titles')
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
  );
}

class _MetadataTitleTile extends StatefulWidget {
  const _MetadataTitleTile({
    required this.item,
    required this.onOpen,
    required this.isTelevision,
    this.onFocused,
    this.focusNode,
  });
  final FocusNode? focusNode;
  final VoidCallback? onFocused;
  final StremioMeta item;
  final ValueChanged<StremioMeta> onOpen;
  final bool isTelevision;
  @override
  State<_MetadataTitleTile> createState() => _MetadataTitleTileState();
}

class _MetadataTitleTileState extends State<_MetadataTitleTile> {
  final _focus = FocusNode();
  bool _opening = false;
  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (_opening) return;
    final scope = ProfileRuntime.scope.value;
    setState(() => _opening = true);
    try {
      final item = await CollectionNativeSourceService.instance
          .resolveIdentity(widget.item)
          .timeout(const Duration(seconds: 4), onTimeout: () => widget.item);
      if (mounted &&
          scope == ProfileRuntime.scope.value &&
          ModalRoute.of(context)?.isCurrent == true) {
        widget.onOpen(item);
      }
    } catch (_) {
      if (mounted && scope == ProfileRuntime.scope.value) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open this title. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: CatalogItemTile(
          item: widget.item,
          isTelevision: widget.isTelevision,
          focusNode: widget.focusNode ?? _focus,
          hasBoundSource: false,
          onOpen: _open,
          onFocused: widget.onFocused,
        ),
      ),
      if (_opening) const Center(child: CircularProgressIndicator()),
    ],
  );
}

class MetadataExploreButton extends StatefulWidget {
  const MetadataExploreButton({
    super.key,
    required this.item,
    required this.onOpen,
    required this.isTelevision,
  }) : discoveryOnly = false;

  const MetadataExploreButton.discover({
    super.key,
    required this.onOpen,
    required this.isTelevision,
  }) : item = null,
       discoveryOnly = true;

  final StremioMeta? item;
  final bool discoveryOnly;
  final ValueChanged<StremioMeta>? onOpen;
  final bool isTelevision;
  @override
  State<MetadataExploreButton> createState() => _MetadataExploreButtonState();
}

class _MetadataExploreButtonState extends State<MetadataExploreButton> {
  MetadataPreferences? _preferences;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    MetadataPreferencesService.revision.addListener(_load);
    ProfileRuntime.scope.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    MetadataPreferencesService.revision.removeListener(_load);
    ProfileRuntime.scope.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _preferences = null);
    try {
      final prefs = await MetadataPreferencesService.load();
      if (mounted && generation == _generation) {
        setState(() => _preferences = prefs);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final prefs = _preferences;
    if (prefs == null ||
        widget.onOpen == null ||
        (widget.discoveryOnly
            ? !prefs.features.contains(MetadataFeature.discovery)
            : prefs.features.isEmpty)) {
      return const SizedBox.shrink();
    }
    return FloatingActionButton.extended(
      heroTag: null,
      label: Text(widget.discoveryOnly ? 'TMDB Discover' : 'Explore'),
      icon: const Icon(Icons.explore_outlined),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => widget.discoveryOnly
              ? MetadataBrowsePage(
                  title: 'TMDB Discover',
                  kind: 'discover',
                  preferences: prefs,
                  onOpen: widget.onOpen!,
                  isTelevision: widget.isTelevision,
                )
              : MetadataExplorePage(
                  item: widget.item!,
                  preferences: prefs,
                  onOpen: widget.onOpen!,
                  isTelevision: widget.isTelevision,
                ),
        ),
      ),
    );
  }
}
