import 'package:flutter/material.dart';

import '../../../models/series_source.dart';
import '../../../models/torrent.dart';

/// Manual direct pin interaction. Data operations are supplied by the
/// caller; this function owns only view guards, feedback and interaction order.
Future<bool> presentDirectSourceBinding(
  BuildContext context,
  Torrent torrent, {
  required String imdbId,
  required Future<void> Function(Torrent) authorize,
  required SeriesSource? Function(Torrent) describe,
  required Future<bool> Function(SeriesSource) save,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return false;
  try {
    await authorize(torrent);
  } catch (_) {
    if (context.mounted && active()) {
      _snack(context, 'Connection changed. Search sources again.');
    }
    return false;
  }
  if (!context.mounted || !active()) return false;
  if (imdbId.isEmpty) {
    _snack(context, 'No IMDb match — can\'t pin a source.');
    return false;
  }
  final source = describe(torrent);
  if (source == null || (!source.isAddonDirect && !source.isMediaServer)) {
    _snack(context, 'This direct stream cannot be refreshed by its addon.');
    return false;
  }
  if (!await save(source)) {
    return false;
  }
  if (context.mounted && active()) {
    _snack(context, 'Direct source pinned for fresh-link playback.');
  }
  return true;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
