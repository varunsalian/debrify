import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Portrait playlist card optimized for grid layouts on desktop/tablet/mobile.
///
/// Displays playlist item with:
/// - Poster thumbnail (portrait 2:3 ratio, like Netflix)
/// - Title overlay at bottom
/// - Provider badge
/// - Progress indicator for in-progress items
/// - Hover effects on desktop
/// - DPAD navigation support with proper focus handling
class PlaylistGridCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? progressData;
  final bool isFavorited;
  final VoidCallback onPlay;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback? onClearProgress;
  final VoidCallback? onToggleFavorite;
  final bool autofocus;
  final void Function(bool focused)? onFocusChanged;
  final FocusNode? focusNode; // External focus node for parent control
  /// Called when up arrow is pressed (for cross-section navigation)
  final VoidCallback? onUpArrowPressed;
  /// Called when down arrow is pressed (for cross-section navigation)
  final VoidCallback? onDownArrowPressed;

  const PlaylistGridCard({
    super.key,
    required this.item,
    this.progressData,
    this.isFavorited = false,
    required this.onPlay,
    required this.onView,
    required this.onDelete,
    this.onClearProgress,
    this.onToggleFavorite,
    this.autofocus = false,
    this.onFocusChanged,
    this.focusNode,
    this.onUpArrowPressed,
    this.onDownArrowPressed,
  });

  @override
  State<PlaylistGridCard> createState() => _PlaylistGridCardState();
}

class _PlaylistGridCardState extends State<PlaylistGridCard> {
  bool _isHovered = false;
  bool _isFocused = false;

  void _updateFocusState(bool focused) {
    if (_isFocused != focused) {
      setState(() => _isFocused = focused);
      widget.onFocusChanged?.call(focused);
    }
  }

  void _updateHoverState(bool hovered) {
    if (_isHovered != hovered) {
      setState(() => _isHovered = hovered);
    }
  }

  void _showActionMenu(BuildContext context) {
    final title = widget.item['title'] as String? ?? 'Untitled';
    final posterUrl = widget.item['posterUrl'] as String?;
    final provider = widget.item['provider'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _PlaylistActionSheet(
        title: title,
        posterUrl: posterUrl,
        provider: provider != null ? _prettifyProvider(provider) : null,
        isFavorited: widget.isFavorited,
        hasProgress: widget.onClearProgress != null,
        hasFavoriteToggle: widget.onToggleFavorite != null,
        onPlay: () {
          Navigator.pop(context);
          widget.onPlay();
        },
        onView: () {
          Navigator.pop(context);
          widget.onView();
        },
        onToggleFavorite: widget.onToggleFavorite != null
            ? () {
                Navigator.pop(context);
                widget.onToggleFavorite?.call();
              }
            : null,
        onClearProgress: widget.onClearProgress != null
            ? () {
                Navigator.pop(context);
                widget.onClearProgress?.call();
              }
            : null,
        onDelete: () {
          Navigator.pop(context);
          widget.onDelete();
        },
      ),
    );
  }

  String _prettifyProvider(String? raw) {
    if (raw == null || raw.isEmpty) return 'RD';
    switch (raw.toLowerCase()) {
      case 'realdebrid':
      case 'real-debrid':
      case 'real_debrid':
        return 'RD';
      case 'torbox':
        return 'TB';
      case 'pikpak':
      case 'pik-pak':
      case 'pik_pak':
        return 'PP';
      case 'alldebrid':
      case 'all-debrid':
      case 'all_debrid':
        return 'AD';
      default:
        return raw.substring(0, 2).toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.item['title'] as String? ?? 'Untitled';
    final posterUrl = widget.item['posterUrl'] as String?;
    final provider = widget.item['provider'] as String?;

    // Calculate progress if available
    double? progress;
    if (widget.progressData != null) {
      final positionMs = widget.progressData!['positionMs'] as int? ?? 0;
      final durationMs = widget.progressData!['durationMs'] as int? ?? 0;
      if (durationMs > 0) {
        progress = (positionMs / durationMs).clamp(0.0, 1.0);
      }
    }

    final bool isActive = _isHovered || _isFocused;

    // Dynamic font size based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final double titleFontSize;
    final int maxLines;

    if (screenWidth > 800) {
      // Desktop/tablet: readable font, 4 lines for long titles
      titleFontSize = 13;
      maxLines = 4;
    } else if (screenWidth > 500) {
      // Larger phones: medium font, 3 lines
      titleFontSize = 13;
      maxLines = 3;
    } else {
      // Standard phones: larger font for better readability, 3 lines
      titleFontSize = 14;
      maxLines = 3;
    }

    return MouseRegion(
      onEnter: (_) => _updateHoverState(true),
      onExit: (_) => _updateHoverState(false),
      child: Focus(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: _updateFocusState,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            final key = event.logicalKey;

            // Handle selection (Enter/Select)
            if (key == LogicalKeyboardKey.select ||
                key == LogicalKeyboardKey.enter) {
              _showActionMenu(context);
              return KeyEventResult.handled;
            }

            // Handle up/down for cross-section navigation (TV horizontal rows)
            if (key == LogicalKeyboardKey.arrowUp && widget.onUpArrowPressed != null) {
              widget.onUpArrowPressed!();
              return KeyEventResult.handled;
            }
            if (key == LogicalKeyboardKey.arrowDown && widget.onDownArrowPressed != null) {
              widget.onDownArrowPressed!();
              return KeyEventResult.handled;
            }

            // Allow left/right arrow keys to propagate for horizontal scrolling
            if (key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight) {
              return KeyEventResult.ignored;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () => _showActionMenu(context),
          // Use TweenAnimationBuilder for smoother GPU-accelerated animations
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 1.0, end: isActive ? 1.08 : 1.0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutBack, // Subtle bounce for premium feel
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: child,
              );
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: isActive
                    ? [
                        // Premium glow effect - Netflix red
                        BoxShadow(
                          color: const Color(0xFFE50914).withValues(alpha: 0.5),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                        // Subtle dark shadow for depth
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [
                        // Subtle resting shadow
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // Poster background
                    _buildPoster(posterUrl),

                    // Gradient overlay (darker at bottom for text readability)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.5),
                              Colors.black.withValues(alpha: 0.9),
                            ],
                            stops: const [0.2, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // Provider badge (top left) with modern design
                    if (provider != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFFB20710)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withValues(alpha: 0.4),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            _prettifyProvider(provider),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                    // Favorite star badge (top right) with glow effect
                    if (widget.isFavorited)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withValues(alpha: 0.7),
                                Colors.black.withValues(alpha: 0.5),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            color: Color(0xFFFFD700),
                            size: 16,
                          ),
                        ),
                      ),

                    // Progress indicator (bottom) with modern style
                    if (progress != null && progress > 0 && progress < 1.0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          child: Container(
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: progress,
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Color(0xFFE50914), Color(0xFFFF4444)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Title overlay (bottom)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: progress != null && progress >= 0.05 && progress <= 0.95 ? 20 : 16,
                      child: Text(
                        title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          shadows: const [
                            Shadow(
                              color: Colors.black,
                              offset: Offset(0, 1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                    // Play button overlay (appears on focus/hover)
                    Positioned.fill(
                      child: AnimatedOpacity(
                        opacity: isActive ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.8, end: isActive ? 1.0 : 0.8),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFE50914).withValues(alpha: 0.6),
                                    blurRadius: 20,
                                    spreadRadius: 2,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Focus/hover border with animated glow effect
                    Positioned.fill(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive
                                ? const Color(0xFFE50914)
                                : Colors.transparent,
                            width: isActive ? 3 : 0,
                          ),
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
    );
  }

  Widget _buildPoster(String? posterUrl) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: posterUrl != null && posterUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: posterUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white24),
                  ),
                ),
              ),
              errorWidget: (context, url, error) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.video_library,
                  size: 64,
                  color: Colors.white24,
                ),
              ),
            )
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(
                Icons.video_library,
                size: 64,
                color: Colors.white24,
              ),
            ),
    );
  }
}

/// Premium action sheet with poster header and glassmorphism design
class _PlaylistActionSheet extends StatefulWidget {
  final String title;
  final String? posterUrl;
  final String? provider;
  final bool isFavorited;
  final bool hasProgress;
  final bool hasFavoriteToggle;
  final VoidCallback onPlay;
  final VoidCallback onView;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onClearProgress;
  final VoidCallback onDelete;

  const _PlaylistActionSheet({
    required this.title,
    this.posterUrl,
    this.provider,
    required this.isFavorited,
    required this.hasProgress,
    required this.hasFavoriteToggle,
    required this.onPlay,
    required this.onView,
    this.onToggleFavorite,
    this.onClearProgress,
    required this.onDelete,
  });

  @override
  State<_PlaylistActionSheet> createState() => _PlaylistActionSheetState();
}

class _PlaylistActionSheetState extends State<_PlaylistActionSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // Focus nodes for DPAD navigation
  final List<FocusNode> _focusNodes = [];
  final FocusScopeNode _focusScopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();

    // Create focus nodes for each action
    _initFocusNodes();

    // Auto-focus first item after animation starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_focusNodes.isNotEmpty) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  void _initFocusNodes() {
    // Count how many actions we have
    int count = 2; // Play + View Files (always present)
    if (widget.hasFavoriteToggle) count++;
    if (widget.hasProgress) count++;
    count++; // Delete (always present)

    for (int i = 0; i < count; i++) {
      _focusNodes.add(FocusNode());
    }
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    _focusScopeNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.black.withValues(alpha: 0.5 * _fadeAnimation.value),
            child: GestureDetector(
              onTap: () {}, // Prevent tap through
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Sheet content
                    Transform.translate(
                      offset: Offset(0, 50 * (1 - _slideAnimation.value)),
                      child: Opacity(
                        opacity: _fadeAnimation.value,
                        child: Container(
                          margin: const EdgeInsets.all(12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.15),
                                    width: 0.5,
                                  ),
                                ),
                                child: FocusScope(
                                  node: _focusScopeNode,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildHeader(),
                                      _buildDivider(),
                                      _buildActions(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      height: 0.5,
      color: Colors.white.withValues(alpha: 0.1),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          // Poster
          Container(
            width: 56,
            height: 84,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: widget.posterUrl != null && widget.posterUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: widget.posterUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => _buildPosterPlaceholder(),
                      errorWidget: (context, url, error) => _buildPosterPlaceholder(),
                    )
                  : _buildPosterPlaceholder(),
            ),
          ),
          const SizedBox(width: 14),
          // Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.provider != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.provider!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPosterPlaceholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.1),
      child: Icon(
        Icons.movie_outlined,
        color: Colors.white.withValues(alpha: 0.3),
        size: 24,
      ),
    );
  }

  Widget _buildActions() {
    int index = 0;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // Play button
          _GlassButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            focusNode: _focusNodes[index++],
            autofocus: true,
            onTap: widget.onPlay,
          ),
          // View Files
          _GlassButton(
            icon: Icons.folder_outlined,
            label: 'View Files',
            focusNode: _focusNodes[index++],
            onTap: widget.onView,
          ),
          // Favorite toggle
          if (widget.hasFavoriteToggle)
            _GlassButton(
              icon: widget.isFavorited ? Icons.star_rounded : Icons.star_outline_rounded,
              label: widget.isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
              iconColor: widget.isFavorited ? const Color(0xFFFFD700) : null,
              focusNode: _focusNodes[index++],
              onTap: widget.onToggleFavorite!,
            ),
          // Clear progress
          if (widget.hasProgress)
            _GlassButton(
              icon: Icons.refresh_rounded,
              label: 'Clear Progress',
              focusNode: _focusNodes[index++],
              onTap: widget.onClearProgress!,
            ),
          // Delete
          _GlassButton(
            icon: Icons.delete_outline_rounded,
            label: 'Delete',
            isDanger: true,
            focusNode: _focusNodes[index],
            onTap: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

/// Minimal glass-style button with DPAD support
class _GlassButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  final bool isDanger;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _GlassButton({
    required this.icon,
    required this.label,
    this.iconColor,
    this.isDanger = false,
    this.autofocus = false,
    this.focusNode,
    required this.onTap,
  });

  @override
  State<_GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<_GlassButton> {
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isPressed || _isFocused;
    final textColor = widget.isDanger
        ? const Color(0xFFFF6B6B)
        : Colors.white.withValues(alpha: _isFocused ? 1.0 : 0.9);
    final iconColor = widget.iconColor ??
        (widget.isDanger
            ? const Color(0xFFFF6B6B)
            : Colors.white.withValues(alpha: _isFocused ? 1.0 : 0.7));

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter) {
            widget.onTap();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isHighlighted
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isFocused
                  ? Colors.white.withValues(alpha: 0.3)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: iconColor, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: _isFocused ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: _isFocused ? 0.5 : 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
