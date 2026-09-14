import 'dart:async';

import 'package:debrify/services/native_playback_progress_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('completion waits for an older save and finish drains both', () async {
    final firstSave = Completer<void>();
    final writes = <int>[];
    final session = NativePlaybackProgressSession(
      id: 7,
      isCurrent: () => true,
      persist: (progress) async {
        final position = progress['positionMs'] as int;
        if (position == 10) await firstSave.future;
        writes.add(position);
      },
    );
    final first = session.enqueue(_progress(7, 10));
    final last = session.enqueue(_progress(7, 100));
    var drained = false;
    final finish = session.closeAndDrain().then((_) => drained = true);
    await Future<void>.delayed(Duration.zero);
    expect(writes, isEmpty);
    expect(drained, isFalse);
    expect(await session.enqueue(_progress(7, 5)), isFalse);
    firstSave.complete();
    expect(await first, isTrue);
    expect(await last, isTrue);
    await finish;
    expect(writes, [10, 100]);
  });

  test('late packets from a different player are rejected', () async {
    final writes = <int>[];
    final session = NativePlaybackProgressSession(
      id: 8,
      isCurrent: () => true,
      persist: (progress) async => writes.add(progress['positionMs'] as int),
    );
    expect(await session.enqueue(_progress(7, 50)), isFalse);
    expect(await session.enqueue(_progress(8, 60)), isTrue);
    expect(writes, [60]);
  });

  test('queued progress is discarded after a profile switch', () async {
    var current = true;
    final firstSave = Completer<void>();
    final writes = <int>[];
    final session = NativePlaybackProgressSession(
      id: 7,
      isCurrent: () => current,
      persist: (progress) async {
        writes.add(progress['positionMs'] as int);
        await firstSave.future;
      },
    );
    final first = session.enqueue(_progress(7, 10));
    final queued = session.enqueue(_progress(7, 20));
    await Future<void>.delayed(Duration.zero);
    current = false;
    firstSave.complete();
    await first;
    expect(await queued, isFalse);
    expect(writes, [10]);
  });

  test(
    'failed saves are not acknowledged and a later checkpoint retries',
    () async {
      var attempts = 0;
      final session = NativePlaybackProgressSession(
        id: 7,
        isCurrent: () => true,
        persist: (_) async {
          if (++attempts == 1) throw StateError('storage unavailable');
        },
      );
      expect(await session.enqueue(_progress(7, 10)), isFalse);
      expect(await session.enqueue(_progress(7, 20)), isTrue);
      await session.closeAndDrain();
    },
  );
}

Map<String, dynamic> _progress(int id, int position) => {
  'sourcePersistenceSessionId': id,
  'positionMs': position,
};
