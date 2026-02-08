import 'package:flutter/material.dart';

import '../../../services/main_page_bridge.dart';

/// Empty state shown when no catalog addons are installed.
class StremioTvEmptyState extends StatelessWidget {
  const StremioTvEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_display_rounded,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Catalog Addons',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Install Stremio catalog addons (like Cinemeta) to discover '
              'channels. Each catalog becomes a TV channel with rotating content.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                // Navigate to Addons tab (index 7)
                MainPageBridge.switchTab?.call(7);
              },
              icon: const Icon(Icons.extension_rounded),
              label: const Text('Go to Addons'),
            ),
          ],
        ),
      ),
    );
  }
}
