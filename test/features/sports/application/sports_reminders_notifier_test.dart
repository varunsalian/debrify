import 'dart:async';

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/data/sports_reminder_store.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/models/sports_reminder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 11, 8, 12);

final class _MemoryPrefs implements SportsPrefs {
  final Map<String, Object> values = {};
  int writes = 0;
  Object? failWrites;

  @override
  List<String>? getStringList(String key) => values[key] as List<String>?;
  @override
  Future<bool> setStringList(String key, List<String> value) async {
    if (failWrites case final error?) throw error;
    writes++;
    values[key] = List.of(value);
    return true;
  }

  @override
  bool? getBool(String key) => values[key] as bool?;
  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }
}

final class _FakeScheduler implements SportsReminderScheduler {
  _FakeScheduler({this.isSupported = true});

  @override
  final bool isSupported;
  bool grant = true;
  int permissionAsks = 0;
  void Function()? duringPrompt;
  final List<List<SportsReminderAlert>> syncs = [];

  @override
  Future<bool> ensurePermission() async {
    permissionAsks++;
    duringPrompt?.call();
    return grant;
  }

  @override
  Future<void> replaceAll(List<SportsReminderAlert> alerts) async {
    syncs.add(List.of(alerts));
  }
}

SportsEvent _game(String id, {Duration fromNow = const Duration(hours: 2)}) =>
    SportsEvent(
      id: id,
      leagueId: 'epl',
      start: _now.add(fromNow),
      status: SportsEventStatus.scheduled,
      home: const SportsTeam(
        id: '1',
        name: 'Arsenal',
        shortName: 'Arsenal',
        abbreviation: 'ARS',
      ),
      away: const SportsTeam(
        id: '2',
        name: 'Spurs',
        shortName: 'Spurs',
        abbreviation: 'TOT',
      ),
    );

void main() {
  late Map<String, _MemoryPrefs> profiles;
  late String owner;
  late ChangeNotifier profileChanges;
  late _FakeScheduler scheduler;
  late ProviderContainer container;

  Future<void>? readGate;

  ProviderContainer build({_FakeScheduler? withScheduler}) {
    scheduler = withScheduler ?? _FakeScheduler();
    return ProviderContainer(
      overrides: [
        sportsReminderStoreProvider.overrideWithValue(
          SportsReminderStore(() async {
            // Resolved per operation, like the app's profile preferences.
            final prefs = profiles[owner]!;
            if (readGate case final gate?) await gate;
            return prefs;
          }),
        ),
        sportsReminderSchedulerProvider.overrideWithValue(scheduler),
        sportsReminderClockProvider.overrideWithValue(() => _now),
        sportsProfileOwnerProvider.overrideWithValue(() => owner),
        sportsProfileChangesProvider.overrideWithValue(profileChanges),
      ],
    );
  }

  setUp(() {
    profiles = {'a': _MemoryPrefs(), 'b': _MemoryPrefs()};
    owner = 'a';
    profileChanges = ChangeNotifier();
    container = build();
  });

  tearDown(() {
    container.dispose();
    profileChanges.dispose();
  });

  SportsRemindersNotifier notifier() =>
      container.read(sportsRemindersProvider.notifier);

  test('loading schedules due reminders and writes nothing', () async {
    profiles['a']!.values[SportsReminderStore.remindersKey] = [
      SportsReminder(
        eventKey: 'epl:old',
        start: _now.subtract(const Duration(hours: 8)),
        title: 'Old',
        league: '',
      ).encode(),
      SportsReminder(
        eventKey: 'epl:next',
        start: _now.add(const Duration(hours: 1)),
        title: 'Next',
        league: '',
      ).encode(),
    ];
    final loaded = await container.read(sportsRemindersProvider.future);
    expect(loaded.map((r) => r.eventKey), ['epl:next']);
    expect(scheduler.syncs.single.single.id, 'epl:next');
    expect(profiles['a']!.writes, 0, reason: 'a load never writes storage');
  });

  test(
    'a switch while loading never schedules or copies the old profile',
    () async {
      profiles['a']!.values[SportsReminderStore.remindersKey] = [
        SportsReminder(
          eventKey: 'epl:a1',
          start: _now.add(const Duration(hours: 1)),
          title: 'A game',
          league: '',
        ).encode(),
      ];
      final gate = Completer<void>();
      readGate = gate.future;
      final sub = container.listen(sportsRemindersProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      owner = 'b';
      profileChanges.notifyListeners();
      readGate = null;
      gate.complete();
      final loaded = await container.read(sportsRemindersProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(loaded, isEmpty);
      expect(
        scheduler.syncs.expand((alerts) => alerts).map((a) => a.id),
        isNot(contains('epl:a1')),
      );
      expect(profiles['b']!.writes, 0);
      sub.close();
    },
  );

  test('a switch during the permission prompt stores nothing', () async {
    await container.read(sportsRemindersProvider.future);
    final sub = container.listen(sportsRemindersProvider, (_, _) {});
    scheduler.duringPrompt = () {
      owner = 'b';
      profileChanges.notifyListeners();
    };
    expect(await notifier().toggle(_game('7')), SportsReminderToggle.failed);
    expect(profiles['a']!.writes, 0);
    expect(profiles['b']!.writes, 0);
    sub.close();
  });

  test('failing storage reports failure and sets no reminder', () async {
    await container.read(sportsRemindersProvider.future);
    profiles['a']!.failWrites = StateError('stale preferences');
    expect(await notifier().toggle(_game('7')), SportsReminderToggle.failed);
    expect(notifier().isSet(_game('7')), isFalse);
    expect(scheduler.syncs, hasLength(1), reason: 'only the load synced');
    profiles['a']!.failWrites = null;
    expect(
      await notifier().toggle(_game('7')),
      SportsReminderToggle.added,
      reason: 'a failure does not stall later toggles',
    );
  });

  test('a toggle asks permission, stores and schedules the game', () async {
    await container.read(sportsRemindersProvider.future);
    final outcome = await notifier().toggle(_game('7'));
    expect(outcome, SportsReminderToggle.added);
    expect(scheduler.permissionAsks, 1);
    expect(notifier().isSet(_game('7')), isTrue);
    final alert = scheduler.syncs.last.single;
    expect(alert.title, 'Arsenal v Spurs');
    expect(alert.body, 'Starts in 15 minutes · Premier League');
    expect(alert.fireAt, _now.add(const Duration(minutes: 105)));
    expect(
      container.read(sportsRemindersProvider).value!.single.eventKey,
      'epl:7',
    );

    expect(await notifier().toggle(_game('7')), SportsReminderToggle.removed);
    expect(scheduler.permissionAsks, 1, reason: 'removing never asks');
    expect(scheduler.syncs.last, isEmpty);
    expect(profiles['a']!.values[SportsReminderStore.remindersKey], isEmpty);
  });

  test('a refused permission stores nothing', () async {
    await container.read(sportsRemindersProvider.future);
    scheduler.grant = false;
    expect(
      await notifier().toggle(_game('7')),
      SportsReminderToggle.permissionDenied,
    );
    expect(notifier().isSet(_game('7')), isFalse);
    expect(profiles['a']!.writes, 0);
  });

  test('too close to kick-off is unavailable without a prompt', () async {
    await container.read(sportsRemindersProvider.future);
    expect(
      await notifier().toggle(_game('7', fromNow: const Duration(minutes: 10))),
      SportsReminderToggle.unavailable,
    );
    expect(scheduler.permissionAsks, 0);
  });

  test('a profile switch schedules only the new profile\'s games', () async {
    await container.read(sportsRemindersProvider.future);
    await notifier().toggle(_game('a1'));
    profiles['b']!.values[SportsReminderStore.remindersKey] = [
      SportsReminder(
        eventKey: 'epl:b1',
        start: _now.add(const Duration(hours: 3)),
        title: 'B game',
        league: '',
      ).encode(),
    ];
    final sub = container.listen(sportsRemindersProvider, (_, _) {});
    owner = 'b';
    profileChanges.notifyListeners();
    final loaded = await container.read(sportsRemindersProvider.future);
    expect(loaded.single.eventKey, 'epl:b1');
    expect(scheduler.syncs.last.map((a) => a.id), ['epl:b1']);
    expect(notifier().isSet(_game('a1')), isFalse);
    sub.close();
  });

  test(
    'a toggle made before a switch never lands in the new profile',
    () async {
      await container.read(sportsRemindersProvider.future);
      final sub = container.listen(sportsRemindersProvider, (_, _) {});
      owner = 'b'; // switched, change not yet delivered
      expect(await notifier().toggle(_game('7')), SportsReminderToggle.failed);
      expect(profiles['b']!.writes, 0);
      expect(profiles['a']!.writes, 0);
      sub.close();
    },
  );

  test('fresh fixtures move a reminder to its new kick-off', () async {
    await container.read(sportsRemindersProvider.future);
    await notifier().toggle(_game('7'));
    await notifier().reconcile([_game('7', fromNow: const Duration(hours: 5))]);
    expect(
      scheduler.syncs.last.single.fireAt,
      _now.add(const Duration(hours: 5) - const Duration(minutes: 15)),
    );
  });

  test('an unsupported device never reads storage or schedules', () async {
    container.dispose();
    container = build(withScheduler: _FakeScheduler(isSupported: false));
    expect(await container.read(sportsRemindersProvider.future), isEmpty);
    expect(
      await notifier().toggle(_game('7')),
      SportsReminderToggle.unavailable,
    );
    expect(scheduler.syncs, isEmpty);
    expect(profiles['a']!.writes, 0);
  });
}
