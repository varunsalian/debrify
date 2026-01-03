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
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E293B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.play_arrow, color: Color(0xFFE50914)),
              title: const Text('Play', style: TextStyle(color: Colors.white, fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                widget.onPlay();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Color(0xFF6366F1)),
              title: const Text('View Files', style: TextStyle(color: Colors.white, fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                widget.onView();
              },
            ),
            if (widget.onToggleFavorite != null)
              ListTile(
                leading: Icon(
                  widget.isFavorited ? Icons.star : Icons.star_border,
                  color: const Color(0xFFFFD700),
                ),
                title: Text(
                  widget.isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onToggleFavorite?.call();
                },
              ),
            if (widget.onClearProgress != null)
              ListTile(
                leading: const Icon(Icons.restart_alt, color: Color(0xFFFF9800)),
                title: const Text('Clear Progress', style: TextStyle(color: Colors.white, fontSize: 18)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onClearProgress?.call();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.white, fontSize: 18)),
              onTap: () {
                Navigator.pop(context);
                widget.onDelete();
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
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

            // Allow arrow keys to propagate for grid navigation
            // Don't handle them here - let GridView's focus traversal handle it
            if (key == LogicalKeyboardKey.arrowUp ||
                key == LogicalKeyboardKey.arrowDown ||
                key == LogicalKeyboardKey.arrowLeft ||
                key == LogicalKeyboardKey.arrowRight) {
              return KeyEventResult.ignored;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () => _showActionMenu(context),
          // Use AnimatedScale for GPU-accelerated smooth scaling
          child: AnimatedScale(
            scale: isActive ? 1.08 : 1.0,
            duration: const Duration(milliseconds: 150), // Snappier
            curve: Curves.easeOutCubic, // Smoother deceleration
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: isActive
                    ? [
                        // Subtle glow effect
                        BoxShadow(
                          color: const Color(0xFFE50914).withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
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

                    // Provider badge (top left)
                    if (provider != null)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _prettifyProvider(provider),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),

                    // Favorite star badge (top right)
                    if (widget.isFavorited)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            Icons.star,
                            color: Color(0xFFFFD700),
                            size: 18,
                          ),
                        ),
                      ),

                    // Progress indicator (bottom)
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
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
                            minHeight: 4,
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

                    // Focus/hover border with animated opacity
                    if (isActive)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFE50914),
                              width: 3,
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
