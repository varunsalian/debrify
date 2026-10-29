// Application layer: owns the league on/off choices and their persistence.
//
// The notifier reads the stored filter when the board first needs it, keeps
// the in-memory filter in sync with every toggle, and drops work that no
// longer belongs to the active profile. Writes are chained so rapid toggles
// apply in call order, each starting from the latest choices.
//
// Two Riverpod 3 details shape the code:
// - The providers read here declare no `dependencies`, which is what allows
//   an app-wide notifier to read them; a read of a provider that could be
//   scoped is rejected.
// - A `state =` that lands while `build()` is still pending is dropped, so
//   the write chain waits for the first read to settle before publishing.
import 'dart:async';

import 'package:debrify/features/sports/application/sports_providers.dart';
import 'package:debrify/features/sports/data/sports_league_filter_store.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Deliberate re-export: the filter type is what every caller of these
// providers passes around, and exposing it here means an import of this file
// is never "unused" even when a caller only reaches the notifier through it.
// ignore_for_file: unnecessary_import
export 'package:debrify/features/sports/models/sports_league_filter.dart';

/// Owns the board's [SportsLeagueFilter].
final class SportsLeagueFilterNotifier
    extends AsyncNotifier<SportsLeagueFilter> {
  /// The choices as they stand inside this notifier. They match the
  /// published state once the first read has settled; while a reload is in
  /// flight the published state is a loading value, so the write chain needs
  /// its own copy.
  SportsLeagueFilter _current = const SportsLeagueFilter();

  SportsLeagueFilterStore? _store;
  Object? Function()? _ownerOf;
  Object? _owner;
  Listenable? _changes;
  VoidCallback? _onChanged;

  /// One slot so a new generation never runs beside the previous one: the
  /// first read reserves it and every later write queues behind it.
  Future<void> _pending = Future<void>.value();

  @override
  Future<SportsLeagueFilter> build() {
    // Drop the previous generation's listener before adding the new one, so a
    // reload cannot stack listeners on the profile signal.
    _removeProfileListener();

    final store = ref.read(sportsLeagueFilterStoreProvider);
    _store = store;
    final ownerOf = ref.read(sportsProfileOwnerProvider);
    _ownerOf = ownerOf;
    _owner = ownerOf();
    final changes = ref.read(sportsProfileChangesProvider);
    _changes = changes;
    if (changes != null) {
      void onChanged() => ref.invalidateSelf();
      _onChanged = onChanged;
      changes.addListener(onChanged);
    }
    ref.onDispose(_removeProfileListener);

    final read = _pending.then((_) => _readCurrent(store));
    _pending = read.then((_) {}, onError: (_) {});
    return read;
  }

  Future<SportsLeagueFilter> _readCurrent(SportsLeagueFilterStore store) async {
    if (!ref.mounted) return _current;
    final filter = await store.read();
    // A profile switch, a cancellation or a disposal may have happened while
    // the store was reading; none of them may publish the old profile's data.
    if (!ref.mounted) return filter;
    _current = filter;
    return filter;
  }

  /// Switches one league and stores the new choices.
  Future<void> setLeague(SportsLeague league, bool enabled) =>
      mutate((filter) => filter.withLeague(league, enabled));

  /// Switches every catalog league of [sport] and stores the new choices.
  Future<void> setSport(SportKind sport, bool enabled) => mutate((filter) {
    var next = filter;
    for (final league in kSportsLeagues) {
      if (league.sport == sport) {
        next = next.withLeague(league, enabled);
      }
    }
    return next;
  });

  /// Drops every choice and stores the empty filter.
  Future<void> reset() => mutate((_) => const SportsLeagueFilter());

  /// Appends one change to the write chain, so concurrent toggles apply in
  /// call order and each starts from the latest choices.
  Future<void> mutate(
    SportsLeagueFilter Function(SportsLeagueFilter filter) update,
  ) {
    final write = _pending.then((_) => _writeLatest(update));
    // Keep the chain alive when one write fails: broken storage must not
    // stall later toggles, whose own errors the caller sees.
    _pending = write.then((_) {}, onError: (_) {});
    return write;
  }

  Future<void> _writeLatest(
    SportsLeagueFilter Function(SportsLeagueFilter filter) update,
  ) async {
    if (!ref.mounted) return;
    final store = _store;
    final ownerOf = _ownerOf;
    if (store == null || ownerOf == null) return;
    // The profile may have changed while the earlier writes were in flight.
    if (ownerOf() != _owner) {
      // Stale action: touch no storage and let the next read serve the new
      // profile instead.
      ref.invalidateSelf();
      return;
    }
    final next = update(_current);
    _current = next;
    state = AsyncData(next);
    await store.write(next);
  }

  /// Stops listening to the profile signal; see [_changes].
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
