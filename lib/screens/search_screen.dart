import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/advanced_search_selection.dart';
import '../models/stremio_addon.dart';
import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';
import '../services/engine/dynamic_engine.dart';
import '../services/engine/engine_registry.dart';
import '../services/engine/settings_manager.dart';
import '../services/main_page_bridge.dart';
import '../services/premiumize_service.dart';
import '../services/series_source_service.dart';
import '../services/stremio_service.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/torrent_bulk_add_service.dart';
import '../services/torrent_playback_service.dart';
import '../services/torrent_service.dart';
import '../utils/dialog_tap_guard.dart';
import '../utils/torrent_filter_matcher.dart';
import '../widgets/catalog_item_tile.dart';
import '../widgets/home/home_theme.dart';
import '../widgets/torrent_filters_sheet.dart';
import '../widgets/torrent_result_row.dart';
import 'catalog_item_detail_screen.dart';
import 'episodes_screen.dart';

/// Dedicated Search tab.
///
/// * CATALOG mode — a Stremio-style board (one horizontal row per addon
///   catalog) with a hero spotlight that reflects the focused title; typing a
///   query searches every searchable addon and shows one horizontal row of
///   results per addon (same board layout).
/// * KEYWORD mode — raw torrent search → tap a result to add/play.
///
/// All playback (catalog auto-best, sources list, keyword) runs in-tab through
/// the isolated [TorrentPlaybackService]; the Home engine is never invoked.
class SearchScreen extends StatefulWidget {
  final bool isTelevision;

  const SearchScreen({super.key, this.isTelevision = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

enum _Mode { catalog, keyword }

class _SearchScreenState extends State<SearchScreen> {
  static const int _tabIndex = 15;

  final StremioService _stremio = StremioService.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'search_field');

  _Mode _mode = _Mode.catalog;

  /// Committed catalog query (drives per-addon catalog search). Empty = board.
  String _catalogQuery = '';
  Timer? _catalogDebounce;

  /// The addon that produced the item currently being played/browsed, threaded
  /// into playback so Continue Watching can route resume / next-episode back to
  /// it (matching Home's `addonId`). Set whenever we open a catalog item.
  String? _activeAddonId;

  // Keyword torrent-search state (submit-based).
  bool _kwLoading = false;
  String? _kwError;
  String _kwQuery = '';
  List<Torrent> _kwAll = []; // unfiltered results from the last search
  List<Torrent> _kwResults = []; // filtered + sorted view actually rendered
  final List<FocusNode> _kwNodes = [];
  TorrentFilterState _kwFilters = const TorrentFilterState.empty();
  String _kwSort = 'relevance';
  Map<String, List<String>> _kwCache = {}; // infohash(lower) → ['TB','PM']

  // Bulk-selection state for keyword results (mirrors Home's multi-select).
  bool _kwSelectionMode = false;
  final Set<String> _kwSelected = {}; // selected torrent infohashes

  /// Monotonic token so a slow earlier keyword search can't clobber a newer one.
  int _kwSearchToken = 0;

  /// True when PikPak is the ONLY configured provider. PikPak can't quick-play
  /// (it queues a cloud download), so catalog "Play" is hidden — matching Home.
  bool _pikpakOnly = false;

  /// imdbId → number of pinned (bound) sources — drives the board tile badge,
  /// detail Sources tint, and the Episodes "Source(s)" button count.
  final Map<String, int> _boundCounts = {};

  // Board state. [_homeSections] is the homepage cache; [_sections] is whatever
  // is currently shown (homepage OR per-addon catalog search results). Both the
  // board and catalog search render through the same horizontal-row layout.
  bool _loading = true;
  String? _error;
  List<CatalogSection> _homeSections = [];
  List<CatalogSection> _sections = [];
  final List<List<FocusNode>> _rowNodes = [];
  bool _catalogSearching = false;
  int _catalogSearchToken = 0;

  // Hero state. Driven by ValueNotifiers so focus-driven hero swaps rebuild
  // only the spotlight, never the whole board (important on low-power TVs).
  final ValueNotifier<StremioMeta?> _heroItem = ValueNotifier<StremioMeta?>(null);
  final ValueNotifier<StremioMeta?> _heroEnriched =
      ValueNotifier<StremioMeta?>(null);
  int _heroReqId = 0;
  Timer? _heroTimer;

  @override
  void initState() {
    super.initState();
    MainPageBridge.registerTvContentFocusHandler(_tabIndex, _focusContent);
    _load();
  }

  @override
  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(_tabIndex, _focusContent);
    _catalogDebounce?.cancel();
    _heroTimer?.cancel();
    _heroItem.dispose();
    _heroEnriched.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _disposeNodes();
    _disposeKwNodes();
    super.dispose();
  }

  void _disposeNodes() {
    for (final row in _rowNodes) {
      for (final node in row) {
        node.dispose();
      }
    }
    _rowNodes.clear();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    unawaited(_refreshPikpakOnly());
    try {
      final sections = await _stremio.fetchHomepageContent();
      if (!mounted) return;
      _homeSections = sections;
      setState(() => _loading = false);
      _applySections(sections);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// IMDb id for a catalog item, or null when it isn't a `tt…` id.
  String? _imdbOf(StremioMeta item) {
    final id = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    return (id != null && id.isNotEmpty) ? id : null;
  }

  bool _isBound(StremioMeta item) {
    final id = _imdbOf(item);
    return id != null && (_boundCounts[id] ?? 0) > 0;
  }

  int _boundCountFor(StremioMeta item) {
    final id = _imdbOf(item);
    return id == null ? 0 : (_boundCounts[id] ?? 0);
  }

  /// Re-read how many pinned sources each currently-displayed title has. Called
  /// after sections load and after any bind/unbind/playback.
  Future<void> _refreshBoundSources() async {
    final counts = <String, int>{};
    final seen = <String>{};
    for (final section in _sections) {
      for (final item in section.items) {
        final imdb = _imdbOf(item);
        if (imdb == null || !seen.add(imdb)) continue;
        final n = (await SeriesSourceService.getSources(imdb)).length;
        if (n > 0) counts[imdb] = n;
      }
    }
    if (!mounted) return;
    setState(() => _boundCounts
      ..clear()
      ..addAll(counts));
  }

  /// PikPak is "only" when it's enabled and no add/resolve provider has a key.
  Future<void> _refreshPikpakOnly() async {
    final pikpak = await StorageService.getPikPakEnabled();
    final rd = await StorageService.getApiKey();
    final tb = await StorageService.getTorboxApiKey();
    final pm = await StorageService.getPremiumizeApiKey();
    final ad = await StorageService.getAllDebridApiKey();
    final anyOther = (rd != null && rd.isNotEmpty) ||
        (tb != null && tb.isNotEmpty) ||
        (pm != null && pm.isNotEmpty) ||
        (ad != null && ad.isNotEmpty);
    final onlyPikpak = pikpak && !anyOther;
    if (mounted && onlyPikpak != _pikpakOnly) {
      setState(() => _pikpakOnly = onlyPikpak);
    }
  }

  /// Swap the displayed sections (homepage or search results): rebuild the
  /// per-row focus nodes and reset the hero to the first item.
  void _applySections(List<CatalogSection> sections) {
    _disposeNodes();
    for (final section in sections) {
      _rowNodes.add(
        List.generate(
          section.items.length,
          (i) => FocusNode(debugLabel: 'search_r${_rowNodes.length}_c$i'),
        ),
      );
    }
    setState(() => _sections = sections);
    unawaited(_refreshBoundSources());
    final first = sections.isNotEmpty && sections.first.items.isNotEmpty
        ? sections.first.items.first
        : null;
    _heroItem.value = first;
    _heroEnriched.value = null;
    if (first != null) _enrichHero(first);
  }

  /// Cross-addon catalog search, grouped as one horizontal row per addon so it
  /// matches the board (not a merged grid).
  Future<void> _runCatalogSearch(String query) async {
    final token = ++_catalogSearchToken;
    setState(() {
      _catalogQuery = query;
      _catalogSearching = true;
    });
    try {
      final addons = (await _stremio.getBrowseableOrSearchableAddons())
          .where((a) => a.hasSearchableCatalogs)
          .toList();
      final raw = await Future.wait(
        addons.map((addon) async {
          try {
            final items = await _stremio.searchAddonCatalogs(addon, query);
            if (items.isEmpty) return null;
            final catalog = addon.catalogs.firstWhere(
              (c) => c.supportsSearch,
              orElse: () => addon.catalogs.first,
            );
            return CatalogSection(
              title: '${addon.name} · Results',
              addon: addon,
              catalog: catalog,
              items: items,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted || token != _catalogSearchToken) return;
      setState(() => _catalogSearching = false);
      _applySections(raw.whereType<CatalogSection>().toList());
    } catch (_) {
      if (!mounted || token != _catalogSearchToken) return;
      setState(() => _catalogSearching = false);
    }
  }

  /// Cancel any pending search and return to the homepage board.
  void _restoreHome() {
    _catalogSearchToken++;
    setState(() {
      _catalogQuery = '';
      _catalogSearching = false;
    });
    _applySections(_homeSections);
  }

  // ── Focus entry ──────────────────────────────────────────────────────────

  void _focusContent() {
    if (_mode == _Mode.keyword) {
      if (_kwNodes.isNotEmpty) {
        _kwNodes.first.requestFocus();
        return;
      }
      _searchFocusNode.requestFocus();
      return;
    }
    if (_rowNodes.isNotEmpty && _rowNodes.first.isNotEmpty) {
      _rowNodes.first.first.requestFocus();
      return;
    }
    _searchFocusNode.requestFocus();
  }

  void _focusRow(int row, int column) {
    if (row < 0 || row >= _rowNodes.length) return;
    final nodes = _rowNodes[row];
    if (nodes.isEmpty) return;
    nodes[column.clamp(0, nodes.length - 1)].requestFocus();
  }

  // ── Hero ─────────────────────────────────────────────────────────────────

  void _setHero(StremioMeta item) {
    if (_heroItem.value?.id == item.id) return;
    _heroItem.value = item;
    _heroEnriched.value = null;
    _enrichHero(item);
  }

  /// Debounced backdrop/description enrichment. Catalog list items usually
  /// omit `background`/`description` (they come from the /meta endpoint), so
  /// fetch them lazily — cached in [StremioService], and guarded against the
  /// focus moving on (req id) so a slow fetch never clobbers a newer hero.
  void _enrichHero(StremioMeta item) {
    _heroTimer?.cancel();
    final needsBg = item.background == null || item.background!.isEmpty;
    final needsDesc = item.description == null || item.description!.isEmpty;
    if (!needsBg && !needsDesc) return;
    final imdb = item.imdbId ?? (item.id.startsWith('tt') ? item.id : null);
    if (imdb == null) return;
    final reqId = ++_heroReqId;
    _heroTimer = Timer(const Duration(milliseconds: 300), () async {
      final details = await _stremio.fetchMetaDetails(
        imdbId: imdb,
        type: item.type,
      );
      if (!mounted || reqId != _heroReqId || details == null) return;
      _heroEnriched.value = details;
    });
  }

  // ── Search field ─────────────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    if (_mode != _Mode.catalog) return;
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final q = value.trim();
      if (q == _catalogQuery) return;
      if (q.isEmpty) {
        _restoreHome();
      } else {
        _runCatalogSearch(q);
      }
    });
  }

  void _onQuerySubmitted(String value) {
    _catalogDebounce?.cancel();
    final q = value.trim();
    if (_mode == _Mode.keyword) {
      _runKeyword(q);
    } else if (q.isEmpty) {
      _restoreHome();
    } else {
      _runCatalogSearch(q);
    }
  }

  void _clearQuery() {
    _catalogDebounce?.cancel();
    _searchController.clear();
    _disposeKwNodes();
    setState(() {
      _kwQuery = '';
      _kwAll = [];
      _kwResults = [];
      _kwCache = {};
      _kwError = null;
    });
    _restoreHome();
  }

  Future<void> _runKeyword(String query) async {
    if (query.isEmpty) return;
    final token = ++_kwSearchToken;
    setState(() {
      _kwLoading = true;
      _kwError = null;
      _kwQuery = query;
      _kwCache = {};
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
    try {
      final result = await TorrentService.searchAllEngines(query);
      // Drop stale results if a newer search started while this was in flight.
      if (!mounted || token != _kwSearchToken) return;
      final torrents = (result['torrents'] as List).cast<Torrent>();
      final engineErrors = result['engineErrors'];
      // Every source errored and nothing came back → surface the failure
      // instead of a misleading "No results" (searchAllEngines fails soft).
      if (torrents.isEmpty && engineErrors is Map && engineErrors.isNotEmpty) {
        setState(() {
          _kwError = 'Search failed on all sources. Check your connection or '
              'enabled sources and try again.';
          _kwLoading = false;
        });
        return;
      }
      _kwAll = torrents;
      setState(() => _kwLoading = false);
      _recomputeKeyword();
      unawaited(_checkKeywordCache(_kwAll, token));
    } catch (e) {
      if (!mounted || token != _kwSearchToken) return;
      setState(() {
        _kwError = e.toString();
        _kwLoading = false;
      });
    }
  }

  // ── Bulk selection (keyword results) ──────────────────────────────────────
  /// Torrents eligible for bulk actions (excludes direct/external streams).
  List<Torrent> get _kwSelectableResults =>
      _kwResults.where((t) => !t.isDirectStream && !t.isExternalStream).toList();

  void _enterKwSelection() {
    setState(() {
      _kwSelectionMode = true;
      _kwSelected.clear();
    });
  }

  void _exitKwSelection() {
    setState(() {
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
  }

  void _toggleKwSelection(Torrent t) {
    setState(() {
      if (_kwSelected.contains(t.infohash)) {
        _kwSelected.remove(t.infohash);
      } else {
        _kwSelected.add(t.infohash);
      }
    });
  }

  void _selectAllKw() {
    setState(() {
      _kwSelected
        ..clear()
        ..addAll(_kwSelectableResults.map((t) => t.infohash));
    });
  }

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void _deselectAllKw() {
    setState(() => _kwSelected.clear());
  }

  bool _kwBulkBusy = false;

  Future<void> _openBulkAdd() async {
    if (_kwBulkBusy) return;
    final chosen =
        _kwResults.where((t) => _kwSelected.contains(t.infohash)).toList();
    if (chosen.isEmpty) return;
    _kwBulkBusy = true;
    bool chose = false;
    try {
      chose = await TorrentBulkAddService.showBulkAddDialog(
        context,
        torrents: chosen,
        keyword: _kwQuery,
      );
    } finally {
      _kwBulkBusy = false;
    }
    // Stay in selection mode if the user just dismissed the chooser.
    if (mounted && chose && _kwSelectionMode) _exitKwSelection();
  }

  /// Re-apply filters + sort to the last search's results and rebuild nodes.
  void _recomputeKeyword() {
    final filtered = TorrentFilterMatcher.apply(_kwAll, _kwFilters);
    final sorted = _sortKeyword(filtered);
    _disposeKwNodes();
    for (var i = 0; i < sorted.length; i++) {
      _kwNodes.add(FocusNode(debugLabel: 'kw_$i'));
    }
    setState(() => _kwResults = sorted);
  }

  List<Torrent> _sortKeyword(List<Torrent> list) {
    final l = [...list];
    switch (_kwSort) {
      case 'seeders':
        l.sort((a, b) => b.seeders.compareTo(a.seeders));
        break;
      case 'size':
        l.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
        break;
      case 'date':
        l.sort((a, b) => b.createdUnix.compareTo(a.createdUnix));
        break;
      case 'name':
        l.sort((a, b) =>
            a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
        break;
      default: // 'relevance' — keep the engine (seeder-deduped) order
        break;
    }
    return l;
  }

  /// Cache-check the results against TorBox/Premiumize (the only providers that
  /// support it) and stamp TB/PM badges onto the rows.
  Future<void> _checkKeywordCache(List<Torrent> torrents, int token) async {
    final hashes = torrents
        .map((t) => t.infohash.toLowerCase())
        .where((h) => h.isNotEmpty)
        .toList();
    if (hashes.isEmpty) return;
    final map = <String, List<String>>{};
    // Only check a provider when the user has cache-checking enabled AND the
    // integration is on AND a key is saved (matches Home's gating).
    try {
      final tb = await StorageService.getTorboxApiKey();
      final enabled = await StorageService.getTorboxCacheCheckEnabled() &&
          await StorageService.getTorboxIntegrationEnabled();
      if (enabled && tb != null && tb.isNotEmpty) {
        final cached =
            await TorboxService.checkCachedTorrents(apiKey: tb, infoHashes: hashes);
        for (final h in cached) {
          (map[h] ??= <String>[]).add('TB');
        }
      }
    } catch (_) {}
    try {
      final pm = await StorageService.getPremiumizeApiKey();
      final enabled = await StorageService.getPremiumizeCacheCheckEnabled() &&
          await StorageService.getPremiumizeIntegrationEnabled();
      if (enabled && pm != null && pm.isNotEmpty) {
        final res = await PremiumizeService.checkCache(pm, hashes);
        for (var i = 0; i < hashes.length && i < res.length; i++) {
          if (res[i]) (map[hashes[i]] ??= <String>[]).add('PM');
        }
      }
    } catch (_) {}
    // Drop badges from a superseded search.
    if (!mounted || token != _kwSearchToken) return;
    setState(() => _kwCache = map);
  }

  Future<void> _openKeywordFilters() async {
    final result = await showDialog<TorrentFilterState>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: TorrentFiltersSheet(initialState: _kwFilters),
      ),
    );
    if (result == null || !mounted) return;
    _kwFilters = result;
    _recomputeKeyword();
  }

  Future<void> _openKeywordSort() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        Widget tile(String value, String label) => ListTile(
              title: Text(label),
              trailing: _kwSort == value
                  ? Icon(Icons.check_rounded, color: scheme.primary)
                  : null,
              onTap: () => Navigator.of(dialogContext).pop(value),
            );
        return AlertDialog(
          backgroundColor: scheme.surfaceContainerHigh,
          title: const Text('Sort by'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile('relevance', 'Relevance'),
              tile('seeders', 'Seeders'),
              tile('size', 'Size'),
              tile('date', 'Date added'),
              tile('name', 'Name'),
            ],
          ),
        );
      },
    );
    if (choice == null || !mounted) return;
    _kwSort = choice;
    _recomputeKeyword();
  }

  Future<void> _openKeywordSources() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _KeywordSourcesDialog(),
    );
    if (!mounted || _kwQuery.isEmpty) return;
    _runKeyword(_kwQuery); // re-search with the new enabled set
  }

  void _disposeKwNodes() {
    for (final n in _kwNodes) {
      n.dispose();
    }
    _kwNodes.clear();
  }

  void _switchMode(_Mode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      // Leaving the keyword list drops any in-progress multi-selection.
      _kwSelectionMode = false;
      _kwSelected.clear();
    });
  }

  // ── Playback / detail delegation ───────────────────────────────────────────

  void _openItem(StremioMeta item, StremioAddon addon) {
    _activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kCatalogDetailRouteName),
            builder: (_) => CatalogItemDetailScreen(
              item: item,
              isTelevision: widget.isTelevision,
              // Hide "Play" when PikPak is the only provider — no quick-play.
              showQuickPlay: !_pikpakOnly,
              // Gold-tint the Sources button when a source is already pinned.
              hasBoundSource: _isBound(item),
              onPlay: () => _onCatalogPlay(item, addon),
              onBrowse: () => _onCatalogBrowse(item, addon),
            ),
          ),
        )
        // A bind/unbind may have happened inside the detail flow.
        .then((_) => _refreshBoundSources());
  }

  // Catalog Play = auto-best in-tab; Sources = manual list in-tab. For a series
  // Play auto-plays the resume episode (last-played by imdbId → title, else
  // S01E01) — the Episodes button is the manual picker. Nothing jumps to Home.
  Future<void> _onCatalogPlay(StremioMeta item, StremioAddon addon) async {
    if (item.type != 'series') {
      // Keep the detail page underneath — the cinematic loading overlay covers
      // it, and after playback Back returns to the detail (like Home).
      _playSelection(_movieSelection(item));
      return;
    }

    _activeAddonId = addon.id;
    final imdbId = item.imdbId ?? (item.id.startsWith('tt') ? item.id : '');
    // Without an IMDb id we can't search torrents for a specific episode, so
    // fall back to the manual episode picker.
    if (imdbId.isEmpty) {
      _openEpisodes(item, addon);
      return;
    }

    // Resolve where to resume, mirroring EpisodesScreen's landing logic:
    // last-played episode for this show (by imdbId, then by title), else S01E01.
    int? season;
    int? episode;
    final byId = await StorageService.getLastPlayedEpisodeByImdbId(imdbId);
    season = byId?['season'] as int?;
    episode = byId?['episode'] as int?;
    if (season == null || episode == null) {
      final byTitle =
          await StorageService.getLastPlayedEpisode(seriesTitle: item.name);
      season ??= byTitle?['season'] as int?;
      episode ??= byTitle?['episode'] as int?;
    }
    season ??= 1;
    episode ??= 1;
    if (!mounted) return;

    _playSelection(AdvancedSearchSelection(
      imdbId: imdbId,
      isSeries: true,
      title: item.name,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.type,
      posterUrl: item.poster,
    ));
  }

  void _onCatalogBrowse(StremioMeta item, StremioAddon addon) {
    if (item.type == 'series') {
      _openEpisodes(item, addon);
    } else {
      _browseSelection(_movieSelection(item));
    }
  }

  AdvancedSearchSelection _movieSelection(StremioMeta item) =>
      AdvancedSearchSelection(
        imdbId: item.imdbId ?? (item.id.startsWith('tt') ? item.id : ''),
        isSeries: false,
        title: item.name,
        year: item.year,
        contentType: item.type,
        posterUrl: item.poster,
      );

  void _openEpisodes(StremioMeta item, StremioAddon addon) {
    _activeAddonId = addon.id;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            settings: const RouteSettings(name: kEpisodesRouteName),
            builder: (_) => EpisodesScreen(
              show: item,
              addon: addon,
              isTelevision: widget.isTelevision,
              // EpisodesScreen pops itself (and the detail route) before firing
              // these, so we're back on the Search screen when they run.
              onQuickPlay: _playSelection,
              onItemSelected: _browseSelection,
              // "Select Source" button: pin a pack as this show's bound source.
              boundSourceCount: _boundCountFor,
              onSelectSource: _openBindSources,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Open the source picker (bind mode) to pin a source for [show]. For a series
  /// this searches season/complete packs (no episode), matching Home.
  void _openBindSources(StremioMeta show) {
    final imdb = _imdbOf(show);
    if (imdb == null) {
      _snack('No IMDb match to pin a source for "${show.name}".');
      return;
    }
    final sel = AdvancedSearchSelection(
      imdbId: imdb,
      isSeries: show.type == 'series',
      title: show.name,
      year: show.year,
      contentType: show.type,
      posterUrl: show.poster,
    );
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
              bindMode: true,
            ),
          ),
        )
        .then((_) => _refreshBoundSources());
  }

  /// Auto-best in-tab play: search torrents for the selection, pick the best
  /// instantly-playable source, and play — never leaving the Search tab.
  PlaybackMeta _metaFor(AdvancedSearchSelection sel) => PlaybackMeta(
        // null (not '') when absent, so the launcher's Trakt auto-sync + local
        // Continue Watching never fire on a garbage id.
        imdbId: sel.imdbId.isEmpty ? null : sel.imdbId,
        contentType: sel.isSeries ? 'series' : 'movie',
        season: sel.season,
        episode: sel.episode,
        title: sel.title,
        posterUrl: sel.posterUrl,
        year: sel.year,
        addonId: _activeAddonId,
        traktProgressPercent: sel.traktProgressPercent,
      );

  /// Catalog auto-best play — the service picks the provider, shows the real
  /// cinematic overlay, searches, and plays (with source list + content
  /// metadata so the in-player Sources switcher + Continue Watching work).
  Future<void> _playSelection(AdvancedSearchSelection sel) =>
      TorrentPlaybackService.playFromSelection(
        context,
        imdbId: sel.imdbId,
        isMovie: !sel.isSeries,
        season: sel.season,
        episode: sel.episode,
        meta: _metaFor(sel),
      );

  /// Manual sources list in-tab — the screen searches itself (own loading) and
  /// each tap plays with the full source list + content metadata.
  void _browseSelection(AdvancedSearchSelection sel) {
    if (sel.imdbId.isEmpty) {
      _snack('No IMDb match to find sources for "${sel.title}".');
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => _SourcesScreen(
              selection: sel,
              meta: _metaFor(sel),
              isTelevision: widget.isTelevision,
            ),
          ),
        )
        // A long-press pin/unpin may have happened in the sources list.
        .then((_) => _refreshBoundSources());
  }


  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final scheme = Theme.of(context).colorScheme;
    final tv = widget.isTelevision;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, tv ? 16 : 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _focusContent();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Container(
                height: tv ? 54 : 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded,
                        size: 20, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        onChanged: _onQueryChanged,
                        onSubmitted: _onQuerySubmitted,
                        textInputAction: TextInputAction.search,
                        style: TextStyle(
                          fontSize: tv ? 16 : 15,
                          color: scheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: _mode == _Mode.catalog
                              ? 'Search movies & shows…'
                              : 'Search torrents by keyword…',
                          hintStyle:
                              TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _searchController,
                      builder: (context, value, _) {
                        if (value.text.isEmpty) return const SizedBox.shrink();
                        return GestureDetector(
                          onTap: _clearQuery,
                          child: Icon(Icons.close_rounded,
                              size: 18, color: scheme.onSurfaceVariant),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _ModeToggle(
            mode: _mode,
            isTelevision: tv,
            onChanged: _switchMode,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_mode == _Mode.keyword) return _buildKeyword();
    if (_catalogSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    return _buildBoard();
  }

  Widget _buildKeyword() {
    if (_kwLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_kwError != null) {
      return _message(Icons.error_outline_rounded, 'Search failed', _kwError!);
    }
    if (_kwQuery.isEmpty) {
      return _message(
        Icons.bolt_rounded,
        'Keyword torrent search',
        'Type a title and press search to find torrents across your enabled '
            'sources, then tap one to play.',
      );
    }
    return Column(
      children: [
        _buildKeywordToolbar(),
        Expanded(
          child: _kwResults.isEmpty
              ? _message(
                  Icons.search_off_rounded,
                  _kwAll.isEmpty ? 'No results' : 'No matches',
                  _kwAll.isEmpty
                      ? 'Nothing found for "$_kwQuery". Try different keywords '
                          'or enable more sources.'
                      : 'No results match your filters. Adjust or clear them.',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  cacheExtent: 1200,
                  itemCount: _kwResults.length,
                  itemBuilder: (context, i) {
                    final t = _kwResults[i];
                    final selectable =
                        !t.isDirectStream && !t.isExternalStream;
                    return TorrentResultRow(
                      key: ValueKey(
                        '${t.infohash}_${_kwSelectionMode}_${_kwSelected.contains(t.infohash)}',
                      ),
                      torrent: t,
                      index: i,
                      focusNode: _kwNodes[i],
                      isTelevision: widget.isTelevision,
                      qualityTier: t.qualityTier,
                      cacheLabels:
                          _kwCache[t.infohash.toLowerCase()] ?? const [],
                      isSelectionMode: _kwSelectionMode && selectable,
                      isSelected: _kwSelected.contains(t.infohash),
                      onTap: () {
                        if (_kwSelectionMode && selectable) {
                          _toggleKwSelection(t);
                          return;
                        }
                        // Swallow a SELECT that leaks through as a toolbar
                        // dialog (sort/filter/sources) closes on TV.
                        if (DialogTapGuard.shouldIgnoreTap()) return;
                        unawaited(TorrentPlaybackService.activateTorrent(
                            context, t,
                            searchKeyword: _kwQuery));
                      },
                      onLongPress: !_kwSelectionMode && selectable
                          ? () {
                              _enterKwSelection();
                              _toggleKwSelection(t);
                            }
                          : null,
                      onNavigateUp: () {
                        if (i > 0) {
                          _kwNodes[i - 1].requestFocus();
                        } else {
                          _searchFocusNode.requestFocus();
                        }
                      },
                      onNavigateDown: () {
                        if (i < _kwNodes.length - 1) {
                          _kwNodes[i + 1].requestFocus();
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKeywordToolbar() {
    final scheme = Theme.of(context).colorScheme;
    final filterCount = _kwFilters.qualities.length +
        _kwFilters.ripSources.length +
        _kwFilters.languages.length;

    Widget pill(IconData icon, String label, VoidCallback onTap,
        {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: 0.16)
                    : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: active
                      ? scheme.primary.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_kwSelectionMode) {
      final selectable = _kwSelectableResults.length;
      final count = _kwSelected.length;
      final allSelected = count > 0 && count == selectable;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: [
            pill(Icons.close_rounded, 'Cancel', _exitKwSelection),
            pill(
              allSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
              allSelected ? 'None' : 'All',
              allSelected ? _deselectAllKw : _selectAllKw,
            ),
            pill(
              Icons.playlist_add_rounded,
              count > 0 ? 'Add · $count' : 'Add',
              count > 0 ? _openBulkAdd : () {},
              active: count > 0,
            ),
          ],
        ),
      );
    }

    final canSelect = _kwSelectableResults.isNotEmpty;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(
        children: [
          pill(Icons.sort_rounded, 'Sort · ${_sortLabel(_kwSort)}',
              _openKeywordSort),
          pill(
            Icons.filter_list_rounded,
            filterCount > 0 ? 'Filters · $filterCount' : 'Filters',
            _openKeywordFilters,
            active: filterCount > 0,
          ),
          pill(Icons.dns_rounded, 'Sources', _openKeywordSources),
          if (canSelect)
            pill(Icons.checklist_rounded, 'Select', _enterKwSelection),
        ],
      ),
    );
  }

  String _sortLabel(String s) =>
      const {
        'relevance': 'Relevance',
        'seeders': 'Seeders',
        'size': 'Size',
        'date': 'Date',
        'name': 'Name',
      }[s] ??
      s;

  Widget _buildBoard() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _message(
        Icons.error_outline_rounded,
        "Couldn't load catalogs",
        _error!,
      );
    }
    if (_sections.isEmpty) {
      if (_catalogQuery.isNotEmpty) {
        return _message(
          Icons.search_off_rounded,
          'No catalog matches',
          'Nothing in your catalogs for "$_catalogQuery". Try different '
              'keywords, or switch to Keyword to search torrents directly.',
        );
      }
      return _message(
        Icons.travel_explore_rounded,
        'No catalogs yet',
        'Install a catalog add-on (e.g. Cinemeta) from Addons to browse '
            'movies and shows here.',
      );
    }

    final tv = widget.isTelevision;
    final width = MediaQuery.of(context).size.width;
    final heroH = tv ? 380.0 : (width >= 900 ? 300.0 : 196.0);

    return Column(
      children: [
        ValueListenableBuilder<StremioMeta?>(
          valueListenable: _heroItem,
          builder: (context, item, _) {
            if (item == null) return const SizedBox.shrink();
            return ValueListenableBuilder<StremioMeta?>(
              valueListenable: _heroEnriched,
              builder: (context, enriched, __) {
                return _HeroSpotlight(
                  item: item,
                  background: item.background?.isNotEmpty == true
                      ? item.background
                      : enriched?.background,
                  description: item.description?.isNotEmpty == true
                      ? item.description
                      : enriched?.description,
                  isTelevision: tv,
                  height: heroH,
                );
              },
            );
          },
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 6, bottom: 32),
            cacheExtent: 2000,
            itemCount: _sections.length,
            itemBuilder: (context, i) => _buildRow(i),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(int rowIndex) {
    final section = _sections[rowIndex];
    final nodes = _rowNodes[rowIndex];
    final tv = widget.isTelevision;
    final posterW = tv ? 148.0 : 122.0;
    final posterH = posterW * 3 / 2;
    final rowH = posterH + 26;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
          child: Text(
            section.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: tv ? 19 : 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        SizedBox(
          height: rowH,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            cacheExtent: 2000,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: section.items.length,
            itemBuilder: (context, col) {
              final item = section.items[col];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Center(
                  child: SizedBox(
                    width: posterW,
                    height: posterH,
                    child: _BoardCell(
                      item: item,
                      isTelevision: tv,
                      focusNode: nodes[col],
                      column: col,
                      rowNodes: nodes,
                      hasBoundSource: _isBound(item),
                      onFocused: () => _setHero(item),
                      onUp: rowIndex == 0
                          ? () => _searchFocusNode.requestFocus()
                          : () => _focusRow(rowIndex - 1, col),
                      onDown: () => _focusRow(rowIndex + 1, col),
                      onOpen: () => _openItem(item, section.addon),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _message(IconData icon, String title, String body) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Stremio-style spotlight. Reflects the currently focused board title —
/// backdrop bleeding in from the right behind a left/bottom scrim, with title,
/// meta line and a short synopsis.
class _HeroSpotlight extends StatelessWidget {
  final StremioMeta item;
  final String? background;
  final String? description;
  final bool isTelevision;
  final double height;

  const _HeroSpotlight({
    required this.item,
    required this.background,
    required this.description,
    required this.isTelevision,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = (background != null && background!.isNotEmpty)
        ? background!
        : (item.poster ?? '');
    final metaParts = <String>[
      if (item.year != null && item.year!.isNotEmpty) item.year!,
      if (item.genres != null && item.genres!.isNotEmpty)
        item.genres!.take(2).join(' · '),
    ];

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (bg.isNotEmpty)
            CachedNetworkImage(
              imageUrl: bg,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          // Left + bottom scrims for legibility.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  scheme.surface,
                  scheme.surface.withValues(alpha: 0.82),
                  scheme.surface.withValues(alpha: 0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.34, 0.66, 1.0],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [scheme.surface, Colors.transparent],
                stops: const [0.02, 0.5],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, isTelevision ? 22 : 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isTelevision ? 640 : 520,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: Text(
                        item.type == 'series' ? 'SERIES' : 'MOVIE',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isTelevision ? 40 : 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.04,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (item.imdbRating != null) ...[
                          const Icon(Icons.star_rounded,
                              size: 16, color: HomeTheme.focusGold),
                          const SizedBox(width: 4),
                          Text(
                            item.imdbRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          if (metaParts.isNotEmpty) _dot(),
                        ],
                        Flexible(
                          child: Text(
                            metaParts.join('   ·   '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        description!,
                        maxLines: isTelevision ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isTelevision ? 14.5 : 13,
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// [CatalogItemTile] plus DPAD arrow navigation. The tile owns SELECT, its
/// focus visuals and ensureVisible; this ancestor [Focus] catches the arrows
/// the tile ignores (left/right within the row, up/down to adjacent rows or
/// the search field) and reports focus to drive the hero.
class _BoardCell extends StatelessWidget {
  final StremioMeta item;
  final bool isTelevision;
  final FocusNode focusNode;
  final int column;
  final List<FocusNode> rowNodes;
  final bool hasBoundSource;
  final VoidCallback onFocused;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onOpen;

  const _BoardCell({
    required this.item,
    required this.isTelevision,
    required this.focusNode,
    required this.column,
    required this.rowNodes,
    required this.hasBoundSource,
    required this.onFocused,
    required this.onUp,
    required this.onDown,
    required this.onOpen,
  });

  KeyEventResult _handleArrows(FocusNode node, KeyEvent event) {
    if (!isTelevision || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (column > 0) {
        rowNodes[column - 1].requestFocus();
      } else {
        MainPageBridge.focusTvSidebar?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (column < rowNodes.length - 1) {
        rowNodes[column + 1].requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      onUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      onDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (has) {
        if (has) onFocused();
      },
      onKeyEvent: _handleArrows,
      child: CatalogItemTile(
        item: item,
        isTelevision: isTelevision,
        focusNode: focusNode,
        hasBoundSource: hasBoundSource,
        onOpen: onOpen,
      ),
    );
  }
}

/// Catalog / Keyword segmented toggle.
class _ModeToggle extends StatelessWidget {
  final _Mode mode;
  final bool isTelevision;
  final ValueChanged<_Mode> onChanged;

  const _ModeToggle({
    required this.mode,
    required this.isTelevision,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: isTelevision ? 54 : 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          _segment(context, _Mode.catalog, 'Catalog', Icons.grid_view_rounded),
          _segment(context, _Mode.keyword, 'Keyword', Icons.bolt_rounded),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _Mode value, String label, IconData icon) {
    final on = mode == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: isTelevision ? 16 : 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? HomeTheme.focusGold : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: on
                    ? const Color(0xFF0A0F18)
                    : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: isTelevision ? 14 : 13,
                fontWeight: FontWeight.w700,
                color: on
                    ? const Color(0xFF0A0F18)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A pushable manual sources list for a catalog title/episode. Searches its own
/// torrent sources (own loading), renders them as [TorrentResultRow]s, and on
/// tap plays via the isolated service with the FULL source list + content
/// metadata (so the in-player Sources switcher + Continue Watching both work).
class _SourcesScreen extends StatefulWidget {
  final AdvancedSearchSelection selection;
  final PlaybackMeta meta;
  final bool isTelevision;

  /// When true the screen is a source PICKER: tapping a row pins it as the
  /// bound source and pops (used by the "Select Source" entry points). When
  /// false it's the normal Sources list: tap plays, long-press pins/unpins.
  final bool bindMode;

  const _SourcesScreen({
    required this.selection,
    required this.meta,
    required this.isTelevision,
    this.bindMode = false,
  });

  @override
  State<_SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<_SourcesScreen> {
  bool _loading = true;
  String? _error;
  List<Torrent> _torrents = [];
  final List<FocusNode> _nodes = [];
  List<SeriesSource> _bound = [];

  String get _imdbId => widget.selection.imdbId;
  bool get _isMovie => !widget.selection.isSeries;
  Set<String> get _boundHashes => _bound.map((s) => s.torrentHash).toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _reloadBound() async {
    final bound =
        _imdbId.isEmpty ? <SeriesSource>[] : await SeriesSourceService.getSources(_imdbId);
    if (!mounted) return;
    setState(() => _bound = bound);
  }

  Future<void> _load() async {
    await _reloadBound();
    try {
      final res = await TorrentService.searchByImdb(
        widget.selection.imdbId,
        isMovie: !widget.selection.isSeries,
        season: widget.selection.season,
        episode: widget.selection.episode,
      );
      if (!mounted) return;
      final torrents = (res['torrents'] as List).cast<Torrent>();
      for (var i = 0; i < torrents.length; i++) {
        _nodes.add(FocusNode(debugLabel: 'src_$i'));
      }
      setState(() {
        _torrents = torrents;
        _loading = false;
      });
      // On TV the list is the only content — give the D-pad an anchor to move
      // from, otherwise the remote has nothing focused and can't select a row.
      if (widget.isTelevision && _nodes.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nodes.first.requestFocus();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool _pinning = false;

  void _play(Torrent t, int i) {
    // Swallow a SELECT that leaks through as the row menu / provider picker
    // closes on TV (armed via DialogTapGuard.markKeyAction in the menu).
    if (DialogTapGuard.shouldIgnoreTap()) return;
    _playNow(t, i);
  }

  void _playNow(Torrent t, int i) {
    unawaited(TorrentPlaybackService.activateTorrent(
      context,
      t,
      meta: widget.meta,
      sources: _torrents,
      sourceIndex: i,
      searchKeyword: widget.selection.title,
    ));
  }

  Future<void> _pin(Torrent t) async {
    if (_pinning) return; // guard concurrent binds (double-tap on TV)
    _pinning = true;
    try {
      final ok = await TorrentPlaybackService.bindSource(
        context,
        t,
        imdbId: _imdbId,
        isMovie: _isMovie,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  Future<void> _unpin(String hash) async {
    await SeriesSourceService.removeSourceByHash(_imdbId, hash);
    await _reloadBound();
  }

  Future<void> _pinLocal() async {
    if (_pinning) return;
    _pinning = true;
    try {
      final ok = await TorrentPlaybackService.bindLocalSource(
        context,
        imdbId: _imdbId,
        isMovie: _isMovie,
        title: widget.selection.title,
        year: widget.selection.year,
      );
      if (!mounted) return;
      if (ok) {
        await _reloadBound();
        if (widget.bindMode && mounted) Navigator.of(context).pop();
      }
    } finally {
      _pinning = false;
    }
  }

  void _showRowMenu(Torrent t, int i) {
    final bound = _boundHashes.contains(t.infohash);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0F172A),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded, color: Colors.white),
              title: const Text('Play', style: TextStyle(color: Colors.white)),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                _playNow(t, i);
              },
            ),
            ListTile(
              leading: Icon(bound ? Icons.link_off_rounded : Icons.link_rounded,
                  color: const Color(0xFFF59E0B)),
              title: Text(bound ? 'Unpin source' : 'Pin as source',
                  style: const TextStyle(color: Colors.white)),
              subtitle: Text(
                bound
                    ? 'Stop reusing this source'
                    : 'Reuse this source for instant playback',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
              ),
              onTap: () {
                DialogTapGuard.markKeyAction();
                Navigator.of(sheetCtx).pop();
                if (bound) {
                  unawaited(_unpin(t.infohash));
                } else {
                  unawaited(_pin(t));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          widget.bindMode
              ? 'Pick a source for ${widget.selection.title}'
              : widget.selection.formattedLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Pin an on-device file/folder as the source. Desktop only — hidden on
          // Android/iOS (incl. Android TV) where local binding is unavailable, so
          // it's never a dead-end D-pad stop.
          if (_imdbId.isNotEmpty && TorrentPlaybackService.localBindingAvailable)
            IconButton(
              tooltip: 'Pin an on-device file or folder',
              icon: const Icon(Icons.folder_open_rounded),
              onPressed: () => unawaited(_pinLocal()),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _centered(scheme, 'Search failed.\n$_error')
              : Column(
                  children: [
                    if (_bound.isNotEmpty) _pinnedBanner(),
                    Expanded(
                      child: _torrents.isEmpty
                          ? _centered(scheme, 'No sources found.')
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              cacheExtent: 1200,
                              itemCount: _torrents.length,
                              itemBuilder: (context, i) {
                                final t = _torrents[i];
                                return TorrentResultRow(
                                  torrent: t,
                                  index: i,
                                  focusNode: _nodes[i],
                                  isTelevision: widget.isTelevision,
                                  qualityTier: t.qualityTier,
                                  onTap: () {
                                    if (widget.bindMode) {
                                      unawaited(_pin(t));
                                    } else {
                                      _play(t, i);
                                    }
                                  },
                                  onLongPress: () => _showRowMenu(t, i),
                                  onNavigateUp: () {
                                    if (i > 0) _nodes[i - 1].requestFocus();
                                  },
                                  onNavigateDown: () {
                                    if (i < _nodes.length - 1) {
                                      _nodes[i + 1].requestFocus();
                                    }
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _pinnedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_rounded, color: Color(0xFFF59E0B), size: 16),
              const SizedBox(width: 6),
              Text(
                _bound.length == 1 ? 'Pinned source' : 'Pinned sources',
                style: const TextStyle(
                  color: Color(0xFFF59E0B),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ..._bound.map((s) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.torrentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    InkWell(
                      onTap: () => unawaited(_unpin(s.torrentHash)),
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded,
                            color: Colors.white70, size: 18),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _centered(ColorScheme scheme, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
}

/// Active-sources checklist for keyword search: toggle which torrent engines
/// are queried. Backed by [SettingsManager] (same store Home uses), so changes
/// persist and apply to the next search.
class _KeywordSourcesDialog extends StatefulWidget {
  const _KeywordSourcesDialog();

  @override
  State<_KeywordSourcesDialog> createState() => _KeywordSourcesDialogState();
}

class _KeywordSourcesDialogState extends State<_KeywordSourcesDialog> {
  final SettingsManager _settings = SettingsManager();
  List<DynamicEngine> _engines = [];
  final Map<String, bool> _enabled = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final engines = EngineRegistry.instance.getKeywordSearchEngines();
    for (final e in engines) {
      _enabled[e.name] = await _settings.getEnabled(e.name, true);
    }
    if (!mounted) return;
    setState(() {
      _engines = engines;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: scheme.surfaceContainerHigh,
      title: const Text('Active sources'),
      content: SizedBox(
        width: 360,
        child: _loading
            ? const SizedBox(
                height: 80, child: Center(child: CircularProgressIndicator()))
            : _engines.isEmpty
                ? const Text('No search sources installed.')
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _engines.map((e) {
                        final on = _enabled[e.name] ?? true;
                        return SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(e.displayName),
                          value: on,
                          onChanged: (v) {
                            setState(() => _enabled[e.name] = v);
                            _settings.setEnabled(e.name, v);
                          },
                        );
                      }).toList(),
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
