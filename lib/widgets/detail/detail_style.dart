import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/platform_util.dart';
import '../home/home_theme.dart';

/// Which shape a details-page layout should draw itself in.
///
/// Resolved from platform + geometry, never width alone: a full-bleed landscape
/// treatment breaks on an 834×1112 tablet, and a landscape phone is a phone.
enum DetailSize { tv, desktop, tabletPortrait, phone }

/// The one resolver. Every layout uses it so breakpoints can't drift apart.
///
/// `shortSide` is deliberately `min(w, h)` — using `size.width` would classify
/// an 800×400 landscape phone as a desktop.
DetailSize resolveDetailSize({required bool isTelevision, required Size size}) {
  if (isTelevision) return DetailSize.tv;
  final shortSide = math.min(size.width, size.height);
  final portrait = size.height >= size.width;
  if (shortSide <= 560) return DetailSize.phone;
  if (portrait && shortSide < 900) return DetailSize.tabletPortrait;
  return DetailSize.desktop;
}

extension DetailSizeX on DetailSize {
  bool get isTv => this == DetailSize.tv;
  bool get isPhone => this == DetailSize.phone;

  /// Layouts that pick between a side-by-side and a stacked arrangement.
  bool get isWide => this == DetailSize.tv || this == DetailSize.desktop;

  /// Compact-height surfaces (a TV is only ~540 logical px tall).
  bool get isTight => this == DetailSize.tv || this == DetailSize.phone;

  double get gutter => switch (this) {
    DetailSize.tv => 34,
    DetailSize.desktop => 30,
    DetailSize.tabletPortrait => 22,
    DetailSize.phone => 16,
  };
}

/// Per-page palette. `accent` is the title colour the screen extracted from the
/// poster; everything else is fixed.
///
/// `gold` is STATE ONLY — watched, progress, bound sources, awards. It is never
/// used for decoration, which is what makes it readable as state at a glance.
class DetailPalette {
  final Color accent;

  const DetailPalette({required this.accent});

  static const Color ink = Color(0xFF0B0B0E);
  static const Color ink2 = Color(0xFF0E0B14);
  static const Color gold = Color(0xFFF5B942);
  static const Color imdb = Color(0xFFF5C518);
  static Color get focus => HomeTheme.focusGold;

  static Color get glass => Colors.white.withValues(alpha: 0.07);
  static Color get hair => Colors.white.withValues(alpha: 0.11);
  static Color get tx2 => Colors.white.withValues(alpha: 0.64);
  static Color get tx3 => Colors.white.withValues(alpha: 0.40);
}

/// Bottom-anchored scrim for identity over artwork.
///
/// Tuned for a **legibility floor, not a look**: artwork can be anything, and
/// stops picked against a dark backdrop wash out completely over a bright one.
/// The identity band sits on ≥0.55 alpha ink whatever the image.
LinearGradient detailIdentityScrim() => const LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [
    DetailPalette.ink,
    Color(0xEB0B0B0E),
    Color(0xA30B0B0E),
    Color(0x610B0B0E),
  ],
  stops: [0.06, 0.42, 0.68, 1.0],
);

/// Top-half scrim for layouts that split art and content (Stage).
LinearGradient detailStageScrim() => const LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [
    DetailPalette.ink,
    Color(0xDB0B0B0E),
    Color(0x660B0B0E),
    Color(0x290B0B0E),
  ],
  stops: [0.04, 0.48, 0.76, 1.0],
);

/// Uppercase section label ("SUMMARY", "MORE LIKE THIS").
Widget detailSlab(String text) => Text(
  text.toUpperCase(),
  style: TextStyle(
    color: DetailPalette.tx3,
    fontSize: 10.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.5,
  ),
);

/// Glass chip used for genres.
Widget detailPill(String text) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
  decoration: BoxDecoration(
    color: DetailPalette.glass,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: DetailPalette.hair),
  ),
  child: Text(text, style: const TextStyle(fontSize: 11.5)),
);

/// The house focus ring: an in-bounds FOREGROUND border.
///
/// Never a spread shadow — those paint a filled rect behind the child, which
/// bleeds through the translucent glass surfaces as a solid gold block, and
/// they paint outside bounds, forcing rails to un-clip.
class DetailFocusRing extends StatelessWidget {
  final bool focused;
  final BorderRadius? radius; // null → circle
  final Widget child;

  const DetailFocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      // Snap on TV (house idiom): a ring fade per DPAD move repaints every
      // element in flight while a held key surfs the rail.
      duration: PlatformUtil.isAndroidTvCached
          ? Duration.zero
          : const Duration(milliseconds: 140),
      foregroundDecoration: BoxDecoration(
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: focused
            ? Border.all(color: DetailPalette.focus, width: 2.5)
            : null,
      ),
      child: child,
    );
  }
}

/// Consumes a directional key at a region's edge so the DPAD cursor stops there
/// instead of escaping to whatever is geometrically nearest.
///
/// A non-focusable ancestor sees the key on its way up from the focused child,
/// before app-level shortcuts turn it into a traversal move.
class DetailEdgeTrap extends StatelessWidget {
  final bool trapLeft;
  final bool trapRight;
  final bool trapUp;
  final bool trapDown;

  /// Invoked instead of dead-stopping, when the edge is a sanctioned crossing.
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onUp;
  final VoidCallback? onDown;

  final Widget child;

  const DetailEdgeTrap({
    super.key,
    required this.child,
    this.trapLeft = false,
    this.trapRight = false,
    this.trapUp = false,
    this.trapDown = false,
    this.onLeft,
    this.onRight,
    this.onUp,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    if (!trapLeft && !trapRight && !trapUp && !trapDown) return child;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        bool fire(bool trap, VoidCallback? cb) {
          if (!trap) return false;
          cb?.call();
          return true;
        }

        if (k == LogicalKeyboardKey.arrowLeft && fire(trapLeft, onLeft)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowRight && fire(trapRight, onRight)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp && fire(trapUp, onUp)) {
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowDown && fire(trapDown, onDown)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

/// Per-episode FocusNodes owned by a layout, keyed by view generation.
///
/// Layouts must not borrow the engine's nodes — those are disposed and rebuilt
/// on every season change, so a retained tab or an outgoing subtree can hold a
/// dead one. Owning them here also fixes the subtler half of that problem:
/// disposal is deferred to after the frame, because a node swapped out during
/// build is still registered with the framework until the `Focus` widget's
/// `didUpdateWidget` runs, and disposing it first throws
/// "A FocusNode was used after being disposed".
class DetailCellNodes {
  final String debugPrefix;
  final Map<String, FocusNode> _live = {};
  int _generation = -1;

  DetailCellNodes(this.debugPrefix);

  FocusNode of(int generation, int season, int number) {
    if (generation != _generation) {
      _retire(_live.values.toList());
      _live.clear();
      _generation = generation;
    }
    final key = '$generation:$season-$number';
    return _live.putIfAbsent(
      key,
      () => FocusNode(debugLabel: '$debugPrefix-$key'),
    );
  }

  FocusNode? lookup(int generation, int season, int number) =>
      _live['$generation:$season-$number'];

  /// The first node that is actually mounted — layouts use this to hand focus
  /// into the collection without assuming an index exists.
  FocusNode? get firstMounted =>
      _live.values.where((n) => n.context != null).firstOrNull;

  void dispose() {
    for (final n in _live.values) {
      n.dispose();
    }
    _live.clear();
  }

  void _retire(List<FocusNode> nodes) {
    if (nodes.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in nodes) {
        n.dispose();
      }
    });
  }
}

/// Reveals the engine's landing episode even when it is far outside a lazy
/// list's built range.
///
/// `Scrollable.ensureVisible` needs the target's context, and a bounded lazy
/// list has not built an item 30 rows down — so a reveal that only fires when
/// the node happens to be mounted silently does nothing for a deep link or a
/// late-season resume.
///
/// Converges by FRACTION rather than by a guessed item extent: each attempt
/// re-reads the live `maxScrollExtent`, which grows more accurate as the list
/// builds, so repeated jumps close in on the target instead of landing on the
/// same wrong offset forever. Once the item mounts, `ensureVisible` places it
/// exactly. Never moves focus.
void revealDetailLanding({
  required ScrollController controller,
  required int index,
  required int itemCount,
  required BuildContext? Function() contextOf,
  double alignment = 0.3,
  int retries = 8,
}) {
  if (index < 0 || itemCount <= 0) return;
  void attempt(int left) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = contextOf();
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: alignment,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          duration: Duration.zero,
        );
        return;
      }
      // hasClients goes false once the layout is disposed — this is also what
      // stops the retry chain rather than a mounted flag it cannot see.
      if (!controller.hasClients || left <= 0) return;
      final max = controller.position.maxScrollExtent;
      if (max <= 0) return;
      final frac = itemCount <= 1 ? 0.0 : index / (itemCount - 1);
      final target = (frac * max).clamp(0.0, max);
      if ((controller.offset - target).abs() > 1) {
        controller.jumpTo(target);
      } else if (left < retries) {
        // Converged on an offset the item still hasn't built at — nothing more
        // to gain from jumping again.
        return;
      }
      attempt(left - 1);
    });
  }

  attempt(retries);
}

/// A soft edge on a scroll region, so a row cut by the fold reads as "there is
/// more" rather than as a clipped element.
///
/// A painted gradient over a known ground colour, deliberately NOT a
/// [ShaderMask]: that forces a saveLayer every frame, which is exactly the
/// per-frame cost the TV budget rules out on a scrolling grid.
class DetailScrollFade extends StatelessWidget {
  final Widget child;
  final AxisDirection edge;
  final double extent;
  final Color ground;

  const DetailScrollFade({
    super.key,
    required this.child,
    this.edge = AxisDirection.down,
    this.extent = 28,
    this.ground = DetailPalette.ink,
  });

  @override
  Widget build(BuildContext context) {
    final vertical =
        edge == AxisDirection.down || edge == AxisDirection.up;
    final fade = IgnorePointer(
      child: SizedBox(
        width: vertical ? null : extent,
        height: vertical ? extent : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: switch (edge) {
                AxisDirection.down => Alignment.bottomCenter,
                AxisDirection.up => Alignment.topCenter,
                AxisDirection.right => Alignment.centerRight,
                AxisDirection.left => Alignment.centerLeft,
              },
              end: switch (edge) {
                AxisDirection.down => Alignment.topCenter,
                AxisDirection.up => Alignment.bottomCenter,
                AxisDirection.right => Alignment.centerLeft,
                AxisDirection.left => Alignment.centerRight,
              },
              colors: [ground, ground.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: edge == AxisDirection.right ? null : 0,
          right: edge == AxisDirection.left ? null : 0,
          top: edge == AxisDirection.down ? null : 0,
          bottom: edge == AxisDirection.up ? null : 0,
          child: fade,
        ),
      ],
    );
  }
}
