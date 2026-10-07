import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One action row in the pane. LEFT hands focus back to the rail; everything
/// else is ordinary vertical traversal.
class IptvTwoPaneRow extends StatefulWidget {
  const IptvTwoPaneRow({
    required this.focusNode,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    required this.onLeft,
    this.danger = false,
    this.isLast = false,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback onLeft;
  final bool danger;
  final bool isLast;

  @override
  State<IptvTwoPaneRow> createState() => IptvTwoPaneRowState();
}

class IptvTwoPaneRowState extends State<IptvTwoPaneRow> {
  /// Live, never cached — a remembered flag survives the focus change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `settings/widgets/settings_widgets.dart`.
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());
  bool get _focused => _focusNode.hasFocus;

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    final tint = widget.danger ? t.danger : t.accent2;
    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.onTap != null,
      descendantsAreFocusable: false,
      onFocusChange: (has) {
        if (!mounted) return;
        setState(() {});
        if (has) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: Duration.zero,
          );
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        switch (event.logicalKey) {
          case LogicalKeyboardKey.arrowLeft:
            widget.onLeft();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.space:
            widget.onTap?.call();
            return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        // Same reason as the rail: the row's padding must be clickable.
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null
            ? null
            : () {
                widget.focusNode?.requestFocus();
                widget.onTap!();
              },
        child: MouseRegion(
          cursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: _focused ? t.panel2 : null,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? t.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: tint),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: widget.danger ? t.danger : null,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: TextStyle(fontSize: 12, color: t.dim),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 12),
                  // The row is the single target for both DPAD and pointer:
                  // a Switch/Radio here would otherwise take the tap itself
                  // and fire the action a second time.
                  IgnorePointer(child: widget.trailing!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
