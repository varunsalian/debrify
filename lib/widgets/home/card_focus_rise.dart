import 'package:flutter/material.dart';

/// Violet-300 focus ring — a light ring over dark art pops at 10ft, while the
/// deep accent stays for chrome (tags, sidebar). Pairs with the calm 1.045
/// scale below.
const Color kCardFocusRing = Color(0xFFA78BFA);

/// Shared focus "rise" chrome for 2:3 poster cards: scale, shadow and
/// selection ring animate together on ONE duration + curve — mismatched timing
/// (scale tweening while ring/shadow snapped) is what read as cheap.
///
/// Everything animated is GPU-cheap: the scale is a transform; the shadow is
/// TWO fixed-blur layers whose colours crossfade (blurRadius/offset are
/// identical on both ends of the lerp, so the tween never re-derives a blur —
/// it only fades a pre-shaped one, and the transparent lift layer is skipped
/// at rest); the ring fades via opacity (skipped at 0). 120ms on TV: two cards
/// animate on every DPAD move (loser + gainer), so the shorter the tween, the
/// shorter the double-repaint window.
///
/// Lives here, outside the board, because the Discover stage's shelf wears the
/// same grammar — focus-feel tuning has to land ONCE for every poster the user
/// walks with a remote.
class CardFocusRise extends StatelessWidget {
  final bool active;
  final bool isTelevision;

  /// Focus ring colour override (the Canvas board and the Discover stage use
  /// white). Null keeps the classic grammar: violet on TV, soft white on
  /// hover elsewhere.
  final Color? ringColor;

  /// The card's content layers, stacked (StackFit.expand) inside the rounded
  /// clip; the selection ring draws above all of them.
  final List<Widget> children;

  const CardFocusRise({
    super.key,
    required this.active,
    required this.isTelevision,
    this.ringColor,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final focusFx = isTelevision
        ? const Duration(milliseconds: 120)
        : const Duration(milliseconds: 160);
    return AnimatedScale(
      duration: focusFx,
      curve: Curves.easeOutCubic,
      // TV pop calmed from 1.09 to the Nuvio-class 1.045: with the lighter
      // ring the smaller lift reads premium, and neighbours shift less.
      scale: active ? (isTelevision ? 1.045 : 1.05) : 1.0,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: AnimatedContainer(
          duration: focusFx,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              // Resting shadow — constant, keeps the card grounded.
              const BoxShadow(
                color: Color(0x59000000),
                blurRadius: 12,
                offset: Offset(0, 10),
              ),
              // Lift shadow — same geometry always, only its alpha animates
              // (transparent at rest, so Skia skips the draw entirely).
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.6 : 0.0),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ...children,
                // Selection ring — accent on TV focus, subtle white on hover.
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: active ? 1.0 : 0.0,
                      duration: focusFx,
                      curve: Curves.easeOutCubic,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                ringColor ??
                                (isTelevision
                                    ? kCardFocusRing
                                    : Colors.white.withValues(alpha: 0.6)),
                            width: isTelevision ? 2.5 : 1.5,
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
  }
}
