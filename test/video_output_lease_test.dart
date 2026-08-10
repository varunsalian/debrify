import 'dart:async';

import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lease is the only thing standing between two media_kit video outputs and
/// a SIGABRT on tvOS, so the properties worth pinning are the ones whose
/// failure mode is "the process dies" or "playback never starts".
void main() {
  setUp(VideoOutputLease.debugReset);

  test('serialises: the second acquire waits for the first release', () async {
    final first = await VideoOutputLease.acquire();
    expect(VideoOutputLease.isHeld, isTrue);

    var secondGranted = false;
    final second = VideoOutputLease.acquire().then((h) {
      secondGranted = true;
      return h;
    });

    // Give the microtask queue every chance to hand the slot over early.
    await Future<void>.delayed(Duration.zero);
    expect(secondGranted, isFalse,
        reason: 'two holders at once is the crash this exists to prevent');

    first.release();
    await second;
    expect(secondGranted, isTrue);
  });

  test('a release that happens only after disposal completes still hands over',
      () async {
    final first = await VideoOutputLease.acquire();
    final disposal = Completer<void>();
    // The real disposer releases from `whenComplete`, so model that: the slot
    // must NOT free when disposal is merely requested.
    unawaited(disposal.future.whenComplete(first.release));

    var granted = false;
    unawaited(VideoOutputLease.acquire().then((_) => granted = true));
    await Future<void>.delayed(Duration.zero);
    expect(granted, isFalse);

    disposal.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(granted, isTrue);
  });

  test('releasing twice is harmless', () async {
    final h = await VideoOutputLease.acquire();
    h.release();
    h.release();
    expect(VideoOutputLease.isHeld, isFalse);
    // And the slot is genuinely re-takeable, not left in a half state.
    final again = await VideoOutputLease.acquire();
    expect(again.released, isFalse);
  });

  test('a failed dispose must not strand the slot', () async {
    final h = await VideoOutputLease.acquire();
    // `whenComplete` fires on the error path too — that is the whole reason the
    // disposer uses it rather than a trailing statement.
    await Future<void>.error(StateError('boom'))
        .whenComplete(h.release)
        .catchError((_) {});
    expect(VideoOutputLease.isHeld, isFalse);
  });

  test('several waiters do not all wake into the slot at once', () async {
    final first = await VideoOutputLease.acquire();
    final granted = <int>[];
    for (var i = 0; i < 3; i++) {
      unawaited(VideoOutputLease.acquire().then((h) {
        granted.add(i);
        // Each holds until explicitly released.
        return h;
      }));
    }
    first.release();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(granted.length, 1,
        reason: 'the loop in acquire() must re-check, not let every parked '
            'waiter through on one completion');
  });
}
