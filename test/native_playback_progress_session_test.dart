import 'dart:async';

import 'package:debrify/services/native_playback_progress_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'source commits are ordered between outgoing and incoming progress',
    () async {
      final release = Completer<void>();
      final events = <String>[];
      final session = NativePlaybackProgressSession(
        id: 7,
        isCurrent: () => true,
        onSourceCommitted: (index) => events.add('source:$index'),
        persist: (progress) async {
          final position = progress['positionMs'] as int;
          if (position == 10) await release.future;
          events.add('position:$position');
        },
      );
      final first = session.enqueue(_progress(7, 10));
      final eof = session.enqueue(_progress(7, 100));
      final commit = session.enqueueSourceCommit(sessionId: 7, sourceIndex: 1);
      final incoming = session.enqueue(_progress(7, 5));
      final finish = session.closeAndDrain();
      expect(
        await session.enqueueSourceCommit(sessionId: 7, sourceIndex: 2),
        false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      release.complete();
      await Future.wait([first, eof, commit, incoming]);
      await finish;
      expect(events, ['position:10', 'position:100', 'source:1', 'position:5']);
    },
  );

  test(
    'stale source commits do not switch the active watch identity',
    () async {
      var current = true;
      final release = Completer<void>();
      final commits = <int>[];
      final session = NativePlaybackProgressSession(
        id: 8,
        isCurrent: () => current,
        onSourceCommitted: commits.add,
        persist: (_) => release.future,
      );
      expect(
        await session.enqueueSourceCommit(sessionId: 7, sourceIndex: 0),
        false,
      );
      expect(
        await session.enqueueSourceCommit(sessionId: 8, sourceIndex: -1),
        false,
      );
      final first = session.enqueue(_progress(8, 10));
      final commit = session.enqueueSourceCommit(sessionId: 8, sourceIndex: 1);
      await Future<void>.delayed(Duration.zero);
      current = false;
      release.complete();
      await first;
      expect(await commit, false);
      await session.closeAndDrain();
      expect(commits, isEmpty);
    },
  );

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
