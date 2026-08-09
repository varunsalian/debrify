import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

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
    final app = AppThemeScope.of(context);
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
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              colors: [
                // The two fade-out stops stay transparent WHITE: a sweep
                // interpolates unpremultiplied, so swapping the invisible ends
                // for a themed hue would change the colours in between.
                // 0xFFB71C1C likewise has no token — it is the arc's deep
                // companion tone, and no role holds that value.
                const Color(0x00FFFFFF),
                app.debrifyTv.accent,
                const Color(0xFFB71C1C),
                const Color(0x00FFFFFF),
              ],
              stops: const [0.15, 0.45, 0.85, 1.0],
            ),
          ),
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: app.debrifyTv.fillWeak,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: app.debrifyTv.textDim,
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
