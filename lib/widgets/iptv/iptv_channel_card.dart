import 'dart:ui';

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
                    // Live badge
                    if (channel.isLive)
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
        Icons.live_tv,
        size: 32,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Grid card widget for IPTV channels with glass morphism effect
class IptvChannelGridCard extends StatefulWidget {
  final IptvChannel channel;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool isFavorited;
  final ValueChanged<bool>? onFavoriteToggle;
  final int gridColumns;
  final int index;
  final int totalItems;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  const IptvChannelGridCard({
    super.key,
    required this.channel,
    required this.onTap,
    this.focusNode,
    this.isFavorited = false,
    this.onFavoriteToggle,
    this.gridColumns = 4,
    this.index = 0,
    this.totalItems = 0,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  @override
  State<IptvChannelGridCard> createState() => _IptvChannelGridCardState();
}

class _IptvChannelGridCardState extends State<IptvChannelGridCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isHovered = false;

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
    setState(() => _isFocused = _focusNode.hasFocus);
    if (_isFocused) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 200),
      );
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // Grid navigation
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      widget.onNavigateUp?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      widget.onNavigateDown?.call();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      final col = widget.index % widget.gridColumns;
      if (col > 0) {
        widget.onNavigateLeft?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      final col = widget.index % widget.gridColumns;
      if (col < widget.gridColumns - 1 && widget.index + 1 < widget.totalItems) {
        widget.onNavigateRight?.call();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Select/Enter - play channel
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      widget.onTap();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final channel = widget.channel;
    final isHighlighted = _isFocused || _isHovered;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            transform: isHighlighted
                ? (Matrix4.identity()..scale(1.05))
                : Matrix4.identity(),
            transformAlignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: isHighlighted ? 0.15 : 0.08),
                        Colors.white.withValues(alpha: isHighlighted ? 0.08 : 0.03),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isHighlighted
                          ? const Color(0xFFEC4899).withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.1),
                      width: isHighlighted ? 2 : 1,
                    ),
                    boxShadow: [
                      if (isHighlighted)
                        BoxShadow(
                          color: const Color(0xFFEC4899).withValues(alpha: 0.3),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo area
                      Expanded(
                        flex: 3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Channel logo
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(13),
                              ),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.3),
                                padding: const EdgeInsets.all(12),
                                child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                                    ? Image.network(
                                        channel.logoUrl!,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) => _buildDefaultIcon(),
                                      )
                                    : _buildDefaultIcon(),
                              ),
                            ),
                            // Live badge
                            if (channel.isLive)
                              Positioned(
                                top: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.red.withValues(alpha: 0.5),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
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
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Favorite badge
                            if (widget.isFavorited)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(
                                    Icons.star_rounded,
                                    size: 14,
                                    color: Color(0xFFFFD700),
                                  ),
                                ),
                              ),
                            // Play overlay on focus
                            if (isHighlighted)
                              Positioned.fill(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(13),
                                    ),
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEC4899),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFEC4899)
                                                .withValues(alpha: 0.5),
                                            blurRadius: 12,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      // Channel info
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Channel name
                              Text(
                                channel.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (channel.group != null && channel.group!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  channel.group!,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 9,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return Center(
      child: Icon(
        Icons.live_tv_rounded,
        size: 36,
        color: Colors.white.withValues(alpha: 0.4),
      ),
    );
  }
}
