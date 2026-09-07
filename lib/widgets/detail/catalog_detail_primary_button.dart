/// The filled / outlined action button used by [CatalogDetailActionRow].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/tv_keys.dart';
import 'theme/detail_theme.dart';

class CatalogDetailPrimaryButton extends StatefulWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;

  /// Filled buttons get a solid background ([accent] when provided, white
  /// otherwise). Outlined buttons have a glass background.
  final bool filled;
  final bool tinted;

  /// Narrow screens: shorter button, smaller icon/text, tighter spacing.
  final bool compact;

  /// TV: skip the focus tween (instant), keep the highlight.
  final bool tv;

  /// Optional brand accent for a filled button. Falls back to white.
  final Color? accent;

  /// Ink for the label ON [accent], scored by the caller.
  ///
  /// Null keeps the shipped rule (`accent == null ? black : white`), which is
  /// right for legacy's fixed red and wrong for an arbitrary poster colour —
  /// white on a pale artwork accent is unreadable.
  final Color? accentInk;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// D-pad "up" handler (TV). Set on the top action row so "up" reveals the
  /// header rather than dead-ending focus traversal.
  final VoidCallback? onArrowUp;

  /// Resume state still resolving — spinner instead of icon+label so the
  /// button never flashes a wrong status. Stays tappable.
  final bool busy;

  const CatalogDetailPrimaryButton({
    super.key,
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
    this.onLongPress,
    this.busy = false,
    this.compact = false,
    this.tv = false,
    this.tinted = false,
    this.accent,
    this.accentInk,
    this.onArrowUp,
  });

  @override
  State<CatalogDetailPrimaryButton> createState() =>
      _CatalogDetailPrimaryButtonState();
}

class _CatalogDetailPrimaryButtonState
    extends State<CatalogDetailPrimaryButton> {
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

  void _onPointerLongPress() {
    HapticFeedback.mediumImpact();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final accent = widget.accent;
    final t = DetailThemeScope.maybeOf(context);

    final filledBg = accent ?? Colors.white;
    final filledFg =
        widget.accentInk ?? (accent == null ? Colors.black : Colors.white);

    final bg = filled
        ? (_focused ? Color.lerp(filledBg, Colors.white, 0.12)! : filledBg)
        : (_focused
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.06));

    final fg = filled ? filledFg : Colors.white;

    // Focus is always shown as a bright gold ring + glow (+ a slight
    // scale-up) regardless of the button's base colour, so it's obvious
    // even on the red Play button.
    final Color borderColor;
    if (_focused) {
      borderColor = t.focus;
    } else if (filled) {
      borderColor = Colors.transparent;
    } else if (widget.tinted) {
      // A bound source: hint with a soft gold resting border.
      borderColor = t.fade(t.focus, 0.5);
    } else {
      borderColor = Colors.white.withValues(alpha: 0.18);
    }
    final borderWidth = _focused ? 2.5 : (filled ? 0.0 : 1.2);

    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) {
        setState(() => _focused = f);
        if (!f) _hold.reset();
      },
      onKeyEvent: (node, event) {
        if (widget.onLongPress != null &&
            isActivateOrSpaceKey(event.logicalKey)) {
          return _hold.handle(event);
        }
        if (event is KeyDownEvent) {
          if (isActivateKey(event.logicalKey) ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // Nothing focusable sits above this row, so consume "up" and use
          // it to bring the header back into view instead of no-op.
          if (widget.onArrowUp != null &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            widget.onArrowUp!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress == null ? null : _onPointerLongPress,
        child: AnimatedScale(
          duration: widget.tv
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          scale: _focused ? 1.035 : 1.0,
          child: AnimatedContainer(
            duration: widget.tv
                ? Duration.zero
                : const Duration(milliseconds: 160),
            height: widget.compact ? 48 : 54,
            padding: EdgeInsets.symmetric(horizontal: widget.compact ? 10 : 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: t.fade(t.focus, 0.55),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: widget.busy
                ? SizedBox(
                    width: widget.compact ? 52 : 64,
                    child: Center(
                      child: SizedBox(
                        width: widget.compact ? 16 : 18,
                        height: widget.compact ? 16 : 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: fg,
                        ),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.icon,
                        color: fg,
                        size: widget.compact ? 20 : 24,
                      ),
                      SizedBox(width: widget.compact ? 7 : 10),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: fg,
                            fontSize: widget.compact ? 14 : 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
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
