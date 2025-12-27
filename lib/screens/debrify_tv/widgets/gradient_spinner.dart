import 'package:flutter/material.dart';

/// An animated gradient spinner widget.
///
/// Displays a rotating circular gradient with a play icon in the center.
/// Used to indicate loading states in the Debrify TV feature.
class GradientSpinner extends StatefulWidget {
  const GradientSpinner({super.key});

  @override
  State<GradientSpinner> createState() => _GradientSpinnerState();
}

class _GradientSpinnerState extends State<GradientSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 56,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.rotate(
            angle: _controller.value * 6.28318,
            child: child,
          );
        },
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                Color(0x00FFFFFF),
                Color(0xFFE50914),
                Color(0xFFB71C1C),
                Color(0x00FFFFFF),
              ],
              stops: [0.15, 0.45, 0.85, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white70,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
