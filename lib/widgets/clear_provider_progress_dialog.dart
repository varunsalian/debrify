import 'package:flutter/material.dart';
import '../models/stremio_addon.dart';
import '../models/tracking_source.dart';
import '../services/series_progress_reset_service.dart';
import '../services/profiles/profile_runtime.dart';
import '../services/profiles/profile_session_memory.dart';
import '../ui/core/progress_reset_dialog.dart';

Future<void> showClearProviderProgressDialog(
  BuildContext context,
  StremioMeta item,
  TrackingSource provider, {
  bool Function()? isCurrent,
  Future<List<String>> Function()? reset,
}) async {
  final owner = ProfileSessionMemory.captureOwner();
  bool current() =>
      owner == ProfileSessionMemory.captureOwner() &&
      (isCurrent?.call() ?? true);
  final label = switch (provider) {
    TrackingSource.trakt => 'Trakt',
    TrackingSource.simkl => 'Simkl',
    TrackingSource.mdblist => 'MDBList',
    _ => throw ArgumentError.value(provider),
  };
  final isMovie = item.type == 'movie';
  await runProgressResetDialog(
    context: context,
    isCurrent: current,
    confirmation: (ctx) => AlertDialog(
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
    reset: () async {
      try {
        Future<List<String>> run() =>
            reset?.call() ??
            SeriesProgressResetService.clearProvider(
              item.progressId ?? item.id,
              item.name,
              provider: provider,
              isMovie: isMovie,
            );
        final scope = owner.scope;
        return scope == null
            ? await run()
            : await ProfileRuntime.withCapturedScope(scope, run);
      } catch (_) {
        return [label];
      }
    },
    message: (failures) => failures.isEmpty
        ? 'Watch progress cleared on $label.'
        : 'Could not fully clear $label progress. Please retry.',
  );
}
