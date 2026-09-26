import 'package:flutter/material.dart';

import '../../../models/series_source.dart';
import '../../../models/torrent.dart';

typedef IptvBindingLog =
    void Function(
      String event, {
      Torrent? source,
      String? catalogType,
      String? outcome,
      Object? error,
    });

/// Manual IPTV pin presentation; data operations and the existing diagnostic
/// sink are supplied by the caller. No persistence or transport is owned here.
Future<bool> presentIptvSourceBinding(
  BuildContext context,
  Torrent torrent, {
  required String imdbId,
  required bool isMovie,
  required Future<void> Function(Torrent) authorize,
  required SeriesSource? Function(Torrent) describe,
  required Future<bool> Function(SeriesSource) save,
  required IptvBindingLog log,
  bool Function()? canContinue,
}) async {
  bool active() => canContinue?.call() ?? true;
  if (canContinue != null && (!context.mounted || !active())) return false;
  log(
    'manual_pin_started',
    source: torrent,
    catalogType: isMovie ? 'vod' : 'series',
  );
  if (imdbId.isEmpty) {
    log('manual_pin_completed', source: torrent, outcome: 'imdb_missing');
    _snack(context, 'No IMDb match — can\'t pin a source.');
    return false;
  }
  try {
    await authorize(torrent);
  } catch (error) {
    log(
      'manual_pin_completed',
      source: torrent,
      outcome: 'authorization_rejected',
      error: error,
    );
    if (context.mounted && active()) {
      _snack(context, 'IPTV connection changed. Search sources again.');
    }
    return false;
  }
  if (!context.mounted || !active()) {
    log(
      'manual_pin_completed',
      source: torrent,
      outcome: context.mounted ? 'session_retired' : 'view_closed',
    );
    return false;
  }
  final source = describe(torrent);
  if (source == null || !source.isIptvDirect) {
    log('manual_pin_completed', source: torrent, outcome: 'provenance_missing');
    _snack(context, 'This IPTV source cannot be refreshed from its catalog.');
    return false;
  }
  try {
    if (!await save(source)) {
      log('manual_pin_completed', source: torrent, outcome: 'session_retired');
      return false;
    }
  } catch (error) {
    log(
      'manual_pin_completed',
      source: torrent,
      outcome: 'storage_failed',
      error: error,
    );
    rethrow;
  }
  log('manual_pin_completed', source: torrent, outcome: 'saved');
  if (context.mounted && active()) {
    _snack(
      context,
      isMovie
          ? 'IPTV movie source pinned.'
          : 'IPTV series source pinned for every episode.',
    );
  }
  return true;
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
  );
}
