import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Premium loading overlay shown when adding a torrent to a debrid service.
/// Replaces the old Dialog-based loader with a cinematic full-screen overlay.
class DebridLoadingOverlay {
  DebridLoadingOverlay._();

  /// Show the loading overlay. Returns the dialog route so it can be dismissed.
  static void show(
    BuildContext context, {
    required String provider,
    required String torrentName,
    Color accentColor = const Color(0xFF6366F1),
    IconData icon = Icons.cloud_download_rounded,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => _DebridLoadingContent(
        provider: provider,
        torrentName: torrentName,
        accentColor: accentColor,
        icon: icon,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: child,
        );
      },
    );
  }

  /// Dismiss the overlay.
  static void dismiss(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Provider-specific helpers
  static void showRealDebrid(BuildContext context, String torrentName) {
    show(
      context,
      provider: 'Real-Debrid',
      torrentName: torrentName,
      accentColor: const Color(0xFF10B981),
      icon: Icons.cloud_download_rounded,
    );
  }

  static void showTorbox(BuildContext context, String torrentName) {
    show(
      context,
      provider: 'Torbox',
      torrentName: torrentName,
      accentColor: const Color(0xFF8B5CF6),
      icon: Icons.flash_on_rounded,
    );
  }
}

class _DebridLoadingContent extends StatefulWidget {
  final String provider;
  final String torrentName;
  final Color accentColor;
  final IconData icon;

  const _DebridLoadingContent({
    required this.provider,
    required this.torrentName,
    required this.accentColor,
    required this.icon,
  });

  @override
  State<_DebridLoadingContent> createState() => _DebridLoadingContentState();
}

class _DebridLoadingContentState extends State<_DebridLoadingContent>
    with TickerProviderStateMixin {
  late AnimationController _ringController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ringController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated ring + icon
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer spinning ring
                AnimatedBuilder(
                  animation: _ringController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _ringController.value * 2 * math.pi,
                      child: CustomPaint(
                        size: const Size(100, 100),
                        painter: _RingPainter(
                          color: widget.accentColor,
                          progress: _ringController.value,
                        ),
                      ),
                    );
                  },
                ),
                // Pulsing glow behind icon
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.accentColor.withValues(
                            alpha: 0.1 * _pulseAnimation.value),
                        boxShadow: [
                          BoxShadow(
                            color: widget.accentColor.withValues(
                                alpha: 0.15 * _pulseAnimation.value),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.accentColor,
                        size: 28,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Provider text
          Text(
            'Adding to ${widget.provider}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
              decoration: TextDecoration.none,
            ),
          ),

          const SizedBox(height: 10),

          // Torrent name
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              widget.torrentName,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the spinning arc ring
class _RingPainter extends CustomPainter {
  final Color color;
  final double progress;

  _RingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Track ring (very subtle)
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    canvas.drawCircle(center, radius, trackPaint);

    // Active arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 1.5,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.6),
          color,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 1.5,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
