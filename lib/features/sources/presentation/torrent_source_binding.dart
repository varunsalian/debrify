import 'package:flutter/material.dart';

import '../../../models/series_source.dart';

/// Manual debrid pin presentation. The loader's dismissal callback owns its exact
/// route; acquisition/cleanup and descriptor/persistence operations are borrowed.
Future<bool> presentTorrentSourceBinding(
  BuildContext context, {
  required String imdbId,
  required String cancelledProvider,
  required Future<String?> Function() pickProvider,
  required VoidCallback Function(String provider) showLoading,
  required Future<({bool ready, String? failureMessage})> Function(
    String provider,
  )
  prepare,
  required SeriesSource Function(String provider) describe,
  required Future<bool> Function(SeriesSource) save,
  required String Function(String provider) providerLabel,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return false;
  if (imdbId.isEmpty) {
    _snack(context, 'No IMDb match — can\'t pin a source.');
    return false;
  }
  final provider = await pickProvider();
  if (!context.mounted || !active() || provider == cancelledProvider) {
    return false;
  }
  if (provider == null) {
    _snack(context, 'No debrid provider configured. Add one in Settings.');
    return false;
  }
  final dismissLoading = showLoading(provider);
  late final ({bool ready, String? failureMessage}) result;
  try {
    result = await prepare(provider);
  } finally {
    // Release this exact route before accessing the possibly retired view.
    dismissLoading();
  }
  if (!context.mounted || !active()) return false;
  if (!result.ready) {
    _snack(
      context,
      result.failureMessage ??
          'That source isn\'t instantly playable on ${providerLabel(provider)} — pick a cached one.',
    );
    return false;
  }
  final source = describe(provider);
  if (!await save(source)) return false;
  if (context.mounted && active()) {
    _snack(context, 'Source pinned for instant playback.');
  }
  return true;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
