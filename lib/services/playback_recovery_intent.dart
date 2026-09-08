import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'diagnostic_log.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_runtime.dart';

/// Local deletion history for the seven-day native recovery window, including
/// devices without WebDAV. This key is deliberately excluded from transfers.
abstract final class PlaybackRecoveryIntent {
  static const _key = 'remote_tv_playback_recovery_deletions_v1';
  static const _retention = Duration(days: 7);
  static const _allPlayback = '*';
  static final _failureCutoffs = <String, int>{};

  static String get _scopeKey => ProfileRuntime.isProfileCommitted
      ? ProfileRuntime.capture().preferencePrefix
      : 'legacy';

  @visibleForTesting
  static bool? debugSupportedOverride;

  @visibleForTesting
  static void debugReset() {
    debugSupportedOverride = null;
    _failureCutoffs.clear();
  }

  static bool get isSupported =>
      debugSupportedOverride ?? (!kIsWeb && Platform.isAndroid);

  /// A clear also invalidates checkpoints whose item has no local row yet.
  static Future<void> recordClearAll() => record(const [_allPlayback]);

  static Future<void> record(Iterable<String> keys) async {
    if (!isSupported) return;
    final removed = keys.toSet();
    if (removed.isEmpty) return;
    final scopeKey = _scopeKey;
    final now = DateTime.now().millisecondsSinceEpoch;
    ProfilePreferences? prefs;
    try {
      prefs = await ProfilePreferences.instance();
      final saved = await prefs.mutateStringAtomically(_key, (encoded) {
        final previous = encoded == null
            ? <String, dynamic>{}
            : jsonDecode(encoded) as Map<String, dynamic>;
        return jsonEncode(<String, int>{
          for (final entry in previous.entries)
            if (entry.value is int &&
                entry.value >= now - _retention.inMilliseconds)
              entry.key: entry.value as int,
          for (final key in removed) key: now,
        });
      });
      if (!saved) {
        throw StateError('Could not persist playback deletion intent');
      }
    } catch (error, stackTrace) {
      // An auxiliary recovery journal must not fail the user's actual clear
      // or unwatch. A tiny coarse cutoff can replace corrupt/oversized history
      // without growing it, at the cost of skipping unrelated older recovery.
      _failureCutoffs[scopeKey] = now;
      try {
        await prefs?.mutateStringAtomically(_key, (_) {
          final cutoff = DateTime.now().millisecondsSinceEpoch;
          _failureCutoffs[scopeKey] = cutoff;
          return jsonEncode({_allPlayback: cutoff});
        });
      } catch (_) {
        // If storage itself is unavailable, keep the in-memory fence and let
        // the primary operation try. No durable write can be promised then.
      }
      DiagnosticLog.instance.recordError(
        source: 'tv_playback_recovery',
        event: 'deletion_intent_fallback',
        durable: true,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<bool> hasNewer(
    Iterable<String> keys,
    int checkpointAtMs,
  ) async {
    if (!isSupported) return false;
    if ((_failureCutoffs[_scopeKey] ?? 0) >= checkpointAtMs) return true;
    final prefs = await ProfilePreferences.instance();
    final encoded = prefs.getString(_key);
    if (encoded == null) return false;
    final records = jsonDecode(encoded) as Map<String, dynamic>;
    return [
      _allPlayback,
      ...keys,
    ].any((key) => records[key] is int && records[key] >= checkpointAtMs);
  }
}
