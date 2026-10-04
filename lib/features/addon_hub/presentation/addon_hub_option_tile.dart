import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddonHubOptionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool autofocus;
  const AddonHubOptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.autofocus = false,
  });

  @override
  State<AddonHubOptionTile> createState() => _OptionTileState();
}

class _OptionTileState extends State<AddonHubOptionTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final color = widget.danger ? const Color(0xFFEF4444) : app.core.tx;
    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: _focused
                ? app.fade(app.seeAll.accent, 0.14)
                : Colors.transparent,
            borderRadius: app.shape.br(11),
            border: Border.all(
              color: _focused ? app.seeAll.accent : Colors.transparent,
              width: _focused ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: color),
              const SizedBox(width: 14),
              Text(
                widget.label,
                style: TextStyle(
                  color: color,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
