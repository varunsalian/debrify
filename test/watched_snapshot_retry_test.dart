import 'dart:async';

import 'package:debrify/services/watched_snapshot_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parallel failure is handled while local storage retries', () async {
    final calendar = Completer<int>();
    final tracker = Completer<int>();
    final failure = StateError('Calendar storage unavailable');
    final captured = captureWatchedRead(
      Future.wait([calendar.future, tracker.future]),
    );
    calendar.completeError(failure);
    // Leave the captured result unawaited across real async turns, as the
    // local retry backoff does. An unhandled error would fail this test.
    var attempts = 0;
    await readWatchedSnapshotWithRetry(() async {
      if (++attempts == 1) throw StateError('Retry local storage');
      return {'tt1'};
    }, retryDelay: const Duration(milliseconds: 1));
    var joined = false;
    unawaited(captured.then((_) => joined = true));
    await Future<void>.delayed(Duration.zero);
    expect(joined, isFalse);
    tracker.complete(1);
    final result = await captured;
    expect(result.unwrap, throwsA(same(failure)));
  });

  test('captured successful reads retain their result', () async {
    final result = await captureWatchedRead(Future.value({'tt1'}));
    expect(result.unwrap(), {'tt1'});
  });

  test('transient storage failures recover the watched snapshot', () async {
    var attempts = 0;
    final result = await readWatchedSnapshotWithRetry(() async {
      if (++attempts < 3) throw StateError('Storage unavailable');
      return {'tt1'};
    }, retryDelay: Duration.zero);
    expect(result, {'tt1'});
    expect(attempts, 3);
  });

  test('persistent failure is bounded and remains observable', () async {
    var attempts = 0;
    await expectLater(
      readWatchedSnapshotWithRetry(() async {
        attempts++;
        throw StateError('Storage unavailable');
      }, retryDelay: Duration.zero),
      throwsStateError,
    );
    expect(attempts, 3);
  });
}
