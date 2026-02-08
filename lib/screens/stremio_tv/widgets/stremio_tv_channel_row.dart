import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import 'stremio_tv_now_playing_card.dart';

/// A single channel row in the Stremio TV guide.
///
/// Shows: channel number | channel name | now playing poster + metadata + progress.
/// Tap to play, long press to favorite/unfavorite.
class StremioTvChannelRow extends StatelessWidget {
  final StremioTvChannel channel;
  final StremioTvNowPlaying? nowPlaying;
  final bool isFocused;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const StremioTvChannelRow({
    super.key,
    required this.channel,
    required this.nowPlaying,
    required this.isFocused,
    required this.focusNode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.select) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isFocused
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: isFocused
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
            width: isFocused ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Channel number + favorite star
                  SizedBox(
                    width: 50,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (channel.isFavorite)
                          Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: Colors.amber.shade600,
                          ),
                        Text(
                          'CH ${channel.channelNumber.toString().padLeft(2, '0')}',
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
                        // Addon name as small label
                        Text(
                          channel.addon.name,
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
                        // Catalog name + genre as main text
                        Text(
                          channel.genre != null
                              ? '${channel.catalog.name} - ${channel.genre}'
                              : channel.catalog.name,
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
                            color: _typeColor(channel.type, theme)
                                .withValues(alpha: 0.15),
                          ),
                          child: Text(
                            channel.type.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: _typeColor(channel.type, theme),
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
                    child: nowPlaying != null
                        ? StremioTvNowPlayingCard(nowPlaying: nowPlaying!)
                        : _buildLoadingPlaceholder(theme),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingPlaceholder(ThemeData theme) {
    return Text(
      'Loading...',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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
