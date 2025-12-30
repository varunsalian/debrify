import 'package:flutter/material.dart';
import 'playlist_grid_card.dart';

/// Adaptive playlist section that uses responsive grid layout
/// for all platforms including Android TV with DPAD support.
///
/// Layout strategy:
/// - Large screens/TV (width > 1200): 5-column grid
/// - Desktop (width > 800): 4-column grid
/// - Tablet (width > 600): 3-column grid
/// - Mobile (width > 400): 2-column grid
/// - Small mobile (width <= 400): Single column
class AdaptivePlaylistSection extends StatefulWidget {
  final String sectionTitle;
  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> progressMap;
  final void Function(Map<String, dynamic> item) onItemPlay;
  final void Function(Map<String, dynamic> item) onItemView;
  final void Function(Map<String, dynamic> item) onItemDelete;
  final void Function(Map<String, dynamic> item)? onItemClearProgress;
  final bool shouldAutofocusFirst;
  final int? targetFocusIndex;
  final bool shouldRestoreFocus;
  final VoidCallback? onFocusRestored;

  const AdaptivePlaylistSection({
    super.key,
    required this.sectionTitle,
    required this.items,
    required this.progressMap,
    required this.onItemPlay,
    required this.onItemView,
    required this.onItemDelete,
    this.onItemClearProgress,
    this.shouldAutofocusFirst = false,
    this.targetFocusIndex,
    this.shouldRestoreFocus = false,
    this.onFocusRestored,
  });

  @override
  State<AdaptivePlaylistSection> createState() => _AdaptivePlaylistSectionState();
}

class _AdaptivePlaylistSectionState extends State<AdaptivePlaylistSection> {
  // Flag to ensure onFocusRestored is called only once per restoration cycle
  bool _hasNotifiedRestore = false;

  @override
  void didUpdateWidget(AdaptivePlaylistSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset flag when shouldRestoreFocus changes from false to true (new restoration cycle)
    if (!oldWidget.shouldRestoreFocus && widget.shouldRestoreFocus) {
      _hasNotifiedRestore = false;
    }
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

  LayoutMode _getLayoutMode(BuildContext context, double screenWidth) {
    // Use responsive grid for all platforms including Android TV
    if (screenWidth > 1200) {
      return LayoutMode.grid5; // Large screens/TV
    } else if (screenWidth > 800) {
      return LayoutMode.grid4; // Desktop
    } else if (screenWidth > 600) {
      return LayoutMode.grid3; // Tablet
    } else if (screenWidth > 400) {
      return LayoutMode.grid2; // Mobile
    } else {
      return LayoutMode.grid1; // Small mobile
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final layoutMode = _getLayoutMode(context, screenWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.sectionTitle.isNotEmpty) ...[
          _buildSectionHeader(),
          const SizedBox(height: 12),
        ],
        _buildGrid(layoutMode),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            widget.sectionTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${widget.items.length})',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(LayoutMode mode) {
    final int crossAxisCount;
    final double childAspectRatio;

    switch (mode) {
      case LayoutMode.grid1:
        crossAxisCount = 1;
        childAspectRatio = 2.0; // Wider cards for single column
        break;
      case LayoutMode.grid2:
        crossAxisCount = 2;
        childAspectRatio = 0.75; // Slightly portrait for mobile
        break;
      case LayoutMode.grid3:
        crossAxisCount = 3;
        childAspectRatio = 0.85; // Taller cards for tablet - more room for titles
        break;
      case LayoutMode.grid4:
        crossAxisCount = 4;
        childAspectRatio = 0.85; // Taller cards for desktop - more room for titles
        break;
      case LayoutMode.grid5:
        crossAxisCount = 5;
        childAspectRatio = 0.85; // Taller cards for large screens/TV - more room for titles
        break;
      default:
        crossAxisCount = 2;
        childAspectRatio = 0.75;
    }

    // GridView with DPAD navigation - removed nested FocusTraversalGroup to allow
    // upward navigation to search button. Parent FocusTraversalGroup handles all traversal.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(), // Changed from NeverScrollableScrollPhysics for better focus handling
        primary: false,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final dedupeKey = _getDedupeKey(item);
          final progressData = widget.progressMap[dedupeKey];

          // Use Builder to get proper context for ensureVisible
          return Builder(
            builder: (BuildContext itemContext) {
              // Determine if this specific card should have autofocus
              final bool shouldAutofocus = (widget.shouldAutofocusFirst && index == 0) ||
                                          (widget.shouldRestoreFocus && widget.targetFocusIndex == index);

              return PlaylistGridCard(
                key: ValueKey('playlist_$dedupeKey'), // Removed index to preserve focus during rebuilds
                item: item,
                progressData: progressData,
                onPlay: () => widget.onItemPlay(item),
                onView: () => widget.onItemView(item),
                onDelete: () => widget.onItemDelete(item),
                onClearProgress: widget.onItemClearProgress != null ? () => widget.onItemClearProgress!(item) : null,
                autofocus: shouldAutofocus,
                onFocusChanged: (focused) {
                  // Notify parent when focus is restored (only once per cycle)
                  if (focused && widget.shouldRestoreFocus && widget.targetFocusIndex == index && !_hasNotifiedRestore) {
                    _hasNotifiedRestore = true;
                    widget.onFocusRestored?.call();
                  }
                  // Ensure focused item is visible when navigating with DPAD
                  if (focused) {
                    // Use addPostFrameCallback for better timing - ensures widget is fully built
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      try {
                        // Only try to scroll if context is still mounted
                        if (itemContext.mounted) {
                          Scrollable.ensureVisible(
                            itemContext,
                            alignment: 0.5,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                          );
                        }
                      } on FlutterError catch (e) {
                        // Only catch FlutterErrors related to unmounted widgets
                        // Let other errors propagate for debugging
                        if (!e.toString().contains('mounted')) {
                          rethrow;
                        }
                      }
                    });
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}

enum LayoutMode {
  grid5,      // Large screens/TV
  grid4,      // Desktop
  grid3,      // Tablet
  grid2,      // Mobile
  grid1,      // Small mobile
}
