import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

/// More engines are in flight; existing rows remain usable beneath the strip.
class SourceSearchProgress extends StatelessWidget {
  const SourceSearchProgress({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Row(
        children: [
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Still searching sources…',
            style: TextStyle(
              fontSize: 11.5,
              color: app.fade(app.core.tx, 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty or failed result message. The view supplies its existing message/color.
class SourceStatusMessage extends StatelessWidget {
  const SourceStatusMessage({
    super.key,
    required this.text,
    required this.color,
  });

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color),
      ),
    ),
  );
}
