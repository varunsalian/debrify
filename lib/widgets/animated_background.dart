import 'package:flutter/material.dart';

/// The app shell's backdrop: a static deep-indigo wash behind everything.
///
/// This used to animate on phone/tablet/desktop — a 12s gradient sweep, a 20s
/// particle drift painted with blurred circles, and a vignette — while TV took
/// a static early-return for performance. That motion is gone: the non-TV shell
/// Scaffold is now opaque page ink (see `main.dart`, `HomeTheme.bg`), because
/// letting the wallpaper show through the SafeArea strips left the status-bar
/// and home-indicator bands a different colour from the page. With the shell
/// opaque, nothing on any platform could see the animation — it was a
/// full-screen repaint per frame, with a MaskFilter blur, behind an opaque
/// surface, for the life of the app.
///
/// What remains is exactly what TV already rendered, so TV is unchanged. Kept
/// as a widget (rather than folded into the shell) so there's still one place
/// to put a backdrop back if a screen ever wants to be translucent again; the
/// animated version is in git history.
class AnimatedPremiumBackground extends StatelessWidget {
  final Widget child;

  const AnimatedPremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1),
          end: Alignment(1, 1),
          colors: [Color(0xFF040610), Color(0xFF0A0E1A), Color(0xFF0E1230)],
        ),
      ),
      child: child,
    );
  }
}
