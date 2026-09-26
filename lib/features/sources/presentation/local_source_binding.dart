import 'package:flutter/material.dart';

import '../../../models/series_source.dart';

/// Local pin interaction; the caller supplies the existing picker and writer.
/// Native acquisition and filesystem work retain their original owners.
Future<bool> presentLocalSourceBinding(
  BuildContext context, {
  required String imdbId,
  required Future<SeriesSource?> Function() pick,
  required Future<bool> Function(SeriesSource) save,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return false;
  if (imdbId.isEmpty) {
    _snack(context, 'No IMDb match — can\'t pin a source.');
    return false;
  }
  final source = await pick();
  if (source == null || !context.mounted || !active()) return false;
  if (!await save(source)) {
    return false;
  }
  if (context.mounted && active()) _snack(context, 'Local source pinned.');
  return true;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
