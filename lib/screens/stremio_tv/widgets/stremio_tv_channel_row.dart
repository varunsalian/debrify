import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import 'stremio_tv_now_playing_card.dart';

/// A single channel row in the Stremio TV guide.
///
/// Shows: channel number | channel name | now playing poster + metadata + progress.
/// Tap to play, long press to favorite/unfavorite.
/// A guide icon at the right edge opens the channel schedule.
/// DPAD: right arrow switches to guide icon, select triggers it.
class StremioTvChannelRow extends StatefulWidget {
  final StremioTvChannel channel;
  final StremioTvNowPlaying? nowPlaying;
  final bool isLoading;
  final bool isFocused;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onGuidePressed;
  final VoidCallback? onLeftPress;
  final VoidCallback? onUpPress;
  final double? displayProgress;

  const StremioTvChannelRow({
    super.key,
    required this.channel,
    required this.nowPlaying,
    this.isLoading = false,
    required this.isFocused,
    required this.focusNode,
    required this.onTap,
    required this.onLongPress,
    this.onGuidePressed,
    this.onLeftPress,
    this.onUpPress,
    this.displayProgress,
  });

  @override
  State<StremioTvChannelRow> createState() => _StremioTvChannelRowState();
}

class _StremioTvChannelRowState extends State<StremioTvChannelRow> {
  /// false = play (row default), true = guide icon
  bool _guideActive = false;

  @override
  void didUpdateWidget(StremioTvChannelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isFocused && oldWidget.isFocused) {
      _guideActive = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGuide = widget.onGuidePressed != null;

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter) {
          if (_guideActive) {
            widget.onGuidePressed?.call();
          } else {
            widget.onTap();
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight && hasGuide) {
          if (!_guideActive) {
            setState(() => _guideActive = true);
          }
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          if (_guideActive) {
            setState(() => _guideActive = false);
            return KeyEventResult.handled;
          }
          widget.onLeftPress?.call();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onUpPress != null) {
          widget.onUpPress!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: widget.isFocused
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: widget.isFocused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
            width: widget.isFocused ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 500;
                  if (isCompact) {
                    return _buildCompactLayout(theme, hasGuide);
                  }
                  return _buildWideLayout(theme, hasGuide);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Action buttons — Play + Guide.
  /// Both always look tappable. DPAD-selected one gets a brighter highlight.
  Widget _buildActionButtons(ThemeData theme) {
    final focused = widget.isFocused;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionBtn(
          theme,
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          dpadSelected: focused && !_guideActive,
          onTap: widget.onTap,
        ),
        const SizedBox(width: 6),
        _buildActionBtn(
          theme,
          icon: Icons.list_rounded,
          label: 'Guide',
          dpadSelected: focused && _guideActive,
          onTap: widget.onGuidePressed,
        ),
      ],
    );
  }

  Widget _buildActionBtn(
    ThemeData theme, {
    required IconData icon,
    required String label,
    required bool dpadSelected,
    VoidCallback? onTap,
  }) {
    return ExcludeFocus(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: dpadSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: dpadSelected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: dpadSelected
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Compact layout for small screens — channel info on top, now playing below.
  Widget _buildCompactLayout(ThemeData theme, bool hasGuide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top: channel header
        Row(
          children: [
            if (widget.channel.isFavorite) ...[
              Icon(
                Icons.star_rounded,
                size: 14,
                color: Colors.amber.shade600,
              ),
              const SizedBox(width: 4),
            ],
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.live_tv_rounded,
                    size: 12,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'CH: ${widget.channel.channelNumber}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.channel.addon.name,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.channel.genre != null
                        ? '${widget.channel.catalog.name} - ${widget.channel.genre}'
                        : widget.channel.catalog.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _typeColor(widget.channel.type, theme)
                    .withValues(alpha: 0.15),
              ),
              child: Text(
                widget.channel.type.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  color: _typeColor(widget.channel.type, theme),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Divider(
          height: 16,
          thickness: 1,
          color: theme.colorScheme.outlineVariant,
        ),
        // Bottom: now playing
        if (widget.nowPlaying != null) ...[
          StremioTvNowPlayingCard(
            nowPlaying: widget.nowPlaying!,
            displayProgress: widget.displayProgress,
          ),
          if (hasGuide) ...[
            Divider(
              height: 16,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            _buildActionButtons(theme),
          ],
        ] else if (widget.isLoading)
          _buildLoadingPlaceholder(theme)
        else
          _buildEmptyPlaceholder(theme),
      ],
    );
  }

  /// Wide layout for large screens — horizontal row with fixed columns.
  Widget _buildWideLayout(ThemeData theme, bool hasGuide) {
    return Row(
      children: [
        // Channel number + favorite star
        SizedBox(
          width: 50,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.channel.isFavorite)
                Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: Colors.amber.shade600,
                ),
              Text(
                'CH ${widget.channel.channelNumber.toString().padLeft(2, '0')}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        // Divider
        Container(
          width: 1,
          height: 60,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 12),
        // Channel name + addon label + type
        SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.channel.addon.name,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.6),
                  letterSpacing: 0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.channel.genre != null
                    ? '${widget.channel.catalog.name} - ${widget.channel.genre}'
                    : widget.channel.catalog.name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: _typeColor(widget.channel.type, theme)
                      .withValues(alpha: 0.15),
                ),
                child: Text(
                  widget.channel.type.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: _typeColor(widget.channel.type, theme),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Divider
        Container(
          width: 1,
          height: 60,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        const SizedBox(width: 12),
        // Now playing card
        Expanded(
          child: widget.nowPlaying != null
              ? StremioTvNowPlayingCard(
                  nowPlaying: widget.nowPlaying!,
                  displayProgress: widget.displayProgress,
                )
              : widget.isLoading
                  ? _buildLoadingPlaceholder(theme)
                  : _buildEmptyPlaceholder(theme),
        ),
        // Action buttons
        if (hasGuide) ...[
          const SizedBox(width: 8),
          _buildActionButtons(theme),
        ],
      ],
    );
  }

  Widget _buildLoadingPlaceholder(ThemeData theme) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading...',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPlaceholder(ThemeData theme) {
    return Text(
      'No items available',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      ),
    );
  }

  Color _typeColor(String type, ThemeData theme) {
    switch (type.toLowerCase()) {
      case 'movie':
        return Colors.blue;
      case 'series':
        return Colors.green;
      case 'anime':
        return Colors.purple;
      default:
        return theme.colorScheme.primary;
    }
  }
}
