import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:sqlite3/sqlite3.dart';

import 'diagnostic_log.dart';

/// Never record SQL text, bound values, database paths, or exception.toString:
/// catalog keys and channel URLs contain provider credentials.
Map<String, Object?> iptvCatalogFailureFields(Object error) {
  final fields = <String, Object?>{'error_type': error.runtimeType.toString()};
  String? message;
  if (error is SqliteException) {
    fields['sqlite_code'] = error.resultCode;
    fields['sqlite_extended_code'] = error.extendedResultCode;
    message = error.message;
    final sql = error.causingStatement;
    if (sql != null) {
      fields['statement_id'] = sha256
          .convert(utf8.encode(sql))
          .toString()
          .substring(0, 12);
      final verb = sql.trimLeft().split(RegExp(r'\s+')).first.toUpperCase();
      if (const [
        'PRAGMA',
        'SELECT',
        'INSERT',
        'UPDATE',
        'DELETE',
        'CREATE',
        'ALTER',
        'DROP',
        'BEGIN',
        'COMMIT',
        'ROLLBACK',
      ].contains(verb)) {
        fields['sql_operation'] = verb;
      }
    }
  } else if (error is StateError) {
    final match = RegExp(
      r'^IPTV catalog SQL failed \((\d+)\): (.*)$',
    ).firstMatch(error.message);
    if (match != null) {
      final code = int.parse(match[1]!);
      fields['sqlite_code'] = code & 255;
      fields['sqlite_extended_code'] = code;
      message = match[2];
    }
  }
  if (message != null) {
    // Static categories only: even SQLite messages can contain user values.
    for (final reason in const [
      'database is locked',
      'database table is locked',
      'database disk image is malformed',
      'disk I/O error',
      'database or disk is full',
      'unable to open database file',
      'attempt to write a readonly database',
      'no such table',
      'no such column',
      'no such function',
      'no such module',
      'not authorized',
      'SQL logic error',
      'UNIQUE constraint failed',
      'NOT NULL constraint failed',
      'near',
    ]) {
      if (message == reason ||
          message.startsWith('$reason:') ||
          message.startsWith('$reason ')) {
        fields['sqlite_reason'] = reason.replaceAll(
          RegExp(r'[^a-zA-Z0-9]+'),
          '_',
        );
        break;
      }
    }
  }
  return fields;
}

void logIptvCatalogFailure(
  String stage,
  Object error,
  StackTrace stack, {
  int? elapsedMs,
}) {
  final fields = <String, Object?>{
    'stage': stage,
    ...iptvCatalogFailureFields(error),
    if (elapsedMs != null) 'elapsed_ms': elapsedMs,
  };
  // Scalar fields survive PrivacyLog's blanket JSON-payload redaction.
  debugPrint(
    'IPTV_CATALOG_DIAG ${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}',
  );
  // Source locations are enough for adb investigation, without error values.
  for (final frame in RegExp(
    r'package:debrify/[a-zA-Z0-9_/]+\.dart:\d+:\d+',
  ).allMatches(stack.toString()).take(6)) {
    debugPrint('IPTV_CATALOG_DIAG frame=${frame[0]}');
  }
  DiagnosticLog.instance.recordEvent(
    source: 'iptv_catalog',
    event: 'failure',
    level: DiagnosticLevel.error,
    fields: fields.map(
      (key, value) =>
          MapEntry(key, value is String ? DiagnosticLabel(value) : value),
    ),
    flushImmediately: true,
  );
  DiagnosticLog.instance.recordError(
    source: 'iptv_catalog',
    event: stage,
    error: error,
    stackTrace: stack,
  );
}
