import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/home/home_theme.dart';
import 'package:flutter/material.dart';

/// Gold DPAD focus ring — an in-bounds *foreground* border, exactly like the
/// episode rows in the right pane (and the same [HomeTheme.focusGold] hue, so
/// the cursor doesn't shift color crossing panes). Every interactive element on
/// this screen wraps itself in one — the default InkWell focus overlay is
/// invisible on both the white Play pill and dark glass surfaces, which made
/// the remote cursor untrackable on TV.
///
/// Deliberately NOT a shadow ring: spread shadows paint a *filled* rect behind
/// the child (they bleed through translucent glass surfaces as a solid gold
/// fill), and they paint outside bounds (forcing rails to un-clip and leak
/// scrolled-out tiles). A foreground border stays crisp on any surface, keeps
/// the glass translucency, and never needs `Clip.none`.
class _FocusHalo extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  /// Null keeps Classic's gold.
  final Color? ringColor;

  const _FocusHalo({
    required this.focused,
    required this.child,
    this.radius,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // Snap on TV (house focus idiom): a 140ms ring fade per DPAD move makes
      // held-key surfing repaint every element in flight on the weak GPU.
      duration: PlatformUtil.isTelevision
          ? Duration.zero
          : const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: focused
            ? Border.all(color: ringColor ?? HomeTheme.focusGold, width: 2.5)
            : null,
      ),
      child: child,
    );
  }
}

typedef MergedFocusHalo = _FocusHalo;

const mergedFocusHaloConstructor = _FocusHalo.new;
