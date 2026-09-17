import 'dart:async';

import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'failed removal finishes before successful source is committed',
    () async {
      final session = StremioSourcePersistenceSession(1);
      final removal = Completer<void>();
      var pins = ['failed'];
      final removing = session.enqueue(() async {
        final snapshot = [...pins];
        await removal.future;
        pins = snapshot..remove('failed');
      });
      final committing = session.enqueue(() async {
        pins = [...pins, 'winner'];
      });
      await Future<void>.delayed(Duration.zero);
      expect(pins, ['failed']);
      removal.complete();
      await Future.wait([removing, committing]);
      expect(pins, ['winner']);
      await session.closeAndDrain();
    },
  );

  test('timed-out removal still blocks a conflicting commit', () async {
    final session = StremioSourcePersistenceSession(
      2,
      waitTimeout: const Duration(milliseconds: 1),
    );
    final removal = Completer<void>();
    final events = <String>[];
    await session.enqueue(() async {
      await removal.future;
      events.add('removed');
    });
    await session.enqueue(() async {
      events.add('committed');
    });
    expect(events, isEmpty);
    removal.complete();
    await session.closeAndDrain();
    expect(events, ['removed', 'committed']);
  });

  test('failed write does not poison later writes', () async {
    final session = StremioSourcePersistenceSession(3);
    var committed = false;
    await session.enqueue(() async {
      throw StateError('storage failed');
    });
    await session.enqueue(() async {
      committed = true;
    });
    expect(committed, isTrue);
    await session.closeAndDrain();
  });
}
