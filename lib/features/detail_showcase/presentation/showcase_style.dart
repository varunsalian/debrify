import 'package:debrify/features/detail_showcase/presentation/showcase_metrics.dart';
import 'package:debrify/theme/app_theme.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _ink = Color(0xFFFFFFFF);

const sInk = _ink;

/// The fill of a card slot whose art has not arrived, and of the ambient bed
/// behind the bands.
///
/// These were `0xFF17171A` and `0xFF0A0A0B` written out at eight call sites —
/// which meant the detail page was the surface that ignored the Background
/// setting while everything around it followed. Derived now, from the same
/// ground the rest of the app takes.
///
/// A placeholder is deliberately a STEP off the page rather than the page
/// itself: an empty slot has to read as a slot. Pointing it at the ground would
/// make loading cards dissolve into the background instead of holding their
/// place.
Color _slotFill(AppTheme app) => Color.lerp(app.home.bg, app.core.tx, 0.045)!;

const sSlotFill = _slotFill;

/// A contained mark — a channel logo — needs a lighter plate than a poster
/// slot, or a dark logo lands on a dark card.
Color _plateFill(AppTheme app) => Color.lerp(app.home.bg, app.core.tx, 0.10)!;

TextStyle _t(double size, {FontWeight w = FontWeight.w400, double a = 1}) =>
    TextStyle(
      fontSize: size,
      fontWeight: w,
      color: _ink.withValues(alpha: a),
      height: 1.3,
    );

const st = _t;

/// OK/Select/Enter, as a remote sends them.
///
/// `GestureDetector.onTap` never fires for a DPAD, so a focusable built only
/// from a gesture is visible, focusable, and completely inert on a TV.
KeyEventResult _activate(KeyEvent e, VoidCallback? onTap) {
  if (e is! KeyDownEvent || onTap == null) return KeyEventResult.ignored;
  final k = e.logicalKey;
  final isOk =
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.gameButtonA;
  if (!isOk) return KeyEventResult.ignored;
  onTap();
  return KeyEventResult.handled;
}

const sActivate = _activate;

/// Keeps a focused item inside a lazy horizontal rail on screen — **within
/// that rail**, and nowhere else.
///
/// Without it, walking a rail moves focus into cached off-screen children and
/// then stalls at the first node that was never mounted.
///
/// `Scrollable.ensureVisible` walks every ancestor scrollable, so a cell in a
/// horizontal rail also scrolled the page's vertical list. That fights
/// `_reveal`, which is the only thing that knows where a band should park — and
/// with a full-height identity it would drag the hero off screen the moment
/// anything below it took focus. Scrolling the nearest scrollable only keeps
/// horizontal travel horizontal.
void _keepVisible(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached) return;
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null) return;
  // HORIZONTAL only. The identity's action circles have no rail of their own,
  // so the nearest scrollable is the page itself — and centring a button in the
  // page scrolls the full-height hero away the instant one takes focus. Rails
  // want this; the hero does not.
  if (scrollable.position.axis != Axis.horizontal) return;
  scrollable.position.ensureVisible(
    box,
    alignment: 0.5,
    duration: const Duration(milliseconds: 220),
    curve: Curves.easeOutCubic,
  );
}

const sKeepVisible = _keepVisible;

/// Pointer hover for a focusable card, feeding the SAME visual the DPAD
/// cursor gets — the ParallaxFocus lift and any focus plate — so mousing
/// across a rail reads like walking it with a remote.
///
/// Purely visual by design: hover never requests real focus, because focus
/// has side effects here ([_keepVisible]'s rail scroll, the guide band's
/// follow-focus select) and a mouse sweeping across the page must not fire
/// them. Owns its own state so each card only ORs the result in.
class _Hover extends StatefulWidget {
  final Widget Function(BuildContext, bool hovered) builder;

  /// Click for cards a tap activates; basic for the focus-only reading cards
  /// (cast, Did You Know) where a pointer press does nothing.
  final MouseCursor cursor;

  const _Hover({required this.builder, this.cursor = SystemMouseCursors.click});

  @override
  State<_Hover> createState() => _HoverState();
}

typedef SHover = _Hover;
const showcaseHoverConstructor = _Hover.new;

class _HoverState extends State<_Hover> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    // No hover layer on a television. An Apple TV remote's trackpad delivers
    // pointer events (see main.dart), so an ungated MouseRegion parks a
    // second lifted card wherever the thumb last brushed — and every DPAD
    // step's centre-scroll then sweeps cards under that parked pointer,
    // firing lift/drop springs mid-scroll. The Spotlight board's `hoverable`
    // is off on TV for exactly this reason; this is the same gate.
    if (PlatformUtil.isTelevision) return widget.builder(context, false);
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      child: widget.builder(context, _h),
    );
  }
}

// ── shared band chrome ─────────────────────────────────────────────────────

class _Band extends StatelessWidget {
  final String title;
  final double height;
  final Widget child;

  /// A quiet count line after the title ("142 trivia · 9 goofs · 26 quotes").
  final String? subtitle;

  const _Band({
    required this.title,
    required this.height,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final m = ShowcaseMetrics.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: EdgeInsets.only(left: m.gutter, bottom: 10),
          // Compact band titles use the phone heading size; wide keeps the
          // shipped 13pt (the 960-canvas number the TV mock pins), k-scaled
          // back to proportion on wide touch surfaces.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                style: _t(
                  m.compact ? 19 : 13 * m.k,
                  w: FontWeight.w600,
                  a: 0.84,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 9),
                Text(
                  subtitle!,
                  style: _t(
                    m.compact ? 11.5 : 8.5 * m.k,
                    w: FontWeight.w600,
                    a: 0.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: height, child: child),
      ],
    );
  }
}

typedef SBand = _Band;
const showcaseBandConstructor = _Band.new;
