import 'package:flutter/material.dart';

/// A failed read must leave an actionable page, without exposing editable
/// fallback values that could overwrite the user's saved settings.
class SettingsLoadError extends StatelessWidget {
  const SettingsLoadError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Unable to load settings. Please try again.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}
