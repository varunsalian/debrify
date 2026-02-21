import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/iptv_playlist.dart';

/// Apple TV-inspired IPTV channel sheet overlay for the video player.
/// Full-height right panel with frosted glass, category rail, search, and channel grid.
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

enum _FocusZone { search, categories, channels }

class _IptvChannelSheetState extends State<IptvChannelSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _categoryScrollController = ScrollController();

  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scrimAnim;

  List<IptvChannel> _filteredChannels = [];
  List<String> _categories = [];
  String? _selectedCategory;
  int _focusedIndex = 0;
  int _focusedCategoryIndex = 0;
  _FocusZone _focusZone = _FocusZone.channels;

  static const _accent = Color(0xFF00E5FF);
  static const _accentDim = Color(0xFF0097A7);

  @override
  void initState() {
    super.initState();

    final catSet = <String>{};
    for (final c in widget.channels) {
      if (c.group != null && c.group!.isNotEmpty) catSet.add(c.group!);
    }
    _categories = catSet.toList()..sort();

    _filteredChannels = List.from(widget.channels);

    if (widget.currentIndex >= 0 && widget.currentIndex < widget.channels.length) {
      final cur = widget.channels[widget.currentIndex];
      final idx = _filteredChannels.indexWhere((c) => c.url == cur.url && c.name == cur.name);
      if (idx >= 0) _focusedIndex = idx;
    }

    _animController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _scrimAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
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
    _categoryScrollController.dispose();
    _animController.dispose();
    super.dispose();
  }

  // ─── Filtering ───────────────────────────────────────────────────────

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredChannels = widget.channels.where((c) {
        final matchCat = _selectedCategory == null || c.group == _selectedCategory;
        final matchQ = query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            (c.group != null && c.group!.toLowerCase().contains(query));
        return matchCat && matchQ;
      }).toList();

      // Preserve focus on current channel
      final cur = (widget.currentIndex >= 0 && widget.currentIndex < widget.channels.length)
          ? widget.channels[widget.currentIndex]
          : null;
      final idx = cur == null
          ? -1
          : _filteredChannels.indexWhere((c) => c.url == cur.url && c.name == cur.name);
      _focusedIndex = idx >= 0
          ? idx
          : _filteredChannels.isNotEmpty
              ? _focusedIndex.clamp(0, _filteredChannels.length - 1)
              : 0;
    });
  }

  void _selectCategory(int chipIndex) {
    setState(() {
      _focusedCategoryIndex = chipIndex;
      _selectedCategory = chipIndex == 0 ? null : _categories[chipIndex - 1];
    });
    _applyFilters();
    _scrollCategoryIntoView(chipIndex);
  }

  // ─── Scrolling ───────────────────────────────────────────────────────

  void _scrollToFocused() {
    if (_filteredChannels.isEmpty || !_scrollController.hasClients) return;
    const h = 76.0;
    final target = _focusedIndex * h;
    final vp = _scrollController.position.viewportDimension;
    final cur = _scrollController.offset;
    if (target < cur || target > cur + vp - h) {
      _scrollController.animateTo(
        (target - vp / 2 + h / 2).clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollCategoryIntoView(int index) {
    if (!_categoryScrollController.hasClients) return;
    const chipWidth = 100.0;
    final target = index * chipWidth;
    final vp = _categoryScrollController.position.viewportDimension;
    final cur = _categoryScrollController.offset;
    if (target < cur || target > cur + vp - chipWidth) {
      _categoryScrollController.animateTo(
        (target - vp / 2 + chipWidth / 2)
            .clamp(0.0, _categoryScrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
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
      case _FocusZone.categories:
        _handleCategoryKeys(event);
        break;
      case _FocusZone.channels:
        _handleChannelKeys(event);
        break;
    }
  }

  void _handleSearchKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _searchFocusNode.unfocus();
      setState(() {
        _focusZone = _categories.isNotEmpty ? _FocusZone.categories : _FocusZone.channels;
      });
    }
  }

  void _handleCategoryKeys(KeyEvent event) {
    final totalChips = _categories.length + 1;
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      if (_focusedCategoryIndex > 0) {
        _selectCategory(_focusedCategoryIndex - 1);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      if (_focusedCategoryIndex < totalChips - 1) {
        _selectCategory(_focusedCategoryIndex + 1);
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _searchFocusNode.requestFocus();
      setState(() => _focusZone = _FocusZone.search);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _focusZone = _FocusZone.channels);
    } else if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.select) {
      _selectCategory(_focusedCategoryIndex);
    }
  }

  void _handleChannelKeys(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_focusedIndex > 0) {
        setState(() => _focusedIndex--);
        _scrollToFocused();
      } else {
        setState(() {
          _focusZone = _categories.isNotEmpty ? _FocusZone.categories : _FocusZone.search;
        });
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
        final oi = widget.channels.indexWhere((c) => c.url == ch.url && c.name == ch.name);
        if (oi >= 0) widget.onChannelSelected(oi);
      }
    }
  }

  int _getOriginalIndex(IptvChannel channel) {
    return widget.channels.indexWhere((c) => c.url == channel.url && c.name == channel.name);
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isLandscape = mq.orientation == Orientation.landscape;
    final panelWidth = isLandscape ? mq.size.width * 0.42 : mq.size.width * 0.92;

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
              opacity: _scrimAnim,
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
                  topLeft: Radius.circular(24),
                  bottomLeft: Radius.circular(24),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xE00A0A12),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        bottomLeft: Radius.circular(24),
                      ),
                      border: Border(
                        left: BorderSide(color: Colors.white.withOpacity(0.06)),
                        top: BorderSide(color: Colors.white.withOpacity(0.04)),
                        bottom: BorderSide(color: Colors.white.withOpacity(0.02)),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildHeader(),
                        _buildSearchBar(),
                        if (_categories.isNotEmpty) _buildCategoryRail(),
                        const SizedBox(height: 4),
                        Expanded(child: _buildChannelList()),
                        _buildFooter(),
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
    final cur = (widget.currentIndex >= 0 && widget.currentIndex < widget.channels.length)
        ? widget.channels[widget.currentIndex]
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Glowing icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_accent, Color(0xFF0097A7)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(color: _accent.withOpacity(0.3), blurRadius: 12, spreadRadius: 1),
                  ],
                ),
                child: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 20),
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
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_filteredChannels.length} of ${widget.channels.length} channels',
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
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
                      color: Colors.white.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.6), size: 18),
                  ),
                ),
              ),
            ],
          ),
          if (cur != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent.withOpacity(0.15)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _accent.withOpacity(0.5), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      cur.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      color: _accent.withOpacity(0.6),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Search ─────────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    final hasFocus = _focusZone == _FocusZone.search;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFocus ? _accent.withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: hasFocus
              ? [BoxShadow(color: _accent.withOpacity(0.1), blurRadius: 8)]
              : [],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search channels...',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
            prefixIcon: Icon(Icons.search_rounded, color: Colors.white.withOpacity(0.4), size: 20),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: Colors.white.withOpacity(0.4), size: 18),
                    onPressed: () {
                      _searchController.clear();
                      _applyFilters();
                    },
                  )
                : null,
            filled: true,
            fillColor: Colors.white.withOpacity(0.06),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (_) => _applyFilters(),
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  // ─── Category Rail ──────────────────────────────────────────────────

  Widget _buildCategoryRail() {
    final isActive = _focusZone == _FocusZone.categories;
    final totalChips = _categories.length + 1;

    return Container(
      height: 48,
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.04)),
        ),
      ),
      child: ListView.builder(
        controller: _categoryScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: totalChips,
        itemBuilder: (context, index) {
          final isAll = index == 0;
          final label = isAll ? 'All' : _categories[index - 1];
          final isSelected = isAll
              ? _selectedCategory == null
              : _selectedCategory == label;
          final isFocused = isActive && index == _focusedCategoryIndex;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => _selectCategory(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? _accent.withOpacity(0.15)
                      : isFocused
                          ? Colors.white.withOpacity(0.1)
                          : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isFocused
                        ? _accent.withOpacity(0.7)
                        : isSelected
                            ? _accent.withOpacity(0.3)
                            : Colors.white.withOpacity(0.06),
                    width: isFocused ? 1.5 : 1,
                  ),
                  boxShadow: isFocused
                      ? [BoxShadow(color: _accent.withOpacity(0.15), blurRadius: 8)]
                      : [],
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected || isFocused
                        ? _accent
                        : Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
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
            Icon(Icons.satellite_alt_rounded, color: Colors.white.withOpacity(0.15), size: 56),
            const SizedBox(height: 16),
            Text(
              'No channels found',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different search or category',
              style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final inChannelZone = _focusZone == _FocusZone.channels;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      itemCount: _filteredChannels.length,
      itemExtent: 76,
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
          onTap: () {
            if (origIdx >= 0) widget.onChannelSelected(origIdx);
          },
        );
      },
    );
  }

  // ─── Footer ─────────────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _footerHint(Icons.swap_vert_rounded, 'Navigate'),
          const SizedBox(width: 20),
          _footerHint(Icons.check_circle_outline_rounded, 'Select'),
          const SizedBox(width: 20),
          _footerHint(Icons.arrow_back_rounded, 'Close'),
        ],
      ),
    );
  }

  Widget _footerHint(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.25), size: 14),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 11),
        ),
      ],
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
  final VoidCallback onTap;

  static const _accent = Color(0xFF00E5FF);

  const _ChannelTile({
    required this.channel,
    required this.isFocused,
    required this.isCurrent,
    required this.channelNumber,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isFocused
              ? Colors.white.withOpacity(0.12)
              : isCurrent
                  ? _accent.withOpacity(0.06)
                  : Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? _accent.withOpacity(0.6)
                : isCurrent
                    ? _accent.withOpacity(0.2)
                    : Colors.transparent,
            width: isFocused ? 1.5 : 1,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(color: _accent.withOpacity(0.08), blurRadius: 12, spreadRadius: 1),
                  BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8),
                ]
              : [],
        ),
        transform: isFocused ? (Matrix4.identity()..scale(1.015)) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        child: Row(
          children: [
            // Channel number
            SizedBox(
              width: 28,
              child: Text(
                channelNumber.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isCurrent
                      ? _accent.withOpacity(0.9)
                      : Colors.white.withOpacity(0.25),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Logo
            _buildLogo(),
            const SizedBox(width: 14),
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
                      color: isCurrent ? _accent : Colors.white.withOpacity(0.92),
                      fontSize: 14,
                      fontWeight: isFocused ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (channel.group != null && channel.group!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        channel.group!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isFocused
                              ? Colors.white.withOpacity(0.45)
                              : Colors.white.withOpacity(0.3),
                          fontSize: 11,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Badges
            if (channel.isLive && !isCurrent) _buildLiveBadge(),
            if (isCurrent) _buildNowBadge(),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    final hasLogo = channel.logoUrl != null && channel.logoUrl!.isNotEmpty;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(
          color: isFocused
              ? Colors.white.withOpacity(0.1)
              : Colors.white.withOpacity(0.04),
        ),
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
    final letter = channel.name.isNotEmpty ? channel.name[0].toUpperCase() : '?';
    final hue = (channel.name.hashCode.abs() % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.5, 0.6).toColor();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.3),
            color.withOpacity(0.15),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: color.withOpacity(0.9),
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLiveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFF1744).withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFF1744).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFFF1744),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF1744).withOpacity(0.6),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'LIVE',
            style: TextStyle(
              color: Color(0xFFFF1744),
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accent, Color(0xFF0097A7)],
        ),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: _accent.withOpacity(0.3), blurRadius: 8),
        ],
      ),
      child: const Text(
        'NOW',
        style: TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
