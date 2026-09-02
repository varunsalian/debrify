import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'profile_preferences.dart';

/// Process-wide and restart-durable barrier around profile database opens.
/// CircleAdoption bypasses this barrier only for its direct, drained file
/// replacement; ordinary services wait until the target bytes are complete.
abstract final class ProfileDatabaseAdoptionGate {
  static const String preferenceKey = 'webdav_sync_db_adoption_gate_v1';
  static final Lock _lock = Lock();
  static Completer<void>? _held;

  static bool get isHeld => _held != null;

  static Future<void> hold() => _lock.synchronized(() async {
    final created = _held == null;
    final gate = _held ??= Completer<void>();
    try {
      final prefs = await DevicePreferences.instance();
      if (!await prefs.setBool(preferenceKey, true)) {
        throw StateError(
          'Could not persist the profile database adoption gate',
        );
      }
    } catch (_) {
      // A failed first hold never became restart-durable. Roll its in-memory
      // barrier back as well or every database open in this process would
      // wait forever for an adoption that never began. An already-held gate
      // remains authoritative when an idempotent persistence retry fails.
      if (created && identical(_held, gate)) {
        _held = null;
        if (!gate.isCompleted) gate.complete();
      }
      rethrow;
    }
  });

  /// Reconstructs the durable barrier once, during app startup after Flutter's
  /// plugin binding is available and before any profile database can open.
  ///
  /// Keeping persistence out of [waitUntilReleased] is intentional: database
  /// classes are also used by pure-Dart tests and tools where the
  /// shared_preferences platform channel does not exist.
  static Future<void> restorePersisted() => _lock.synchronized(() async {
    if (_held != null) return;
    final prefs = await DevicePreferences.instance();
    if (prefs.getBool(preferenceKey) == true) {
      _held = Completer<void>();
    }
  });

  static Future<void> waitUntilReleased() async => _held?.future;

  static Future<void> release() => _lock.synchronized(() async {
    Object? failure;
    StackTrace? failureStack;
    try {
      final prefs = await DevicePreferences.instance();
      if (!await prefs.remove(preferenceKey)) {
        throw StateError('Could not clear the profile database adoption gate');
      }
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    } finally {
      // Once the adoption operation has asked to release, never leave ordinary
      // database users blocked for the rest of this process. If clearing the
      // durable flag failed, the error is still reported and startup recovery
      // will see the stale flag on the next launch.
      final gate = _held;
      _held = null;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  });

  @visibleForTesting
  static void debugReset() {
    final gate = _held;
    _held = null;
    if (gate != null && !gate.isCompleted) gate.complete();
  }
}
