import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/torrent.dart';

/// Premium Stremio source sheet overlay for the video player.
/// Right-sliding frosted glass panel with Direct/Torrent tabs and source list.
class SourceSheet extends StatefulWidget {
  final List<Torrent> sources;
  final int currentSourceIndex;
  final Future<String?> Function(Torrent) resolveSource;
  final void Function(int index, String resolvedUrl) onSourceSelected;
  final VoidCallback onClose;

  const SourceSheet({
    Key? key,
    required this.sources,
    required this.currentSourceIndex,
    required this.resolveSource,
    required this.onSourceSelected,
    required this.onClose,
  }) : super(key: key);

  @override
  State<SourceSheet> createState() => _SourceSheetState();
}

enum _FocusZone { tabs, search, sources }

class _SourceSheetState extends State<SourceSheet>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _fadeAnim;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // Tab state: 0 = Direct, 1 = Torrent
  int _activeTab = 0;
  List<Torrent> _directSources = [];
  List<Torrent> _torrentSources = [];
  List<Torrent> _filteredSources = [];
  int _focusedIndex = 0;
  _FocusZone _focusZone = _FocusZone.sources;

  // Resolution state
  int? _resolvingIndex; // Original index in widget.sources being resolved
  String? _errorMessage; // Brief error message shown at bottom

  // Design tokens
  static const _accent = Color(0xFF536DFE); // Indigo accent
  static const _accentAlt = Color(0xFF3D5AFE);
  static const _surfaceDark = Color(0xFF101016);

  @override
  void initState() {
    super.initState();

    _categorizeSources();
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

    // Pulsing glow for now-playing
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

  void _categorizeSources() {
    _directSources = widget.sources
        .where((t) => t.isDirectStream)
        .toList();
    _torrentSources = widget.sources
        .where((t) => t.streamType == StreamType.torrent)
        .toList();
  }

  void _autoSelectTab() {
    // Auto-select tab that has the currently playing source
    if (widget.currentSourceIndex >= 0 &&
        widget.currentSourceIndex < widget.sources.length) {
      final current = widget.sources[widget.currentSourceIndex];
      if (current.isDirectStream) {
        _activeTab = 0;
      } else {
        _activeTab = 1;
      }
    } else if (_directSources.isEmpty && _torrentSources.isNotEmpty) {
      _activeTab = 1;
    }
  }

  List<Torrent> get _currentTabSources =>
      _activeTab == 0 ? _directSources : _torrentSources;

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
      } else {
        _focusedIndex = _filteredSources.isNotEmpty
            ? _focusedIndex.clamp(0, _filteredSources.length - 1)
            : 0;
      }
    } else {
      _focusedIndex = 0;
    }
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
    if (_filteredSources.isEmpty || !_scrollController.hasClients) return;
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

  // ─── Keyboard / DPAD ──────────────────────────────────────────────

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
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
          _activeTab = 0;
          _recomputeFilters();
        });
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_activeTab < 1) {
        setState(() {
          _activeTab = 1;
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
      setState(() => _focusZone = _FocusZone.tabs);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
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
      if (_focusedIndex < _filteredSources.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (_filteredSources.isNotEmpty && _resolvingIndex == null) {
        _selectSource(_filteredSources[_focusedIndex]);
      }
    }
  }

  // ─── Quality Helpers ───────────────────────────────────────────────

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
        return const Color(0xFFFFB300); // Amber
      case '1080p':
        return const Color(0xFF42A5F5); // Blue
      case '720p':
        return const Color(0xFF66BB6A); // Green
      default:
        return Colors.white.withOpacity(0.4); // Gray
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

  // ─── Build ─────────────────────────────────────────────────────────

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
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                  child: Container(
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
                        _buildNowPlaying(),
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
                colors: [_accent, _accentAlt],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: _accent.withOpacity(0.25),
                    blurRadius: 16,
                    spreadRadius: 2),
                BoxShadow(
                    color: _accentAlt.withOpacity(0.15),
                    blurRadius: 24,
                    spreadRadius: 4),
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

  // ─── Now Playing ───────────────────────────────────────────────────

  Widget _buildNowPlaying() {
    if (widget.currentSourceIndex < 0 ||
        widget.currentSourceIndex >= widget.sources.length) {
      return const SizedBox.shrink();
    }

    final cur = widget.sources[widget.currentSourceIndex];
    final quality = _detectQuality(cur.name);

    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _accent.withOpacity(0.08),
                _accentAlt.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _accent.withOpacity(0.12 + _pulseAnim.value * 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.05),
                blurRadius: 20,
              ),
            ],
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: _EqualizerBars(color: _accent),
              ),
              const SizedBox(width: 12),
              // Quality badge mini
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _qualityColor(quality).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  quality,
                  style: TextStyle(
                    color: _qualityColor(quality),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (cur.source.isNotEmpty)
                      Text(
                        cur.source,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PLAYING',
                  style: TextStyle(
                    color: _accent.withOpacity(0.9),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
            _buildTab(
              label: 'Direct',
              count: _directSources.length,
              index: 0,
              isFocused: inTabZone && _activeTab == 0,
            ),
            _buildTab(
              label: 'Torrent',
              count: _torrentSources.length,
              index: 1,
              isFocused: inTabZone && _activeTab == 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required int count,
    required int index,
    required bool isFocused,
  }) {
    final isActive = _activeTab == index;
    final isEmpty = count == 0;

    return Expanded(
      child: GestureDetector(
        onTap: isEmpty
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
                ? LinearGradient(
                    colors: [_accent, _accentAlt],
                  )
                : null,
            borderRadius: BorderRadius.circular(10),
            border: isFocused && !isActive
                ? Border.all(color: _accent.withOpacity(0.5), width: 1.5)
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isEmpty
                      ? Colors.white.withOpacity(0.2)
                      : isActive
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.2,
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
            color: hasFocus ? _accent.withOpacity(0.4) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: hasFocus
              ? [BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 16)]
              : [],
        ),
        child: TextField(
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
                    ? _accent.withOpacity(0.7)
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
    if (_filteredSources.isEmpty) {
      final typeName = _activeTab == 0 ? 'direct' : 'torrent';
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
                _activeTab == 0
                    ? Icons.link_off_rounded
                    : Icons.cloud_off_rounded,
                color: Colors.white.withOpacity(0.1),
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No $typeName sources available',
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
                  : 'This content has no $typeName streams',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final inSourceZone = _focusZone == _FocusZone.sources;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _filteredSources.length,
      itemExtent: 72,
      itemBuilder: (context, index) {
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
          isTorrentTab: _activeTab == 1,
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
  final bool isTorrentTab;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  static const _accent = Color(0xFF536DFE);
  static const _accentAlt = Color(0xFF3D5AFE);

  const _SourceTile({
    required this.source,
    required this.isFocused,
    required this.isCurrent,
    required this.isResolving,
    required this.isError,
    required this.isTorrentTab,
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
                        _accent.withOpacity(0.08),
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
                    ? _accent.withOpacity(0.5)
                    : isCurrent
                        ? _accent.withOpacity(0.12)
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
                          ? _accent
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
                      if (isTorrentTab && source.seeders > 0) ...[
                        if (size.isNotEmpty) const SizedBox(width: 6),
                        _buildChip('${source.seeders} S', const Color(0xFF66BB6A)),
                      ],
                      if (source.source.isNotEmpty) ...[
                        if (size.isNotEmpty || (isTorrentTab && source.seeders > 0))
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
                  valueColor: AlwaysStoppedAnimation(_accent.withOpacity(0.7)),
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
                _accentAlt.withOpacity(0.6 + pulseAnim.value * 0.2),
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

// ═══════════════════════════════════════════════════════════════════════════
// Equalizer Bars (animated "playing" indicator)
// ═══════════════════════════════════════════════════════════════════════════

class _EqualizerBars extends StatefulWidget {
  final Color color;
  const _EqualizerBars({required this.color});

  @override
  State<_EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<_EqualizerBars>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    final rng = math.Random();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        duration: Duration(milliseconds: 400 + rng.nextInt(300)),
        vsync: this,
      )..repeat(reverse: true);
    });
    _animations = _controllers.map((c) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: c, curve: Curves.easeInOut),
      );
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (context, child) {
            return Container(
              width: 3,
              height: 14 * _animations[i].value,
              margin: EdgeInsets.only(right: i < 2 ? 2 : 0),
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.8),
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}
