import 'dart:async';

import 'package:debrify/services/remote_control/remote_control_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final state = RemoteControlState();

  setUp(() async {
    await state.debugResetForTesting();
  });

  tearDown(() async {
    await state.debugResetForTesting();
  });

  test(
    'distinct leases restore only after the final caller releases',
    () async {
      final calls = <String>[];
      state.debugSenderStarter = () async => calls.add('sender');
      state.debugReceiverStarter = (name) async => calls.add('receiver:$name');
      state.debugRoleStopper = () async => calls.add('stop');

      await state.startMobileDiscovery();
      final first = await state.ensureReceiverMode('Living room');
      final second = await state.ensureReceiverMode('Living room');
      expect(identical(first, second), isFalse);
      expect(state.debugRole, 'receiver');

      await second.release();
      expect(state.debugRole, 'receiver');
      await first.release();
      expect(state.debugRole, 'sender');
      expect(calls, <String>[
        'sender',
        'stop',
        'receiver:Living room',
        'stop',
        'sender',
      ]);
    },
  );

  test(
    'leaving while receiver bind is pending ends in the prior role',
    () async {
      final bind = Completer<void>();
      state.debugSenderStarter = () async {};
      state.debugReceiverStarter = (_) => bind.future;
      state.debugRoleStopper = () async {};
      await state.startMobileDiscovery();

      final acquisition = state.ensureReceiverMode('Pending TV');
      final backedOut = acquisition.then((lease) => lease.release());
      await Future<void>.delayed(Duration.zero);
      expect(state.debugRole, 'stopped');
      bind.complete();
      await backedOut;
      expect(state.debugRole, 'sender');
    },
  );

  test('a lease cannot stop a receiver role that predated it', () async {
    var starts = 0;
    state.debugReceiverStarter = (_) async => starts++;
    state.debugRoleStopper = () async {};
    await state.startTvListener('Debrify TV');
    final lease = await state.ensureReceiverMode('Debrify TV');
    await lease.release();
    expect(state.debugRole, 'receiver');
    expect(starts, 1);
  });

  test('a failed acquisition restores the previous sender role', () async {
    var senderStarts = 0;
    state.debugSenderStarter = () async => senderStarts++;
    state.debugReceiverStarter = (_) async => throw StateError('bind failed');
    state.debugRoleStopper = () async {};

    await state.startMobileDiscovery();
    await expectLater(
      state.ensureReceiverMode('Unavailable TV'),
      throwsA(isA<StateError>()),
    );

    expect(state.debugRole, 'sender');
    expect(senderStarts, 2);
  });
}
