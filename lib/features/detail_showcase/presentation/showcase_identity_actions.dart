import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/features/detail_showcase/presentation/showcase_style.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _Primary extends StatefulWidget {
  final FocusNode node;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onFocused;

  /// Resume state still resolving — spinner instead of the label so the pill
  /// never flashes a wrong status.
  final bool busy;

  const _Primary({
    required this.node,
    required this.label,
    required this.onTap,
    required this.onLongPress,
    required this.onFocused,
    this.busy = false,
  });

  @override
  State<_Primary> createState() => _PrimaryState();
}

typedef SPrimary = _Primary;
const showcasePrimaryConstructor = _Primary.new;

class _PrimaryState extends State<_Primary> {
  bool _f = false;
  late final TvHoldOk _hold;

  @override
  void initState() {
    super.initState();
    _hold = TvHoldOk(
      onTap: () => widget.onTap(),
      onHold: () => widget.onLongPress?.call(),
    );
  }

  @override
  void dispose() {
    _hold.reset();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (widget.onLongPress == null || !isActivateOrSpaceKey(event.logicalKey)) {
      return sActivate(event, widget.onTap);
    }
    return _hold.handle(event);
  }

  void _onPointerLongPress() {
    HapticFeedback.mediumImpact();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    autofocus: true,
    onFocusChange: (v) {
      setState(() => _f = v);
      if (!v) _hold.reset();
      if (v) widget.onFocused();
    },
    // By key IDENTITY, not by keyLabel string — a remote's Select has no
    // label to match and would silently never activate.
    onKeyEvent: (_, e) => _onKey(e),
    child: GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null ? null : _onPointerLongPress,
      child: Builder(
        builder: (context) {
          // TV draws at the mock's 960-canvas numbers (k = 1); a wide touch
          // surface scales them back to proportion, and a phone needs a real
          // finger target and the phone type ramp — the Apple reference
          // pill is 42pt with 15pt text, and SOLID white at rest (there is
          // no focus state to flip through on touch).
          final m = ShowcaseMetrics.of(context);
          final compact = m.compact;
          final solid = _f || compact;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: compact ? 44 : 30 * m.k,
            padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 17 * m.k),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // The focus flip: ghost at rest, SOLID WHITE on black when
              // focused. The reference's primary is the one thing that does
              // not merely lift.
              color: solid ? sInk : sInk.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(compact ? 22 : 15 * m.k),
            ),
            child: widget.busy
                ? SizedBox(
                    width: compact ? 44 : 32 * m.k,
                    child: Center(
                      child: SizedBox(
                        width: compact ? 16 : 11 * m.k,
                        height: compact ? 16 : 11 * m.k,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: solid ? Colors.black : sInk,
                        ),
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: compact ? 20 : 14 * m.k,
                        color: solid ? Colors.black : sInk,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: compact ? 15 : 10.5 * m.k,
                          fontWeight: FontWeight.w600,
                          color: solid ? Colors.black : sInk,
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    ),
  );
}

class _Circle extends StatefulWidget {
  final FocusNode node;
  final IconData? icon;
  final Widget? mark;
  final String label;
  final VoidCallback onTap;

  const _Circle({
    required this.node,
    required IconData this.icon,
    required this.label,
    required this.onTap,
  }) : mark = null;

  const _Circle.mark({
    required this.node,
    required Widget this.mark,
    required this.label,
    required this.onTap,
  }) : icon = null;

  @override
  State<_Circle> createState() => _CircleState();
}

typedef SCircle = _Circle;
const showcaseCircleConstructor = _Circle.new;

const showcaseCircleMarkConstructor = _Circle.mark;

class _CircleState extends State<_Circle> {
  bool _f = false;
  bool _h = false;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: widget.node,
    onFocusChange: (v) {
      setState(() => _f = v);
      if (v) sKeepVisible(context);
    },
    // Without this the tracker, trailer and More buttons focus correctly
    // and do NOTHING on a remote.
    onKeyEvent: (_, e) => sActivate(e, widget.onTap),
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Builder(
          builder: (context) {
            final m = ShowcaseMetrics.of(context);
            final compact = m.compact;
            final d = compact ? 44.0 : 26.0 * m.k;
            // Hover and focus both light the pill: DPAD/keyboard land on
            // `_f`, a desktop pointer on `_h` — same treatment either way.
            final lit = _f || _h;
            final glyph =
                widget.mark ??
                Icon(
                  widget.icon,
                  size: compact ? 20 : 13 * m.k,
                  color: lit ? Colors.black : sInk,
                );
            // Lit (non-compact): the circle stretches into a pill that
            // names itself — the tooltip a DPAD user can actually read.
            // Compact stays a plain circle — touch has no dwell, and a pill
            // popping under a finger would just shove its siblings — so it
            // falls back to the platform's long-press Tooltip below.
            final labelled = lit && !compact;
            final body = AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              height: d,
              decoration: BoxDecoration(
                color: lit ? sInk : sInk.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(d / 2),
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                alignment: Alignment.centerLeft,
                child: labelled
                    ? Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10 * m.k),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            glyph,
                            SizedBox(width: 6 * m.k),
                            Text(
                              widget.label,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 11 * m.k,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SizedBox(
                        width: d,
                        height: d,
                        child: Center(child: glyph),
                      ),
              ),
            );
            if (!compact) return body;
            return Tooltip(
              message: widget.label,
              triggerMode: TooltipTriggerMode.longPress,
              child: body,
            );
          },
        ),
      ),
    ),
  );
}
