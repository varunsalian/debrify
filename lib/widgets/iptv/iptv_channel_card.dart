import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';

/// Card widget for displaying an IPTV channel
class IptvChannelCard extends StatefulWidget {
  final IptvChannel channel;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool isFavorited;
  final ValueChanged<bool>? onFavoriteToggle;

  const IptvChannelCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.focusNode,
    this.isFavorited = false,
    this.onFavoriteToggle,
  });

  @override
  State<IptvChannelCard> createState() => _IptvChannelCardState();
}

class _IptvChannelCardState extends State<IptvChannelCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  // 0 = play button selected, 1 = favorite button selected
  int _selectedAction = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
      // Reset to play button when losing focus
      if (!_isFocused) {
        _selectedAction = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final channel = widget.channel;
    final hasFavoriteButton = widget.onFavoriteToggle != null;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // Select/Enter - activate currently selected action
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            if (_selectedAction == 0) {
              widget.onTap();
            } else if (_selectedAction == 1 && widget.onFavoriteToggle != null) {
              widget.onFavoriteToggle!(!widget.isFavorited);
            }
            return KeyEventResult.handled;
          }

          // Right arrow - move to favorite button (if available)
          if (event.logicalKey == LogicalKeyboardKey.arrowRight && hasFavoriteButton) {
            if (_selectedAction == 0) {
              setState(() => _selectedAction = 1);
              return KeyEventResult.handled;
            }
            // If already on favorite, let it propagate (might move to next card or do nothing)
          }

          // Left arrow - move to play button
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            if (_selectedAction == 1) {
              setState(() => _selectedAction = 0);
              return KeyEventResult.handled;
            }
            // If already on play, let it propagate
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused ? colorScheme.primary : Colors.transparent,
              width: _isFocused ? 2 : 0,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo/Icon
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 70,
                      color: colorScheme.surfaceContainerHigh,
                      child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                          ? Image.network(
                              channel.logoUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _buildDefaultIcon(colorScheme),
                            )
                          : _buildDefaultIcon(colorScheme),
                    ),
                    // Live/VOD badge
                    if (channel.contentType == 'vod')
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.movie,
                                size: 8,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'MOVIE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (channel.isLive)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                size: 6,
                                color: Colors.white,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // Play icon overlay on focus when play is selected
                    if (_isFocused && _selectedAction == 0)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black.withValues(alpha: 0.3),
                          child: const Center(
                            child: Icon(
                              Icons.play_arrow,
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Channel name
                      Text(
                        channel.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // Category/Group
                      if (channel.group != null && channel.group!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.folder_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                channel.group!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Play button (first action - index 0)
              GestureDetector(
                onTap: widget.onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: (_isFocused && _selectedAction == 0)
                        ? colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.play_circle_outline,
                    color: (_isFocused && _selectedAction == 0)
                        ? Colors.white
                        : colorScheme.onSurfaceVariant,
                    size: 28,
                  ),
                ),
              ),

              // Favorite button (second action - index 1)
              if (hasFavoriteButton)
                GestureDetector(
                  onTap: () => widget.onFavoriteToggle?.call(!widget.isFavorited),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: (_isFocused && _selectedAction == 1)
                          ? colorScheme.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      widget.isFavorited ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: widget.isFavorited
                          ? const Color(0xFFFFD700)
                          : (_isFocused && _selectedAction == 1)
                              ? Colors.white
                              : colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultIcon(ColorScheme colorScheme) {
    return Center(
      child: Icon(
        widget.channel.contentType == 'vod' ? Icons.movie : Icons.live_tv,
        size: 32,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
