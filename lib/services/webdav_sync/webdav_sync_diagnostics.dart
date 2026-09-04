import 'package:flutter/foundation.dart' show debugPrint;

import '../diagnostic_log.dart';
import '../webdav_protocol_client.dart';

typedef WebDavSyncAuthorityDiagnostic =
    void Function(String message, Object? error);

/// Production sink for audited WebDAV sync notes.
///
/// Error objects are deliberately ignored: transport errors can contain
/// endpoints or paths, while each message passed here is a fixed, audited
/// description of the condition.
void recordWebDavSyncDiagnostic(String message, Object? _) {
  try {
    debugPrint(message);
  } catch (_) {
    // Continue to the retained sink if the live console is unavailable.
  }
  try {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'engine_note',
      level: _webDavSyncDiagnosticLevel(message),
      fields: <String, Object?>{
        'message': DiagnosticLabel(_webDavSyncMessageLabel(message)),
      },
    );
  } catch (_) {
    // Observability must never affect sync work.
  }
}

/// Records only the audited authority step and a non-secret-bearing status.
///
/// Never pass the underlying error to the sink: protocol exceptions may carry
/// a credentialed endpoint or a private path.
void recordWebDavSyncAuthorityFailure(
  WebDavSyncAuthorityDiagnostic diagnostic, {
  required String step,
  Object? error,
  int? statusCode,
}) {
  final resolvedStatus =
      statusCode ?? (error is WebDavException ? error.statusCode : null);
  final outcome = resolvedStatus != null
      ? 'HTTP $resolvedStatus'
      : error is WebDavException
      ? 'kind ${error.kind.name}'
      : 'kind exception';
  diagnostic('WebDAV sync authority failure: $step, $outcome', null);
}

String _webDavSyncMessageLabel(String message) {
  final label = message
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9_.:+-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (label.isEmpty) return 'unknown';
  return label.length <= 80 ? label : label.substring(0, 80);
}

/// Records the single most recent logical preference key that caused a
/// coalesced local-change cycle. Preference values never enter this event.
void recordWebDavSyncLocalChangeTrigger(String logicalKey) {
  try {
    debugPrint('WebDAV sync local change triggered by $logicalKey');
  } catch (_) {
    // Continue to the retained sink if the live console is unavailable.
  }
  try {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'local_change_trigger',
      fields: <String, Object?>{'preferenceKey': DiagnosticLabel(logicalKey)},
    );
  } catch (_) {
    // Observability must never affect sync scheduling.
  }
}

/// Records a local-change intent that could not flush this attempt and the
/// bounded retry the scheduler armed for it. Reasons are constant labels.
void recordWebDavSyncLocalChangeDeferred(
  String reason,
  int attempt,
  Duration delay,
) {
  try {
    debugPrint(
      'WebDAV sync local change deferred ($reason); '
      'retry #$attempt in ${delay.inSeconds}s',
    );
  } catch (_) {
    // Continue to the retained sink if the live console is unavailable.
  }
  try {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_sync',
      event: 'local_change_deferred',
      level: DiagnosticLevel.warning,
      fields: <String, Object?>{
        'reason': DiagnosticLabel(reason),
        'attempt': attempt,
        'delayMs': delay.inMilliseconds,
      },
    );
  } catch (_) {
    // Observability must never affect sync scheduling.
  }
}

DiagnosticLevel _webDavSyncDiagnosticLevel(String message) {
  final normalized = message.toLowerCase();
  if (normalized.contains('ignored') ||
      normalized.contains('deferred') ||
      normalized.contains('dropped') ||
      normalized.contains('pending') ||
      normalized.contains('quarantined') ||
      normalized.contains('skipped') ||
      normalized.contains('retained')) {
    return DiagnosticLevel.warning;
  }
  return DiagnosticLevel.info;
}
