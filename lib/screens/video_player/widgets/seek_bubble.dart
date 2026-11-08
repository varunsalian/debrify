import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// The time under the pointer, in a small pill above the seek bar.
///
/// Shown while a pointer hovers the bar (desktop) and, following the thumb,
/// while the bar is held down (any input). The pill is the only feedback a
/// drag gets before the player has seeked, so it answers at once.
class SeekBubble extends StatefulWidget {
  const SeekBubble({
    super.key,
    required this.duration,
    required this.progress,
    required this.inset,
    required this.format,
    required this.fill,
    required this.ink,
    required this.fontSize,
    required this.child,
  });

  final Duration duration;

  /// The thumb's position, 0..1; the bubble follows it while held.
  final double progress;

  /// Horizontal room the slider keeps for its thumb at either end: the
  /// track runs from [inset] to width - [inset].
  final double inset;
  final String Function(Duration) format;
  final Color fill;
  final Color ink;
  final double fontSize;
  final Widget child;

  @override
  State<SeekBubble> createState() => _SeekBubbleState();
}

class _SeekBubbleState extends State<SeekBubble> {
  /// The pointer's x in visual space, from hover or, for a mouse, from the
  /// moves of a drag (a held button sends no hover events).
  double? _hover;
  int? _heldPointer;

  double _visual(double dx, double width) {
    final travel = width - 2 * widget.inset;
    if (travel <= 0) return 0;
    return ((dx - widget.inset) / travel).clamp(0.0, 1.0);
  }

  void _down(PointerDownEvent e) {
    if (_heldPointer != null || !mounted) return;
    setState(() => _heldPointer = e.pointer);
  }

  void _move(PointerMoveEvent e) {
    if (e.kind == PointerDeviceKind.mouse) _hover = e.localPosition.dx;
  }

  void _release(PointerEvent e) {
    if (e.pointer != _heldPointer || !mounted) return;
    // A mouse let go outside the bar is not hovering it either.
    final size = context.size;
    final inside =
        e.kind == PointerDeviceKind.mouse &&
        size != null &&
        (Offset.zero & size).contains(e.localPosition);
    setState(() {
      _heldPointer = null;
      if (!inside) _hover = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // Visual fraction along the bar (left to right) and the time it
        // names; an RTL bar runs the other way.
        double? visual;
        double? time;
        if (_heldPointer != null) {
          time = widget.progress;
          visual = rtl ? 1 - time : time;
        } else if (_hover != null) {
          visual = _visual(_hover!, width);
          time = rtl ? 1 - visual : visual;
        }
        return MouseRegion(
          onHover: (e) => setState(() => _hover = e.localPosition.dx),
          onExit: (_) => setState(() => _hover = null),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _down,
            onPointerMove: _move,
            onPointerUp: _release,
            onPointerCancel: _release,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child,
                if (visual != null &&
                    time != null &&
                    widget.duration > Duration.zero)
                  // Laid out above the bar at its own size, centred on the
                  // point and kept within the bar's width, so the row keeps
                  // the slider's height whatever bounds it has.
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 0,
                    child: CustomSingleChildLayout(
                      delegate: _PillLayout(
                        widget.inset + visual * (width - 2 * widget.inset),
                      ),
                      child: _Pill(
                        text: widget.format(widget.duration * time),
                        fill: widget.fill,
                        ink: widget.ink,
                        fontSize: widget.fontSize,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Puts the pill above the bar, centred on [centre] and clamped to the bar's
/// width; the pill's real laid-out size is used, so any font or text scale
/// stays inside.
class _PillLayout extends SingleChildLayoutDelegate {
  const _PillLayout(this.centre);
  final double centre;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final left = (centre - childSize.width / 2).clamp(
      0.0,
      (size.width - childSize.width).clamp(0.0, double.infinity),
    );
    return Offset(left, -childSize.height);
  }

  @override
  bool shouldRelayout(_PillLayout oldDelegate) => oldDelegate.centre != centre;
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.fill,
    required this.ink,
    required this.fontSize,
  });
  final String text;
  final Color fill;
  final Color ink;
  final double fontSize;

  static const padding = 8.0;

  @override
  Widget build(BuildContext context) {
    // The slider already announces its value; a pill that appears and moves
    // at hover rate would only churn the semantics tree.
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: padding, vertical: 4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            text,
            style: TextStyle(
              color: ink,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}
