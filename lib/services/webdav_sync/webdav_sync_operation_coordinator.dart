import 'dart:async';

import 'package:synchronized/synchronized.dart';

/// Serializes every production operation that can read, apply, or publish
/// circle state. The lock is re-entrant because graph adoption finishes by
/// invoking one hot merge inside the already-exclusive adoption operation.
final class WebDavSyncOperationCoordinator {
  final Lock _lock = Lock(reentrant: true);

  Future<T> run<T>(FutureOr<T> Function() operation) =>
      _lock.synchronized(operation);
}
