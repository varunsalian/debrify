import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../theme/app_theme_scope.dart';
import '../../../utils/platform_util.dart';
import '../../../utils/tv_keys.dart';

/// A switch row widget with Android TV focus support.
///
/// Displays a switch with title and subtitle, supporting D-pad navigation
/// and activation via select/enter/space keys.
class SwitchRow extends StatefulWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SwitchRow> createState() => _SwitchRowState();
}

class _SwitchRowState extends State<SwitchRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final tv = app.debrifyTv;
    final background = _isFocused ? app.core.tx : tv.fillWeak;
    final ink = _isFocused ? app.inkOn(app.core.tx) : app.core.tx;
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowUp ||
              key == LogicalKeyboardKey.arrowLeft) {
            node.previousFocus();
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowRight) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
        }
        if (event is KeyDownEvent) {
          if (isActivateKey(event.logicalKey) ||
              event.logicalKey == LogicalKeyboardKey.space) {
            widget.onChanged(!widget.value);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        // TV: snap — see TvFocusableCard.
        duration: PlatformUtil.isTelevision
            ? Duration.zero
            : const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _isFocused ? app.core.tx : tv.hairline),
          boxShadow: _isFocused
              ? const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ]
              : null,
        ),
        child: SwitchListTile(
          title: Text(
            widget.title,
            style: TextStyle(color: ink, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            widget.subtitle,
            style: TextStyle(
              color: _isFocused ? ink.withValues(alpha: .55) : tv.textDim,
            ),
          ),
          value: widget.value,
          onChanged: widget.onChanged,
          activeThumbColor: _isFocused ? app.inkOn(app.core.tx) : tv.accent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      ),
    );
  }
}
