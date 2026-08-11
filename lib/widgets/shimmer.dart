import 'package:flutter/material.dart';

/// Skeleton placeholder shared by themed surfaces, surfaces still scheduled for
/// conversion, and the permanently-frozen video player.
///
/// It deliberately does NOT read the app theme: the player renders it and must
/// never follow the palette. Hosts that are themed pass their own resolved
/// tokens instead (`theme.downloads.shimmerBase` / `.shimmerHighlight`), so one
/// widget can serve every side at once.
class Shimmer extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  /// Resting fill — gradient stops 1 and 3.
  ///
  /// Set ONLY by a themed host. Omitting it (or passing null) keeps today's
  /// exact literal, which is what the frozen player, Classic details and every
  /// not-yet-converted surface must keep rendering.
  final Color? base;

  /// The travelling bright stop — gradient stop 2. Same opt-in rule as [base].
  final Color? highlight;

  const Shimmer({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.base = const Color(0xFF223049),
    this.highlight = const Color(0xFF2A3A55),
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        // `??` covers a host forwarding a nullable token; omission is covered by
        // the constructor default. Both land on today's legacy literal.
        final base = widget.base ?? const Color(0xFF223049);
        final highlight = widget.highlight ?? const Color(0xFF2A3A55);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: [base, highlight, base],
              stops: const [0.1, 0.3, 0.5],
            ),
          ),
        );
      },
    );
  }
}

class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  const PressableScale({super.key, required this.child, this.onTap, this.borderRadius});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 120));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapCancel: () => _ctrl.reverse(),
      onTapUp: (_) => _ctrl.reverse(),
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: 0.98).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut)),
        child: ClipRRect(
          borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
          child: widget.child,
        ),
      ),
    );
  }
} 