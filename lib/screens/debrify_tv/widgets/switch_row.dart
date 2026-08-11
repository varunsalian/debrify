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
    final tv = AppThemeScope.of(context).debrifyTv;
    return Focus(
      onFocusChange: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onKeyEvent: (node, event) {
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
          color: _isFocused ? tv.cardFocusBg : tv.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isFocused ? tv.focusRing : tv.hairline,
            width: _isFocused ? 2 : 1,
          ),
          boxShadow: _isFocused
              ? [
                  BoxShadow(
                    color: tv.fillStrong,
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: SwitchListTile(
          title: Text(
            widget.title,
          ),
          subtitle: Text(
            widget.subtitle,
            style: TextStyle(color: tv.textDim),
          ),
          value: widget.value,
          onChanged: widget.onChanged,
          activeColor: tv.accent,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 0,
          ),
        ),
      ),
    );
  }
}
