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
  /// Called when up arrow is pressed from any card in this section
  final VoidCallback? onUpArrowPressed;
  /// Called when down arrow is pressed from any card in this section
  final VoidCallback? onDownArrowPressed;

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
    this.onUpArrowPressed,
    this.onDownArrowPressed,
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
  /// Also scrolls the item into view in the parent scroll view
  bool requestFocusOnFirstItem() {
    if (_cardFocusNodes.isEmpty) return false;
    final node = _cardFocusNodes[0];
    node.requestFocus();
    // Scroll into view after focus is applied
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) {
        Scrollable.ensureVisible(
          node.context!,
          alignment: 0.15, // Closer to top to show search button above
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
    return true;
  }

  /// Request focus on the last item in this section
  /// Returns true if focus was requested successfully
  /// Also scrolls the item into view in the parent scroll view
  bool requestFocusOnLastItem() {
    if (_cardFocusNodes.isEmpty) return false;
    final node = _cardFocusNodes.last;
    node.requestFocus();
    // Scroll into view after focus is applied
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (node.context != null) {
        Scrollable.ensureVisible(
          node.context!,
          alignment: 0.7,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
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

    // Use LayoutBuilder to get actual available width (accounts for sidebar)
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isTV = _isTV(availableWidth);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.sectionTitle.isNotEmpty) ...[
              _buildSectionHeader(),
              const SizedBox(height: 16),
            ],
            if (isTV)
              _buildHorizontalRow(availableWidth)
            else
              _buildGrid(availableWidth),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (widget.sectionIcon != null) ...[
            // Animated icon container with glow
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (widget.sectionIconColor ?? const Color(0xFFFFD700)).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: (widget.sectionIconColor ?? const Color(0xFFFFD700)).withValues(alpha: 0.2),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Icon(
                widget.sectionIcon,
                color: widget.sectionIconColor ?? const Color(0xFFFFD700),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
          ],
          // Section title with gradient text effect
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                Colors.white,
                Colors.white.withValues(alpha: 0.85),
              ],
            ).createShader(bounds),
            child: Text(
              widget.sectionTitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Count badge with modern design
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withValues(alpha: 0.12),
                  Colors.white.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Text(
              '${widget.items.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// TV layout: Horizontal scrolling row with Netflix-style cards
  Widget _buildHorizontalRow(double screenWidth) {
    // Card dimensions - balanced size for TV viewing
    const double cardWidth = 165;
    const double cardHeight = 230; // ~2:3 aspect ratio (Netflix poster style)

    return SizedBox(
      height: cardHeight + 35, // Extra space for scale animation overflow + shadows
      child: ShaderMask(
        // Subtle fade effect at edges to hint at more content
        shaderCallback: (Rect bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: const [0.0, 0.02, 0.98, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          clipBehavior: Clip.none, // Allow shadow overflow
          cacheExtent: 600, // Pre-cache more items for smoother scrolling
          itemCount: widget.items.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: EdgeInsets.only(
                right: index < widget.items.length - 1 ? 18 : 0,
              ),
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _buildCardItem(context, index),
              ),
            );
          },
        ),
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
        onUpArrowPressed: widget.onUpArrowPressed,
        onDownArrowPressed: widget.onDownArrowPressed,
        onFocusChanged: (focused) {
          if (focused && widget.shouldRestoreFocus && widget.targetFocusIndex == index && !_hasNotifiedRestore) {
            _hasNotifiedRestore = true;
            widget.onFocusRestored?.call();
          }
          // Auto-scroll to focused item within horizontal row
          if (focused && _scrollController.hasClients) {
            _scrollToIndex(index);
          }
          // Also scroll item into view in parent scroll view (for cross-section visibility)
          if (focused && focusNode?.context != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (focusNode?.context != null && focusNode!.context!.mounted) {
                Scrollable.ensureVisible(
                  focusNode.context!,
                  alignment: 0.2, // Show more content above focused item
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              }
            });
          }
        },
      ),
    );
  }

  /// Scroll to make the focused item visible with smooth centering
  void _scrollToIndex(int index) {
    // Guard against scroll controller not being attached
    if (!_scrollController.hasClients) return;

    const double cardWidth = 165; // Match card dimensions
    const double spacing = 18;
    const double padding = 20;

    // Calculate target to center the focused item with slight left offset for context
    final viewportWidth = _scrollController.position.viewportDimension;
    final targetOffset = (index * (cardWidth + spacing)) + padding - (viewportWidth / 2) + (cardWidth / 2);
    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    // Only animate if the change is significant (avoids jitter on small moves)
    final currentOffset = _scrollController.offset;
    if ((currentOffset - clampedOffset).abs() < 10) return;

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 250), // Smooth but responsive
      curve: Curves.easeOutCubic, // Natural deceleration
    );
  }
}
