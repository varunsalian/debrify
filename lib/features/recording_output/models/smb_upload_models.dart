// Tracking, retries and cancellation for SMB uploads.

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Why an upload attempt failed.
enum SmbFailureKind {
  auth,
  notFound,
  accessDenied,
  noSpace,
  network,
  sizeMismatch,
  readFailed,
  cancelled,
  other,
}

/// One finished local recording waiting to go out.
@immutable
final class SmbLocalRecording {
  const SmbLocalRecording({
    required this.uri,
    required this.name,
    required this.bytes,
    required this.recordedAtMs,
    this.finishedAtMs,
  });

  final String uri;
  final String name;
  final int bytes;
  final int recordedAtMs;

  /// When the recording ended, where known (Android times a recording by its
  /// start, desktop by its file's last write).
  final int? finishedAtMs;

  /// The latest moment the recording was still being made.
  int get endedAtMs => finishedAtMs ?? recordedAtMs;

  @override
  bool operator ==(Object other) =>
      other is SmbLocalRecording &&
      other.uri == uri &&
      other.name == name &&
      other.bytes == bytes &&
      other.recordedAtMs == recordedAtMs &&
      other.finishedAtMs == finishedAtMs;

  @override
  int get hashCode => Object.hash(uri, name, bytes, recordedAtMs, finishedAtMs);
}

/// Outcome tracked for one recording in the ledger.
enum SmbUploadState { uploaded, failed, gaveUp }

/// Ledger entry for one recording.
@immutable
final class SmbUploadRecord {
  const SmbUploadRecord({
    required this.uri,
    required this.bytes,
    required this.state,
    this.attempts = 0,
    this.failure,
    this.message,
    this.remotePath,
    required this.updatedAtMs,
    this.nextAttemptAtMs,
  });

  final String uri;
  final int bytes;
  final SmbUploadState state;
  final int attempts;
  final SmbFailureKind? failure;
  final String? message;
  final String? remotePath;
  final int updatedAtMs;
  final int? nextAttemptAtMs;

  /// Enums are stored by [Enum.name]; null fields are omitted.
  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'uri': uri,
      'bytes': bytes,
      'state': state.name,
      'attempts': attempts,
      'updatedAtMs': updatedAtMs,
    };
    final failure = this.failure;
    if (failure != null) json['failure'] = failure.name;
    final message = this.message;
    if (message != null) json['message'] = message;
    final remotePath = this.remotePath;
    if (remotePath != null) json['remotePath'] = remotePath;
    final nextAttemptAtMs = this.nextAttemptAtMs;
    if (nextAttemptAtMs != null) json['nextAttemptAtMs'] = nextAttemptAtMs;
    return json;
  }

  /// Null when uri/bytes/state/updatedAtMs are missing or invalid. An
  /// unknown failure name is dropped instead of invalidating the record.
  static SmbUploadRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final uri = json['uri'];
    final bytes = json['bytes'];
    final state = _enumByName(SmbUploadState.values, json['state']);
    final updatedAtMs = json['updatedAtMs'];
    if (uri is! String ||
        bytes is! int ||
        state == null ||
        updatedAtMs is! int) {
      return null;
    }
    final attempts = json['attempts'] is int ? json['attempts'] as int : 0;
    return SmbUploadRecord(
      uri: uri,
      bytes: bytes,
      state: state,
      attempts: attempts,
      failure: _enumByName(SmbFailureKind.values, json['failure']),
      message: json['message'] is String ? json['message'] as String? : null,
      remotePath: json['remotePath'] is String
          ? json['remotePath'] as String?
          : null,
      updatedAtMs: updatedAtMs,
      nextAttemptAtMs: json['nextAttemptAtMs'] is int
          ? json['nextAttemptAtMs'] as int
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SmbUploadRecord &&
      other.uri == uri &&
      other.bytes == bytes &&
      other.state == state &&
      other.attempts == attempts &&
      other.failure == failure &&
      other.message == message &&
      other.remotePath == remotePath &&
      other.updatedAtMs == updatedAtMs &&
      other.nextAttemptAtMs == nextAttemptAtMs;

  @override
  int get hashCode => Object.hash(
    uri,
    bytes,
    state,
    attempts,
    failure,
    message,
    remotePath,
    updatedAtMs,
    nextAttemptAtMs,
  );
}

T? _enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name is! String) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

/// Known upload outcomes, keyed by recording uri.
@immutable
final class SmbUploadLedger {
  const SmbUploadLedger([this.records = const {}]);

  final Map<String, SmbUploadRecord> records;

  static const maxRecords = 500;

  SmbUploadRecord? operator [](String uri) => records[uri];

  /// New ledger with [record] stored under its uri. Past [maxRecords] the
  /// records with the smallest updatedAtMs are dropped, never the new one.
  ///
  /// [present] are the uris still in the local library: over the cap, records
  /// of files that are gone are evicted first, so a large kept library never
  /// forgets (and re-uploads) a file it still holds while history is spare.
  SmbUploadLedger withRecord(
    SmbUploadRecord record, {
    Set<String> present = const {},
  }) {
    final next = Map<String, SmbUploadRecord>.from(records)
      ..[record.uri] = record;
    if (next.length > maxRecords) {
      final byAge = next.entries.toList()
        ..sort((a, b) {
          final aKept = present.contains(a.key) ? 1 : 0;
          final bKept = present.contains(b.key) ? 1 : 0;
          if (aKept != bKept) return aKept - bKept;
          final byTime = a.value.updatedAtMs.compareTo(b.value.updatedAtMs);
          return byTime != 0 ? byTime : a.key.compareTo(b.key);
        });
      for (final entry in byAge) {
        if (next.length <= maxRecords) break;
        if (entry.key == record.uri) continue;
        next.remove(entry.key);
      }
    }
    return SmbUploadLedger(next);
  }

  /// Keeps only `uploaded` records (used when the target changes).
  SmbUploadLedger withoutFailures() => SmbUploadLedger({
    for (final entry in records.entries)
      if (entry.value.state == SmbUploadState.uploaded) entry.key: entry.value,
  });

  String encode() =>
      jsonEncode([for (final record in records.values) record.toJson()]);

  /// Invalid input yields an empty ledger; invalid entries are skipped.
  static SmbUploadLedger decode(String? raw) {
    if (raw == null || raw.isEmpty) return const SmbUploadLedger();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const SmbUploadLedger();
      var ledger = const SmbUploadLedger();
      for (final entry in decoded) {
        final record = SmbUploadRecord.fromJson(entry);
        if (record != null) ledger = ledger.withRecord(record);
      }
      return ledger;
    } catch (_) {
      return const SmbUploadLedger();
    }
  }
}

/// What the uploader is doing right now, for the status UI.
enum SmbUploadPhase { disabled, idle, uploading }

@immutable
final class SmbUploadStatus {
  const SmbUploadStatus({
    this.phase = SmbUploadPhase.disabled,
    this.currentName,
    this.sentBytes = 0,
    this.totalBytes = 0,
    this.waiting = 0,
    this.lastUploadedName,
    this.lastFailure,
    this.lastMessage,
    this.lastRunAtMs,
  });

  final SmbUploadPhase phase;
  final String? currentName;
  final int sentBytes;
  final int totalBytes;

  /// Ready files not yet uploaded in this run.
  final int waiting;
  final String? lastUploadedName;
  final SmbFailureKind? lastFailure;
  final String? lastMessage;
  final int? lastRunAtMs;

  /// 0..100, 0 when [totalBytes] is 0; floor(sent*100/total) clamped.
  int get percent {
    if (totalBytes <= 0) return 0;
    final value = (sentBytes * 100) ~/ totalBytes;
    return value.clamp(0, 100);
  }

  /// Nullable fields cannot be cleared: passing null keeps the current value.
  SmbUploadStatus copyWith({
    SmbUploadPhase? phase,
    String? currentName,
    int? sentBytes,
    int? totalBytes,
    int? waiting,
    String? lastUploadedName,
    SmbFailureKind? lastFailure,
    String? lastMessage,
    int? lastRunAtMs,
  }) {
    return SmbUploadStatus(
      phase: phase ?? this.phase,
      currentName: currentName ?? this.currentName,
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      waiting: waiting ?? this.waiting,
      lastUploadedName: lastUploadedName ?? this.lastUploadedName,
      lastFailure: lastFailure ?? this.lastFailure,
      lastMessage: lastMessage ?? this.lastMessage,
      lastRunAtMs: lastRunAtMs ?? this.lastRunAtMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SmbUploadStatus &&
      other.phase == phase &&
      other.currentName == currentName &&
      other.sentBytes == sentBytes &&
      other.totalBytes == totalBytes &&
      other.waiting == waiting &&
      other.lastUploadedName == lastUploadedName &&
      other.lastFailure == lastFailure &&
      other.lastMessage == lastMessage &&
      other.lastRunAtMs == lastRunAtMs;

  @override
  int get hashCode => Object.hash(
    phase,
    currentName,
    sentBytes,
    totalBytes,
    waiting,
    lastUploadedName,
    lastFailure,
    lastMessage,
    lastRunAtMs,
  );
}
