import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'playlist_landscape_card.dart';
import 'playlist_grid_card.dart';

/// Adaptive playlist section that switches between grid and horizontal scroll
/// based on device platform and screen size.
///
/// Layout strategy:
/// - Android TV (Android + width > 1200): Horizontal scrolling rows
/// - Desktop/Mac/Windows (width > 800): 4-column grid
/// - Tablet (width > 600): 3-column grid
/// - Mobile (width > 400): 2-column grid
/// - Mobile small (width <= 400): Single column
class AdaptivePlaylistSection extends StatelessWidget {
  final String sectionTitle;
  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> progressMap;
  final void Function(Map<String, dynamic> item) onItemPlay;
  final void Function(Map<String, dynamic> item) onItemView;
  final void Function(Map<String, dynamic> item) onItemDelete;
  final void Function(Map<String, dynamic> item)? onItemClearProgress;

  const AdaptivePlaylistSection({
    super.key,
    required this.sectionTitle,
    required this.items,
    required this.progressMap,
    required this.onItemPlay,
    required this.onItemView,
    required this.onItemDelete,
    this.onItemClearProgress,
  });

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

  bool _isAndroidTV() {
    // Check if running on Android TV
    if (defaultTargetPlatform == TargetPlatform.android) {
      // On Android TV, screen width is typically very large (1920px+)
      // and the app is in landscape mode
      // We can also check for TV-specific features
      return true; // Will be refined with screen width check
    }
    return false;
  }

  LayoutMode _getLayoutMode(BuildContext context, double screenWidth) {
    // Android TV: Always use horizontal scrolling
    if (defaultTargetPlatform == TargetPlatform.android && screenWidth > 1200) {
      return LayoutMode.horizontal; // Android TV
    }

    // All other platforms (iOS, macOS, Windows, Linux, web, mobile Android):
    // Use responsive grid based on screen width
    if (screenWidth > 800) {
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
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final layoutMode = _getLayoutMode(context, screenWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 12),
        layoutMode == LayoutMode.horizontal
            ? _buildHorizontalScroll()
            : _buildGrid(layoutMode),
      ],
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            sectionTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '(${items.length})',
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

  Widget _buildHorizontalScroll() {
    const cardHeight = 150.0;
    const spacing = 16.0;

    return SizedBox(
      height: cardHeight + 8,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final dedupeKey = _getDedupeKey(item);
          final progressData = progressMap[dedupeKey];

          return Padding(
            padding: EdgeInsets.only(
              right: index == items.length - 1 ? 0 : spacing,
            ),
            child: PlaylistLandscapeCard(
              item: item,
              progressData: progressData,
              onPlay: () => onItemPlay(item),
              onView: () => onItemView(item),
              onDelete: () => onItemDelete(item),
              onClearProgress: onItemClearProgress != null ? () => onItemClearProgress!(item) : null,
              height: cardHeight,
            ),
          );
        },
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
      default:
        crossAxisCount = 2;
        childAspectRatio = 0.75;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final dedupeKey = _getDedupeKey(item);
          final progressData = progressMap[dedupeKey];

          return PlaylistGridCard(
            item: item,
            progressData: progressData,
            onPlay: () => onItemPlay(item),
            onView: () => onItemView(item),
            onDelete: () => onItemDelete(item),
            onClearProgress: onItemClearProgress != null ? () => onItemClearProgress!(item) : null,
          );
        },
      ),
    );
  }
}

enum LayoutMode {
  horizontal, // TV
  grid4,      // Desktop
  grid3,      // Tablet
  grid2,      // Mobile
  grid1,      // Small mobile
}
