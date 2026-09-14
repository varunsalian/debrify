/// Retry transient local-storage failures without repeating tracker requests.
/// Exhaustion remains an error so the caller can log it and retry on activation.
Future<T> readWatchedSnapshotWithRetry<T>(
  Future<T> Function() read, {
  Duration retryDelay = const Duration(milliseconds: 200),
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await read();
    } catch (_) {
      if (attempt == 2) rethrow;
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  }
}

/// Stores an asynchronous error until the consumer is ready to handle it.
/// The capture future itself never fails, even when awaited after local retries.
Future<CapturedWatchedRead<T>> captureWatchedRead<T>(Future<T> read) =>
    read.then(
      (value) => CapturedWatchedRead<T>._(value, null, null),
      onError: (Object error, StackTrace stack) =>
          CapturedWatchedRead<T>._(null, error, stack),
    );

class CapturedWatchedRead<T> {
  CapturedWatchedRead._(this._value, this._error, this._stack);

  final T? _value;
  final Object? _error;
  final StackTrace? _stack;

  T unwrap() {
    final error = _error;
    if (error != null) Error.throwWithStackTrace(error, _stack!);
    return _value as T;
  }
}
