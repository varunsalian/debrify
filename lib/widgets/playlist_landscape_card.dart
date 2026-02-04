import 'dart:async';
import 'dart:ui';
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

  void _showActionMenu(BuildContext context) {
    final title = widget.item['title'] as String? ?? 'Untitled';
    final posterUrl = widget.item['posterUrl'] as String?;
    final provider = widget.item['provider'] as String?;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _LandscapeActionSheet(
        title: title,
        posterUrl: posterUrl,
        provider: provider != null ? _prettifyProvider(provider) : null,
        hasProgress: widget.onClearProgress != null,
        onPlay: () {
          Navigator.pop(context);
          widget.onPlay();
        },
        onView: () {
          Navigator.pop(context);
          widget.onView();
        },
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

/// Premium action sheet with poster header and glassmorphism design (Landscape variant)
class _LandscapeActionSheet extends StatefulWidget {
  final String title;
  final String? posterUrl;
  final String? provider;
  final bool hasProgress;
  final VoidCallback onPlay;
  final VoidCallback onView;
  final VoidCallback? onClearProgress;
  final VoidCallback onDelete;

  const _LandscapeActionSheet({
    required this.title,
    this.posterUrl,
    this.provider,
    required this.hasProgress,
    required this.onPlay,
    required this.onView,
    this.onClearProgress,
    required this.onDelete,
  });

  @override
  State<_LandscapeActionSheet> createState() => _LandscapeActionSheetState();
}

class _LandscapeActionSheetState extends State<_LandscapeActionSheet>
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
          _LandscapeGlassButton(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            focusNode: _focusNodes[index++],
            autofocus: true,
            onTap: widget.onPlay,
          ),
          // View Files
          _LandscapeGlassButton(
            icon: Icons.folder_outlined,
            label: 'View Files',
            focusNode: _focusNodes[index++],
            onTap: widget.onView,
          ),
          // Clear progress
          if (widget.hasProgress)
            _LandscapeGlassButton(
              icon: Icons.refresh_rounded,
              label: 'Clear Progress',
              focusNode: _focusNodes[index++],
              onTap: widget.onClearProgress!,
            ),
          // Delete
          _LandscapeGlassButton(
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
class _LandscapeGlassButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isDanger;
  final bool autofocus;
  final FocusNode? focusNode;
  final VoidCallback onTap;

  const _LandscapeGlassButton({
    required this.icon,
    required this.label,
    this.isDanger = false,
    this.autofocus = false,
    this.focusNode,
    required this.onTap,
  });

  @override
  State<_LandscapeGlassButton> createState() => _LandscapeGlassButtonState();
}

class _LandscapeGlassButtonState extends State<_LandscapeGlassButton> {
  bool _isPressed = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final isHighlighted = _isPressed || _isFocused;
    final textColor = widget.isDanger
        ? const Color(0xFFFF6B6B)
        : Colors.white.withValues(alpha: _isFocused ? 1.0 : 0.9);
    final iconColor = widget.isDanger
        ? const Color(0xFFFF6B6B)
        : Colors.white.withValues(alpha: _isFocused ? 1.0 : 0.7);

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
