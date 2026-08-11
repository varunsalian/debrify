import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../theme/ui_feedback.dart';
import '../../../theme/widgets/focus_expression.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

/// TV-optimized focusable button.
///
/// A larger button with icon and label that scales on focus, designed
/// for Android TV navigation with D-pad support.
class TvFocusableButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color backgroundColor;
  final double? width;

  const TvFocusableButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    this.width,
  });

  @override
  State<TvFocusableButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<TvFocusableButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    // Legacy paints its own cursor — the 3px ring AND the 1.1 pop below, both
    // of which move to the theme's expression everywhere else. They travel
    // together on purpose: a ring stacked on a scale reads as two cursors, and
    // `FocusTokens.legacy` is 2.5 with no width override to hand this site, so
    // the shipped 3 could not survive the box anyway.
    final ownCursor = app.isLegacy;

    // Legacy keeps the shipped white: call sites pass literal action tones
    // (gold, green, blue), and contrast-scoring against the gold would flip
    // today's label to near-black — a visible change to an app that has always
    // been white-on-gold here.
    //
    // Every OTHER theme must score, though. `core.tx` unconditionally is
    // white-on-white on Noir and Frost (white accents) and amber-on-amber on
    // Phosphor — 1:1, an invisible label. The split is the point: preserve the
    // shipped pixel exactly, and stop pretending page ink is legible on an
    // arbitrary fill.
    final restingInk =
        app.isLegacy ? app.core.tx : app.inkOn(widget.backgroundColor);

    // A closure rather than an inline tree so `inverted` can hand the same
    // button back wearing the accent's ink: the icon and the label are all the
    // ink this widget has, which is what makes it worth inverting at all.
    Widget button({required Color fill, required Color ink}) => Container(
      width: widget.width,
      decoration: BoxDecoration(
        borderRadius: app.shape.br(16),
        // TV: the white border is the focus cue; skip the blurred glow.
        boxShadow: _isFocused && ownCursor && !PlatformUtil.isTelevision
            ? [
                BoxShadow(
                  // The glow is the focus ring bled out. 77, not
                  // `withValues(alpha: 0.3)`: the source composed this
                  // with `withOpacity`, which rounds to an 8-bit alpha
                  // (77/255 = 0.3020) — 0.3 exactly is a different colour.
                  color: tv.focusRing.withAlpha(77),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ]
            : null,
        border: _isFocused && ownCursor
            ? Border.all(color: tv.focusRing, width: 3)
            : null,
      ),
      child: FilledButton.icon(
        // The pointer path gets the same feedback the key path does — a mouse
        // click and a tvOS trackpad click both arrive here, not through the
        // key handler, and an activation that is audible by DPAD and silent by
        // click is worse than one that is silent either way.
        onPressed: widget.onPressed == null
            ? null
            : () {
                UiFeedback.instance.activate();
                widget.onPressed!();
              },
        icon: Icon(widget.icon, size: 20),
        label: Text(
          widget.label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: app.shape.br(16),
          ),
        ),
      ),
    );

    final Widget cursor = ownCursor
        ? AnimatedScale(
            scale: _isFocused ? 1.1 : 1.0,
            // TV: snap — animating the scale re-rasters the button (and its
            // blurred shadow) for ~12 frames per focus move.
            duration: PlatformUtil.isTelevision
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: button(fill: widget.backgroundColor, ink: restingInk),
          )
        : FocusExpressionBox(
            focused: _isFocused,
            radius: 16,
            // The fill IS the surface the ring sits on, and it is an arbitrary
            // call-site colour — this is the site the rescue was written for.
            on: widget.backgroundColor,
            // Inverting means the accent becomes the fill, so the button's own
            // must get out of the way.
            inverted: (context, accentInk) =>
                button(fill: Colors.transparent, ink: accentInk),
            child: button(fill: widget.backgroundColor, ink: restingInk),
          );

    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            isActivateKey(event.logicalKey)) {
          // Activation feedback is an EXPLICIT call at the chokepoint, never
          // inferred from focus: the only thing that knows a button was
          // pressed is the button. Silent under every look that asks for
          // silence, which is all of them but two.
          UiFeedback.instance.activate();
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: cursor,
    );
  }
}
