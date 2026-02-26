import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/torrent.dart';
import '../../../widgets/shimmer.dart';

/// Stremio TV channel guide overlay for the Flutter video player.
/// Right-sliding frosted glass panel with search, now-playing, and channel list.
/// Follows the IptvChannelSheet pattern.
class StremioTvGuideSheet extends StatefulWidget {
  final List<Map<String, dynamic>> channels;
  final String? currentChannelId;
  final Future<Map<String, dynamic>?> Function(List<String>)? guideDataProvider;
  final Future<Map<String, dynamic>?> Function(String) channelSwitchProvider;
  final void Function(
    String channelId,
    String url,
    String title, {
    String? contentImdbId,
    String? contentType,
    double? startAtPercent,
    List<Torrent>? newSources,
    int? newSourceIndex,
    Future<String?> Function(Torrent)? sourceResolver,
  }) onChannelSwitched;
  final VoidCallback onClose;

  const StremioTvGuideSheet({
    Key? key,
    required this.channels,
    this.currentChannelId,
    this.guideDataProvider,
    required this.channelSwitchProvider,
    required this.onChannelSwitched,
    required this.onClose,
  }) : super(key: key);

  @override
  State<StremioTvGuideSheet> createState() => _StremioTvGuideSheetState();
}

enum _FocusZone { search, channels }

class _StremioTvGuideSheetState extends State<StremioTvGuideSheet>
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

  List<_ChannelData> _allChannels = [];
  List<_ChannelData> _filteredChannels = [];
  String? _currentChannelId;
  int _focusedIndex = 0;
  _FocusZone _focusZone = _FocusZone.channels;

  String? _switchingChannelId;
  String? _errorMessage;
  Timer? _errorTimer;
  final Set<String> _loadingIds = {};

  // Design tokens (matching IptvChannelSheet)
  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00B8D4);
  static const _surfaceDark = Color(0xFF101016);

  @override
  void initState() {
    super.initState();

    _currentChannelId = widget.currentChannelId;
    _parseChannels();

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
      _scrollToFocused();
      _loadGuideDataForRange(_focusedIndex);
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
    _errorTimer?.cancel();
    super.dispose();
  }

  // ─── Data Parsing ─────────────────────────────────────────────────

  void _parseChannels() {
    _allChannels = widget.channels.asMap().entries.map((e) {
      return _ChannelData.fromMap(e.value, index: e.key);
    }).toList();

    _filteredChannels = List.from(_allChannels);

    // Focus on current channel
    if (_currentChannelId != null) {
      final idx =
          _filteredChannels.indexWhere((c) => c.id == _currentChannelId);
      if (idx >= 0) _focusedIndex = idx;
    }
  }

  void _loadGuideDataForRange(int centerIndex) {
    if (widget.guideDataProvider == null) return;

    final start = math.max(0, centerIndex - 5);
    final end = math.min(_filteredChannels.length - 1, centerIndex + 5);
    if (start > end) return;

    final idsToLoad = <String>[];
    for (int i = start; i <= end; i++) {
      final ch = _filteredChannels[i];
      if (!ch.hasGuideData && !_loadingIds.contains(ch.id)) {
        idsToLoad.add(ch.id);
      }
    }
    if (idsToLoad.isEmpty) return;

    _loadingIds.addAll(idsToLoad);

    // Fire-and-forget — don't block UI
    widget.guideDataProvider!(idsToLoad).then((result) {
      _loadingIds.removeAll(idsToLoad);
      if (result == null || !mounted) return;
      setState(() {
        for (final ch in _allChannels) {
          if (result.containsKey(ch.id)) {
            final data = result[ch.id] as Map<String, dynamic>;
            ch.applyGuideData(data);
          }
        }
      });
    }).catchError((e) {
      debugPrint('StremioTvGuide: Failed to load guide data: $e');
      _loadingIds.removeAll(idsToLoad);
    });
  }

  // ─── Filtering ────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredChannels = _allChannels.where((c) {
        if (query.isEmpty) return true;
        return c.name.toLowerCase().contains(query) ||
            c.type.toLowerCase().contains(query) ||
            (c.nowPlayingTitle?.toLowerCase().contains(query) ?? false);
      }).toList();

      if (_currentChannelId != null) {
        final idx =
            _filteredChannels.indexWhere((c) => c.id == _currentChannelId);
        _focusedIndex = idx >= 0
            ? idx
            : _filteredChannels.isNotEmpty
                ? _focusedIndex.clamp(0, _filteredChannels.length - 1)
                : 0;
      } else {
        _focusedIndex = _filteredChannels.isNotEmpty
            ? _focusedIndex.clamp(0, _filteredChannels.length - 1)
            : 0;
      }
    });
    _loadGuideDataForRange(_focusedIndex);
  }

  // ─── Scrolling ────────────────────────────────────────────────────

  void _scrollToFocused() {
    if (_filteredChannels.isEmpty || !_scrollController.hasClients) return;
    const h = 104.0;
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

  // ─── Channel Selection ────────────────────────────────────────────

  Future<void> _selectChannel(_ChannelData channel) async {
    if (_switchingChannelId != null) return; // guard against rapid taps
    if (channel.id == _currentChannelId) return; // already playing

    setState(() {
      _switchingChannelId = channel.id;
      _errorMessage = null;
    });
    _errorTimer?.cancel();

    try {
      final result = await widget.channelSwitchProvider(channel.id);
      if (!mounted) return;

      if (result == null) {
        _showError('Channel unavailable');
        return;
      }

      final url = result['url'] as String?;
      final title = result['title'] as String? ?? channel.name;
      if (url == null || url.isEmpty) {
        _showError('No stream available');
        return;
      }

      // Parse sources if provided
      List<Torrent>? newSources;
      int? newSourceIndex;
      final rawSources = result['stremioSources'];
      if (rawSources is List) {
        newSources = rawSources
            .map((s) => s is Map<String, dynamic> ? Torrent.fromJson(s) : null)
            .whereType<Torrent>()
            .toList();
        newSourceIndex = result['stremioCurrentSourceIndex'] as int? ?? 0;
      }

      setState(() {
        _currentChannelId = channel.id;
        _switchingChannelId = null;
      });

      // Extract source resolver if provided
      final sourceResolver = result['sourceResolver'] as Future<String?> Function(Torrent)?;

      widget.onChannelSwitched(
        channel.id,
        url,
        title,
        contentImdbId: result['contentImdbId'] as String?,
        contentType: result['contentType'] as String?,
        startAtPercent: (result['startAtPercent'] as num?)?.toDouble(),
        newSources: newSources,
        newSourceIndex: newSourceIndex,
        sourceResolver: sourceResolver,
      );
    } catch (e) {
      debugPrint('StremioTvGuide: Channel switch failed: $e');
      if (mounted) _showError('Switch failed');
    }
  }

  void _showError(String message) {
    setState(() {
      _switchingChannelId = null;
      _errorMessage = message;
    });
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _errorMessage = null);
    });
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
      case _FocusZone.search:
        _handleSearchKeys(event);
        break;
      case _FocusZone.channels:
        _handleChannelKeys(event);
        break;
    }
  }

  void _handleSearchKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
      setState(() => _focusZone = _FocusZone.channels);
    }
  }

  void _handleChannelKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
        _loadGuideDataForRange(_focusedIndex);
      } else {
        _searchFocusNode.requestFocus();
        setState(() => _focusZone = _FocusZone.search);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _filteredChannels.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
        _loadGuideDataForRange(_focusedIndex);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (_filteredChannels.isNotEmpty) {
        _selectChannel(_filteredChannels[_focusedIndex]);
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────

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
                        _buildSearchBar(),
                        if (_errorMessage != null) _buildErrorBanner(),
                        Expanded(child: _buildChannelList()),
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

  // ─── Header ───────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
      child: Row(
        children: [
          // Icon with gradient glow
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
            child: const Icon(Icons.tv_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Channel Guide',
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
                  '${_filteredChannels.length} of ${_allChannels.length} channels',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Close button
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

  // ─── Now Playing ──────────────────────────────────────────────────

  Widget _buildNowPlaying() {
    final current = _currentChannelId != null
        ? _allChannels.where((c) => c.id == _currentChannelId).firstOrNull
        : null;
    if (current == null) return const SizedBox.shrink();

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
              // Equalizer bars
              SizedBox(
                width: 16,
                height: 16,
                child: _EqualizerBars(color: _accent),
              ),
              const SizedBox(width: 12),
              // Poster mini (36×54)
              _buildMiniPoster(current),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (current.nowPlayingTitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatNowPlayingText(current),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.45),
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _accent.withOpacity(0.8),
                      _accentAlt.withOpacity(0.6),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.25),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Text(
                  'PLAYING',
                  style: TextStyle(
                    color: Colors.white,
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

  String _formatNowPlayingText(_ChannelData ch) {
    final parts = <String>[];
    if (ch.nowPlayingTitle != null) parts.add(ch.nowPlayingTitle!);
    if (ch.nowPlayingYear != null) parts.add('(${ch.nowPlayingYear})');
    if (ch.nowPlayingRating != null) parts.add('\u2605 ${ch.nowPlayingRating!.toStringAsFixed(1)}');
    return parts.join(' ');
  }

  Widget _buildMiniPoster(_ChannelData channel) {
    final hasPoster =
        channel.nowPlayingPoster != null && channel.nowPlayingPoster!.isNotEmpty;
    return Container(
      width: 36,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withOpacity(0.06),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasPoster
          ? CachedNetworkImage(
              imageUrl: channel.nowPlayingPoster!,
              fit: BoxFit.cover,
              placeholder: (_, __) => _letterAvatar(channel.name, 12),
              errorWidget: (_, __, ___) => _letterAvatar(channel.name, 12),
            )
          : _letterAvatar(channel.name, 12),
    );
  }

  // ─── Search ───────────────────────────────────────────────────────

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
            hintText: 'Search channels...',
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
          onChanged: (_) => _applyFilters(),
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  // ─── Error Banner ─────────────────────────────────────────────────

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded,
              color: Colors.red.withOpacity(0.7), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: Colors.red.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Channel List ─────────────────────────────────────────────────

  Widget _buildChannelList() {
    if (_filteredChannels.isEmpty) {
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
              child: Icon(Icons.satellite_alt_rounded,
                  color: Colors.white.withOpacity(0.1), size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              'No channels found',
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search term',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.2), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final inChannelZone = _focusZone == _FocusZone.channels;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      itemCount: _filteredChannels.length,
      itemExtent: 104,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        final isCurrent = channel.id == _currentChannelId;
        final isFocused = inChannelZone && index == _focusedIndex;
        final isSwitching = channel.id == _switchingChannelId;

        return _ChannelTile(
          channel: channel,
          isFocused: isFocused,
          isCurrent: isCurrent,
          isSwitching: isSwitching,
          pulseAnim: _pulseAnim,
          onTap: () => _selectChannel(channel),
        );
      },
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────

  static Widget _letterAvatar(String name, double fontSize) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final color = _avatarColor(name);
    return Container(
      color: color.withOpacity(0.15),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
            color: color, fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
    );
  }

  static Color _avatarColor(String name) {
    const hues = [0.0, 15.0, 160.0, 190.0, 210.0, 240.0, 270.0, 300.0, 330.0];
    final index = name.hashCode.abs() % hues.length;
    return HSLColor.fromAHSL(1.0, hues[index], 0.6, 0.6).toColor();
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Channel Data Model
// ═════════════════════════════════════════════════════════════════════════════

class _ChannelData {
  final String id;
  final String name;
  final String type;
  final int number;
  final bool isFavorite;

  // Now playing (nullable, loaded lazily)
  String? nowPlayingTitle;
  String? nowPlayingPoster;
  String? nowPlayingYear;
  double? nowPlayingRating;
  double? nowPlayingProgress;
  int? nowPlayingSlotEndMs;

  // Next up
  String? nextUpTitle;
  String? nextUpYear;
  double? nextUpRating;

  bool hasGuideData;

  _ChannelData({
    required this.id,
    required this.name,
    required this.type,
    required this.number,
    this.isFavorite = false,
    this.hasGuideData = false,
  });

  factory _ChannelData.fromMap(Map<String, dynamic> map, {int index = 0}) {
    final ch = _ChannelData(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? 'Unknown',
      type: map['type'] as String? ?? 'movie',
      number: map['number'] as int? ?? (index + 1),
      isFavorite: map['isFavorite'] as bool? ?? false,
    );

    // Parse pre-loaded now-playing data
    final np = map['nowPlaying'];
    if (np is Map<String, dynamic>) {
      ch.nowPlayingTitle = np['title'] as String?;
      ch.nowPlayingPoster = np['poster'] as String?;
      ch.nowPlayingYear = np['year']?.toString();
      ch.nowPlayingRating = (np['rating'] as num?)?.toDouble();
      ch.nowPlayingProgress = (np['progress'] as num?)?.toDouble();
      ch.nowPlayingSlotEndMs = np['slotEndMs'] as int?;
      ch.hasGuideData = true;
    }

    final next = map['nextUp'];
    if (next is Map<String, dynamic>) {
      ch.nextUpTitle = next['title'] as String?;
      ch.nextUpYear = next['year']?.toString();
      ch.nextUpRating = (next['rating'] as num?)?.toDouble();
    }

    return ch;
  }

  void applyGuideData(Map<String, dynamic> data) {
    final np = data['nowPlaying'];
    if (np is Map<String, dynamic>) {
      nowPlayingTitle = np['title'] as String?;
      nowPlayingPoster = np['poster'] as String?;
      nowPlayingYear = np['year']?.toString();
      nowPlayingRating = (np['rating'] as num?)?.toDouble();
      nowPlayingProgress = (np['progress'] as num?)?.toDouble();
      nowPlayingSlotEndMs = np['slotEndMs'] as int?;
    }
    final next = data['nextUp'];
    if (next is Map<String, dynamic>) {
      nextUpTitle = next['title'] as String?;
      nextUpYear = next['year']?.toString();
      nextUpRating = (next['rating'] as num?)?.toDouble();
    }
    hasGuideData = true;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Channel Tile
// ═════════════════════════════════════════════════════════════════════════════

class _ChannelTile extends StatelessWidget {
  final _ChannelData channel;
  final bool isFocused;
  final bool isCurrent;
  final bool isSwitching;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00BCD4);
  static const _goldStar = Color(0xFFFFD700);

  static Color _avatarColor(String name) {
    const hues = [0.0, 15.0, 160.0, 190.0, 210.0, 240.0, 270.0, 300.0, 330.0];
    final index = name.hashCode.abs() % hues.length;
    return HSLColor.fromAHSL(1.0, hues[index], 0.6, 0.6).toColor();
  }

  const _ChannelTile({
    required this.channel,
    required this.isFocused,
    required this.isCurrent,
    required this.isSwitching,
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showAccent = isCurrent || isFocused;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
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
                        _accent.withOpacity(0.03),
                      ],
                    )
                  : null,
          color: (!isFocused && !isCurrent) ? Colors.transparent : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? _accent.withOpacity(0.5)
                : isCurrent
                    ? _accent.withOpacity(0.12)
                    : Colors.transparent,
            width: isFocused ? 1.5 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                      color: _accent.withOpacity(0.12),
                      blurRadius: 16,
                      spreadRadius: 2),
                  BoxShadow(
                      color: _accent.withOpacity(0.06),
                      blurRadius: 24,
                      spreadRadius: 4),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Left accent bar
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              height: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                gradient: showAccent
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_accent, _accentAlt],
                      )
                    : null,
                color: showAccent ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
            const SizedBox(width: 6),
            // Channel number
            SizedBox(
              width: 30,
              child: Text(
                channel.number.toString().padLeft(2, ' '),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isCurrent
                      ? _accent.withOpacity(0.8)
                      : isFocused
                          ? Colors.white.withOpacity(0.5)
                          : Colors.white.withOpacity(0.18),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Poster (48×72)
            _buildPoster(),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Channel name + type badge
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          channel.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? _accent
                                : isFocused
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.85),
                            fontSize: 12,
                            fontWeight:
                                isFocused || isCurrent ? FontWeight.w600 : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _buildTypeBadge(),
                    ],
                  ),
                  // Now playing with gold star
                  if (channel.nowPlayingTitle != null) ...[
                    const SizedBox(height: 2),
                    _buildNowPlayingRichText(),
                  ],
                  // Next up
                  if (channel.nextUpTitle != null) ...[
                    const SizedBox(height: 1),
                    Text(
                      _buildNextUpLine(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  // Progress bar with glow
                  if (channel.nowPlayingProgress != null &&
                      channel.nowPlayingProgress! > 0) ...[
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: _accent.withOpacity(0.3),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: channel.nowPlayingProgress!.clamp(0.0, 1.0),
                          backgroundColor: Colors.white.withOpacity(0.06),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isCurrent
                                ? _accent.withOpacity(0.7)
                                : _accent.withOpacity(0.3),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Loading shimmer state
                  if (!channel.hasGuideData && channel.nowPlayingTitle == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Shimmer(
                            width: 120,
                            height: 10,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 4),
                          Shimmer(
                            width: 80,
                            height: 8,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status badge
            if (isSwitching)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                      _accent.withOpacity(0.7)),
                ),
              )
            else if (isCurrent)
              _buildNowBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
    final typeLabel = channel.type.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        typeLabel == 'MOVIE' ? 'MOVIE' : 'SERIES',
        style: TextStyle(
          color: isCurrent ? _accent : Colors.white.withOpacity(0.35),
          fontSize: 8,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildNowPlayingRichText() {
    final parts = <String>[];
    if (channel.nowPlayingTitle != null) parts.add(channel.nowPlayingTitle!);
    if (channel.nowPlayingYear != null) parts.add('(${channel.nowPlayingYear})');

    final baseText = parts.join(' ');
    final hasRating = channel.nowPlayingRating != null && channel.nowPlayingRating! > 0;

    if (!hasRating) {
      return Text(
        baseText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isFocused
              ? Colors.white.withOpacity(0.7)
              : Colors.white.withOpacity(0.5),
          fontSize: 11,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    final ratingText = ' \u2605 ${channel.nowPlayingRating!.toStringAsFixed(1)}';
    final textColor = isFocused
        ? Colors.white.withOpacity(0.7)
        : Colors.white.withOpacity(0.5);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: baseText,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          TextSpan(
            text: ratingText,
            style: const TextStyle(
              color: _goldStar,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _buildNextUpLine() {
    final parts = <String>['Next:'];
    if (channel.nextUpTitle != null) parts.add(channel.nextUpTitle!);
    if (channel.nextUpYear != null) parts.add('(${channel.nextUpYear})');
    return parts.join(' ');
  }

  Widget _buildPoster() {
    final hasPoster =
        channel.nowPlayingPoster != null && channel.nowPlayingPoster!.isNotEmpty;

    return Container(
      width: 48,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: isCurrent
              ? _accent.withOpacity(0.15)
              : isFocused
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.03),
        ),
        boxShadow: [
          if (isCurrent)
            BoxShadow(color: _accent.withOpacity(0.1), blurRadius: 10),
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: hasPoster
                ? CachedNetworkImage(
                    imageUrl: channel.nowPlayingPoster!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => _buildLetterAvatar(),
                    errorWidget: (_, __, ___) => _buildLetterAvatar(),
                  )
                : _buildLetterAvatar(),
          ),
          // Bottom gradient overlay for depth
          if (hasPoster)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.4),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLetterAvatar() {
    final letter =
        channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '?';
    final color = _avatarColor(channel.name);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.25),
            color.withOpacity(0.1),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: color.withOpacity(0.85),
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNowBadge() {
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
            'NOW',
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

// ═════════════════════════════════════════════════════════════════════════════
// Equalizer Bars (animated "playing" indicator)
// ═════════════════════════════════════════════════════════════════════════════

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
