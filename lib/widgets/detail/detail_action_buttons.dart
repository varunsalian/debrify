// Extracted verbatim from lib/screens/merged_series_detail_screen.dart
// (that screen's private presentational tail). Behaviour is unchanged; the
// only edits are the renames that make these public and the parameters that
// replace the host's private members.

import 'package:flutter/material.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';
import 'detail_focus_chrome.dart';
import 'theme/detail_theme.dart';

class DetailPrimaryButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Resume state still resolving — spinner instead of the label so the pill
  /// never flashes a wrong status. Stays tappable (plays from the top).
  final bool busy;

  /// Per-title accent used for the soft glow behind the white pill, so the
  /// primary CTA reads as belonging to this title.
  final Color glow;

  const DetailPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.busy = false,
    this.glow = kDetailGold,
  });

  @override
  State<DetailPrimaryButton> createState() => _DetailPrimaryButtonState();
}

class _DetailPrimaryButtonState extends State<DetailPrimaryButton> {
  bool _focused = false;
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
      return KeyEventResult.ignored;
    }
    return _hold.handle(event);
  }

  @override
  Widget build(BuildContext context) {
    final button = AnimatedScale(
      // Snap on TV: every frame of the scale pop re-rasters the pill AND its
      // blur-18 glow shadow; instant scale keeps the glow a one-time paint.
      duration: PlatformUtil.isTelevision
          ? Duration.zero
          : const Duration(milliseconds: 140),
      scale: _focused ? 1.05 : 1.0,
      child: DetailFocusHalo(
        focused: _focused,
        radius: BorderRadius.circular(999),
        // Soft accent glow behind the pill. A static drop shadow (rasterised
        // once, carried by the AnimatedScale transform) — not a per-frame
        // backdrop blur — so it's safe on the weak TV GPU. Animates its color
        // to the title accent when it resolves.
        child: TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 500),
          tween: ColorTween(end: widget.glow.withValues(alpha: 0.45)),
          builder: (_, color, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: color ?? Colors.transparent,
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: child,
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              onFocusChange: (f) {
                setState(() => _focused = f);
                if (!f) _hold.reset();
              },
              borderRadius: BorderRadius.circular(999),
              onTap: widget.onTap,
              // InkWell supplies the platform long-press feedback itself.
              onLongPress: widget.onLongPress,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 11,
                ),
                child: widget.busy
                    ? const SizedBox(
                        width: 48,
                        height: 20,
                        child: Center(
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0D0D10),
                            ),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.icon,
                            color: const Color(0xFF0D0D10),
                            size: 20,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Color(0xFF0D0D10),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.onLongPress == null) return button;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => _onKey(event),
      child: button,
    );
  }
}

/// Subtle "trailer playing in background" hint pill. An informational hint, not
/// a primary control (the focusable "Watch Trailer" button is the DPAD way to
/// promote), so it's pointer/touch-tappable only — `canRequestFocus: false`
/// keeps it out of DPAD traversal entirely, so it can never steal focus or
/// strand the remote when it appears/disappears as the trailer plays/pauses.
class DetailTrailerPlayingChip extends StatelessWidget {
  final VoidCallback onTap;

  /// Null for Classic.
  final DetailTheme? theme;

  const DetailTrailerPlayingChip({super.key, required this.onTap, this.theme});

  @override
  Widget build(BuildContext context) {
    final t = theme;
    final radius = t?.brBtn ?? BorderRadius.circular(999);
    return Material(
      color:
          t?.ground.withValues(alpha: 0.6) ??
          Colors.black.withValues(alpha: 0.42),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        canRequestFocus: false,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: t?.hair ?? Colors.white.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 14,
                color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 7),
              Text(
                'Trailer playing',
                style: TextStyle(
                  color: t?.tx ?? Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DetailGhostButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  /// Shows a small spinner in place of the icon (e.g. trailer resolving).
  final bool busy;

  const DetailGhostButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  State<DetailGhostButton> createState() => _DetailGhostButtonState();
}

class _DetailGhostButtonState extends State<DetailGhostButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return DetailFocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

class DetailSourcePill extends StatefulWidget {
  final int count;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  const DetailSourcePill({
    super.key,
    required this.count,
    required this.onTap,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  State<DetailSourcePill> createState() => _DetailSourcePillState();
}

class _DetailSourcePillState extends State<DetailSourcePill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final bound = widget.count > 0;
    const gold = kDetailGold;
    final label = bound
        ? (widget.count > 1 ? '${widget.count} sources' : '1 source')
        : 'Bind source';
    return DetailFocusHalo(
      focused: _focused,
      radius: BorderRadius.circular(999),
      child: Material(
        color: bound
            ? gold.withValues(alpha: 0.13)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(999),
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: bound
                    ? gold.withValues(alpha: 0.30)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  bound ? Icons.link_rounded : Icons.link_off_rounded,
                  color: bound ? gold : Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    color: bound ? gold : Colors.white70,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

/// A tracker's identity in the action row: its brand mark, its name, and the
/// live relationship it holds to this title, in one control that opens that
/// tracker's sheet.
///
/// This replaces the pair of anonymous round icon buttons *and* the status
/// chip rows under the title — the chips rendered exactly the state these
/// pills now carry, so the hero showed every fact twice.
///
/// [tracked] drives the two forms: brand-tinted when the tracker holds the
/// title, plain outline when it doesn't (and while the status loads, so the
/// row keeps its geometry).
class DetailTrackerPill extends StatefulWidget {
  final Widget mark;

  /// Short brand name, drawn as the pill's uppercase eyebrow.
  final String brand;

  /// The live state line — "Watchlist · Collected", "Watching", "Not tracked".
  final String state;

  /// 1–10 tracker rating, shown in its own compartment when set.
  final int? rating;

  /// The tracker's brand colour, used for the tint, border and rating.
  final Color accent;
  final bool tracked;
  final String tooltip;
  final VoidCallback onTap;

  const DetailTrackerPill({
    super.key,
    required this.mark,
    required this.brand,
    required this.state,
    required this.rating,
    required this.accent,
    required this.tracked,
    required this.tooltip,
    required this.onTap,
  });

  @override
  State<DetailTrackerPill> createState() => _DetailTrackerPillState();
}

class _DetailTrackerPillState extends State<DetailTrackerPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    final tracked = widget.tracked;
    final radius = BorderRadius.circular(999);
    final pill = DetailFocusHalo(
      focused: _focused,
      radius: radius,
      child: Material(
        color: tracked
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 8, 15, 8),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: tracked
                    ? accent.withValues(alpha: 0.42)
                    : Colors.white.withValues(alpha: 0.14),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.mark,
                const SizedBox(width: 9),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.brand,
                      style: TextStyle(
                        color: tracked
                            ? accent
                            : Colors.white.withValues(alpha: 0.5),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.3,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.state,
                      style: TextStyle(
                        color: tracked
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                  ],
                ),
                if (widget.rating != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    height: 20,
                    width: 1,
                    color: accent.withValues(alpha: 0.45),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${widget.rating}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(message: widget.tooltip, child: pill);
  }
}

/// Circular translucent icon button used for the hero "More" (⋮) affordance.
class DetailRoundIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  final FocusNode? focusNode;

  /// Null for Classic, which keeps its circle and its gold ring exactly.
  final DetailTheme? theme;

  const DetailRoundIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
    this.focusNode,
    this.theme,
  });

  @override
  State<DetailRoundIconButton> createState() => _DetailRoundIconButtonState();
}

class _DetailRoundIconButtonState extends State<DetailRoundIconButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.theme;
    final circular = t == null || t.radiusBtn >= 999;
    final side = BorderSide(
      color: t?.ghostBorder ?? Colors.white.withValues(alpha: 0.16),
    );
    final shape = circular
        ? CircleBorder(side: side)
        : RoundedRectangleBorder(borderRadius: t.brBtn, side: side);
    final btn = DetailFocusHalo(
      focused: _focused,
      radius: circular ? null : t.brBtn,
      ringColor: t?.focus,
      child: Material(
        color: widget.background ?? Colors.white.withValues(alpha: 0.08),
        shape: shape,
        child: InkWell(
          customBorder: shape,
          focusNode: widget.focusNode,
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(widget.icon, color: t?.tx ?? Colors.white, size: 22),
          ),
        ),
      ),
    );
    return widget.tooltip == null
        ? btn
        : Tooltip(message: widget.tooltip!, child: btn);
  }
}
