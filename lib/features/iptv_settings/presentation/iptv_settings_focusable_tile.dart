import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

/// Plain focusable action row for the Lists section header actions.
class IptvSettingsFocusableTile extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const IptvSettingsFocusableTile({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppThemeScope.of(context).settings;
    return ListTile(
      focusNode: focusNode,
      leading: Icon(icon, color: t.accent),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onTap: onTap,
    );
  }
}
