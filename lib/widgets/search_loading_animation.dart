import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Phases of the torrent search process.
enum SearchPhase {
  idle,
  fetchingMetadata,  // Series only: fetching season info from IMDb
  searching,
  checkingCache,
  filtering,
  complete,
}

/// Extension to get user-friendly status text for each phase.
extension SearchPhaseExtension on SearchPhase {
  String get statusText {
    switch (this) {
      case SearchPhase.idle:
        return '';
      case SearchPhase.fetchingMetadata:
        return 'Fetching series info...';
      case SearchPhase.searching:
        return 'Searching sources...';
      case SearchPhase.checkingCache:
        return 'Checking cache...';
      case SearchPhase.filtering:
        return 'Processing results...';
      case SearchPhase.complete:
        return 'Done!';
    }
  }

  String get subtitle {
    switch (this) {
      case SearchPhase.idle:
        return '';
      case SearchPhase.fetchingMetadata:
        return 'Loading season & episode data';
      case SearchPhase.searching:
        return 'Querying torrent indexers';
      case SearchPhase.checkingCache:
        return 'Verifying instant availability';
      case SearchPhase.filtering:
        return 'Applying filters & sorting';
      case SearchPhase.complete:
        return '';
    }
  }

  int get stepIndex {
    switch (this) {
      case SearchPhase.idle:
        return 0;
      case SearchPhase.fetchingMetadata:
        return 1;
      case SearchPhase.searching:
        return 2;
      case SearchPhase.checkingCache:
        return 3;
      case SearchPhase.filtering:
        return 4;
      case SearchPhase.complete:
        return 5;
    }
  }

  IconData get icon {
    switch (this) {
      case SearchPhase.idle:
        return Icons.search_rounded;
      case SearchPhase.fetchingMetadata:
        return Icons.tv_rounded;
      case SearchPhase.searching:
        return Icons.manage_search_rounded;
      case SearchPhase.checkingCache:
        return Icons.cached_rounded;
      case SearchPhase.filtering:
        return Icons.filter_list_rounded;
      case SearchPhase.complete:
        return Icons.check_circle_rounded;
    }
  }
}

/// Animated loading widget for torrent search with phase tracking.
/// Shows a cool animated icon with status text and step indicator.
class SearchLoadingAnimation extends StatefulWidget {
  final SearchPhase phase;
  final int? sourceCount;
  final bool isSeries;

  const SearchLoadingAnimation({
    super.key,
    required this.phase,
    this.sourceCount,
    this.isSeries = false,
  });

  @override
  State<SearchLoadingAnimation> createState() => _SearchLoadingAnimationState();
}

class _SearchLoadingAnimationState extends State<SearchLoadingAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _rotateController;
  late final AnimationController _fadeController;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _rotateAnimation;
  late final Animation<double> _fadeAnimation;

  // Time-based message progression for long searches (series only)
  int _searchDurationTier = 0; // 0 = initial, 1 = 3s+, 2 = 7s+

  @override
  void initState() {
    super.initState();

    // Start tracking search duration if already in searching phase
    if (widget.phase == SearchPhase.searching) {
      _startDurationTimer();
    }

    // Pulse animation for the glow effect
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Rotation animation for the icon
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _rotateAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.linear),
    );

    // Fade animation for text transitions
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1.0,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
  }

  void _startDurationTimer() {
    // Check every second to update duration tier
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (widget.phase == SearchPhase.searching && _searchDurationTier < 1) {
        setState(() => _searchDurationTier = 1);
        _fadeController.forward(from: 0.0);
      }
    });
    Future.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      if (widget.phase == SearchPhase.searching && _searchDurationTier < 2) {
        setState(() => _searchDurationTier = 2);
        _fadeController.forward(from: 0.0);
      }
    });
  }

  @override
  void didUpdateWidget(SearchLoadingAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) {
      // Trigger fade animation on phase change
      _fadeController.forward(from: 0.0);

      // Reset and start timer when entering searching phase
      if (widget.phase == SearchPhase.searching) {
        _searchDurationTier = 0;
        _startDurationTimer();
      } else {
        // Reset when leaving searching phase
        _searchDurationTier = 0;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotateController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  /// Get dynamic status text based on phase and duration (for series)
  String _getStatusText() {
    if (widget.phase == SearchPhase.searching && widget.isSeries) {
      switch (_searchDurationTier) {
        case 0:
          return 'Searching sources...';
        case 1:
          return 'Scanning seasons...';
        case 2:
          return 'Still searching...';
        default:
          return 'Searching sources...';
      }
    }
    return widget.phase.statusText;
  }

  /// Get dynamic subtitle based on phase and duration (for series)
  String _getSubtitle() {
    if (widget.phase == SearchPhase.searching && widget.isSeries) {
      switch (_searchDurationTier) {
        case 0:
          return 'Querying torrent indexers';
        case 1:
          return 'Probing S1, S2, S3... for packs';
        case 2:
          return 'Searching across multiple seasons';
        default:
          return 'Querying torrent indexers';
      }
    }
    return widget.phase.subtitle;
  }

  @override
  Widget build(BuildContext context) {
    final isTV = MediaQuery.of(context).size.width > 800;
    final iconSize = isTV ? 80.0 : 64.0;
    final fontSize = isTV ? 20.0 : 16.0;
    final subtitleSize = isTV ? 14.0 : 12.0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated icon with glow
            AnimatedBuilder(
              animation: Listenable.merge([_pulseAnimation, _rotateAnimation]),
              builder: (context, child) {
                return Container(
                  width: iconSize + 40,
                  height: iconSize + 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: 0.3 * _pulseAnimation.value),
                        blurRadius: 30 * _pulseAnimation.value,
                        spreadRadius: 5 * _pulseAnimation.value,
                      ),
                      BoxShadow(
                        color: const Color(0xFF8B5CF6)
                            .withValues(alpha: 0.2 * _pulseAnimation.value),
                        blurRadius: 50 * _pulseAnimation.value,
                        spreadRadius: 10 * _pulseAnimation.value,
                      ),
                    ],
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF1E293B).withValues(alpha: 0.9),
                          const Color(0xFF0F172A).withValues(alpha: 0.9),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFF6366F1)
                            .withValues(alpha: 0.3 + 0.2 * _pulseAnimation.value),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Transform.rotate(
                        angle: widget.phase == SearchPhase.fetchingMetadata ||
                                widget.phase == SearchPhase.searching ||
                                widget.phase == SearchPhase.checkingCache
                            ? _rotateAnimation.value
                            : 0,
                        child: ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF6366F1),
                              Color(0xFF8B5CF6),
                              Color(0xFFA855F7),
                            ],
                          ).createShader(bounds),
                          child: Icon(
                            widget.phase.icon,
                            size: iconSize,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Status text with fade animation
            FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  Text(
                    _getStatusText(),
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_getSubtitle().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _getSubtitle(),
                      style: TextStyle(
                        fontSize: subtitleSize,
                        color: Colors.white.withValues(alpha: 0.6),
                        letterSpacing: 0.3,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Step indicator dots
            _buildStepIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepIndicator() {
    // Series has 4 steps (metadata + search + cache + filter)
    // Movies have 3 steps (search + cache + filter)
    final steps = widget.isSeries
        ? [
            SearchPhase.fetchingMetadata,
            SearchPhase.searching,
            SearchPhase.checkingCache,
            SearchPhase.filtering,
          ]
        : [
            SearchPhase.searching,
            SearchPhase.checkingCache,
            SearchPhase.filtering,
          ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isActive = widget.phase.stepIndex >= step.stepIndex;
        final isCurrent = widget.phase == step;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 24 : 10,
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                gradient: isActive
                    ? const LinearGradient(
                        colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      )
                    : null,
                color: isActive ? null : const Color(0xFF374151),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            if (index < steps.length - 1)
              Container(
                width: 20,
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: widget.phase.stepIndex > step.stepIndex
                      ? const Color(0xFF6366F1).withValues(alpha: 0.5)
                      : const Color(0xFF374151),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        );
      }).toList(),
    );
  }
}

/// Compact version of search loading for smaller spaces.
class SearchLoadingCompact extends StatefulWidget {
  final SearchPhase phase;

  const SearchLoadingCompact({super.key, required this.phase});

  @override
  State<SearchLoadingCompact> createState() => _SearchLoadingCompactState();
}

class _SearchLoadingCompactState extends State<SearchLoadingCompact>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.rotate(
              angle: _controller.value * 2 * math.pi,
              child: Icon(
                widget.phase.icon,
                size: 18,
                color: const Color(0xFF6366F1),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        Text(
          widget.phase.statusText,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
