import 'package:flutter/material.dart';

class Shimmer extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  const Shimmer({super.key, this.width, this.height, this.borderRadius});

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
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * t, 0),
              end: Alignment(1 + 2 * t, 0),
              colors: const [
                Color(0xFF223049),
                Color(0xFF2A3A55),
                Color(0xFF223049),
              ],
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