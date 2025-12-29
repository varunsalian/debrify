import 'package:flutter/material.dart';
import 'playlist_landscape_card.dart';

/// Horizontal scrolling row of playlist items (YouTube TV style).
///
/// Features:
/// - Auto-calculates cards per viewport based on screen width
/// - Smooth horizontal scrolling with D-pad navigation
/// - Section title with optional "See all" button
/// - Auto-scroll to keep focused card in view (Phase 3)
class HorizontalPlaylistRow extends StatefulWidget {
  final String sectionTitle;
  final List<Map<String, dynamic>> items;
  final Map<String, Map<String, dynamic>> progressMap;
  final void Function(Map<String, dynamic> item) onItemPlay;
  final void Function(Map<String, dynamic> item) onItemView;
  final void Function(Map<String, dynamic> item) onItemDelete;
  final double cardHeight;
  final bool showSeeAll;
  final VoidCallback? onSeeAllTap;

  const HorizontalPlaylistRow({
    super.key,
    required this.sectionTitle,
    required this.items,
    required this.progressMap,
    required this.onItemPlay,
    required this.onItemView,
    required this.onItemDelete,
    this.cardHeight = 150,
    this.showSeeAll = false,
    this.onSeeAllTap,
  });

  @override
  State<HorizontalPlaylistRow> createState() => _HorizontalPlaylistRowState();
}

class _HorizontalPlaylistRowState extends State<HorizontalPlaylistRow> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _cardKeys = [];

  @override
  void initState() {
    super.initState();
    _cardKeys.addAll(
      List.generate(widget.items.length, (index) => GlobalKey()),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCard(int index) {
    if (!_scrollController.hasClients) return;
    if (index < 0 || index >= _cardKeys.length) return;

    final key = _cardKeys[index];
    final cardContext = key.currentContext;
    if (cardContext == null) return;

    final cardWidth = widget.cardHeight * (16.0 / 9.0);
    const spacing = 16.0;
    const horizontalPadding = 24.0; // ListView horizontal padding

    // Calculate target scroll position to center the card
    // Account for ListView padding to get true viewport width
    final viewportWidth = MediaQuery.of(context).size.width - (horizontalPadding * 2);
    final targetOffset = (index * (cardWidth + spacing)) - (viewportWidth / 2) + (cardWidth / 2);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  String _getDedupeKey(Map<String, dynamic> item) {
    // Simple dedupe key based on provider and ID
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

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSectionHeader(),
        const SizedBox(height: 12),
        _buildHorizontalScroll(),
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
          const Spacer(),
          if (widget.showSeeAll && widget.onSeeAllTap != null)
            TextButton(
              onPressed: widget.onSeeAllTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: const Color(0xFFE50914).withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 16,
                    color: const Color(0xFFE50914).withValues(alpha: 0.9),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalScroll() {
    const spacing = 16.0;

    return SizedBox(
      height: widget.cardHeight + 8, // Extra padding for shadow
      child: ListView.builder(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final dedupeKey = _getDedupeKey(item);
          final progressData = widget.progressMap[dedupeKey];

          return Padding(
            padding: EdgeInsets.only(
              right: index == widget.items.length - 1 ? 0 : spacing,
            ),
            child: PlaylistLandscapeCard(
              key: _cardKeys[index],
              item: item,
              progressData: progressData,
              onPlay: () => widget.onItemPlay(item),
              onView: () => widget.onItemView(item),
              onDelete: () => widget.onItemDelete(item),
              height: widget.cardHeight,
              onFocusChange: (focused) {
                if (focused) {
                  _scrollToCard(index);
                }
              },
            ),
          );
        },
      ),
    );
  }
}
