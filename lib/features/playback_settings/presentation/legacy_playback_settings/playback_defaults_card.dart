import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaybackDefaultsCardDependencies = ({BuildContext Function() context});

class PlaybackDefaultsCard {
  final PlaybackDefaultsCardDependencies _deps;
  PlaybackDefaultsCard(this._deps);

  Widget defaultsCard(String title, String subtitle, List<Widget> children) {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
