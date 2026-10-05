import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _SpotlightChoiceChip extends StatefulWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;
  final IconData? trailingIcon;

  const _SpotlightChoiceChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onPressed,
    this.trailingIcon,
  });

  @override
  State<_SpotlightChoiceChip> createState() => _SpotlightChoiceChipState();
}

class _SpotlightChoiceChipState extends State<_SpotlightChoiceChip> {
  bool _focused = false;
  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final focused = _focused && widget.enabled;
    final fill = focused
        ? app.core.tx
        : widget.selected
        ? tv.accent
        : tv.fillWeak;
    final ink = focused
        ? app.inkOn(app.core.tx)
        : widget.selected
        ? app.inkOn(tv.accent)
        : tv.textDim;
    return Focus(
      canRequestFocus: widget.enabled,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.arrowUp) {
            node.previousFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.arrowDown) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent && isActivateOrSpaceKey(key)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: true,
        selected: widget.selected,
        enabled: widget.enabled,
        label: widget.label,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: focused
                ? (Matrix4.identity()..translateByDouble(0, -2, 0, 1))
                : Matrix4.identity(),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: widget.enabled ? fill : tv.fillWeak.withValues(alpha: .3),
              borderRadius: app.shape.br(99),
              border: Border.all(
                color: focused
                    ? app.core.tx
                    : widget.selected
                    ? tv.accent
                    : tv.hairline,
              ),
              boxShadow: focused
                  ? const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 9),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.enabled ? ink : tv.textFaint,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 7),
                  Icon(widget.trailingIcon, size: 14, color: ink),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

typedef DebrifyTvChoiceChip = _SpotlightChoiceChip;
Widget debrifyTvChoiceChip({
  required String label,
  required bool selected,
  required bool enabled,
  required VoidCallback onPressed,
  IconData? trailingIcon,
}) => DebrifyTvChoiceChip(
  label: label,
  selected: selected,
  enabled: enabled,
  onPressed: onPressed,
  trailingIcon: trailingIcon,
);
