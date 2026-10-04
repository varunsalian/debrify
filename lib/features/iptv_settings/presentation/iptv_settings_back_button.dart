import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV-focusable back button for AppBar
class IptvSettingsBackButton extends StatefulWidget {
  const IptvSettingsBackButton({required this.focusNode, this.onDownArrow});

  final FocusNode focusNode;
  final VoidCallback? onDownArrow;

  @override
  State<IptvSettingsBackButton> createState() => _TvFocusableBackButtonState();
}

class _TvFocusableBackButtonState extends State<IptvSettingsBackButton> {
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
  void didUpdateWidget(covariant IptvSettingsBackButton oldWidget) {
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

  void _goBack() {
    if (mounted) {
      // maybePop, not pop: the page's PopScope turns a sub-view back press
      // into "return to the hub" — a direct pop would bypass it and close
      // the whole page from anywhere.
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // Select/Enter to go back
        if (isActivateKey(event.logicalKey)) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Back button to go back
        if (event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.browserBack ||
            event.logicalKey == LogicalKeyboardKey.escape) {
          _goBack();
          return KeyEventResult.handled;
        }

        // Down arrow to go to name field
        if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
            widget.onDownArrow != null) {
          widget.onDownArrow!();
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      // Snap, don't tween — TV GPU rule.
      child: Container(
        margin: const EdgeInsets.all(4),
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
            icon: Icon(Icons.arrow_back, color: _isFocused ? t.accent2 : null),
            tooltip: 'Go back',
            onPressed: _goBack,
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
