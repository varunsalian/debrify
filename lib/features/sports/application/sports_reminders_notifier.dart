// Application layer: owns the active profile's kick-off reminders, their
// persistence, and keeping the device's scheduled alerts in step with them.
//
// The device holds one set of alerts: the active profile's. Every (re)build
// reads that profile's reminders and replaces the scheduled set, so a
// profile switch silences the previous profile's games and arms the new
// one's. That device sync is the only side effect of a build: it is
// idempotent, and storage is written only by an explicit toggle or a board
// refresh. Writes are chained like the league filter's, and a write made in
// one profile never lands in another (see [SportsLeagueFilterNotifier]).
//
// Riverpod reuses this object across rebuilds and `ref.mounted` stays true
// through them, so a load checks its own [_generation] instead.
import 'dart:async';

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/application/sports_reminder_plan.dart';
import 'package:debrify/features/sports/data/sports_reminder_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/models/sports_reminder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a reminder toggle did.
enum SportsReminderToggle {
  added,
  removed,
  permissionDenied,
  unavailable,

  /// Not saved: storage failed, or the profile changed meanwhile.
  failed,
}

final class SportsRemindersNotifier
    extends AsyncNotifier<List<SportsReminder>> {
  /// The reminders as they stand inside this notifier; see the league
  /// filter notifier for why the write chain keeps its own copy.
  List<SportsReminder> _current = const [];

  SportsReminderStore? _store;
  SportsReminderScheduler? _scheduler;
  DateTime Function() _now = DateTime.now;
  Object? Function()? _ownerOf;
  Object? _owner;
  Listenable? _changes;
  VoidCallback? _onChanged;

  Future<void> _pending = Future<void>.value();

  /// Bumped by every build; a load from an older build publishes nothing.
  int _generation = 0;

  @override
  Future<List<SportsReminder>> build() {
    final generation = ++_generation;
    _removeProfileListener();
    final scheduler = ref.read(sportsReminderSchedulerProvider);
    _scheduler = scheduler;
    _now = ref.read(sportsReminderClockProvider);
    final ownerOf = ref.read(sportsProfileOwnerProvider);
    _ownerOf = ownerOf;
    _owner = ownerOf();
    _current = const [];
    if (!scheduler.isSupported) {
      _store = null;
      return Future.value(const []);
    }
    final store = ref.read(sportsReminderStoreProvider);
    _store = store;
    final changes = ref.read(sportsProfileChangesProvider);
    _changes = changes;
    if (changes != null) {
      void onChanged() => ref.invalidateSelf();
      _onChanged = onChanged;
      changes.addListener(onChanged);
    }
    ref.onDispose(_removeProfileListener);

    final read = _pending.then(
      (_) => _readCurrent(store, scheduler, generation),
    );
    _pending = read.then((_) {}, onError: (_) {});
    return read;
  }

  Future<List<SportsReminder>> _readCurrent(
    SportsReminderStore store,
    SportsReminderScheduler scheduler,
    int generation,
  ) async {
    bool current() => ref.mounted && generation == _generation;
    if (!current()) return const [];
    final stored = await store.read();
    // A switch, cancellation or disposal while reading must not publish or
    // schedule the old profile's games. Games long over are left in storage
    // (the plan ignores them) until the next toggle or refresh rewrites it.
    if (!current()) return const [];
    final due = sportsRemindersStillDue(stored, _now());
    _current = due;
    await _sync(scheduler, due);
    return due;
  }

  /// Whether [event] has a reminder.
  bool isSet(SportsEvent event) {
    final key = SportsReminder.keyOf(event);
    return _current.any((reminder) => reminder.eventKey == key);
  }

  /// Adds or removes the reminder for [event]. Adding asks for notification
  /// permission first and stores nothing if it is refused.
  Future<SportsReminderToggle> toggle(SportsEvent event) async {
    final scheduler = _scheduler;
    if (scheduler == null || !scheduler.isSupported) {
      return SportsReminderToggle.unavailable;
    }
    // The profile the tap was made in, captured before the permission
    // prompt: a switch during the prompt makes the write stale.
    final origin = _ownerOf?.call();
    final builtFor = _owner;
    final key = SportsReminder.keyOf(event);
    final adding = !isSet(event);
    if (adding) {
      if (!sportsReminderAvailable(event, _now())) {
        return SportsReminderToggle.unavailable;
      }
      if (!await scheduler.ensurePermission()) {
        return SportsReminderToggle.permissionDenied;
      }
    }
    final applied = await _enqueue(
      (list) => [
        for (final reminder in list)
          if (reminder.eventKey != key) reminder,
        if (adding)
          SportsReminder(
            eventKey: key,
            start: event.start.toUtc(),
            title: event.displayTitle,
            league: sportsLeagueById(event.leagueId)?.name ?? '',
          ),
      ],
      origin: origin,
      builtFor: builtFor,
    );
    if (!applied) return SportsReminderToggle.failed;
    return adding ? SportsReminderToggle.added : SportsReminderToggle.removed;
  }

  /// Follows the board's latest fixtures: a moved kick-off moves its alert,
  /// a postponed or finished game drops it.
  Future<void> reconcile(List<SportsEvent> events) async {
    if (_store == null) return;
    await _enqueue(
      (list) => reconcileSportsReminders(list, events),
      origin: _ownerOf?.call(),
      builtFor: _owner,
    );
  }

  /// Appends one change to the write chain. [update] returns null when it
  /// changes nothing, which skips the write and the re-plan. Completes with
  /// whether the change now stands; failures are logged, never thrown.
  Future<bool> _enqueue(
    List<SportsReminder>? Function(List<SportsReminder> list) update, {
    required Object? origin,
    required Object? builtFor,
  }) {
    final write = _pending
        .then((_) => _writeLatest(update, origin: origin, builtFor: builtFor))
        .catchError((Object error) {
          debugPrint(
            '[SportsReminders] event=write_failed error=${error.runtimeType}',
          );
          return false;
        });
    _pending = write.then((_) {});
    return write;
  }

  Future<bool> _writeLatest(
    List<SportsReminder>? Function(List<SportsReminder> list) update, {
    required Object? origin,
    required Object? builtFor,
  }) async {
    if (!ref.mounted) return false;
    final store = _store;
    final scheduler = _scheduler;
    final ownerOf = _ownerOf;
    if (store == null || scheduler == null || ownerOf == null) return false;
    if (ownerOf() != origin || origin != builtFor || _owner != builtFor) {
      if (_owner == builtFor) ref.invalidateSelf();
      return false;
    }
    final next = update(_current);
    if (next == null) return true;
    // Stored first: a failed write leaves neither the bell nor an alert.
    await store.write(next);
    _current = next;
    state = AsyncData(next);
    await _sync(scheduler, next);
    return true;
  }

  /// Scheduling failures are logged, never thrown: the stored reminders
  /// stay, and the next change or app start re-plans them.
  Future<void> _sync(
    SportsReminderScheduler scheduler,
    List<SportsReminder> reminders,
  ) async {
    try {
      await scheduler.replaceAll(planSportsReminderAlerts(reminders, _now()));
    } catch (error) {
      debugPrint(
        '[SportsReminders] event=schedule_failed '
        'error=${error.runtimeType} count=${reminders.length}',
      );
    }
  }

  void _removeProfileListener() {
    final changes = _changes;
    final onChanged = _onChanged;
    _changes = null;
    _onChanged = null;
    if (changes != null && onChanged != null) {
      changes.removeListener(onChanged);
    }
  }
}
