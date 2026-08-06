import 'package:flutter/material.dart';

import '../see_all/see_all_theme.dart';

/// Empty state for the YouTube source before a search is run.
class YoutubeEmptyState extends StatelessWidget {
  const YoutubeEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: kSeeAllAccent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_display_outlined,
                size: 64,
                color: kSeeAllAccent,
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
                color: Colors.white.withValues(alpha: 0.5),
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
