import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/torrent.dart';
import 'diagnostic_log.dart';

/// Structural source tracing, without signed URLs, headers or addon credentials.
void logSourceSelection(
  String event, {
  Torrent? source,
  int? index,
  int? season,
  int? episode,
  String? reason,
  String? player,
  int? previousIndex,
}) {
  final sourceId = source == null
      ? null
      : sha256
            .convert(
              utf8.encode(
                jsonEncode([
                  source.stremioAddonKey,
                  source.stremioStreamKey,
                  source.stremioVideoId,
                  source.infohash,
                ]),
              ),
            )
            .toString()
            .substring(0, 12);
  final fields = <String, Object?>{
    'source_id': sourceId == null ? null : DiagnosticLabel(sourceId),
    'index': index,
    'previous_index': previousIndex,
    'season': season,
    'episode': episode,
    'transport': source == null
        ? null
        : DiagnosticLabel(source.streamType.name),
    'reason': reason == null ? null : DiagnosticLabel(reason),
    'player': player == null ? null : DiagnosticLabel(player),
    'has_binge_group': source?.stremioBingeGroup?.isNotEmpty,
  };
  DiagnosticLog.instance.recordEvent(
    source: 'source_selection',
    event: event,
    fields: fields,
  );
  // Scalar output avoids the console privacy filter treating a map as payload.
  debugPrint(
    'SourceSelect: event=$event sourceId=$sourceId index=$index '
    'previous=$previousIndex season=$season episode=$episode '
    'transport=${source?.streamType.name} reason=$reason player=$player',
  );
}
