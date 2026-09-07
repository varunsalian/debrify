/// The cinematic hero backdrop behind `CatalogItemDetailScreen`.
library;

import 'package:flutter/material.dart';

// ── Backdrop ────────────────────────────────────────────────────────────────

/// Cinematic backdrop: a slow Ken-Burns push-in, a gentle fade-in once the
/// image decodes, a layered vertical scrim, a corner vignette, and (on wide)
/// a left-side scrim where the content sits.
class CatalogDetailBackdrop extends StatefulWidget {
  final String? url;
  final bool isWide;

  /// When false (TV) the Ken-Burns push-in and fade-in are skipped — a
  /// static image, so there's no continuous repaint on low-power devices.
  final bool animate;
  const CatalogDetailBackdrop({
    super.key,
    required this.url,
    required this.isWide,
    this.animate = true,
  });

  @override
  State<CatalogDetailBackdrop> createState() => _CatalogDetailBackdropState();
}

class _CatalogDetailBackdropState extends State<CatalogDetailBackdrop>
    with SingleTickerProviderStateMixin {
  AnimationController? _ken;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _ken = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 22),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ken?.dispose();
    super.dispose();
  }

  Widget _image(String url) {
    final ken = _ken;

    // Static (TV): no fade-in, no Ken-Burns — cheapest possible.
    if (ken == null) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      );
    }

    return AnimatedBuilder(
      animation: ken,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(ken.value);
        return Transform.scale(
          scale: 1.0 + 0.07 * t,
          alignment: Alignment(0, -0.7 + 0.2 * t),
          child: child,
        );
      },
      child: Image.network(
        url,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        frameBuilder: (_, child, frame, wasSync) {
          if (wasSync) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOut,
            child: child,
          );
        },
        errorBuilder: (_, __, ___) => Container(color: Colors.black),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = widget.isWide;
    final url = widget.url;

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null && url.isNotEmpty)
            _image(url)
          else
            Container(color: Colors.black),

          // Base darkening wash — guarantees legibility even on pure-white
          // or very bright posters. Uniform tint, no gradient.
          const ColoredBox(color: Color(0x44000000)),

          // Corner vignette — frames the art, cinema style.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.25),
                radius: 1.15,
                colors: [
                  Color(0x00000000),
                  Color(0x00000000),
                  Color(0x66000000),
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),

          // Vertical scrim — heavier than before so content stays readable
          // regardless of poster brightness.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0x33000000),
                  Color(0x66000000),
                  Color(0xCC050507),
                  Color(0xF5050507),
                  Color(0xFF050507),
                ],
                stops: isWide
                    ? const [0.0, 0.30, 0.58, 0.82, 1.0]
                    : const [0.0, 0.32, 0.62, 0.86, 1.0],
              ),
            ),
          ),

          // Side scrim on wide layouts — darken the left where content sits,
          // fade to clear art on the right.
          if (isWide)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Color(0xEE050507),
                    Color(0x99050507),
                    Color(0x33000000),
                    Color(0x00000000),
                  ],
                  stops: [0.0, 0.32, 0.60, 1.0],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
