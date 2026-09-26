import 'package:flutter/material.dart';

import '../../../theme/app_theme_scope.dart';

/// Small pill next to a catalog-row header marking it as Movies / Series / etc.
/// An optional leading [icon] lets a pill carry meaning beyond the label (e.g.
/// a star on the Debrify TV "Favorites" pill).
class CategoryTag extends StatelessWidget {
  final String label;
  final IconData? icon;
  const CategoryTag(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: app.fade(app.home.chromeAccent, 0.16),
        borderRadius: app.shape.br(8),
        border: Border.all(color: app.fade(app.home.chromeAccent, 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: const Color(0xFFB9A9FF)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB9A9FF),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
