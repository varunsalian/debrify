import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-focusable button with icon and label
class IptvSettingsTvButton extends StatefulWidget {
  const IptvSettingsTvButton({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.onUpArrow,
    this.onDownArrow,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final VoidCallback? onUpArrow;
  final VoidCallback? onDownArrow;

  @override
  State<IptvSettingsTvButton> createState() => _TvFocusableButtonState();
}

class _TvFocusableButtonState extends State<IptvSettingsTvButton> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get _isFocused => widget.focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant IptvSettingsTvButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        if (isActivateKey(event.logicalKey)) {
          widget.onPressed();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
            widget.onUpArrow != null) {
          widget.onUpArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — animated focus decorations jank weak TV GPUs.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: _isFocused ? Border.all(color: t.accent2, width: 2) : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control: the outer Focus owns DPAD (OK is handled
        // above). Without this the inner Material button is a SECOND,
        // invisible traversal stop — an arrow press moves focus "into" the
        // button and the custom ring vanishes for a beat.
        child: ExcludeFocus(
          child: FilledButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon),
            label: Text(widget.label),
            style: FilledButton.styleFrom(
              backgroundColor: _isFocused ? t.accent2 : null,
            ),
          ),
        ),
      ),
    );
  }
}
