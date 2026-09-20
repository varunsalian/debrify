import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/torrent.dart';
import 'diagnostic_log.dart';

String? _opaqueDiagnosticId(String? value) {
  if (value == null || value.isEmpty) return null;
  return sha256.convert(utf8.encode(value)).toString().substring(0, 12);
}

String? _safeCatalogType(String? value) {
  if (value == null) return null;
  return const {'vod', 'series'}.contains(value) ? value : 'unknown';
}

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

/// Privacy-safe tracing for IPTV discovery, Quick Play, and durable pins.
///
/// Provider and catalog identifiers are hashed. Callers must pass only fixed,
/// audited labels (not titles, URLs, credentials, or provider names) for
/// [stage], [outcome], and [providerKind].
void logIptvSourceEvent(
  String event, {
  Torrent? source,
  String? playlistId,
  String? entryKey,
  String? catalogType,
  String? providerKind,
  String? stage,
  String? outcome,
  int? season,
  int? episode,
  int? playlistCount,
  int? candidateCount,
  int? resultCount,
  int? failedCount,
  int? elapsedMs,
  bool? timedOut,
  bool? fallbackScan,
  Object? error,
}) {
  final resolvedPlaylistId = playlistId ?? source?.iptvPlaylistId;
  final resolvedEntryKey = entryKey ?? source?.iptvEntryKey;
  final resolvedCatalogType = _safeCatalogType(
    catalogType ?? source?.iptvCatalogType,
  );
  final playlistHash = _opaqueDiagnosticId(resolvedPlaylistId);
  final entryHash = _opaqueDiagnosticId(resolvedEntryKey);
  final fields = <String, Object?>{
    'playlist_id': playlistHash == null ? null : DiagnosticLabel(playlistHash),
    'entry_id': entryHash == null ? null : DiagnosticLabel(entryHash),
    'catalog_type': resolvedCatalogType == null
        ? null
        : DiagnosticLabel(resolvedCatalogType),
    'provider_kind': providerKind == null
        ? null
        : DiagnosticLabel(providerKind),
    'stage': stage == null ? null : DiagnosticLabel(stage),
    'outcome': outcome == null ? null : DiagnosticLabel(outcome),
    'season': season,
    'episode': episode,
    'playlist_count': playlistCount,
    'candidate_count': candidateCount,
    'result_count': resultCount,
    'failed_count': failedCount,
    'elapsed_ms': elapsedMs,
    'timed_out': timedOut,
    'fallback_scan': fallbackScan,
    'error_type': error == null
        ? null
        : DiagnosticLabel(error.runtimeType.toString()),
  };
  DiagnosticLog.instance.recordEvent(
    source: 'iptv_source',
    event: event,
    fields: fields,
  );
  // Keep console output scalar-only and free of content or connection data.
  debugPrint(
    'IptvSource: event=$event playlist=$playlistHash entry=$entryHash '
    'catalog=$resolvedCatalogType provider=$providerKind stage=$stage '
    'outcome=$outcome season=$season episode=$episode '
    'playlists=$playlistCount candidates=$candidateCount results=$resultCount '
    'failed=$failedCount elapsedMs=$elapsedMs timedOut=$timedOut '
    'fallbackScan=$fallbackScan errorType=${error?.runtimeType}',
  );
}
