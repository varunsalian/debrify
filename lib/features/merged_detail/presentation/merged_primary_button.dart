import 'package:debrify/features/merged_detail/presentation/merged_detail_palette.dart';
import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';

class _PrimaryButton extends StatefulWidget {
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

  const _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.focusNode,
    this.autofocus = false,
    this.busy = false,
    this.glow = MergedDetailPalette.gold,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
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
      child: MergedFocusHalo(
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

typedef MergedPrimaryButton = _PrimaryButton;

const mergedPrimaryButtonConstructor = _PrimaryButton.new;
