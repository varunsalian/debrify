import 'dart:async';

import 'package:debrify/services/profiles/profile_session_memory.dart';

/// A short-lived, profile-owned cache for one account-wide read.
///
/// - Concurrent readers join one in-flight request.
/// - A value is only reused by the profile session that fetched it.
/// - [invalidate] (after a write, sign-in or sign-out) both drops the value
///   and stops a request already in flight from publishing its now stale
///   result, and later readers never join that stale request.
/// - Failures (null) are never cached.
class LedgerCache<T extends Object> {
  LedgerCache(this.ttl, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;

  T? _value;
  DateTime? _storedAt;
  ProfileSessionOwner? _owner;
  int _generation = 0;
  Future<T?>? _inFlight;
  Object? _inFlightToken;
  int _inFlightGeneration = -1;
  ProfileSessionOwner? _inFlightOwner;

  Future<T?> read(Future<T?> Function() fetch) {
    final owner = ProfileSessionMemory.captureOwner();
    final storedAt = _storedAt;
    if (_value != null &&
        storedAt != null &&
        _owner == owner &&
        _now().difference(storedAt) < ttl) {
      return Future<T?>.value(_value);
    }
    final pending = _inFlight;
    if (pending != null &&
        _inFlightGeneration == _generation &&
        _inFlightOwner == owner) {
      return pending;
    }
    final generation = _generation;
    final token = Object();
    _inFlightToken = token;
    final operation = () async {
      try {
        final value = await fetch();
        if (value != null &&
            generation == _generation &&
            ProfileSessionMemory.captureOwner() == owner) {
          _value = value;
          _storedAt = _now();
          _owner = owner;
        }
        return value;
      } finally {
        if (identical(_inFlightToken, token)) {
          _inFlight = null;
          _inFlightToken = null;
        }
      }
    }();
    if (identical(_inFlightToken, token)) _inFlight = operation;
    _inFlightGeneration = generation;
    _inFlightOwner = owner;
    return operation;
  }

  void invalidate() {
    _value = null;
    _storedAt = null;
    _owner = null;
    _generation++;
  }
}
