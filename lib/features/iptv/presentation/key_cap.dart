import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

class KeyCap extends StatelessWidget {
  final String label;
  const KeyCap(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        borderRadius: app.shape.br(5),
        border: Border.all(color: app.core.tx.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: app.home.focus.withValues(alpha: 0.95),
          fontSize: 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
  }
}
