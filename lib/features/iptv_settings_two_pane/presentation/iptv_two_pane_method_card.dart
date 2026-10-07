import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class IptvTwoPaneMethodCard extends StatefulWidget {
  const IptvTwoPaneMethodCard({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    required this.onLeft,
    required this.onRight,
    required this.onDown,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLeft;
  final VoidCallback? onRight;
  final VoidCallback onDown;

  @override
  State<IptvTwoPaneMethodCard> createState() => IptvTwoPaneMethodCardState();
}

class IptvTwoPaneMethodCardState extends State<IptvTwoPaneMethodCard> {
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  bool get _focused => widget.focusNode.hasFocus;

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (has) {
        if (mounted) setState(() {});
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            widget.onLeft();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            if (widget.onRight == null) return KeyEventResult.handled;
            widget.onRight!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            widget.onDown();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onTap();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // Same reason as the rail: the whole card is the target.
        behavior: HitTestBehavior.opaque,
        onTap: () {
          widget.focusNode.requestFocus();
          widget.onTap();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: _focused ? t.panel2 : (widget.selected ? t.panel : null),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: _focused
                    ? t.accent
                    : (widget.selected ? t.accent2 : t.line),
                width: 2,
              ),
            ),
            child: Column(
              children: [
                Icon(widget.icon, size: 24, color: t.accent2),
                const SizedBox(height: 9),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  widget.hint,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(fontSize: 11.5, color: t.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
