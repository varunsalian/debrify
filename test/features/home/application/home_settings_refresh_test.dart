import 'dart:async';
import 'package:debrify/features/home/application/home_configuration_changes.dart';
import 'package:debrify/features/home/application/home_settings_refresh.dart';
import 'package:flutter_test/flutter_test.dart';

const changedConfiguration = (
  changed: true,
  reloadBoard: true,
  reloadHero: false,
  reloadIptv: true,
);

class RefreshProbe {
  RefreshProbe(this.operation);
  final HomeSettingsRefresh operation;
  final events = <String>[];
  final guards = <bool Function()>[];
  String? blocked;
  String? failed;
  final barrier = Completer<void>();
  final arrived = Completer<void>();
  bool active = true;
  bool mergeChanged = true;
  HomeConfigurationChanges? configuration = changedConfiguration;
  void Function()? onReconcile;
  Future<void>? trailer;
  Future<void> step(String name, bool Function() current) async {
    events.add(name);
    guards.add(current);
    if (name == failed) throw StateError(name);
    if (name == blocked) {
      arrived.complete();
      await barrier.future;
    }
  }

  Future<void> run() => operation.run(
    isCurrent: () => active,
    refreshAppearance: (current) => step('appearance', current),
    refreshDisplay: (current) => step('display', current),
    refreshContinuation: (current) async {
      await step('continuation', current);
      return mergeChanged;
    },
    reconcileContinuation: () {
      events.add('reconcile');
      onReconcile?.call();
    },
    refreshTrailers: (current) async {
      await step('trailer', current);
      await trailer;
    },
    selectDefaultView: (current) => step('default', current),
    refreshConfiguration: (current) async {
      await step('configuration', current);
      return configuration;
    },
    applyConfiguration: (changes) {
      expect(changes, configuration);
      events.add('apply');
    },
  );
}

void main() {
  test(
    'ordered refresh keeps trailer completion independent and dispatches accepted effects',
    () async {
      final operation = HomeSettingsRefresh(isOwnerCurrent: () => true);
      final probe = RefreshProbe(operation);
      final trailer = Completer<void>();
      probe.trailer = trailer.future;
      await probe.run();
      expect(probe.events, [
        'appearance',
        'display',
        'continuation',
        'reconcile',
        'trailer',
        'default',
        'configuration',
        'apply',
      ]);
      expect(probe.guards.every((current) => current()), isTrue);
      trailer.complete();
    },
  );
  for (final configuration in [
    null,
    (changed: false, reloadBoard: false, reloadHero: false, reloadIptv: false),
  ]) {
    test(
      'unchanged/null configuration skips effects: $configuration',
      () async {
        final probe =
            RefreshProbe(HomeSettingsRefresh(isOwnerCurrent: () => true))
              ..mergeChanged = false
              ..configuration = configuration;
        await probe.run();
        expect(probe.events, [
          'appearance',
          'display',
          'continuation',
          'trailer',
          'default',
          'configuration',
        ]);
      },
    );
  }
  for (final stage in [
    'appearance',
    'display',
    'continuation',
    'default',
    'configuration',
  ]) {
    test('a newer refresh retires work awaiting $stage', () async {
      final operation = HomeSettingsRefresh(isOwnerCurrent: () => true);
      final old = RefreshProbe(operation)..blocked = stage;
      final pending = old.run();
      await old.arrived.future;
      final before = List.of(old.events);
      final newer = RefreshProbe(operation);
      await newer.run();
      old.barrier.complete();
      await pending;
      expect(old.events, before);
      expect(old.guards.every((current) => !current()), isTrue);
      expect(newer.events.last, 'apply');
    });
  }
  for (final reason in ['profile', 'view', 'dispose']) {
    test('$reason retires the first await and prevents later reads', () async {
      var owner = true;
      final operation = HomeSettingsRefresh(isOwnerCurrent: () => owner);
      final probe = RefreshProbe(operation)..blocked = 'appearance';
      final pending = probe.run();
      await probe.arrived.future;
      switch (reason) {
        case 'profile':
          owner = false;
        case 'view':
          probe.active = false;
        case 'dispose':
          operation.dispose();
      }
      probe.barrier.complete();
      await pending;
      await probe.run();
      expect(probe.events, ['appearance']);
      expect(probe.guards.single(), isFalse);
    });
  }
  test(
    'synchronous retirement during reconciliation prevents trailer/default work',
    () async {
      final operation = HomeSettingsRefresh(isOwnerCurrent: () => true);
      final probe = RefreshProbe(operation)..onReconcile = operation.dispose;
      await probe.run();
      expect(probe.events.last, 'reconcile');
    },
  );
  test('failure propagates and stops the remaining sequence', () async {
    final probe = RefreshProbe(HomeSettingsRefresh(isOwnerCurrent: () => true))
      ..failed = 'display';
    await expectLater(probe.run(), throwsStateError);
    expect(probe.events, ['appearance', 'display']);
  });
  test('a rejected call does not cancel an earlier current refresh', () async {
    final operation = HomeSettingsRefresh(isOwnerCurrent: () => true);
    final old = RefreshProbe(operation)..blocked = 'appearance';
    final pending = old.run();
    await old.arrived.future;
    final rejected = RefreshProbe(operation)..active = false;
    await rejected.run();
    old.barrier.complete();
    await pending;
    expect(rejected.events, isEmpty);
    expect(old.events.last, 'apply');
  });
}
