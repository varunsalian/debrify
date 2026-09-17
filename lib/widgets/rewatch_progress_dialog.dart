import 'package:flutter/material.dart';
import '../services/series_progress_reset_service.dart';

/// Uses the same global reset as the title menu. Never launches on partial reset.
Future<bool> resetProgressForRewatch(
  BuildContext context, {
  required String id,
  required String title,
  required bool isMovie,
  required VoidCallback onConfirmed,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isMovie ? 'Rewatch movie?' : 'Rewatch series?'),
      content: Text(
        'Clear watched history and resume progress on this device and connected Trakt, Simkl and MDBList accounts, then ${isMovie ? 'play from the beginning' : 'start Season 1, Episode 1'}. Saved sources are kept. This cannot be undone.'
        '${isMovie ? '\n\nIf Simkl is connected, its movie reset also removes the movie from its library and permanently deletes its saved rating.' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Clear progress and rewatch'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;
  onConfirmed();
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Clearing watch progress…')),
          ],
        ),
      ),
    ),
  );
  List<String> failures;
  try {
    failures = await SeriesProgressResetService.clear(
      id,
      title,
      isMovie: isMovie,
    );
  } catch (_) {
    failures = ['watch progress'];
  } finally {
    if (navigator.mounted) navigator.pop();
  }
  if (!context.mounted) return false;
  if (failures.isNotEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Could not fully clear: ${failures.join(', ')}. Please retry.',
        ),
      ),
    );
    return false;
  }
  return true;
}
