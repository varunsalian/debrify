import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../profiles/privacy_log.dart';

/// Privacy-safe milestones for diagnosing an all-profile remote transfer.
///
/// Android release builds strip native verbose/debug/info calls in ProGuard,
/// so these lines are also forwarded to a warning-level native log sink. Keep
/// fields structural: phases, counts, sizes, durations, booleans, and runtime
/// types only. Never pass payloads, URLs, addresses, credentials, names, or
/// full persistent identifiers.
abstract final class RemoteTransferDiagnostics {
  static const MethodChannel _androidLog = MethodChannel(
    'debrify/remote_transfer_diagnostics',
  );

  static final RegExp _fieldKey = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{0,39}$');

  static String? traceToken(String? requestId) {
    if (requestId == null || requestId.isEmpty) return null;
    final safe = requestId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (safe.isEmpty) return null;
    return safe.length <= 8 ? safe : safe.substring(0, 8);
  }

  static void record(
    String event, {
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final parts = <String>['DEBRIFY_TRANSFER', 'event=$event'];
    for (final entry in fields.entries) {
      if (!_fieldKey.hasMatch(entry.key) || entry.value == null) continue;
      final raw = entry.value
          .toString()
          .replaceAll('\n', ' ')
          .replaceAll('\r', ' ');
      final bounded = raw.length <= 80 ? raw : raw.substring(0, 80);
      parts.add('${entry.key}=$bounded');
    }
    final message = PrivacyLog.redact(parts.join(' '));
    debugPrint(message);
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(
        _androidLog
            .invokeMethod<void>('write', <String, Object?>{'message': message})
            .catchError((_) {}),
      );
    }
  }
}
