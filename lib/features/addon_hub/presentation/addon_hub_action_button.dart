import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Buttons & dialog chrome ──────────────────────────────────────────────────
/// A pill button that matches the Discover chrome: panel fill, purple focus ring;
/// [primary] fills with the accent tint.
class AddonHubHubActionButton extends StatefulWidget {
  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool primary;
  final FocusNode? focusNode;

  /// Fill the parent's width with centred content (narrow filter bar rows)
  /// instead of hugging the icon+label.
  final bool expand;

  const AddonHubHubActionButton({
    required this.icon,
    required this.onTap,
    this.label,
    this.primary = false,
    this.focusNode,
    this.expand = false,
  });

  @override
  State<AddonHubHubActionButton> createState() => _HubActionButtonState();
}

class _HubActionButtonState extends State<AddonHubHubActionButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    // Primary = solid accent (like Stremio's filled "Add addon"); others sit on
    // the quiet panel fill. Border is a constant 2px — width changes feed into
    // Container's layout and shake the whole filter row on focus moves.
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color borderColor;
    // Primary's label/ring sit ON the accent fill; the quiet variant's sit on
    // the panel fill, which is page ink's ground.
    final Color ink;
    if (widget.primary) {
      fill = _focused ? app.seeAll.accent2 : app.seeAll.accent;
      ink = app.inkOn(app.seeAll.accent);
      borderColor = _focused ? ink : Colors.transparent;
    } else {
      fill = app.seeAll.panel;
      borderColor = _focused ? app.seeAll.accent : app.seeAll.line;
      ink = app.core.tx;
    }
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && isActivateKey(event.logicalKey)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.label == null ? 10 : 16,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: app.shape.br(11),
              border: Border.all(width: 2, color: borderColor),
            ),
            child: Row(
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 17, color: ink),
                if (widget.label != null) ...[
                  const SizedBox(width: 7),
                  Text(
                    widget.label!,
                    style: TextStyle(
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
