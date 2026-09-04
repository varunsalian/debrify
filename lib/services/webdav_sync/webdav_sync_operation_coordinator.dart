import 'dart:async';

import 'package:synchronized/synchronized.dart';

/// Serializes every production operation that can read, apply, or publish
/// circle state. The lock is re-entrant because graph adoption finishes by
/// invoking one hot merge inside the already-exclusive adoption operation.
final class WebDavSyncOperationCoordinator {
  final Lock _lock = Lock(reentrant: true);

  bool get isRunning => _lock.locked;

  Future<T> run<T>(FutureOr<T> Function() operation) =>
      _lock.synchronized(operation);

  Future<T> runIfIdle<T>(
    FutureOr<T> Function() operation, {
    required T whenBusy,
  }) {
    if (_lock.locked) return Future<T>.value(whenBusy);
    return _lock.synchronized(operation);
  }
}

/// Keeps the post-switch retirement apply on the same exclusion boundary as
/// live sync cycles while leaving the coordinator independently testable.
Future<T> serializeWebDavSyncPendingActiveProfileApply<T>({
  required WebDavSyncOperationCoordinator operations,
  required FutureOr<T> Function() apply,
}) => operations.run(apply);
