import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
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
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            isActivateKey(event.logicalKey)) {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: _isFocused ? 1.1 : 1.0,
        // TV: snap — animating the scale re-rasters the button (and its
        // blurred shadow) for ~12 frames per focus move.
        duration: PlatformUtil.isTelevision
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: Container(
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: app.shape.br(16),
            // TV: the white border is the focus cue; skip the blurred glow.
            boxShadow: _isFocused && !PlatformUtil.isTelevision
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
            border: _isFocused
                ? Border.all(color: tv.focusRing, width: 3)
                : null,
          ),
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 20),
            label: Text(
              widget.label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: widget.backgroundColor,
              // Legacy keeps the shipped white: call sites pass literal action
              // tones (gold, green, blue), and contrast-scoring against the
              // gold would flip today's label to near-black — a visible change
              // to an app that has always been white-on-gold here.
              //
              // Every OTHER theme must score, though. `core.tx` unconditionally
              // is white-on-white on Noir and Frost (white accents) and
              // amber-on-amber on Phosphor — 1:1, an invisible label. The
              // split is the point: preserve the shipped pixel exactly, and
              // stop pretending page ink is legible on an arbitrary fill.
              foregroundColor: app.isLegacy
                  ? app.core.tx
                  : app.inkOn(widget.backgroundColor),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: app.shape.br(16),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
