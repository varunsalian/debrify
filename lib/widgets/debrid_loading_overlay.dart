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

  /// Show PikPak loading overlay with progress tracking.
  /// Returns a [PikPakOverlayHandle] to update progress and show timeout options.
  /// The [onDismissed] callback fires with the pop result when the user taps
  /// 'background', 'view_later', or 'cancel' — or null if dismissed by polling.
  static PikPakOverlayHandle showPikPak(
    BuildContext context,
    String torrentName, {
    void Function(String? result)? onDismissed,
  }) {
    final progress = ValueNotifier<int>(0);
    final showTimeoutOptions = ValueNotifier<bool>(false);
    final statusText = ValueNotifier<String>('Checking status...');

    showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => _PikPakLoadingContent(
        torrentName: torrentName,
        progress: progress,
        showTimeoutOptions: showTimeoutOptions,
        statusText: statusText,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(opacity: curved, child: child);
      },
    ).then((result) {
      onDismissed?.call(result);
    });

    return PikPakOverlayHandle(
      progress: progress,
      showTimeoutOptions: showTimeoutOptions,
      statusText: statusText,
    );
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

/// Handle for controlling the PikPak overlay from outside.
class PikPakOverlayHandle {
  final ValueNotifier<int> progress;
  final ValueNotifier<bool> showTimeoutOptions;
  final ValueNotifier<String> statusText;

  PikPakOverlayHandle({
    required this.progress,
    required this.showTimeoutOptions,
    required this.statusText,
  });

  void updateProgress(int value) => progress.value = value;
  void setTimeoutOptions(bool show) => showTimeoutOptions.value = show;
  void setStatus(String text) => statusText.value = text;

  void dispose() {
    progress.dispose();
    showTimeoutOptions.dispose();
    statusText.dispose();
  }
}

/// PikPak loading overlay with progress ring and timeout options.
class _PikPakLoadingContent extends StatefulWidget {
  final String torrentName;
  final ValueNotifier<int> progress;
  final ValueNotifier<bool> showTimeoutOptions;
  final ValueNotifier<String> statusText;

  const _PikPakLoadingContent({
    required this.torrentName,
    required this.progress,
    required this.showTimeoutOptions,
    required this.statusText,
  });

  @override
  State<_PikPakLoadingContent> createState() => _PikPakLoadingContentState();
}

class _PikPakLoadingContentState extends State<_PikPakLoadingContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _ringController;

  static const _accentColor = Color(0xFFFFAA00);

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.showTimeoutOptions,
        builder: (context, showTimeout, _) {
          if (showTimeout) return _buildTimeoutView();
          return _buildProgressView();
        },
      ),
    );
  }

  Widget _buildProgressView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress ring with percentage
        SizedBox(
          width: 120,
          height: 120,
          child: ValueListenableBuilder<int>(
            valueListenable: widget.progress,
            builder: (context, progress, _) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  // Spinning ring (indeterminate) or progress arc
                  AnimatedBuilder(
                    animation: _ringController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: const Size(120, 120),
                        painter: progress > 0
                            ? _ProgressRingPainter(
                                color: _accentColor,
                                progress: progress / 100,
                              )
                            : _RingPainter(
                                color: _accentColor,
                                progress: _ringController.value,
                              ),
                      );
                    },
                  ),
                  // Percentage text or icon
                  if (progress > 0)
                    Text(
                      '$progress%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.5,
                        decoration: TextDecoration.none,
                      ),
                    )
                  else
                    Icon(
                      Icons.cloud_sync_rounded,
                      color: _accentColor,
                      size: 32,
                    ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 28),

        // Title
        const Text(
          'Processing on PikPak',
          style: TextStyle(
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

        const SizedBox(height: 16),

        // Status text
        ValueListenableBuilder<String>(
          valueListenable: widget.statusText,
          builder: (context, status, _) {
            return Text(
              status,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // Background button
        TextButton(
          onPressed: () {
            Navigator.of(context).pop('background');
          },
          child: Text(
            'Run in Background',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeoutView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timer_outlined,
          color: _accentColor.withValues(alpha: 0.7),
          size: 48,
        ),

        const SizedBox(height: 20),

        const Text(
          'Taking longer than expected',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.none,
          ),
        ),

        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: Text(
            'This torrent is still processing. What would you like to do?',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 28),

        // Action buttons
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTimeoutButton(
              label: 'Keep Waiting',
              icon: Icons.hourglass_top_rounded,
              onTap: () {
                widget.showTimeoutOptions.value = false;
              },
            ),
            const SizedBox(width: 12),
            _buildTimeoutButton(
              label: 'View Later',
              icon: Icons.schedule_rounded,
              onTap: () {
                Navigator.of(context).pop('view_later');
              },
            ),
            const SizedBox(width: 12),
            _buildTimeoutButton(
              label: 'Cancel',
              icon: Icons.close_rounded,
              color: const Color(0xFFEF4444),
              onTap: () {
                Navigator.of(context).pop('cancel');
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeoutButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color.withValues(alpha: 0.7), size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Progress ring painter — shows a determinate arc based on progress (0.0-1.0)
class _ProgressRingPainter extends CustomPainter {
  final Color color;
  final double progress;

  _ProgressRingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;

    // Track
    final trackPaint = Paint()
      ..color = color.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawCircle(center, radius, trackPaint);

    // Progress arc
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
