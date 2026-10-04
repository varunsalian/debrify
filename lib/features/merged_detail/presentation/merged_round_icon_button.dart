import 'package:debrify/features/merged_detail/presentation/merged_focus_halo.dart';
import 'package:debrify/widgets/detail/theme/detail_theme.dart';
import 'package:flutter/material.dart';

/// Circular translucent icon button used for the hero "More" (⋮) affordance.
class _RoundIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final Color? background;
  final FocusNode? focusNode;

  /// Null for Classic, which keeps its circle and its gold ring exactly.
  final DetailTheme? theme;

  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.background,
    this.focusNode,
    this.theme,
  });

  @override
  State<_RoundIconButton> createState() => _RoundIconButtonState();
}

class _RoundIconButtonState extends State<_RoundIconButton> {
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
    final btn = MergedFocusHalo(
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

typedef MergedRoundIconButton = _RoundIconButton;

const mergedRoundIconButtonConstructor = _RoundIconButton.new;
