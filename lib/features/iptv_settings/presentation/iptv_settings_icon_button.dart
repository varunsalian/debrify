import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Focusable icon button for TV navigation
class IptvSettingsIconButton extends StatefulWidget {
  const IptvSettingsIconButton({
    this.focusNode,
    required this.icon,
    this.color,
    this.tooltip,
    this.isBusy = false,
    required this.onPressed,
    this.onLeftArrow,
    this.onRightArrow,
  });

  final FocusNode? focusNode;
  final IconData icon;
  final Color? color;
  final String? tooltip;
  final bool isBusy;
  final VoidCallback? onPressed;
  final VoidCallback? onLeftArrow;
  final VoidCallback? onRightArrow;

  @override
  State<IptvSettingsIconButton> createState() => _FocusableIconButtonState();
}

class _FocusableIconButtonState extends State<IptvSettingsIconButton> {
  /// Live, never cached — Flutter can skip the falling edge of a focus
  /// notification, and a remembered flag then survives the change it
  /// missed. See the note on `_SettingsTileState._focused` in
  /// `widgets/settings_widgets.dart`.
  bool get _isFocused => widget.focusNode?.hasFocus ?? false;

  @override
  void initState() {
    super.initState();
    widget.focusNode?.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant IptvSettingsIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_onFocusChange);
      widget.focusNode?.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode?.removeListener(_onFocusChange);
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
          if (!widget.isBusy) widget.onPressed?.call();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
            widget.onLeftArrow != null) {
          widget.onLeftArrow!();
          return KeyEventResult.handled;
        }

        if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
            widget.onRightArrow != null) {
          widget.onRightArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — TV GPU rule.
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: _isFocused ? Border.all(color: t.accent, width: 2) : null,
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: t.accent.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        // One DPAD stop per control — see _TvFocusableButton's ExcludeFocus.
        child: ExcludeFocus(
          child: IconButton(
            icon: widget.isBusy
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _isFocused ? t.accent2 : widget.color,
                    ),
                  )
                : Icon(
                    widget.icon,
                    color: _isFocused ? t.accent2 : widget.color,
                  ),
            tooltip: widget.tooltip,
            onPressed: widget.isBusy ? null : widget.onPressed,
            style: IconButton.styleFrom(
              backgroundColor: _isFocused
                  ? t.accent.withValues(alpha: 0.16)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
