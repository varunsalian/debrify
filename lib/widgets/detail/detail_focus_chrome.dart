// Extracted verbatim from lib/screens/merged_series_detail_screen.dart
// (that screen's private presentational tail). Behaviour is unchanged; the
// only edits are the renames that make these public and the parameters that
// replace the host's private members.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform_util.dart';
import '../home/home_theme.dart';

/// The merged detail screen's fallback accent: the gold every unthemed pill,
/// glow and tint on that page falls back to until artwork resolves one.
const Color kDetailGold = Color(0xFFF5B942);

/// One-shot entrance for a hero-block item: after [delayMs], fades up from
/// transparent while rising 12px, so the detail header assembles itself around
/// the shared-element poster flight instead of popping in fully formed.
///
/// Cheap and TV-safe: a single 340ms opacity+translate on a small widget, run
/// once on mount (the controller never resets, so metadata-load rebuilds don't
/// replay it). [enabled] is false under OS reduced-motion — the child shows
/// immediately with no controller. Late-arriving sections (their own first
/// mount happens when enrichment lands) simply fade in on arrival.
class DetailStaggerReveal extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final bool enabled;

  const DetailStaggerReveal({
    super.key,
    required this.child,
    this.delayMs = 0,
    this.enabled = true,
  });

  @override
  State<DetailStaggerReveal> createState() => _DetailStaggerRevealState();
}

class _DetailStaggerRevealState extends State<DetailStaggerReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
    );
    _timer = Timer(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _controller?.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      builder: (_, child) {
        final t = Curves.easeOutCubic.transform(c.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 12),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

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
class DetailFocusHalo extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  /// Null keeps Classic's gold.
  final Color? ringColor;

  const DetailFocusHalo({
    super.key,
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

/// Wraps a rail's end cards: consumes LEFT on the first / RIGHT on the last so
/// the DPAD cursor stops at the rail's edge instead of escaping to whatever is
/// geometrically nearest (the episodes pane, the back button). A non-focusable
/// ancestor node sees the key on its way up from the focused card, before the
/// app-level shortcuts turn it into a traversal move.
class DetailRailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final Widget child;

  /// When set, RIGHT on the last card invokes this (pane crossing) instead of
  /// dead-stopping.
  final VoidCallback? onTrapRight;

  const DetailRailEdgeTrap({
    super.key,
    required this.trapLeft,
    required this.trapRight,
    required this.child,
    this.onTrapRight,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (trapLeft && key == LogicalKeyboardKey.arrowLeft) {
          return KeyEventResult.handled;
        }
        if (trapRight && key == LogicalKeyboardKey.arrowRight) {
          onTrapRight?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Auto-scrolls the enclosing scrollable when any descendant gains focus.
///
/// [Focus.onFocusChange] fires when this node *or a descendant* changes focus,
/// so wrapping a section with this (non-focusable, traversal-skipping) node
/// lets us react to a child button/tile being focused via DPAD:
///  • [toTop] snaps the column to offset 0 (reveals the header above the first
///    focusable — the "can't scroll back up to the details" fix);
///  • otherwise it `ensureVisible`s the wrapped section at [alignment].
class DetailScrollAnchor extends StatelessWidget {
  final Widget child;
  final bool toTop;
  final double alignment;

  /// Only meaningful on TV (DPAD focus scroll). On pointer/desktop this is a
  /// passthrough so a mouse click doesn't yank the column around.
  final bool active;

  const DetailScrollAnchor({
    super.key,
    required this.child,
    this.toTop = false,
    this.alignment = 0.5,
    this.active = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // Defer so it wins over the framework's own focus-ensureVisible and
        // runs after layout settles.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          if (toTop) {
            Scrollable.maybeOf(context)?.position.animateTo(
              0,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          } else {
            Scrollable.ensureVisible(
              context,
              alignment: alignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
            );
          }
        });
      },
      child: child,
    );
  }
}
