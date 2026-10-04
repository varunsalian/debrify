import 'package:debrify/features/addon_hub/presentation/addon_hub_focus_card.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/see_all/see_all_theme.dart';
import 'package:flutter/material.dart';

/// A themed torrent-engine row (imported or available). Whole card is the tap
/// target — matching the classic engine screen — with a trailing action pill.
class AddonHubEngineRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final bool primary;
  final bool danger;
  final FocusNode? focusNode;
  final VoidCallback onTap;
  const AddonHubEngineRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
    this.primary = false,
    this.danger = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return AddonHubFocusCard(
      onTap: onTap,
      focusNode: focusNode,
      builder: (focused) => Container(
        decoration: addonHubCardDecoration(focused),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, color: kSeeAllAccent2, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            AddonHubEngineActionPill(
              label: actionLabel,
              primary: primary,
              danger: danger,
            ),
          ],
        ),
      ),
    );
  }
}

/// A non-focusable label pill inside an engine row (the whole row is the button;
/// this just states the action). Install = accent, Remove = danger outline.
class AddonHubEngineActionPill extends StatelessWidget {
  final String label;
  final bool primary;
  final bool danger;
  const AddonHubEngineActionPill({
    required this.label,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final Color fill;
    final Color border;
    final Color text;
    if (danger) {
      fill = Colors.transparent;
      border = const Color(0xFFEF4444).withValues(alpha: 0.5);
      text = const Color(0xFFEF4444);
    } else if (primary) {
      fill = app.seeAll.accent;
      border = Colors.transparent;
      text = app.inkOn(app.seeAll.accent);
    } else {
      fill = Colors.transparent;
      border = Colors.white.withValues(alpha: 0.22);
      text = Colors.white;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: app.shape.br(24),
        border: Border.all(width: 2, color: border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
