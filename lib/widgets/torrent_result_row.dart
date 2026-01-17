import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/torrent.dart';
import '../models/torrent_filter_state.dart';

/// Compact torrent result row with quality color accent
///
/// Features:
/// - Quality color accent bar on left (4K=Gold, 1080p=Blue, 720p=Green, SD=Gray)
/// - Shows title, size, seeds, source, cache indicator
/// - TV d-pad navigation support
/// - Single tap triggers service picker
class TorrentResultRow extends StatefulWidget {
  const TorrentResultRow({
    super.key,
    required this.torrent,
    required this.index,
    required this.focusNode,
    required this.isTelevision,
    required this.qualityTier,
    this.isCached = false,
    this.cacheService,
    required this.onTap,
    this.onLongPress,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final Torrent torrent;
  final int index;
  final FocusNode focusNode;
  final bool isTelevision;
  final QualityTier qualityTier;
  final bool isCached;
  final String? cacheService; // 'torbox', 'realdebrid', or null

  /// Called when row is tapped - should show service picker
  final VoidCallback onTap;

  /// Called when row is long-pressed - shows provider selection dialog
  final VoidCallback? onLongPress;

  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  State<TorrentResultRow> createState() => _TorrentResultRowState();
}

class _TorrentResultRowState extends State<TorrentResultRow> {
  bool _isFocused = false;

  // For DPAD long press detection
  Timer? _longPressTimer;
  bool _longPressTriggered = false;
  static const _longPressDuration = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (_isFocused != focused) {
      setState(() {
        _isFocused = focused;
      });

      // Auto-scroll on focus for TV
      if (focused && widget.isTelevision) {
        _ensureVisible();
      }
    }
  }

  void _ensureVisible() {
    final ctx = context;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final isSelectKey = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter;

    // Handle Select/Enter key with long press support
    if (isSelectKey) {
      if (event is KeyDownEvent) {
        // Start long press timer
        _longPressTriggered = false;
        _longPressTimer?.cancel();
        _longPressTimer = Timer(_longPressDuration, () {
          if (!mounted) return;
          _longPressTriggered = true;
          // Trigger long press callback if available, otherwise fall back to tap
          if (widget.onLongPress != null) {
            widget.onLongPress!();
          } else {
            widget.onTap();
          }
        });
        return KeyEventResult.handled;
      } else if (event is KeyUpEvent) {
        // Cancel timer and trigger tap if long press wasn't triggered
        _longPressTimer?.cancel();
        _longPressTimer = null;
        if (!_longPressTriggered) {
          widget.onTap();
        }
        _longPressTriggered = false;
        return KeyEventResult.handled;
      }
    }

    // Arrow navigation (only on key down)
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onNavigateUp?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onNavigateDown?.call();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  Color get _qualityColor {
    switch (widget.qualityTier) {
      case QualityTier.ultraHd:
        return const Color(0xFFF59E0B); // Amber/Gold
      case QualityTier.fullHd:
        return const Color(0xFF3B82F6); // Blue
      case QualityTier.hd:
        return const Color(0xFF10B981); // Green
      case QualityTier.sd:
        return const Color(0xFF6B7280); // Gray
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return 'N/A';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${suffixes[i]}';
  }

  String _formatDate(int unix) {
    if (unix <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
    return '${(diff.inDays / 365).floor()}y ago';
  }

  // Dark theme colors
  static const _cardBg = Color(0xFF1E293B); // Slate 800
  static const _cardBgHover = Color(0xFF334155); // Slate 700
  static const _textPrimary = Colors.white;
  static const _textSecondary = Color(0xFF94A3B8); // Slate 400

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: _isFocused ? _cardBgHover : _cardBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? _qualityColor : Colors.transparent,
              width: _isFocused ? 2 : 1,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: _qualityColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: _buildMainRow(),
          ),
        ),
      ),
    );
  }

  Widget _buildMainRow() {
    return IntrinsicHeight(
      child: Row(
        children: [
          // Quality accent bar
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: _qualityColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    widget.torrent.displayTitle,
                    style: const TextStyle(
                      color: _textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Metadata row
                  _buildMetadataRow(),
                ],
              ),
            ),
          ),

          // Chevron to indicate tappable
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              Icons.chevron_right_rounded,
              color: _isFocused ? _qualityColor : _textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetadataRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Size
        _buildMetaChip(
          icon: Icons.storage_rounded,
          label: _formatSize(widget.torrent.sizeBytes),
          color: const Color(0xFF60A5FA), // Blue 400
        ),

        // Seeders
        _buildMetaChip(
          icon: Icons.arrow_upward_rounded,
          label: widget.torrent.seeders.toString(),
          color: const Color(0xFF10B981), // Green
        ),

        // Leechers
        if (widget.torrent.leechers > 0)
          _buildMetaChip(
            icon: Icons.arrow_downward_rounded,
            label: widget.torrent.leechers.toString(),
            color: const Color(0xFFEF4444), // Red
          ),

        // Source
        _buildMetaChip(
          icon: Icons.source_rounded,
          label: widget.torrent.source.toUpperCase(),
          color: const Color(0xFFA78BFA), // Purple 400
        ),

        // Date
        if (widget.torrent.createdUnix > 0)
          Text(
            _formatDate(widget.torrent.createdUnix),
            style: TextStyle(
              color: _textSecondary.withValues(alpha: 0.7),
              fontSize: 11,
            ),
          ),

        // Cache indicator - only show when we know which service has it cached
        if (widget.isCached && widget.cacheService != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.bolt_rounded,
                  size: 12,
                  color: Color(0xFF10B981),
                ),
                const SizedBox(width: 2),
                Text(
                  widget.cacheService == 'torbox'
                      ? 'TB'
                      : widget.cacheService == 'realdebrid'
                          ? 'RD'
                          : 'Cached',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Extension to detect quality tier from torrent name
extension TorrentQualityExtension on Torrent {
  QualityTier get qualityTier {
    final nameLower = name.toLowerCase();

    // 4K/UHD detection
    if (nameLower.contains('2160p') ||
        nameLower.contains('4k') ||
        nameLower.contains('uhd') ||
        nameLower.contains('4096')) {
      return QualityTier.ultraHd;
    }

    // 1080p detection
    if (nameLower.contains('1080p') ||
        nameLower.contains('1080i') ||
        nameLower.contains('fullhd') ||
        nameLower.contains('full hd')) {
      return QualityTier.fullHd;
    }

    // 720p detection
    if (nameLower.contains('720p') ||
        nameLower.contains('720i') ||
        nameLower.contains('hd ') ||
        nameLower.contains('hdrip')) {
      return QualityTier.hd;
    }

    // SD/unknown - default to SD
    return QualityTier.sd;
  }
}
