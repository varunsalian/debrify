import 'dart:ui';
import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';
import '../../../models/torrent.dart';
import '../../../services/series_source_fetcher.dart';
import '../../../widgets/tv_text_field.dart';

/// In-player source switcher panel (right-sliding, Netflix-dark).
///
/// Flat plays show Direct/Torrent tabs. Series plays that carry a
/// [SeriesSourceFetcher] split torrents into Packs/Episodes/Direct (same
/// coverage_type classification as the Android TV player), and tabs whose
/// dedicated search never ran offer a "Load more sources" action that runs
/// the missing search and appends the results (append-only merge).
class SourceSheet extends StatefulWidget {
  final List<Torrent> sources;
  final int currentSourceIndex;
  final Future<String?> Function(Torrent) resolveSource;
  final void Function(int index, String resolvedUrl) onSourceSelected;
  final VoidCallback onClose;

  /// Load-more backend. Null for plays without one (IPTV, YouTube, manual
  /// picks…) — the sheet then behaves like the classic flat picker.
  final SeriesSourceFetcher? seriesFetcher;

  /// Currently playing position, so "Load more → Episodes" targets the
  /// episode on screen (pack playlists auto-advance without relaunching).
  final int? currentSeason;
  final int? currentEpisode;

  /// Fired with the full merged list after a successful load-more. The owner
  /// must adopt it as the new effective sources (append-only: existing
  /// entries keep their positions).
  final void Function(List<Torrent> merged)? onSourcesMerged;

  const SourceSheet({
    Key? key,
    required this.sources,
    required this.currentSourceIndex,
    required this.resolveSource,
    required this.onSourceSelected,
    required this.onClose,
    this.seriesFetcher,
    this.currentSeason,
    this.currentEpisode,
    this.onSourcesMerged,
  }) : super(key: key);

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

enum _FocusZone { tabs, search, sources }

class _TabDef {
  final String id;
  final String label;
  final List<Torrent> sources;
  final bool hasCurrent;
  const _TabDef(this.id, this.label, this.sources, this.hasCurrent);
}

class _SourceSheetState extends State<SourceSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  // Pulsing glow for playing badge on source tiles
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  List<_TabDef> _tabs = [];
  int _activeTab = 0;
  List<Torrent> _filteredSources = [];
  int _focusedIndex = 0;
  _FocusZone _focusZone = _FocusZone.sources;

  // Resolution state
  int? _resolvingIndex; // Original index in widget.sources being resolved
  String? _errorMessage; // Brief error message shown at bottom

  // Load-more state: the mode currently in flight, or null.
  String? _loadingMode;

  // Design tokens (Netflix-dark, matching the TV unified menu)
  static const _accent = Color(0xFFE50914);
  static const _accentSoft = Color(0xFFFF4D57);
  static const _surfaceDark = Color(0xFF141414);

  bool get _seriesTabs =>
      widget.seriesFetcher != null && !widget.seriesFetcher!.isMovie;

  @override
  void initState() {
    super.initState();

    // A television opens this over the player, whose root Focus already holds
    // focus in this scope — so `autofocus: true` on the KeyboardListener never
    // wins and the sheet renders its virtual focus while receiving no keys at
    // all (the DPAD appears dead). Claim focus explicitly once mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });

    _rebuildTabs();
    _autoSelectTab();
    _recomputeFilters();

    // Slide + fade in
    _animController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
        parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );

    // Pulsing glow for playing badge
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _animController.forward();

    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _focusZone != _FocusZone.search) {
        setState(() => _focusZone = _FocusZone.search);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentSource();
    });
  }

  @override
  void didUpdateWidget(SourceSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Load-more merged in a new sources list (owner adopted it): re-bucket.
    // Append-only merge keeps tab identity stable, so the active tab stays.
    if (!identical(oldWidget.sources, widget.sources) ||
        oldWidget.currentSourceIndex != widget.currentSourceIndex) {
      _rebuildTabs();
      if (_activeTab >= _tabs.length) _activeTab = 0;
      // Keep the user's focus where it was (append-only merges preserve
      // indices) instead of letting the recompute snap it back to the
      // PLAYING row above the freshly appended results.
      final keepFocus = _focusedIndex;
      _recomputeFilters();
      _focusedIndex = keepFocus.clamp(0, _maxFocusIndex);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    _animController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  // ─── Categorization ────────────────────────────────────────────────

  static bool _isPack(Torrent t) =>
      t.coverageType == 'seasonPack' ||
      t.coverageType == 'multiSeasonPack' ||
      t.coverageType == 'completeSeries';

  void _rebuildTabs() {
    final direct =
        widget.sources.where((t) => t.isDirectStream).toList();
    final torrents = widget.sources
        .where((t) => t.streamType == StreamType.torrent)
        .toList();

    final cur = (widget.currentSourceIndex >= 0 &&
            widget.currentSourceIndex < widget.sources.length)
        ? widget.sources[widget.currentSourceIndex]
        : null;
    bool hasCur(List<Torrent> list) =>
        cur != null && list.any((t) => _isSameTorrent(t, cur));

    if (_seriesTabs) {
      final packs = torrents.where(_isPack).toList();
      final episodes = torrents.where((t) => !_isPack(t)).toList();
      _tabs = [
        _TabDef('packs', 'Packs', packs, hasCur(packs)),
        _TabDef('episodes', 'Episodes', episodes, hasCur(episodes)),
        _TabDef('direct', 'Direct', direct, hasCur(direct)),
      ];
    } else {
      _tabs = [
        _TabDef('direct', 'Direct', direct, hasCur(direct)),
        _TabDef('torrent', 'Torrent', torrents, hasCur(torrents)),
      ];
    }
  }

  void _autoSelectTab() {
    // Land on the tab holding the currently playing source; otherwise the
    // first tab that has anything to show (or offers load-more).
    final curIdx = _tabs.indexWhere((t) => t.hasCurrent);
    if (curIdx >= 0) {
      _activeTab = curIdx;
      return;
    }
    final nonEmpty = _tabs.indexWhere((t) => t.sources.isNotEmpty);
    if (nonEmpty >= 0) _activeTab = nonEmpty;
  }

  List<Torrent> get _currentTabSources =>
      _tabs.isEmpty ? const [] : _tabs[_activeTab].sources;

  /// Fetch mode offered on the active tab, or null when that tab's search
  /// already ran (or there is no fetcher).
  String? get _activeLoadMoreMode {
    final f = widget.seriesFetcher;
    if (f == null || _tabs.isEmpty) return null;
    final id = _tabs[_activeTab].id;
    if (f.isMovie) {
      return (id == 'torrent' && !f.movieFetched)
          ? SeriesSourceFetcher.modeMovie
          : null;
    }
    if (id == 'packs' && !f.packsFetched) return SeriesSourceFetcher.modePacks;
    if (id == 'episodes' && !f.episodesFetched) {
      return SeriesSourceFetcher.modeEpisodes;
    }
    return null;
  }

  // ─── Filtering ─────────────────────────────────────────────────────

  /// Recompute filtered sources and focused index. Mutates state directly
  /// without calling setState — safe to call from inside a setState block.
  void _recomputeFilters() {
    final query = _searchController.text.toLowerCase();
    final tabSources = _currentTabSources;
    _filteredSources = tabSources.where((t) {
      if (query.isEmpty) return true;
      return t.displayTitle.toLowerCase().contains(query) ||
          t.source.toLowerCase().contains(query);
    }).toList();

    final currentOrigIdx = widget.currentSourceIndex;
    if (currentOrigIdx >= 0 && currentOrigIdx < widget.sources.length) {
      final current = widget.sources[currentOrigIdx];
      final idx = _filteredSources.indexWhere((t) => _isSameTorrent(t, current));
      if (idx >= 0) {
        _focusedIndex = idx;
        return;
      }
    }
    _focusedIndex = _focusedIndex.clamp(0, _maxFocusIndex);
  }

  /// Whether the load-more row/CTA is actually on screen: a search query
  /// that empties the tab shows the plain "no matches" state instead.
  bool get _loadMoreVisible =>
      _activeLoadMoreMode != null &&
      (_filteredSources.isNotEmpty || _searchController.text.isEmpty);

  /// Highest focusable index in the list zone: sources, plus the trailing
  /// load-more row when visible (also focusable at 0 on an empty tab).
  int get _maxFocusIndex {
    final count = _filteredSources.length + (_loadMoreVisible ? 1 : 0);
    return count > 0 ? count - 1 : 0;
  }

  /// Recompute filters and trigger a rebuild.
  void _applyFilters() {
    setState(() {
      _recomputeFilters();
    });
  }

  bool _isSameTorrent(Torrent a, Torrent b) {
    if (a.infohash.isNotEmpty && b.infohash.isNotEmpty) {
      return a.infohash == b.infohash;
    }
    return a.directUrl == b.directUrl && a.name == b.name;
  }

  int _getOriginalIndex(Torrent torrent) {
    return widget.sources.indexWhere((t) => _isSameTorrent(t, torrent));
  }

  // ─── Scrolling ─────────────────────────────────────────────────────

  void _scrollToFocused() {
    if (!_scrollController.hasClients) return;
    const h = 72.0;
    final target = _focusedIndex * h;
    final vp = _scrollController.position.viewportDimension;
    final cur = _scrollController.offset;
    if (target < cur || target > cur + vp - h) {
      _scrollController.animateTo(
        (target - vp / 2 + h / 2)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _scrollToCurrentSource() {
    if (_filteredSources.isEmpty || !_scrollController.hasClients) return;
    final currentOrigIdx = widget.currentSourceIndex;
    if (currentOrigIdx >= 0 && currentOrigIdx < widget.sources.length) {
      final current = widget.sources[currentOrigIdx];
      final idx = _filteredSources.indexWhere((t) => _isSameTorrent(t, current));
      if (idx >= 0) {
        _focusedIndex = idx;
        _scrollToFocused();
      }
    }
  }

  // ─── Source Selection ──────────────────────────────────────────────

  Future<void> _selectSource(Torrent torrent) async {
    final origIdx = _getOriginalIndex(torrent);
    if (origIdx < 0) return;
    if (origIdx == widget.currentSourceIndex) return; // Already playing

    setState(() => _resolvingIndex = origIdx);

    try {
      final url = await widget.resolveSource(torrent);
      if (!mounted) return;

      if (url != null && url.isNotEmpty) {
        widget.onSourceSelected(origIdx, url);
      } else {
        // Resolution failed — flash red on tile + show error message
        setState(() {
          _resolvingIndex = -1;
          _errorMessage = 'Source unavailable — not cached or not a video';
        });
        await Future.delayed(const Duration(seconds: 3));
        if (mounted) setState(() { _resolvingIndex = null; _errorMessage = null; });
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('SourceSheet: Resolution error: $e');
      setState(() {
        _resolvingIndex = -1;
        _errorMessage = 'Failed to resolve source';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) setState(() { _resolvingIndex = null; _errorMessage = null; });
    }
  }

  // ─── Load more ─────────────────────────────────────────────────────

  Future<void> _loadMore() async {
    final mode = _activeLoadMoreMode;
    final fetcher = widget.seriesFetcher;
    if (mode == null || fetcher == null || _loadingMode != null) return;

    setState(() {
      _loadingMode = mode;
      _errorMessage = null;
    });

    List<Torrent>? fetched;
    try {
      fetched = await fetcher.fetch(
        mode,
        season: widget.currentSeason,
        episode: widget.currentEpisode,
      );
    } catch (e) {
      debugPrint('SourceSheet: Load more failed: $e');
      fetched = null;
    }

    if (fetched != null) {
      // Deliver the merge even if the sheet was closed mid-fetch: the
      // fetcher's flag has already flipped, so dropping the results here
      // would lose them with no way to re-run the search.
      final merged = SeriesSourceFetcher.mergeSources(widget.sources, fetched);
      widget.onSourcesMerged?.call(merged);
      if (mounted) {
        setState(() => _loadingMode = null);
      }
      return;
    }

    if (!mounted) return;

    // Failure: the fetcher keeps the flag down, so the row survives for a
    // retry — mirror the resolution-error banner pattern.
    setState(() {
      _loadingMode = null;
      _errorMessage = "Couldn't fetch more sources — try again";
    });
    await Future.delayed(const Duration(seconds: 3));
    if (mounted && _loadingMode == null) {
      setState(() => _errorMessage = null);
    }
  }

  // ─── Keyboard / DPAD ──────────────────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      TvOverlayBack.mark();
      widget.onClose();
      return;
    }

    switch (_focusZone) {
      case _FocusZone.tabs:
        _handleTabKeys(event);
        break;
      case _FocusZone.search:
        _handleSearchKeys(event);
        break;
      case _FocusZone.sources:
        _handleSourceKeys(event);
        break;
    }
  }

  void _handleTabKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_activeTab > 0) {
        setState(() {
          _activeTab--;
          _focusedIndex = 0;
          _recomputeFilters();
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_activeTab < _tabs.length - 1) {
        setState(() {
          _activeTab++;
          _focusedIndex = 0;
          _recomputeFilters();
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusZone = _FocusZone.search);
      _searchFocusNode.requestFocus();
    }
  }

  void _handleSearchKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _searchFocusNode.unfocus();
      // Reclaim the sheet's key listener: unfocusing clears the scope's
      // focused child, and without this the list paints a focused row but
      // stops receiving DPAD keys entirely.
      _keyboardFocusNode.requestFocus();
      setState(() => _focusZone = _FocusZone.tabs);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
      // Reclaim the sheet's key listener: unfocusing clears the scope's
      // focused child, and without this the list paints a focused row but
      // stops receiving DPAD keys entirely.
      _keyboardFocusNode.requestFocus();
      setState(() => _focusZone = _FocusZone.sources);
    }
  }

  void _handleSourceKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
      } else {
        _searchFocusNode.requestFocus();
        setState(() => _focusZone = _FocusZone.search);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _maxFocusIndex) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
      }
    } else if (isActivateKey(event.logicalKey)) {
      if (_focusedIndex >= _filteredSources.length) {
        // Trailing load-more row (or the empty-tab CTA at index 0).
        if (_loadMoreVisible) _loadMore();
      } else if (_filteredSources.isNotEmpty && _resolvingIndex == null) {
        _selectSource(_filteredSources[_focusedIndex]);
      }
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────

  /// TV: skip the frosted-glass BackdropFilter. The panel fill is 97% opaque,
  /// so the blur is barely visible — but its saveLayer re-blurs the live video
  /// underneath on every frame, which weak TV GPUs can't afford.
  Widget _frost(Widget child) {
    if (PlatformUtil.isTelevision) return child;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final panelWidth =
        isLandscape ? mq.size.width * 0.42 : mq.size.width * 0.92;

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Stack(
        children: [
          // Scrim
          GestureDetector(
            onTap: widget.onClose,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Container(color: Colors.black54),
            ),
          ),
          // Panel
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: panelWidth,
            child: SlideTransition(
              position: _slideAnim,
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  bottomLeft: Radius.circular(28),
                ),
                child: _frost(
                  Container(
                    decoration: BoxDecoration(
                      color: _surfaceDark.withOpacity(0.97),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        bottomLeft: Radius.circular(28),
                      ),
                      border: Border(
                        left: BorderSide(
                            color: Colors.white.withOpacity(0.06), width: 0.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildHeader(),
                        _buildTabBar(),
                        _buildSearchBar(),
                        Expanded(child: _buildSourceList()),
                        if (_errorMessage != null)
                          _buildErrorBanner(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Error Banner ──────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return AnimatedOpacity(
      opacity: _errorMessage != null ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 4, 20, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red.withOpacity(0.8), size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _errorMessage ?? '',
                style: TextStyle(
                  color: Colors.red.withOpacity(0.9),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Header ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final totalCount = widget.sources.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_accent, _accentSoft],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: _accent.withOpacity(0.25),
                    blurRadius: 16,
                    spreadRadius: 2),
              ],
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Sources',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$totalCount sources available',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onClose,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Icon(Icons.close_rounded,
                    color: Colors.white.withOpacity(0.5), size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab Bar ───────────────────────────────────────────────────────

  Widget _buildTabBar() {
    final inTabZone = _focusZone == _FocusZone.tabs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _buildTab(
                tab: _tabs[i],
                index: i,
                isFocused: inTabZone && _activeTab == i,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab({
    required _TabDef tab,
    required int index,
    required bool isFocused,
  }) {
    final isActive = _activeTab == index;
    final count = tab.sources.length;
    final isEmpty = count == 0;
    // An empty tab stays tappable when it can load more sources.
    final canLoadMore = widget.seriesFetcher != null &&
        (widget.seriesFetcher!.isMovie
            ? (tab.id == 'torrent' && !widget.seriesFetcher!.movieFetched)
            : (tab.id == 'packs' && !widget.seriesFetcher!.packsFetched) ||
                (tab.id == 'episodes' &&
                    !widget.seriesFetcher!.episodesFetched));

    return Expanded(
      child: GestureDetector(
        onTap: (isEmpty && !canLoadMore)
            ? null
            : () {
                setState(() {
                  _activeTab = index;
                  _focusedIndex = 0;
                  _recomputeFilters();
                });
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: isActive
                ? const LinearGradient(
                    colors: [_accent, _accentSoft],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
            border: isFocused && !isActive
                ? Border.all(color: _accentSoft.withOpacity(0.6), width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (tab.hasCurrent && !isActive) ...[
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: _accentSoft,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: (isEmpty && !canLoadMore)
                        ? Colors.white.withOpacity(0.2)
                        : isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withOpacity(0.2)
                      : isEmpty
                          ? Colors.white.withOpacity(0.04)
                          : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isEmpty
                        ? Colors.white.withOpacity(0.15)
                        : isActive
                            ? Colors.white
                            : Colors.white.withOpacity(0.4),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Search ────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final hasFocus = _focusZone == _FocusZone.search;
    final hasQuery = _searchController.text.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: hasFocus
              ? Colors.white.withOpacity(0.08)
              : Colors.white.withOpacity(0.04),
          border: Border.all(
            color: hasFocus ? _accentSoft.withOpacity(0.4) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: hasFocus
              ? [BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 16)]
              : [],
        ),
        child: TvTextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w400),
          decoration: InputDecoration(
            hintText: 'Search sources...',
            hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.25),
                fontSize: 13,
                fontWeight: FontWeight.w400),
            prefixIcon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                hasQuery ? Icons.filter_list_rounded : Icons.search_rounded,
                key: ValueKey(hasQuery),
                color: hasFocus
                    ? _accentSoft.withOpacity(0.7)
                    : Colors.white.withOpacity(0.3),
                size: 20,
              ),
            ),
            suffixIcon: hasQuery
                ? IconButton(
                    icon: Icon(Icons.clear_rounded,
                        color: Colors.white.withOpacity(0.4), size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                    },
                  )
                : null,
            filled: false,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) {
            _applyFilters();
          },
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  // ─── Source List ───────────────────────────────────────────────────

  Widget _buildSourceList() {
    final loadMoreMode = _activeLoadMoreMode;
    final inSourceZone = _focusZone == _FocusZone.sources;

    if (_filteredSources.isEmpty) {
      if (loadMoreMode != null && _searchController.text.isEmpty) {
        return _buildEmptyLoadMoreState(
            focused: inSourceZone && _focusedIndex == 0);
      }
      return _buildEmptyState();
    }

    final extraRow = _loadMoreVisible ? 1 : 0;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _filteredSources.length + extraRow,
      itemBuilder: (context, index) {
        if (index >= _filteredSources.length) {
          return _LoadMoreRow(
            isLoading: _loadingMode != null,
            isFocused: inSourceZone && _focusedIndex == index,
            onTap: _loadMore,
          );
        }
        final source = _filteredSources[index];
        final origIdx = _getOriginalIndex(source);
        final isCurrent = origIdx == widget.currentSourceIndex;
        final isFocused = inSourceZone && index == _focusedIndex;
        final isResolving = _resolvingIndex == origIdx;
        final isError = _resolvingIndex == -1 && index == _focusedIndex;

        return _SourceTile(
          source: source,
          isFocused: isFocused,
          isCurrent: isCurrent,
          isResolving: isResolving,
          isError: isError,
          showSeeders: source.streamType == StreamType.torrent,
          pulseAnim: _pulseAnim,
          onTap: () {
            if (_resolvingIndex == null) {
              _selectSource(source);
            }
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final tabName =
        _tabs.isEmpty ? 'matching' : _tabs[_activeTab].label.toLowerCase();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cloud_off_rounded,
              color: Colors.white.withOpacity(0.1),
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No $tabName sources available',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _searchController.text.isNotEmpty
                ? 'Try a different search term'
                : 'This content has no $tabName streams',
            style: TextStyle(
                color: Colors.white.withOpacity(0.2), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyLoadMoreState({required bool focused}) {
    final tab = _tabs[_activeTab];
    final isLoading = _loadingMode != null;
    final String subtitle;
    if (tab.id == 'packs') {
      subtitle = "A dedicated season-pack search hasn't run for this play.";
    } else if (tab.id == 'episodes') {
      subtitle = "Individual episodes weren't searched for this play.";
    } else {
      subtitle = "A full source search hasn't run for this play.";
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.travel_explore_rounded,
              color: Colors.white.withOpacity(0.25),
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No ${tab.label.toLowerCase()} sources yet',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11.5,
                  height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: isLoading ? null : _loadMore,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                gradient: isLoading
                    ? null
                    : const LinearGradient(colors: [_accent, _accentSoft]),
                color: isLoading ? Colors.white.withOpacity(0.06) : null,
                borderRadius: BorderRadius.circular(10),
                border: focused
                    ? Border.all(color: Colors.white, width: 1.5)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _accentSoft,
                      ),
                    )
                  else
                    const Icon(Icons.add_rounded,
                        color: Colors.white, size: 17),
                  const SizedBox(width: 8),
                  Text(
                    isLoading ? 'Searching for sources…' : 'Load more sources',
                    style: TextStyle(
                      color:
                          isLoading ? Colors.white.withOpacity(0.6) : Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Load-more Row
// ═══════════════════════════════════════════════════════════════════════════

class _LoadMoreRow extends StatelessWidget {
  final bool isLoading;
  final bool isFocused;
  final VoidCallback onTap;

  static const _accentSoft = Color(0xFFFF4D57);

  const _LoadMoreRow({
    required this.isLoading,
    required this.isFocused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        height: 48,
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isFocused
              ? _accentSoft.withOpacity(0.08)
              : Colors.transparent,
          border: Border.all(
            color: isFocused
                ? _accentSoft.withOpacity(0.8)
                : _accentSoft.withOpacity(isLoading ? 0.2 : 0.45),
            width: 1.5,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _accentSoft,
                  ),
                )
              else
                const Icon(Icons.add_rounded, color: _accentSoft, size: 18),
              const SizedBox(width: 8),
              Text(
                isLoading ? 'Searching for sources…' : 'Load more sources',
                style: TextStyle(
                  color: isLoading
                      ? Colors.white.withOpacity(0.5)
                      : _accentSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Source Tile
// ═══════════════════════════════════════════════════════════════════════════

class _SourceTile extends StatelessWidget {
  final Torrent source;
  final bool isFocused;
  final bool isCurrent;
  final bool isResolving;
  final bool isError;
  final bool showSeeders;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  static const _accent = Color(0xFFE50914);
  static const _accentSoft = Color(0xFFFF4D57);

  const _SourceTile({
    required this.source,
    required this.isFocused,
    required this.isCurrent,
    required this.isResolving,
    required this.isError,
    required this.showSeeders,
    required this.pulseAnim,
    required this.onTap,
  });

  static String _detectQuality(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd')) return '4K';
    if (lower.contains('1080p') || lower.contains('1080i')) return '1080p';
    if (lower.contains('720p')) return '720p';
    if (lower.contains('480p') || lower.contains('sd')) return '480p';
    return '?';
  }

  static Color _qualityColor(String quality) {
    switch (quality) {
      case '4K':
        return const Color(0xFFFFB300);
      case '1080p':
        return const Color(0xFF42A5F5);
      case '720p':
        return const Color(0xFF66BB6A);
      default:
        return Colors.white.withOpacity(0.4);
    }
  }

  static String _formatSize(int bytes) {
    if (bytes <= 0) return '';
    const gb = 1024 * 1024 * 1024;
    const mb = 1024 * 1024;
    if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(1)} GB';
    }
    if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final quality = _detectQuality(source.name);
    final qColor = _qualityColor(quality);
    final size = _formatSize(source.sizeBytes);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        height: 64,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isFocused
              ? LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.06),
                  ],
                )
              : isCurrent
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        _accent.withOpacity(0.10),
                        _accent.withOpacity(0.02),
                      ],
                    )
                  : isError
                      ? LinearGradient(
                          colors: [
                            Colors.red.withOpacity(0.15),
                            Colors.red.withOpacity(0.05),
                          ],
                        )
                      : null,
          color: (!isFocused && !isCurrent && !isError)
              ? Colors.transparent
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isError
                ? Colors.red.withOpacity(0.5)
                : isFocused
                    ? _accentSoft.withOpacity(0.6)
                    : isCurrent
                        ? _accent.withOpacity(0.25)
                        : Colors.transparent,
            width: isFocused ? 1.5 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                      color: _accent.withOpacity(0.1),
                      blurRadius: 16,
                      spreadRadius: 2),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Quality badge
            Container(
              width: 48,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: qColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: qColor.withOpacity(0.2)),
              ),
              child: Text(
                quality,
                style: TextStyle(
                  color: qColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    source.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? _accentSoft
                          : isFocused
                              ? Colors.white
                              : Colors.white.withOpacity(0.85),
                      fontSize: 13,
                      fontWeight:
                          isFocused || isCurrent ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (size.isNotEmpty)
                        _buildChip(size, const Color(0xFF42A5F5)),
                      if (showSeeders && source.seeders > 0) ...[
                        if (size.isNotEmpty) const SizedBox(width: 6),
                        _buildChip('${source.seeders} S', const Color(0xFF66BB6A)),
                      ],
                      if (source.source.isNotEmpty) ...[
                        if (size.isNotEmpty || (showSeeders && source.seeders > 0))
                          const SizedBox(width: 6),
                        _buildChip(source.source, const Color(0xFFAB47BC)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status badge
            if (isResolving)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(_accentSoft.withOpacity(0.8)),
                ),
              )
            else if (isCurrent)
              _buildPlayingBadge()
            else if (isError)
              Icon(Icons.error_outline_rounded,
                  color: Colors.red.withOpacity(0.7), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color.withOpacity(0.8),
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPlayingBadge() {
    return AnimatedBuilder(
      animation: pulseAnim,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _accent.withOpacity(0.8 + pulseAnim.value * 0.2),
                _accentSoft.withOpacity(0.6 + pulseAnim.value * 0.2),
              ],
            ),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: _accent.withOpacity(0.2 + pulseAnim.value * 0.1),
                  blurRadius: 10),
            ],
          ),
          child: const Text(
            'PLAYING',
            style: TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        );
      },
    );
  }
}
