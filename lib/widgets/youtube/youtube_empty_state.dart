import 'package:flutter/material.dart';

import '../../theme/app_theme_scope.dart';

/// Empty state for the YouTube source before a search is run.
class YoutubeEmptyState extends StatelessWidget {
  const YoutubeEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: app.seeAll.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.smart_display_outlined,
                size: 64,
                color: app.seeAll.accent,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'YouTube',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for any video — streamed on-device, no account needed',
              style: TextStyle(
                color: app.youtube.textDim,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
