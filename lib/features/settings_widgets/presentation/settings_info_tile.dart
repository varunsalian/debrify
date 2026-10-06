import 'package:debrify/features/settings_widgets/presentation/settings_rows.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Non-interactive key/value row (e.g. Version).
class SettingsInfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const SettingsInfoTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  factory SettingsInfoTile.spec(
    SettingsRowContent content, {
    Key? key,
    required String value,
  }) {
    return SettingsInfoTile(
      key: key,
      icon: content.icon,
      title: content.title,
      value: value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    final t = app.settings;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          SizedBox(width: 34, child: Icon(icon, color: t.dim, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              // No color: inherits onSurface (Text Brightness).
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: app.fade(app.core.tx, 0.05),
              borderRadius: app.shape.br(8),
              border: Border.all(color: t.line),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
