import 'dart:ui';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/iptv_playlist.dart';

/// Premium IPTV channel sheet overlay for the video player.
/// Full-height right panel with frosted glass, search, and channel list.
class IptvChannelSheet extends StatefulWidget {
  final List<IptvChannel> channels;
  final int currentIndex;
  final void Function(int index) onChannelSelected;
  final VoidCallback onClose;

  const IptvChannelSheet({
    Key? key,
    required this.channels,
    required this.currentIndex,
    required this.onChannelSelected,
    required this.onClose,
  }) : super(key: key);

  @override
  State<IptvChannelSheet> createState() => _IptvChannelSheetState();
}

enum _FocusZone { search, channels }

class _IptvChannelSheetState extends State<IptvChannelSheet>
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

  List<IptvChannel> _filteredChannels = [];
  int _focusedIndex = 0;
  _FocusZone _focusZone = _FocusZone.channels;

  // Design tokens
  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00B8D4);
  static const _surfaceDark = Color(0xFF101016);

  @override
  void initState() {
    super.initState();

    _filteredChannels = List.from(widget.channels);

    if (widget.currentIndex >= 0 &&
        widget.currentIndex < widget.channels.length) {
      final cur = widget.channels[widget.currentIndex];
      final idx = _filteredChannels
          .indexWhere((c) => c.url == cur.url && c.name == cur.name);
      if (idx >= 0) _focusedIndex = idx;
    }

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

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToFocused());
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

  // ─── Filtering ───────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredChannels = widget.channels.where((c) {
        return query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            (c.group != null && c.group!.toLowerCase().contains(query));
      }).toList();

      final cur = (widget.currentIndex >= 0 &&
              widget.currentIndex < widget.channels.length)
          ? widget.channels[widget.currentIndex]
          : null;
      final idx = cur == null
          ? -1
          : _filteredChannels
              .indexWhere((c) => c.url == cur.url && c.name == cur.name);
      _focusedIndex = idx >= 0
          ? idx
          : _filteredChannels.isNotEmpty
              ? _focusedIndex.clamp(0, _filteredChannels.length - 1)
              : 0;
    });
  }

  // ─── Scrolling ───────────────────────────────────────────────────────

  void _scrollToFocused() {
    if (_filteredChannels.isEmpty || !_scrollController.hasClients) return;
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

  // ─── Keyboard / DPAD ────────────────────────────────────────────────

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
      } else {
        _searchFocusNode.requestFocus();
        setState(() => _focusZone = _FocusZone.search);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_focusedIndex < _filteredChannels.length - 1) {
        setState(() => _focusedIndex++);
        _scrollToFocused();
      }
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      if (_filteredChannels.isNotEmpty) {
        final ch = _filteredChannels[_focusedIndex];
        final oi = widget.channels
            .indexWhere((c) => c.url == ch.url && c.name == ch.name);
        if (oi >= 0) widget.onChannelSelected(oi);
      }
    }
  }

  int _getOriginalIndex(IptvChannel channel) {
    return widget.channels
        .indexWhere((c) => c.url == channel.url && c.name == channel.name);
  }

  // ─── Build ──────────────────────────────────────────────────────────

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

  // ─── Header ─────────────────────────────────────────────────────────

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
            child: const Icon(Icons.live_tv_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Channels',
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
                  '${_filteredChannels.length} of ${widget.channels.length} channels',
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

  // ─── Now Playing ───────────────────────────────────────────────────

  Widget _buildNowPlaying() {
    final cur = (widget.currentIndex >= 0 &&
            widget.currentIndex < widget.channels.length)
        ? widget.channels[widget.currentIndex]
        : null;
    if (cur == null) return const SizedBox.shrink();

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
              // Animated equalizer bars
              SizedBox(
                width: 16,
                height: 16,
                child: _EqualizerBars(color: _accent),
              ),
              const SizedBox(width: 12),
              // Channel logo mini
              _buildMiniLogo(cur),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (cur.group != null && cur.group!.isNotEmpty)
                      Text(
                        cur.group!,
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

  /// Generate a vibrant avatar color — avoids muddy yellows/olives
  static Color _avatarColor(String name) {
    // Use a curated palette of vibrant hues that look great on dark backgrounds
    const hues = [0.0, 15.0, 160.0, 190.0, 210.0, 240.0, 270.0, 300.0, 330.0];
    final index = name.hashCode.abs() % hues.length;
    return HSLColor.fromAHSL(1.0, hues[index], 0.6, 0.6).toColor();
  }

  Widget _buildMiniLogo(IptvChannel channel) {
    final hasLogo = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(7),
        color: Colors.white.withOpacity(0.06),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: channel.logoUrl!,
              fit: BoxFit.contain,
              placeholder: (_, __) => _letterAvatar(channel, 12),
              errorWidget: (_, __, ___) => _letterAvatar(channel, 12),
            )
          : _letterAvatar(channel, 12),
    );
  }

  Widget _letterAvatar(IptvChannel channel, double fontSize) {
    final letter =
        channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '?';
    final color = _avatarColor(channel.name);
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

  // ─── Search ─────────────────────────────────────────────────────────

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
            hintText: 'Search channels or categories...',
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

  // ─── Channel List ───────────────────────────────────────────────────

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
      itemExtent: 72,
      itemBuilder: (context, index) {
        final channel = _filteredChannels[index];
        final origIdx = _getOriginalIndex(channel);
        final isCurrent = origIdx == widget.currentIndex;
        final isFocused = inChannelZone && index == _focusedIndex;

        return _ChannelTile(
          channel: channel,
          isFocused: isFocused,
          isCurrent: isCurrent,
          channelNumber: origIdx + 1,
          pulseAnim: _pulseAnim,
          onTap: () {
            if (origIdx >= 0) widget.onChannelSelected(origIdx);
          },
        );
      },
    );
  }

}

// ═══════════════════════════════════════════════════════════════════════════
// Channel Tile
// ═══════════════════════════════════════════════════════════════════════════

class _ChannelTile extends StatelessWidget {
  final IptvChannel channel;
  final bool isFocused;
  final bool isCurrent;
  final int channelNumber;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  static const _accent = Color(0xFF00E5FF);
  static const _accentAlt = Color(0xFF00B8D4);
  static const _liveDot = Color(0xFFFF3D71);

  static Color _avatarColor(String name) {
    const hues = [0.0, 15.0, 160.0, 190.0, 210.0, 240.0, 270.0, 300.0, 330.0];
    final index = name.hashCode.abs() % hues.length;
    return HSLColor.fromAHSL(1.0, hues[index], 0.6, 0.6).toColor();
  }

  const _ChannelTile({
    required this.channel,
    required this.isFocused,
    required this.isCurrent,
    required this.channelNumber,
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                      color: _accent.withOpacity(0.1),
                      blurRadius: 16,
                      spreadRadius: 2),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Channel number
            SizedBox(
              width: 30,
              child: Text(
                channelNumber.toString().padLeft(2, ' '),
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
            const SizedBox(width: 10),
            // Logo
            _buildLogo(),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent
                          ? _accent
                          : isFocused
                              ? Colors.white
                              : Colors.white.withOpacity(0.85),
                      fontSize: 13.5,
                      fontWeight:
                          isFocused || isCurrent ? FontWeight.w600 : FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (channel.group != null && channel.group!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        channel.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isFocused
                              ? Colors.white.withOpacity(0.4)
                              : Colors.white.withOpacity(0.22),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Status badge
            if (isCurrent)
              _buildNowBadge()
            else if (channel.isLive)
              _buildLiveBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final hasLogo = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(
          color: isCurrent
              ? _accent.withOpacity(0.15)
              : isFocused
                  ? Colors.white.withOpacity(0.08)
                  : Colors.white.withOpacity(0.03),
        ),
        boxShadow: isCurrent
            ? [BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 8)]
            : [],
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLogo
          ? CachedNetworkImage(
              imageUrl: channel.logoUrl!,
              fit: BoxFit.contain,
              placeholder: (_, __) => _buildLetterAvatar(),
              errorWidget: (_, __, ___) => _buildLetterAvatar(),
            )
          : _buildLetterAvatar(),
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

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: _liveDot.withOpacity(0.08),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _liveDot.withOpacity(0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _liveDot.withOpacity(0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              color: _liveDot.withOpacity(0.7),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
