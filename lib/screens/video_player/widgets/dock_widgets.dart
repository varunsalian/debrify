/// The styled dock's building blocks. Used ONLY by the `two_tier` branch —
/// `classic` keeps `NetflixControlButton` untouched, which is what makes the
/// legacy path provably unchanged.
///
/// See `design/plans/PLAYER_DOCK_STYLES_PLAN.md` §3.
library;

import 'package:flutter/material.dart';

import 'dock_style.dart';

/// One tool control: icon, optional label, minimum [DockMetrics.target] tall.
class DockChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Hidden when the row has collapsed to icons. The label still reaches
  /// assistive tech and pointer users through [Semantics] and [Tooltip].
  final bool showLabel;
  final bool active;

  /// Semantic override for the accent — the record red. Null uses the palette.
  final Color? tint;
  final VoidCallback onPressed;
  final DockMetrics metrics;
  final DockPalette palette;

  const DockChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.metrics,
    required this.palette,
    this.showLabel = true,
    this.active = false,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      // Centred so an icon-only chip sits in the middle of its minWidth box.
      // The Container must NOT use `alignment` for this: a Container with an
      // alignment expands to fill bounded constraints, which made every chip
      // in the tools Wrap a full-width row.
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: metrics.icon,
          color: tint ?? (active ? palette.tick : palette.ink),
        ),
        if (showLabel) ...[
          SizedBox(width: metrics.gap * 0.75),
          // Flexible + ellipsis so a long label in a constrained row (a Wrap
          // line, or the wide arrangement's tool cluster) shrinks instead of
          // overflowing. The full text stays available via Tooltip/Semantics.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              // The BASE size. Labels ride the platform's own clamped scaler,
              // so pre-multiplying here would apply it twice.
              style: TextStyle(
                fontSize: metrics.label,
                fontWeight: FontWeight.w600,
                color: tint ?? (active ? palette.tick : palette.ink),
              ),
            ),
          ),
        ],
      ],
    );

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        label: label,
        selected: active,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(metrics.radius),
            child: Container(
              constraints: BoxConstraints(
                minHeight: metrics.target,
                minWidth: showLabel ? 0 : metrics.target,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: showLabel ? metrics.padX : metrics.padY,
                vertical: metrics.padY,
              ),
              decoration: BoxDecoration(
                color: active
                    ? (tint?.withValues(alpha: 0.22) ?? palette.activeFill)
                    : palette.chipFill,
                borderRadius: BorderRadius.circular(metrics.radius),
                border: Border.all(
                  color: active
                      ? (tint?.withValues(alpha: 0.55) ?? palette.activeEdge)
                      : palette.chipEdge,
                  width: 1,
                ),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular transport control. The [primary] variant is painted as a lit
/// object rather than a filled circle — a linear accent gradient, a radial
/// hot-spot, a specular hairline along the top edge, and a two-layer glow cast
/// onto the scrim. Hue alone does not read as premium.
///
/// The two gradients need two layers: a single [BoxDecoration] carries one
/// gradient and cannot composite a linear ramp with a radial highlight.
class DockTransportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final DockMetrics metrics;
  final DockPalette palette;
  final bool primary;

  const DockTransportButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.metrics,
    required this.palette,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final double size = primary ? metrics.target * 1.32 : metrics.target;
    final double iconSize = primary ? metrics.icon * 1.5 : metrics.icon * 1.15;

    Widget child = Icon(
      icon,
      size: iconSize,
      // aurum and ice both need dark ink here; hardcoding white would ship an
      // invisible glyph on either.
      color: primary ? palette.onPrimary : palette.ink,
    );

    if (primary) {
      child = DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            center: const Alignment(-0.44, -0.76),
            radius: 1.15,
            colors: [palette.specular, const Color(0x00FFFFFF)],
            stops: const [0.0, 0.52],
          ),
        ),
        child: Center(child: child),
      );
    }

    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 600),
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: primary
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [palette.hot, palette.deep],
                      )
                    : null,
                color: primary ? null : palette.chipFill,
                border: primary
                    ? Border.all(color: palette.specular, width: 1)
                    : null,
                boxShadow: primary
                    ? [
                        BoxShadow(
                          color: palette.glow,
                          blurRadius: 18 * metrics.k,
                          spreadRadius: -5 * metrics.k,
                          offset: Offset(0, 5 * metrics.k),
                        ),
                        BoxShadow(
                          color: palette.glow,
                          blurRadius: 34 * metrics.k,
                          spreadRadius: -14 * metrics.k,
                          offset: Offset(0, 12 * metrics.k),
                        ),
                      ]
                    : null,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// One entry in the overflow sheet.
class DockOverflowAction {
  final IconData icon;
  final String label;

  /// Right-aligned state readout — the speed, the aspect mode, the armed
  /// sleep timer. Null when the action has no state to show.
  final String? value;
  final bool active;
  final VoidCallback onPressed;

  const DockOverflowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.value,
    this.active = false,
  });
}

/// Everything the narrow dock could not fit, as a labelled list.
///
/// A list is more discoverable than a row that scrolls off-screen, which is
/// the defect this replaces. It lists **every** available control including
/// the promoted ones, so it is never a subset the user has to reason about.
class DockOverflowSheet extends StatelessWidget {
  final List<DockOverflowAction> actions;
  final DockPalette palette;
  final DockMetrics metrics;

  const DockOverflowSheet({
    super.key,
    required this.actions,
    required this.palette,
    required this.metrics,
  });

  static Future<void> show(
    BuildContext context, {
    required List<DockOverflowAction> actions,
    required DockPalette palette,
    required DockMetrics metrics,
  }) {
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x9E040610),
      isScrollControlled: true,
      // Landscape gets a side sheet: a bottom sheet in a 390lp-tall viewport
      // would cover the film entirely.
      constraints: landscape
          ? BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.46)
          : null,
      builder: (context) => DockOverflowSheet(
        actions: actions,
        palette: palette,
        metrics: metrics,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: palette.scrim,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(metrics.radius * 1.8),
          ),
          border: Border.all(color: palette.chipEdge, width: 1),
        ),
        padding: EdgeInsets.symmetric(vertical: metrics.padY * 1.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: EdgeInsets.only(bottom: metrics.padY),
              decoration: BoxDecoration(
                color: palette.inactiveTrack,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [for (final action in actions) _row(context, action)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, DockOverflowAction action) {
    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        onTap: () {
          Navigator.of(context).pop();
          action.onPressed();
        },
        child: Container(
          constraints: BoxConstraints(minHeight: metrics.target),
          padding: EdgeInsets.symmetric(
            horizontal: metrics.padX * 1.6,
            vertical: metrics.padY,
          ),
          child: Row(
            children: [
              Icon(
                action.icon,
                size: metrics.icon,
                color: action.active ? palette.tick : palette.ink,
              ),
              SizedBox(width: metrics.gap * 1.5),
              Expanded(
                child: Text(
                  action.label,
                  style: TextStyle(
                    fontSize: metrics.label * 1.1,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
              ),
              if (action.value != null)
                Text(
                  action.value!,
                  style: TextStyle(
                    fontSize: metrics.label,
                    fontWeight: FontWeight.w600,
                    color: action.active ? palette.tick : palette.inkDim,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reports its child's height after every layout, once, without dirtying the
/// tree during layout.
///
/// The dock's height is variable under `two_tier`, and six host behaviours
/// (the skip button, four gesture bands and the PikPak overlay) assume a fixed
/// one. This is how they learn the real value.
class DockExtentReporter extends StatefulWidget {
  final Widget child;

  /// Called with the measured height AND the generation it was measured
  /// under, so the host can discard a report that arrives after the geometry
  /// has already changed underneath it.
  final void Function(double height, int generation) onExtent;

  /// Incremented by the host on any geometry change. A change also resets the
  /// local cache, so the next measurement always publishes.
  final int generation;

  const DockExtentReporter({
    super.key,
    required this.child,
    required this.onExtent,
    this.generation = 0,
  });

  @override
  State<DockExtentReporter> createState() => _DockExtentReporterState();
}

class _DockExtentReporterState extends State<DockExtentReporter> {
  final GlobalKey _key = GlobalKey();
  double? _last;

  @override
  void didUpdateWidget(DockExtentReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // New geometry — the previous measurement says nothing about it.
    if (oldWidget.generation != widget.generation) _last = null;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final height = box.size.height;
      // Asymmetric: publish every increase exactly, because a protected band
      // shorter than the dock is the bug this exists to prevent. Only shrink
      // when it is worth a frame.
      final previous = _last;
      if (previous != null && height <= previous && (previous - height) < 1.0) {
        return;
      }
      if (previous == height) return;
      _last = height;
      widget.onExtent(height, widget.generation);
    });
    return KeyedSubtree(key: _key, child: widget.child);
  }
}

/// A slider track painted with the palette's accent **gradient**, running
/// `deep → hot` so the played edge is the brightest point on the bar.
///
/// Material's `SliderThemeData` only takes flat `Color`s, so the shipped dock
/// drew a solid pink bar while the design called for a gradient with a bloom
/// at the leading edge. This is what closes that gap.
class GradientSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  final Color deep;
  final Color hot;
  final Color inactive;
  final Color glow;

  const GradientSliderTrackShape({
    required this.deep,
    required this.hot,
    required this.inactive,
    required this.glow,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;
    final radius = Radius.circular(rect.height / 2);
    final canvas = context.canvas;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = inactive,
    );

    // In RTL the thumb travels right-to-left, so the played portion runs from
    // the RIGHT edge to the thumb. Taking left->thumb unconditionally showed a
    // full bar at position 0 and an empty one at the end.
    final ltr = textDirection == TextDirection.ltr;
    final thumbX = thumbCenter.dx.clamp(rect.left, rect.right);
    final played = ltr
        ? Rect.fromLTRB(rect.left, rect.top, thumbX, rect.bottom)
        : Rect.fromLTRB(thumbX, rect.top, rect.right, rect.bottom);
    if (played.width <= 0) return;

    // The bloom sits under the fill so the leading edge reads as lit.
    canvas.drawRRect(
      RRect.fromRectAndRadius(played, radius),
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(played, radius),
      Paint()
        ..shader =
            LinearGradient(
              // The hot end always sits at the leading (played) edge.
              begin: ltr ? Alignment.centerLeft : Alignment.centerRight,
              end: ltr ? Alignment.centerRight : Alignment.centerLeft,
              colors: [deep, hot],
            ).createShader(played),
    );
  }
}
