import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/stremio_addon.dart';
import '../models/advanced_search_selection.dart';
import '../services/main_page_bridge.dart';
import '../services/stremio_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/local_bound_source_service.dart';
import '../services/series_source_service.dart';
import '../services/storage_service.dart';
import '../screens/debrid_downloads_screen.dart';
import '../screens/stremio_tv/widgets/stremio_tv_catalog_picker_dialog.dart';
import '../screens/torbox/torbox_downloads_screen.dart';
import 'add_source_picker_dialog.dart';
import 'catalog_item_tile.dart';
import 'trakt/trakt_menu_helpers.dart';
import '../screens/catalog_item_detail_screen.dart';

/// Displays aggregated search results from all catalog sources
///
/// Features:
/// - First result: "Search [keyword]" action card
/// - Remaining results: Catalog search results as a grid
/// - Quick Play and Sources buttons for each catalog item
/// - TV D-pad navigation support
class AggregatedSearchResults extends StatefulWidget {
  /// The search query
  final String query;

  /// Callback when user clicks "Search [keyword]" action
  final VoidCallback onKeywordSearch;

  /// Callback when user selects a catalog item (Sources button)
  final void Function(AdvancedSearchSelection selection)? onItemSelected;

  /// Callback when user wants to quick play an item (Quick Play button)
  /// If null, Quick Play button will fallback to onItemSelected behavior
  final void Function(AdvancedSearchSelection selection)? onQuickPlay;

  /// Whether to show the Quick Play button (hide when PikPak is default provider)
  final bool showQuickPlay;

  /// Whether running on TV
  final bool isTelevision;

  /// Callback when keyword search focus node is ready (for external focus control)
  final void Function(FocusNode focusNode)? onKeywordFocusNodeReady;

  /// Callback when user presses Up arrow from keyword card (to return focus to search field)
  final VoidCallback? onRequestFocusAbove;

  /// Callback when user selects "Select Source" for a series
  final void Function(StremioMeta)? onSelectSource;
  final void Function(StremioMeta)? onKeywordSelectSource;

  /// Callback when user selects "Play Random Episode" for a series
  final Future<void> Function(StremioMeta show, StremioAddon? addon)?
  onPlayRandomEpisode;

  /// Callback when user selects "Search Season Packs" for a series
  final void Function(StremioMeta)? onSearchPacks;

  /// Callback when user wants to browse a series with episode drill-down
  /// Passes the show and its source addon so the parent can switch to that addon's CatalogBrowser
  final void Function(StremioMeta show, StremioAddon addon)?
  onBrowseSeriesEpisodes;

  const AggregatedSearchResults({
    super.key,
    required this.query,
    required this.onKeywordSearch,
    this.onItemSelected,
    this.onQuickPlay,
    this.showQuickPlay = true,
    this.isTelevision = false,
    this.onKeywordFocusNodeReady,
    this.onRequestFocusAbove,
    this.onSelectSource,
    this.onKeywordSelectSource,
    this.onPlayRandomEpisode,
    this.onSearchPacks,
    this.onBrowseSeriesEpisodes,
  });

  @override
  State<AggregatedSearchResults> createState() =>
      AggregatedSearchResultsState();
}

class AggregatedSearchResultsState extends State<AggregatedSearchResults> {
  final StremioService _stremioService = StremioService.instance;
  final ScrollController _scrollController = ScrollController();

  List<StremioMeta> _results = [];
  bool _isLoading = false;
  String? _error;
  String _lastSearchedQuery =
      ''; // Track last searched query to avoid duplicate searches

  // Race condition protection - ignore stale search responses
  int _activeSearchRequestId = 0;

  // Debounce timer for search
  Timer? _debounceTimer;
  // Longer debounce for TV (remote typing is slower)
  Duration get _debounceDuration => widget.isTelevision
      ? const Duration(milliseconds: 750)
      : const Duration(milliseconds: 400);

  late FocusNode _keywordSearchFocusNode;
  late List<FocusNode> _resultFocusNodes;
  late List<GlobalKey> _resultCardKeys; // Keys for scroll-into-view
  int _focusedIndex = -1; // -1 = keyword card focused, 0+ = result index

  // Trakt integration
  bool _isTraktAuthenticated = false;

  // Bound sources for movies
  Map<String, List<SeriesSource>> _boundSources = {};

  @override
  void initState() {
    super.initState();
    _keywordSearchFocusNode = FocusNode(debugLabel: 'keyword_search_card');
    _resultFocusNodes = [];
    _resultCardKeys = [];
    // Notify parent of the focus node for external focus control
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onKeywordFocusNodeReady?.call(_keywordSearchFocusNode);
    });
    _refreshTraktAuthState();
    MainPageBridge.addIntegrationListener(_handleIntegrationChanged);
    // Initial search without debounce
    _performSearch();
  }

  Future<void> _refreshTraktAuthState() async {
    final auth = await TraktService.instance.isAuthenticated();
    if (!mounted) return;
    setState(() => _isTraktAuthenticated = auth);
  }

  void _handleIntegrationChanged() {
    _refreshTraktAuthState();
  }

  /// Request focus on the first result card (for DPAD navigation from Sources)
  /// Returns true if focus was set, false if no results to focus
  bool requestFocusOnFirstResult() {
    if (_resultFocusNodes.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return true;
    }
    return false;
  }

  /// Request focus on the last focused result card (for sidebar navigation)
  /// Returns true if focus was restored, false if no valid target
  bool requestFocusOnLastResult() {
    // If keyword card was last focused, focus it
    if (_focusedIndex == -1) {
      _keywordSearchFocusNode.requestFocus();
      return true;
    }
    // If a result was last focused, restore focus to it
    if (_focusedIndex >= 0 && _focusedIndex < _resultFocusNodes.length) {
      _resultFocusNodes[_focusedIndex].requestFocus();
      return true;
    }
    // Fallback to first result or keyword card
    if (_resultFocusNodes.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return true;
    }
    _keywordSearchFocusNode.requestFocus();
    return true;
  }

  /// Request focus on the keyword search card (for DPAD navigation from Sources)
  void requestFocusOnKeywordCard() {
    _keywordSearchFocusNode.requestFocus();
  }

  /// Check if there are results to navigate to
  bool get hasResults => _results.isNotEmpty;

  @override
  void didUpdateWidget(AggregatedSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only search if query actually changed AND we don't already have results for this query
    if (oldWidget.query != widget.query && widget.query != _lastSearchedQuery) {
      _debouncedSearch();
    }
  }

  void _debouncedSearch() {
    // Cancel any pending search
    _debounceTimer?.cancel();

    // If query is empty, clear results immediately
    if (widget.query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    // Start debounce timer
    _debounceTimer = Timer(_debounceDuration, () {
      if (mounted) {
        _performSearch();
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _scrollController.dispose();
    _keywordSearchFocusNode.dispose();
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    MainPageBridge.removeIntegrationListener(_handleIntegrationChanged);
    super.dispose();
  }

  Future<void> _performSearch() async {
    if (widget.query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isLoading = false;
      });
      return;
    }

    // Increment request ID to track this specific search request
    final int requestId = ++_activeSearchRequestId;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final searchQuery = widget.query; // Capture query at start of search
      final results = await _stremioService.searchCatalogs(searchQuery);

      // Race condition check: ignore stale responses from older requests
      if (!mounted || requestId != _activeSearchRequestId) {
        debugPrint(
          'AggregatedSearchResults: Ignoring stale response for "$searchQuery" (request $requestId, current $_activeSearchRequestId)',
        );
        return;
      }

      // Sort results by relevance (title match priority)
      final sortedResults = _sortByRelevance(results, searchQuery);

      // Update focus nodes for new results
      _updateFocusNodes(sortedResults.length);

      setState(() {
        _results = sortedResults;
        _isLoading = false;
        _lastSearchedQuery = searchQuery; // Remember what we searched for
      });
      _loadBoundSources();
    } catch (e) {
      // Race condition check for error case too
      if (!mounted || requestId != _activeSearchRequestId) {
        return;
      }
      setState(() {
        _error = 'Search failed: $e';
        _isLoading = false;
      });
    }
  }

  void _updateFocusNodes(int count) {
    // Dispose old nodes
    for (final node in _resultFocusNodes) {
      node.dispose();
    }
    // Create new nodes and keys
    _resultFocusNodes = List.generate(
      count,
      (i) => FocusNode(debugLabel: 'search_result_$i'),
    );
    _resultCardKeys = List.generate(
      count,
      (i) => GlobalKey(debugLabel: 'search_result_key_$i'),
    );
  }

  /// Sort results by relevance to the search query
  /// Priority: exact match > starts with > contains > other
  List<StremioMeta> _sortByRelevance(List<StremioMeta> results, String query) {
    final queryLower = query.toLowerCase().trim();

    int relevanceScore(StremioMeta item) {
      final titleLower = item.name.toLowerCase();

      // Exact match (highest priority)
      if (titleLower == queryLower) return 100;

      // Title starts with query
      if (titleLower.startsWith(queryLower)) return 80;

      // Query is a complete word in title
      final words = titleLower.split(RegExp(r'\s+'));
      if (words.any((w) => w == queryLower)) return 70;

      // Title contains query as substring
      if (titleLower.contains(queryLower)) return 50;

      // Any word in title starts with query
      if (words.any((w) => w.startsWith(queryLower))) return 30;

      // No direct match (lowest priority)
      return 0;
    }

    // Sort by relevance score (descending), then by rating if available
    final sorted = List<StremioMeta>.from(results);
    sorted.sort((a, b) {
      final scoreA = relevanceScore(a);
      final scoreB = relevanceScore(b);

      if (scoreA != scoreB) return scoreB - scoreA;

      // Secondary sort by rating
      final ratingA = a.imdbRating ?? 0;
      final ratingB = b.imdbRating ?? 0;
      return ratingB.compareTo(ratingA);
    });

    return sorted;
  }

  Future<void> _openItemDetail(StremioMeta item) async {
    final hasTrakt = item.hasValidImdbId ||
        (item.hasValidId &&
            (item.type == 'movie' || item.type == 'series'));
    final hasBoundSource =
        _boundSources.containsKey(item.effectiveImdbId ?? item.id);

    final traktItems = hasTrakt
        ? buildTraktAddOnlyMenuOptions(
            isSeries: item.type == 'series',
            isMovie: item.type == 'movie',
            hasBoundSource: hasBoundSource,
            isTraktAuthenticated: _isTraktAuthenticated,
          )
        : const <TraktMenuOption>[];

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CatalogItemDetailScreen(
          item: item,
          isTelevision: widget.isTelevision,
          showQuickPlay: widget.showQuickPlay,
          hasBoundSource: hasBoundSource,
          traktMenuOptions: traktItems,
          onTraktAction: (action) {
            // searchPacks/selectSource/stremioTv/random replace or leave
            // the host screen; the detail screen is pushed on top, so
            // close it first or the result happens invisibly behind it.
            const leaves = {
              TraktItemMenuAction.searchPacks,
              TraktItemMenuAction.selectSource,
              TraktItemMenuAction.addToStremioTv,
              TraktItemMenuAction.playRandomEpisode,
            };
            if (leaves.contains(action) &&
                Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
            handleTraktMenuAction(
              context,
              item,
              action,
              onSelectSource: widget.onSelectSource,
              onEditSource: _handleSelectSourceAction,
              onPlayRandomEpisode: (show) async {
                await widget.onPlayRandomEpisode?.call(
                  show,
                  show.sourceAddon,
                );
              },
              onSearchPacks: widget.onSearchPacks,
              onAddToStremioTv: _handleAddToStremioTv,
            );
          },
          onPlay: () => _onQuickPlay(item),
          // The shared detail screen no longer self-pops on Browse; preserve
          // the prior pop-then-callback behaviour here (aggregated episode
          // mode is still inline — migrated in a later slice).
          onBrowse: () {
            Navigator.of(context).pop();
            _onItemSelected(item);
          },
        ),
      ),
    );
  }

  void _onItemSelected(StremioMeta item) {
    // For series, try episode drill-down if source addon supports meta
    if (item.type == 'series' &&
        item.sourceAddon != null &&
        item.sourceAddon!.supportsMeta &&
        widget.onBrowseSeriesEpisodes != null) {
      widget.onBrowseSeriesEpisodes!(item, item.sourceAddon!);
      return;
    }

    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      contentType: item.type,
      posterUrl: item.poster,
    );
    widget.onItemSelected?.call(selection);
  }

  void _onQuickPlay(StremioMeta item) async {
    int? season;
    int? episode;

    // For series, look up last played episode to determine S/E
    if (item.type == 'series') {
      final imdbId = item.effectiveImdbId;
      if (imdbId != null) {
        final lastPlayed = await StorageService.getLastPlayedEpisodeByImdbId(
          imdbId,
        );
        if (!mounted) return;
        if (lastPlayed != null) {
          season = lastPlayed['season'] as int?;
          episode = lastPlayed['episode'] as int?;
        }
      }
      // Fallback to title-based lookup
      if (season == null || episode == null) {
        final byTitle = await StorageService.getLastPlayedEpisode(
          seriesTitle: item.name,
        );
        if (!mounted) return;
        if (byTitle != null) {
          season = byTitle['season'] as int?;
          episode = byTitle['episode'] as int?;
        }
      }
      season ??= 1;
      episode ??= 1;
    }

    final selection = AdvancedSearchSelection(
      imdbId: item.effectiveImdbId ?? item.id,
      isSeries: item.type == 'series',
      title: item.name,
      year: item.year,
      season: season,
      episode: episode,
      contentType: item.type,
      posterUrl: item.poster,
    );
    // Use onQuickPlay if available, otherwise fallback to onItemSelected
    if (widget.onQuickPlay != null) {
      widget.onQuickPlay!(selection);
    } else if (widget.onItemSelected != null) {
      widget.onItemSelected!(selection);
    }
  }

  KeyEventResult _handleKeywordCardKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onKeywordSearch();
      return KeyEventResult.handled;
    }

    // Up arrow: return focus to search field
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onRequestFocusAbove?.call();
      return KeyEventResult.handled;
    }

    // Down arrow: move to first result
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        _results.isNotEmpty) {
      _resultFocusNodes[0].requestFocus();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// Public: refresh bound sources cache (call after Select Source completes).
  void refreshBoundSources() => _loadBoundSources();

  /// Load bound sources for displayed movie and series items.
  Future<void> _loadBoundSources() async {
    final items = _results.where(
      (i) => i.type == 'movie' || i.type == 'series',
    );
    final sources = <String, List<SeriesSource>>{};
    for (final item in items) {
      final imdbId = item.effectiveImdbId ?? item.id;
      final list = await SeriesSourceService.getSources(imdbId);
      if (list.isNotEmpty) sources[imdbId] = list;
    }
    if (mounted) setState(() => _boundSources = sources);
  }

  /// Handle select source action — show edit dialog if source exists, otherwise show picker.
  void _handleSelectSourceAction(StremioMeta item) {
    final imdbId = item.effectiveImdbId ?? item.id;
    if (_boundSources.containsKey(imdbId)) {
      _showEditSourceDialog(item);
    } else {
      _showAddSourcePicker(item, imdbId);
    }
  }

  /// Show the add-source picker (Torrent Search / Real-Debrid / TorBox).
  /// Skips the picker if no cloud providers are enabled.
  Future<void> _showAddSourcePicker(StremioMeta item, String imdbId) async {
    final rdKey = await StorageService.getApiKey();
    final torboxKey = await StorageService.getTorboxApiKey();
    final rdEnabled = rdKey != null && rdKey.isNotEmpty;
    final torboxEnabled = torboxKey != null && torboxKey.isNotEmpty;

    if (!mounted) return;

    final isMovie = item.type == 'movie';
    final supportsLocal = isMovie || item.type == 'series';

    if (!rdEnabled && !torboxEnabled && !supportsLocal) {
      widget.onSelectSource?.call(item);
      return;
    }

    await showAddSourcePickerDialog(
      context,
      onTorrentSearch: () => widget.onSelectSource?.call(item),
      onKeywordSearch: widget.onKeywordSelectSource != null
          ? () => widget.onKeywordSelectSource!.call(item)
          : null,
      onLocal: supportsLocal && !LocalBoundSourceService.isLocalBindingDisabled
          ? () => _pickAndSaveLocalSource(item, imdbId)
          : null,
      localDisabledReason: supportsLocal
          ? LocalBoundSourceService.localDisabledReason
          : null,
      onRealDebrid: rdEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: true,
              torboxEnabled: false,
            )
          : null,
      onTorbox: torboxEnabled
          ? () => _pushDebridSelectSource(
              show: item,
              imdbId: imdbId,
              rdEnabled: false,
              torboxEnabled: true,
            )
          : null,
    );
  }

  Future<void> _pickAndSaveLocalSource(StremioMeta item, String imdbId) async {
    final SeriesSource? source;
    if (item.type == 'series') {
      source = await LocalBoundSourceService.pickSeriesSource(
        context,
        title: item.name,
      );
    } else {
      source = await LocalBoundSourceService.pickMovieSource(
        context,
        title: item.name,
        year: item.year,
      );
    }
    if (source == null) return;

    if (item.type == 'series') {
      await SeriesSourceService.addSource(imdbId, source);
    } else {
      await SeriesSourceService.setSources(imdbId, [source]);
    }
    final updated = await SeriesSourceService.getSources(imdbId);
    if (!mounted) return;
    setState(() => _boundSources[imdbId] = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Local source set: ${source.torrentName}'),
        backgroundColor: const Color(0xFF10B981),
      ),
    );
  }

  /// Show "Edit Sources" dialog with list of bound sources and management options.
  Future<void> _showEditSourceDialog(StremioMeta show) async {
    final imdbId = show.effectiveImdbId ?? show.id;
    final isMovie = show.type == 'movie';
    var sources = List<SeriesSource>.of(
      _boundSources[imdbId] ?? await SeriesSourceService.getSources(imdbId),
    );
    if (sources.isEmpty || !mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 450,
                  maxHeight: 500,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF60A5FA),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isMovie
                                ? 'Movie Source'
                                : 'Series Sources (${sources.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (!isMovie) ...[
                        const SizedBox(height: 4),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'First match wins — reorder by priority',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Flexible(
                        child: isMovie
                            ? ListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                itemBuilder: (context, index) {
                                  final source = sources[index];
                                  return _buildSourceListTile(
                                    key: ValueKey(source.torrentHash),
                                    source: source,
                                    index: index,
                                    showDragHandle: false,
                                    onDelete: () async {
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
                                      setDialogState(() {
                                        sources.clear();
                                        sources.addAll(updated);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          if (updated.isEmpty) {
                                            _boundSources.remove(imdbId);
                                          } else {
                                            _boundSources[imdbId] = updated;
                                          }
                                        });
                                      }
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                                  );
                                },
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: sources.length,
                                onReorder: (oldIndex, newIndex) {
                                  if (newIndex > oldIndex) newIndex--;
                                  setDialogState(() {
                                    final item = sources.removeAt(oldIndex);
                                    sources.insert(newIndex, item);
                                  });
                                  SeriesSourceService.setSources(
                                    imdbId,
                                    List.of(sources),
                                  );
                                  setState(
                                    () => _boundSources[imdbId] = List.of(
                                      sources,
                                    ),
                                  );
                                },
                                proxyDecorator: (child, index, animation) {
                                  return Material(
                                    color: Colors.transparent,
                                    elevation: 4,
                                    child: child,
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final source = sources[index];
                                  return _buildSourceListTile(
                                    key: ValueKey(source.torrentHash),
                                    source: source,
                                    index: index,
                                    onDelete: () async {
                                      await SeriesSourceService.removeSourceByHash(
                                        imdbId,
                                        source.torrentHash,
                                      );
                                      final updated =
                                          await SeriesSourceService.getSources(
                                            imdbId,
                                          );
                                      setDialogState(() {
                                        sources.clear();
                                        sources.addAll(updated);
                                      });
                                      if (mounted) {
                                        setState(() {
                                          if (updated.isEmpty) {
                                            _boundSources.remove(imdbId);
                                          } else {
                                            _boundSources[imdbId] = updated;
                                          }
                                        });
                                      }
                                      if (updated.isEmpty &&
                                          dialogContext.mounted) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _showAddSourcePicker(show, imdbId);
                              },
                              icon: Icon(
                                isMovie
                                    ? Icons.swap_horiz_rounded
                                    : Icons.add_rounded,
                                size: 18,
                              ),
                              label: Text(
                                isMovie ? 'Change Source' : 'Add Source',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF6366F1),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          if (!isMovie && sources.length > 1) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  if (mounted) {
                                    setState(
                                      () => _boundSources.remove(imdbId),
                                    );
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'Remove All',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (isMovie) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await SeriesSourceService.removeAllSources(
                                    imdbId,
                                  );
                                  if (mounted) {
                                    setState(
                                      () => _boundSources.remove(imdbId),
                                    );
                                  }
                                  if (dialogContext.mounted)
                                    Navigator.of(dialogContext).pop();
                                },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Color(0xFFEF4444),
                                ),
                                label: const Text(
                                  'Remove',
                                  style: TextStyle(color: Color(0xFFEF4444)),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: Color(0xFFEF4444),
                                    width: 1,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text(
                          'Close',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _handleAddToStremioTv(StremioMeta item) async {
    final result = await StremioTvCatalogPickerDialog.show(context, item: item);
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.duplicate
            ? Colors.orange.shade700
            : const Color(0xFF34D399),
      ),
    );
  }

  /// Push debrid downloads screen in select-source mode.
  /// If both providers enabled, shows a picker first.
  void _pushDebridSelectSource({
    required StremioMeta show,
    required String imdbId,
    required bool rdEnabled,
    required bool torboxEnabled,
  }) {
    final isMovie = show.type == 'movie';

    Future<void> saveSource(SeriesSource source) async {
      if (isMovie) {
        await SeriesSourceService.setSources(imdbId, [source]);
      } else {
        await SeriesSourceService.addSource(imdbId, source);
      }
      final updated = await SeriesSourceService.getSources(imdbId);
      if (mounted) {
        setState(() => _boundSources[imdbId] = updated);
      }
    }

    void pushRd() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DebridDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    void pushTorbox() {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TorboxDownloadsScreen(
            isPushedRoute: true,
            initialSearchQuery: show.name,
            selectSourceMode: true,
            onSourceSelected: saveSource,
          ),
        ),
      );
    }

    // If only one provider, push directly
    if (rdEnabled && !torboxEnabled) {
      pushRd();
      return;
    }
    if (torboxEnabled && !rdEnabled) {
      pushTorbox();
      return;
    }

    // Both enabled — show picker
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Select Provider',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF22C55E)),
              title: const Text(
                'Real-Debrid',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushRd();
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud, color: Color(0xFF7C3AED)),
              title: const Text(
                'TorBox',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                pushTorbox();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Build a single source tile for the Edit Sources dialog.
  Widget _buildSourceListTile({
    required Key key,
    required SeriesSource source,
    required int index,
    required VoidCallback onDelete,
    bool showDragHandle = true,
  }) {
    Color serviceColor;
    String serviceLabel;
    switch (source.debridService) {
      case 'rd':
        serviceColor = const Color(0xFF10B981);
        serviceLabel = 'Real-Debrid';
      case 'torbox':
        serviceColor = const Color(0xFF3B82F6);
        serviceLabel = 'TorBox';
      case 'pikpak':
        serviceColor = const Color(0xFFF59E0B);
        serviceLabel = 'PikPak';
      case 'premiumize':
        serviceColor = const Color(0xFFFB923C);
        serviceLabel = 'Premiumize';
      case SeriesSource.localService:
        serviceColor = const Color(0xFF60A5FA);
        serviceLabel = 'Local';
      default:
        serviceColor = Colors.white54;
        serviceLabel = source.debridService;
    }

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          if (showDragHandle) ...[
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF60A5FA).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${index + 1}',
                style: const TextStyle(
                  color: Color(0xFF60A5FA),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.torrentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: serviceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    serviceLabel,
                    style: TextStyle(
                      color: serviceColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFFEF4444),
            ),
            onPressed: onDelete,
            tooltip: 'Remove source',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          if (showDragHandle)
            const Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: Colors.white24,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        // "Search [keyword]" action card - always first
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _KeywordSearchCard(
              query: widget.query,
              focusNode: _keywordSearchFocusNode,
              isFocused: _focusedIndex == -1,
              onTap: widget.onKeywordSearch,
              onFocusChange: (focused) {
                setState(() {
                  _focusedIndex = focused ? -1 : _focusedIndex;
                });
              },
              onKeyEvent: _handleKeywordCardKeyEvent,
            ),
          ),
        ),

        // Results section header
        if (_results.isNotEmpty || _isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.movie_filter,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Catalog Results',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!_isLoading) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_results.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Loading state
        if (_isLoading)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ShimmerCard(),
                ),
                childCount: 6,
              ),
            ),
          ),

        // Error state
        if (_error != null && !_isLoading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

        // Results grid
        if (!_isLoading && _error == null && _results.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              MediaQuery.of(context).size.width >= 900 ? 40 : 20,
              8,
              MediaQuery.of(context).size.width >= 900 ? 40 : 20,
              24,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: catalogGridColumnsFor(
                  MediaQuery.of(context).size.width,
                  isTelevision: widget.isTelevision,
                ),
                childAspectRatio: 0.667,
                mainAxisSpacing: 24,
                crossAxisSpacing: 18,
              ),
              delegate: SliverChildBuilderDelegate((context, index) {
                final item = _results[index];
                return KeyedSubtree(
                  key: _resultCardKeys[index],
                  child: CatalogItemTile(
                    item: item,
                    isTelevision: widget.isTelevision,
                    focusNode: _resultFocusNodes[index],
                    hasBoundSource: _boundSources.containsKey(
                      item.effectiveImdbId ?? item.id,
                    ),
                    onOpen: () => _openItemDetail(item),
                    onLongPress: widget.showQuickPlay
                        ? () => _onQuickPlay(item)
                        : null,
                  ),
                );
              }, childCount: _results.length),
            ),
          ),

        // Empty state
        if (!_isLoading && _error == null && _results.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No catalog results found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try the keyword search above for torrent results',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(
                        0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact "Search torrents" action chip
class _KeywordSearchCard extends StatelessWidget {
  final String query;
  final FocusNode focusNode;
  final bool isFocused;
  final VoidCallback onTap;
  final ValueChanged<bool> onFocusChange;
  final KeyEventResult Function(FocusNode, KeyEvent) onKeyEvent;

  const _KeywordSearchCard({
    required this.query,
    required this.focusNode,
    required this.isFocused,
    required this.onTap,
    required this.onFocusChange,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Focus(
      focusNode: focusNode,
      onFocusChange: onFocusChange,
      onKeyEvent: onKeyEvent,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(28),
              border: isFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: 'Tap to search ',
                          style: TextStyle(color: Colors.white70),
                        ),
                        TextSpan(
                          text: '"$query"',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward,
                  color: Colors.white70,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal catalog result card with thumbnail on left
/// Features Quick Play and Sources buttons with DPAD navigation support
class _ShimmerCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          // Thumbnail placeholder
          Container(
            width: 56,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: 120,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 80,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
