import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Landscape playlist card optimized for Android TV horizontal scrolling.
///
/// Displays playlist item with:
/// - Poster thumbnail (16:9 landscape ratio)
/// - Title with marquee on focus
/// - Metadata chips (provider, size, file count)
/// - Progress bar for in-progress items (5-95%)
/// - Focus effects: border animation, metadata overlay, gradient
class PlaylistLandscapeCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic>? progressData;
  final VoidCallback onPlay;
  final VoidCallback onView;
  final VoidCallback onDelete;
  final VoidCallback? onClearProgress;
  final double height;
  final void Function(bool focused)? onFocusChange;

  const PlaylistLandscapeCard({
    super.key,
    required this.item,
    this.progressData,
    required this.onPlay,
    required this.onView,
    required this.onDelete,
    this.onClearProgress,
    this.height = 150,
    this.onFocusChange,
  });

  @override
  State<PlaylistLandscapeCard> createState() => _PlaylistLandscapeCardState();
}

class _PlaylistLandscapeCardState extends State<PlaylistLandscapeCard> {
  bool _isFocused = false;
  final ScrollController _titleScrollController = ScrollController();
  Timer? _marqueeTimer;
  bool _isMarqueeActive = false;
  bool _shouldContinueMarquee = false; // Flag to prevent memory leaks

  @override
  void dispose() {
    _shouldContinueMarquee = false; // Cancel all pending marquee operations
    _marqueeTimer?.cancel();
    _titleScrollController.dispose();
    super.dispose();
  }

  void _startMarquee() {
    if (!_isFocused || _isMarqueeActive) return;

    _shouldContinueMarquee = true; // Start marquee sequence

    // Wait a bit before starting marquee
    _marqueeTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted || !_isFocused || !_shouldContinueMarquee) return;

      setState(() {
        _isMarqueeActive = true;
      });

      // Calculate scroll distance
      final maxScroll = _titleScrollController.position.maxScrollExtent;
      if (maxScroll <= 0) {
        setState(() {
          _isMarqueeActive = false;
        });
        return;
      }

      // Animate scroll
      _titleScrollController.animateTo(
        maxScroll,
        duration: Duration(milliseconds: (maxScroll * 20).toInt()), // ~20ms per pixel
        curve: Curves.linear,
      ).then((_) {
        if (!mounted || !_isFocused || !_shouldContinueMarquee) return;
        // Pause at end, then scroll back
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted || !_isFocused || !_shouldContinueMarquee) return;
          _titleScrollController.animateTo(
            0,
            duration: Duration(milliseconds: (maxScroll * 20).toInt()),
            curve: Curves.linear,
          ).then((_) {
            if (!mounted || !_shouldContinueMarquee) return;
            setState(() {
              _isMarqueeActive = false;
            });
            // Restart marquee after pause
            if (_isFocused && _shouldContinueMarquee) {
              Future.delayed(const Duration(milliseconds: 1000), _startMarquee);
            }
          });
        });
      });
    });
  }

  void _stopMarquee() {
    _shouldContinueMarquee = false; // Stop all pending marquee operations
    _marqueeTimer?.cancel();
    if (_titleScrollController.hasClients) {
      _titleScrollController.jumpTo(0);
    }
    setState(() {
      _isMarqueeActive = false;
    });
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

  @override
  Widget build(BuildContext context) {
    final width = widget.height * (16.0 / 9.0); // Landscape aspect ratio
    final title = widget.item['title'] as String? ?? 'Untitled';
    final posterUrl = widget.item['posterUrl'] as String?;

    // Calculate progress if available
    double? progress;
    if (widget.progressData != null) {
      final positionMs = widget.progressData!['positionMs'] as int? ?? 0;
      final durationMs = widget.progressData!['durationMs'] as int? ?? 0;
      if (durationMs > 0) {
        progress = (positionMs / durationMs).clamp(0.0, 1.0);
      }
    }

    return SizedBox(
      width: width,
      height: widget.height,
      child: Focus(
        onFocusChange: (focused) {
          setState(() {
            _isFocused = focused;
          });

          if (focused) {
            _startMarquee();
          } else {
            _stopMarquee();
          }

          // Notify parent about focus change
          widget.onFocusChange?.call(focused);
        },
        onKeyEvent: (node, event) {
          // On Android TV, pressing Select/Enter shows action menu
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter) {
              _showActionMenu(context);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () => _showActionMenu(context),
          child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isFocused
                      ? const Color(0xFFE50914) // Netflix red
                      : Colors.white.withValues(alpha: 0.12),
                  width: _isFocused ? 2 : 1,
                ),
                boxShadow: _isFocused
                    ? [
                        BoxShadow(
                          color: const Color(0xFFE50914).withValues(alpha: 0.4),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 0,
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Row(
                  children: [
                    // Poster section (40% of width)
                    _buildPoster(posterUrl, width * 0.4),

                    // Info section (60% of width)
                    Expanded(
                      child: _buildInfoPanel(title, progress, showButtons: false),
                    ),
                  ],
                ),
              ),
          ),
        ),
      ),
    );
  }

  Widget _buildPoster(String? posterUrl, double posterWidth) {
    return SizedBox(
      width: posterWidth,
      height: widget.height,
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
                  size: 48,
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
                size: 48,
                color: Colors.white24,
              ),
            ),
    );
  }

  Widget _buildInfoPanel(String title, double? progress, {bool showButtons = true}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isFocused
              ? [const Color(0xFF2A2A2A), const Color(0xFF1A1A1A)]
              : [const Color(0xFF1A1A1A), const Color(0xFF0F0F0F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title with marquee on focus
          SizedBox(
            height: 38, // 2 lines at fontSize 14
            child: SingleChildScrollView(
              controller: _titleScrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width * 0.15,
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),

          // Metadata chips
          _buildMetadata(),

          // Progress bar if available
          if (progress != null && progress > 0 && progress < 1.0)
            _buildProgressBar(progress)
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }


  Widget _buildMetadata() {
    final metadata = <String>[];

    // Provider
    final provider = widget.item['provider'] as String?;
    if (provider != null) {
      metadata.add(provider.toUpperCase());
    }

    // File count
    final fileCount = widget.item['fileCount'] as int?;
    if (fileCount != null && fileCount > 1) {
      metadata.add('$fileCount files');
    }

    // Size
    final sizeBytes = widget.item['sizeBytes'] as int?;
    if (sizeBytes != null) {
      final sizeGB = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1);
      metadata.add('${sizeGB}GB');
    }

    if (metadata.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: metadata.take(2).map((label) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildProgressBar(double progress) {
    final percentWatched = (progress * 100).toInt();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation(Color(0xFFE50914)),
            minHeight: 3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '$percentWatched% watched',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
