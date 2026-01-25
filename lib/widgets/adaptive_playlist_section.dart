import 'package:flutter/material.dart';
import 'playlist_grid_card.dart';

/// Adaptive playlist section with platform-optimized layouts:
/// - TV/Large screens (width > 1000): Horizontal scrolling rows (Netflix-style)
/// - Mobile/Tablet: Responsive grid layout
///
/// TV navigation:
/// - Left/Right: Scroll within the row
/// - Up/Down: Move between sections
class AdaptivePlaylistSection extends StatefulWidget {
  final String sectionTitle;
  final IconData? sectionIcon;
  final Color? sectionIconColor;
  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> progressMap;
  final Set<String> favoriteKeys;
  final void Function(Map<String, dynamic> item) onItemPlay;
  final void Function(Map<String, dynamic> item) onItemView;
  final void Function(Map<String, dynamic> item) onItemDelete;
  final void Function(Map<String, dynamic> item)? onItemClearProgress;
  final void Function(Map<String, dynamic> item)? onItemToggleFavorite;
  final bool shouldAutofocusFirst;
  final int? targetFocusIndex;
  final bool shouldRestoreFocus;
  final VoidCallback? onFocusRestored;

  const AdaptivePlaylistSection({
    super.key,
    required this.sectionTitle,
    this.sectionIcon,
    this.sectionIconColor,
    required this.items,
    required this.progressMap,
    this.favoriteKeys = const {},
    required this.onItemPlay,
    required this.onItemView,
    required this.onItemDelete,
    this.onItemClearProgress,
    this.onItemToggleFavorite,
    this.shouldAutofocusFirst = false,
    this.targetFocusIndex,
    this.shouldRestoreFocus = false,
    this.onFocusRestored,
  });

  @override
  State<AdaptivePlaylistSection> createState() => AdaptivePlaylistSectionState();
}

/// State is public so parent can call requestFocusOnFirstItem()
class AdaptivePlaylistSectionState extends State<AdaptivePlaylistSection> {
  bool _hasNotifiedRestore = false;
  final ScrollController _scrollController = ScrollController();

  // Focus nodes for each card item
  final List<FocusNode> _cardFocusNodes = [];

  /// Whether this section has items
  bool get hasItems => widget.items.isNotEmpty;

  /// Request focus on the first item in this section
  /// Returns true if focus was requested successfully
  bool requestFocusOnFirstItem() {
    if (_cardFocusNodes.isEmpty) return false;
    _cardFocusNodes[0].requestFocus();
    return true;
  }

  /// Request focus on the last item in this section
  /// Returns true if focus was requested successfully
  bool requestFocusOnLastItem() {
    if (_cardFocusNodes.isEmpty) return false;
    _cardFocusNodes.last.requestFocus();
    return true;
  }

  @override
  void initState() {
    super.initState();
    _ensureFocusNodes();
  }

  @override
  void didUpdateWidget(AdaptivePlaylistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shouldRestoreFocus && widget.shouldRestoreFocus) {
      _hasNotifiedRestore = false;
    }
    // Update focus nodes if item count changed
    _ensureFocusNodes();
  }

  void _ensureFocusNodes() {
    final neededCount = widget.items.length;

    // Dispose extra nodes
    while (_cardFocusNodes.length > neededCount) {
      _cardFocusNodes.removeLast().dispose();
    }

    // Add new nodes
    while (_cardFocusNodes.length < neededCount) {
      _cardFocusNodes.add(FocusNode(debugLabel: 'playlist_card_${_cardFocusNodes.length}'));
    }
  }

  @override
  void dispose() {
    for (final node in _cardFocusNodes) {
      node.dispose();
    }
    _scrollController.dispose();
    super.dispose();
  }

String _getDedupeKey(Map<String, dynamic> item) {
    final provider = (item['provider'] as String? ?? 'realdebrid').toLowerCase();
    final rdTorrentId = item['rdTorrentId'] as String?;
    final torrentHash = item['torrent_hash'] as String?;
    final torboxId = item['torboxTorrentId']?.toString();
    final pikpakId = item['pikpakFileId'] as String?;

    if (torrentHash != null && torrentHash.isNotEmpty) {
      return '$provider|hash:$torrentHash';
    }
    if (torboxId != null) {
      return '$provider|torbox:$torboxId';
    }
    if (pikpakId != null) {
      return '$provider|pikpak:$pikpakId';
    }
    if (rdTorrentId != null) {
      return '$provider|rd:$rdTorrentId';
    }

    final title = item['title'] as String? ?? 'unknown';
    return '$provider|${title.toLowerCase()}';
  }

  // Force horizontal layout for any screen > 600 (tablets and TVs)
  bool _isTV(double screenWidth) => screenWidth > 600;

  (int, double) _getGridParams(double screenWidth) {
    if (screenWidth > 900) {
      return (5, 0.68);
    } else if (screenWidth > 600) {
      return (4, 0.72);
    } else if (screenWidth > 500) {
      // Larger phones/small tablets: 3 columns
      return (3, 0.62);
    } else {
      // Standard phones: 2 columns with taller cards for better visibility
      return (2, 0.58);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isTV = _isTV(screenWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.sectionTitle.isNotEmpty) ...[
          _buildSectionHeader(),
          const SizedBox(height: 16),
        ],
        if (isTV)
          _buildHorizontalRow(screenWidth)
        else
          _buildGrid(screenWidth),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (widget.sectionIcon != null) ...[
            Icon(
              widget.sectionIcon,
              color: widget.sectionIconColor ?? const Color(0xFFFFD700),
              size: 22,
            ),
            const SizedBox(width: 10),
          ],
          Text(
            widget.sectionTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${widget.items.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TV layout: Horizontal scrolling row with Netflix-style cards
  Widget _buildHorizontalRow(double screenWidth) {
    // Card dimensions for TV - portrait poster style
    const double cardWidth = 180;
    const double cardHeight = 270; // ~2:3 aspect ratio

    return SizedBox(
      height: cardHeight + 20, // Extra space for scale animation overflow
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        clipBehavior: Clip.none, // Allow scale animation to overflow
        cacheExtent: 500, // Pre-cache items for smoother scrolling
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(
              right: index < widget.items.length - 1 ? 16 : 0,
            ),
            child: SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _buildCardItem(context, index),
            ),
          );
        },
      ),
    );
  }

  /// Mobile/Tablet layout: Responsive grid
  Widget _buildGrid(double screenWidth) {
    final (crossAxisCount, childAspectRatio) = _getGridParams(screenWidth);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        primary: false,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: widget.items.length,
        itemBuilder: _buildCardItem,
      ),
    );
  }

  Widget _buildCardItem(BuildContext context, int index) {
    final item = widget.items[index];
    final dedupeKey = _getDedupeKey(item);
    final progressData = widget.progressMap[dedupeKey];
    final bool shouldAutofocus = (widget.shouldAutofocusFirst && index == 0) ||
                                (widget.shouldRestoreFocus && widget.targetFocusIndex == index);

    // Get focus node for this card (with bounds check)
    final focusNode = index < _cardFocusNodes.length ? _cardFocusNodes[index] : null;

    return RepaintBoundary(
      child: PlaylistGridCard(
        key: ValueKey('playlist_$dedupeKey'),
        item: item,
        progressData: progressData,
        isFavorited: widget.favoriteKeys.contains(dedupeKey),
        onPlay: () => widget.onItemPlay(item),
        onView: () => widget.onItemView(item),
        onDelete: () => widget.onItemDelete(item),
        onClearProgress: widget.onItemClearProgress != null ? () => widget.onItemClearProgress!(item) : null,
        onToggleFavorite: widget.onItemToggleFavorite != null ? () => widget.onItemToggleFavorite!(item) : null,
        autofocus: shouldAutofocus,
        focusNode: focusNode,
        onFocusChanged: (focused) {
          if (focused && widget.shouldRestoreFocus && widget.targetFocusIndex == index && !_hasNotifiedRestore) {
            _hasNotifiedRestore = true;
            widget.onFocusRestored?.call();
          }
          // Auto-scroll to focused item on TV
          if (focused && _scrollController.hasClients) {
            _scrollToIndex(index);
          }
        },
      ),
    );
  }

  /// Scroll to make the focused item visible with some padding
  void _scrollToIndex(int index) {
    // Guard against scroll controller not being attached
    if (!_scrollController.hasClients) return;

    const double cardWidth = 180;
    const double spacing = 16;
    const double padding = 20;

    // Calculate target to center the focused item
    final viewportWidth = _scrollController.position.viewportDimension;
    final targetOffset = (index * (cardWidth + spacing)) + padding - (viewportWidth / 2) + (cardWidth / 2);
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 150), // Snappier animation
      curve: Curves.easeOutCubic, // Smoother deceleration
    );
  }
}
