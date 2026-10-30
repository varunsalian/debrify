// Pure retry/upload policy for SMB uploads: no I/O, no state.

import '../models/smb_upload_models.dart';

/// Attempts allowed for one recording before the uploader gives up.
const int maxSmbUploadAttempts = 6;

/// Retry delay after [attempts] failed attempts:
/// 1 → 1 min, 2 → 5 min, 3 → 15 min, ≥4 → 60 min (≤0 → 1 min).
Duration smbRetryDelay(int attempts) {
  if (attempts >= 4) return const Duration(minutes: 60);
  if (attempts == 3) return const Duration(minutes: 15);
  if (attempts == 2) return const Duration(minutes: 5);
  return const Duration(minutes: 1);
}

/// Retrying cannot help until the user changes settings.
bool isPermanentSmbFailure(SmbFailureKind kind) => switch (kind) {
  SmbFailureKind.auth => true,
  SmbFailureKind.notFound => true,
  SmbFailureKind.accessDenied => true,
  SmbFailureKind.noSpace => false,
  SmbFailureKind.network => false,
  SmbFailureKind.sizeMismatch => false,
  SmbFailureKind.readFailed => false,
  SmbFailureKind.cancelled => false,
  SmbFailureKind.other => false,
};

/// Every following file would fail the same way, so the run stops.
bool stopsSmbRun(SmbFailureKind kind) => switch (kind) {
  SmbFailureKind.auth => true,
  SmbFailureKind.notFound => true,
  SmbFailureKind.accessDenied => true,
  SmbFailureKind.network => true,
  SmbFailureKind.noSpace => true,
  SmbFailureKind.sizeMismatch => false,
  SmbFailureKind.readFailed => false,
  SmbFailureKind.cancelled => false,
  SmbFailureKind.other => false,
};

/// Which recordings to upload now, oldest [SmbLocalRecording.recordedAtMs]
/// first (ties broken by uri).
///
/// A recording is ready when all of these hold:
///  - bytes > 0 and its uri is not in [activeUris];
///  - previousBytes contains it with the same size (seen unchanged in the
///    previous scan, so the file is finished);
///  - the ledger has no record for it, OR the recorded size differs (a
///    changed file starts over), OR the record is `failed` and its
///    nextAttemptAtMs (0 when absent) has passed. `uploaded` and `gaveUp`
///    records with the same size are never ready;
///  - it was still being recorded at or after [copySinceMs], when that is
///    set (a recording running when the share was set up is copied).
List<SmbLocalRecording> smbReadyForUpload({
  required List<SmbLocalRecording> current,
  required Map<String, int> previousBytes,
  required Set<String> activeUris,
  required SmbUploadLedger ledger,
  required int nowMs,
  int? copySinceMs,
}) {
  final ready = <SmbLocalRecording>[];
  for (final recording in current) {
    if (recording.bytes <= 0) continue;
    if (copySinceMs != null && recording.endedAtMs < copySinceMs) continue;
    if (activeUris.contains(recording.uri)) continue;
    if (previousBytes[recording.uri] != recording.bytes) continue;
    final record = ledger[recording.uri];
    if (record != null && record.bytes == recording.bytes) {
      if (record.state != SmbUploadState.failed) continue;
      final next = record.nextAttemptAtMs ?? 0;
      if (next > nowMs) continue;
    }
    ready.add(recording);
  }
  ready.sort((a, b) {
    final byTime = a.recordedAtMs.compareTo(b.recordedAtMs);
    return byTime != 0 ? byTime : a.uri.compareTo(b.uri);
  });
  return ready;
}

/// The ledger record after a failed attempt of [recording]. Attempts restart
/// at 1 when there is no previous record or its size differs. The record
/// gives up immediately on permanent failures or once attempts reach
/// [maxSmbUploadAttempts]; giving up clears nextAttemptAtMs.
SmbUploadRecord smbFailedRecord({
  required SmbUploadRecord? previous,
  required SmbLocalRecording recording,
  required SmbFailureKind kind,
  String? message,
  required int nowMs,
}) {
  final restart = previous == null || previous.bytes != recording.bytes;
  final attempts = restart ? 1 : previous.attempts + 1;
  final gaveUp =
      isPermanentSmbFailure(kind) || attempts >= maxSmbUploadAttempts;
  return SmbUploadRecord(
    uri: recording.uri,
    bytes: recording.bytes,
    state: gaveUp ? SmbUploadState.gaveUp : SmbUploadState.failed,
    attempts: attempts,
    failure: kind,
    message: message,
    updatedAtMs: nowMs,
    nextAttemptAtMs: gaveUp
        ? null
        : nowMs + smbRetryDelay(attempts).inMilliseconds,
  );
}
