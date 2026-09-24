import 'package:flutter/material.dart';
import '../models/stremio_addon.dart';
import '../models/tracking_source.dart';
import '../services/series_progress_reset_service.dart';

Future<void> showClearProviderProgressDialog(
  BuildContext context,
  StremioMeta item,
  TrackingSource provider,
) async {
  final label = switch (provider) {
    TrackingSource.trakt => 'Trakt',
    TrackingSource.simkl => 'Simkl',
    TrackingSource.mdblist => 'MDBList',
    _ => throw ArgumentError.value(provider),
  };
  final isMovie = item.type == 'movie';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Clear watch progress on $label?'),
      content: Text(
        'Clear ${isMovie ? 'watched history and resume progress' : 'watched history and resume progress for all episodes'} of ${item.name} on $label only?\n\nLocal progress and other trackers will not be changed. This cannot be undone.'
        '${provider == TrackingSource.simkl && isMovie ? '\n\nSimkl’s movie reset also removes the movie from its library.' : ''}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Clear progress'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
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
  var success = false;
  try {
    success = (await SeriesProgressResetService.clearProvider(
      item.progressId ?? item.id,
      item.name,
      provider: provider,
      isMovie: isMovie,
    )).isEmpty;
  } catch (_) {
    success = false;
  } finally {
    if (navigator.mounted) navigator.pop();
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        success
            ? 'Watch progress cleared on $label.'
            : 'Could not fully clear $label progress. Please retry.',
      ),
    ),
  );
}
