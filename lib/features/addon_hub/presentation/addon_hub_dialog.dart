import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A dark-glass dialog matching the hub theme (AlertDialog styling gets awkward
/// against the purple palette, so we roll a minimal one).
class AddonHubHubDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final List<Widget> actions;
  const AddonHubHubDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Dialog(
      backgroundColor: app.seeAll.panel,
      shape: RoundedRectangleBorder(
        borderRadius: app.shape.br(18),
        side: BorderSide(color: app.seeAll.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            content,
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                for (final a in actions) ...[a, const SizedBox(width: 8)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AddonHubHubDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool primary;
  final bool danger;
  const AddonHubHubDialogButton({
    required this.label,
    required this.onTap,
    this.primary = false,
    this.danger = false,
  });

  @override
  State<AddonHubHubDialogButton> createState() => _HubDialogButtonState();
}

class _HubDialogButtonState extends State<AddonHubHubDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    Color fill;
    Color textColor;
    if (widget.danger) {
      fill = const Color(0xFFEF4444).withValues(alpha: 0.16);
      textColor = const Color(0xFFEF4444);
    } else if (widget.primary) {
      fill = app.fade(app.seeAll.accent, 0.20);
      textColor = app.core.tx;
    } else {
      fill = Colors.transparent;
      textColor = app.fade(app.core.tx, 0.75);
    }
    final borderColor = _focused
        ? app.seeAll.accent
        : (widget.primary || widget.danger
              ? app.seeAll.accentBorder
              : app.seeAll.line);
    return Focus(
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: app.shape.br(10),
            // Constant width — see _HubActionButton (focus resize = shake).
            border: Border.all(
              width: 2,
              color: widget.danger && !_focused
                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                  : borderColor,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
