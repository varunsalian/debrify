import 'dart:async';

import 'package:debrify/features/ledger/application/ledger_sign_in_controller.dart';
import 'package:debrify/features/ledger/application/ledger_title_controller.dart';
import 'package:debrify/features/ledger/models/ledger_title.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Gateway implements LedgerTitleGateway {
  @override
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  bool connected = true;
  bool supported = true;
  bool accept = true;
  LedgerTitleStatus? held = const LedgerTitleStatus();
  final List<String> sent = [];
  int reads = 0;

  /// When set, the next status read waits for it.
  Completer<void>? readGate;

  /// When set, the next write waits for it.
  Completer<void>? writeGate;

  @override
  bool supports(String imdbId) => supported;

  @override
  Future<bool> isConnected() async => connected;

  @override
  Future<LedgerTitleStatus?> status(LedgerTitleKey key) async {
    reads++;
    final snapshot = held;
    final gate = readGate;
    readGate = null;
    if (gate != null) await gate.future;
    return snapshot;
  }

  Future<bool> _write(String name, LedgerTitleStatus next) async {
    sent.add(name);
    final gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (accept) held = next;
    return accept;
  }

  @override
  Future<bool> setPlanned(LedgerTitleKey key, bool planned) =>
      _write('planned:$planned', LedgerTitleStatus(planned: planned));

  @override
  Future<bool> setCompleted(LedgerTitleKey key, bool completed) => _write(
    'completed:$completed',
    LedgerTitleStatus(completed: completed, started: completed),
  );

  @override
  Future<bool> setDropped(LedgerTitleKey key, bool dropped) =>
      _write('dropped:$dropped', LedgerTitleStatus(dropped: dropped));

  @override
  Future<bool> rate(LedgerTitleKey key, int? rating) =>
      _write('rate:$rating', LedgerTitleStatus(rating: rating));

  @override
  Future<bool> clearProgress(LedgerTitleKey key) =>
      _write('clear', const LedgerTitleStatus());
}

const LedgerTitleKey _key = (imdbId: 'tt1000001', contentType: 'series');

void main() {
  late _Gateway gateway;
  Object? scope;

  ProviderContainer container() {
    final c = ProviderContainer.test(
      overrides: [
        ledgerTitleGatewayProvider.overrideWithValue(gateway),
        ledgerSignInScopeProvider.overrideWithValue(() => scope),
      ],
    );
    // Keep the auto-disposed controller alive for the test.
    c.listen(ledgerTitleControllerProvider(_key), (_, _) {});
    return c;
  }

  setUp(() {
    gateway = _Gateway();
    scope = 'profile-a';
  });

  final provider = ledgerTitleControllerProvider(_key);

  test('signed out or an unsupported id offers no button', () async {
    gateway.connected = false;
    var c = container();
    expect((await c.read(provider.future)).available, isFalse);
    expect(gateway.reads, 0);

    gateway
      ..connected = true
      ..supported = false;
    c = container();
    expect((await c.read(provider.future)).available, isFalse);
    expect(gateway.reads, 0);
  });

  test('the label names the strongest status', () {
    expect(const LedgerTitleStatus().label, 'Not tracked');
    expect(const LedgerTitleStatus().tracked, isFalse);
    expect(const LedgerTitleStatus(rating: 7).label, 'Rated');
    expect(const LedgerTitleStatus(started: true).label, 'Watching');
    expect(
      const LedgerTitleStatus(planned: true, started: true).label,
      'Plan to Watch',
    );
    expect(
      const LedgerTitleStatus(planned: true, completed: true).label,
      'Completed',
    );
    expect(
      const LedgerTitleStatus(completed: true, dropped: true).label,
      'Dropped',
    );
  });

  test('a change is sent once and the status is read back', () async {
    final c = container();
    await c.read(provider.future);
    final controller = c.read(provider.notifier);

    expect(await controller.setPlanned(true), isTrue);
    expect(c.read(provider).value!.status.planned, isTrue);
    expect(await controller.setDropped(true), isTrue);
    expect(await controller.rate(8), isTrue);
    expect(await controller.setCompleted(true), isTrue);
    expect(await controller.clearProgress(), isTrue);

    expect(gateway.sent, [
      'planned:true',
      'dropped:true',
      'rate:8',
      'completed:true',
      'clear',
    ]);
    final state = c.read(provider).value!;
    expect(state.busy, isFalse);
    expect(state.status.tracked, isFalse);
  });

  test('a refused change reports false and keeps what is held', () async {
    gateway.held = const LedgerTitleStatus(planned: true);
    final c = container();
    await c.read(provider.future);
    gateway.accept = false;

    expect(await c.read(provider.notifier).setDropped(true), isFalse);
    final state = c.read(provider).value!;
    expect(state.status.planned, isTrue);
    expect(state.status.dropped, isFalse);
    expect(state.busy, isFalse);
  });

  test('a status that cannot be read keeps the last known one', () async {
    gateway.held = const LedgerTitleStatus(rating: 9);
    final c = container();
    await c.read(provider.future);

    gateway.held = null;
    gateway.changes.value++;
    await pumpEventQueue();
    expect(c.read(provider).value!.status.rating, 9);
  });

  test('a second change while one is running is not sent', () async {
    final c = container();
    await c.read(provider.future);
    final controller = c.read(provider.notifier);

    final gate = gateway.writeGate = Completer<void>();
    final first = controller.setPlanned(true);
    await pumpEventQueue();
    expect(c.read(provider).value!.busy, isTrue);
    expect(await controller.setDropped(true), isFalse);

    gate.complete();
    expect(await first, isTrue);
    expect(gateway.sent, ['planned:true']);
    expect(c.read(provider).value!.busy, isFalse);
  });

  test('an account change reloads, but not during our own change', () async {
    final c = container();
    await c.read(provider.future);
    final reads = gateway.reads;

    gateway.held = const LedgerTitleStatus(completed: true, started: true);
    gateway.changes.value++;
    await pumpEventQueue();
    expect(gateway.reads, reads + 1);
    expect(c.read(provider).value!.status.completed, isTrue);

    final gate = gateway.writeGate = Completer<void>();
    final change = c.read(provider.notifier).setPlanned(true);
    await pumpEventQueue();
    gateway.changes.value++;
    await pumpEventQueue();
    expect(gateway.reads, reads + 1, reason: 'the change reloads when done');
    gate.complete();
    await change;
    expect(gateway.reads, reads + 2);
  });

  test('an older reload cannot overwrite a newer change', () async {
    final c = container();
    await c.read(provider.future);
    final controller = c.read(provider.notifier);

    // A reload starts and stalls holding the old (empty) status.
    final stale = gateway.readGate = Completer<void>();
    gateway.changes.value++;
    await pumpEventQueue();

    expect(await controller.rate(6), isTrue);
    expect(c.read(provider).value!.status.rating, 6);

    stale.complete();
    await pumpEventQueue();
    final state = c.read(provider).value!;
    expect(state.status.rating, 6);
    expect(state.busy, isFalse);
  });

  test(
    'after a profile change the old profile\'s status is not kept',
    () async {
      gateway.held = const LedgerTitleStatus(planned: true);
      final c = container();
      await c.read(provider.future);

      final gate = gateway.writeGate = Completer<void>();
      final change = c.read(provider.notifier).rate(4);
      await pumpEventQueue();
      // The incoming profile's status cannot be read: nothing may be carried
      // over from the outgoing one.
      scope = 'profile-b';
      gateway.accept = false;
      gateway.held = null;
      gate.complete();
      await change;

      final state = c.read(provider).value!;
      expect(state.status.planned, isFalse);
      expect(state.status.tracked, isFalse);
      expect(state.busy, isFalse);
    },
  );

  test('leaving the page mid-change raises nothing', () async {
    final c = container();
    await c.read(provider.future);

    final gate = gateway.writeGate = Completer<void>();
    final change = c.read(provider.notifier).setPlanned(true);
    await pumpEventQueue();
    c.dispose();
    gate.complete();
    expect(await change, isTrue);
    gateway.changes.value++;
    await pumpEventQueue();
  });

  test('disposal stops listening to the account', () async {
    final c = container();
    await c.read(provider.future);
    final reads = gateway.reads;
    c.dispose();
    gateway.changes.value++;
    await pumpEventQueue();
    expect(gateway.reads, reads);
  });
}
