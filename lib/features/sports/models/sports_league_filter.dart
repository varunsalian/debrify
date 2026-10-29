// The league on/off choices the board filters its catalog with.
//
// Model layer: a plain immutable value. A league is enabled when the user's
// explicit choice says so; a choice that equals the league's default lives in
// neither set, so the persisted shape stays tiny (see withLeague).
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';

/// Explicit on/off overrides keyed by league id.
@immutable
final class SportsLeagueFilter {
  const SportsLeagueFilter({this.on = const {}, this.off = const {}});

  /// Enabled although off by default.
  final Set<String> on;

  /// Disabled although on by default.
  final Set<String> off;

  /// Off wins, then on, then the league's own default.
  bool isEnabled(SportsLeague league) {
    if (off.contains(league.id)) return false;
    if (on.contains(league.id)) return true;
    return league.enabledByDefault;
  }

  /// A copy where [league] is switched to [enabled].
  ///
  /// Normalised: a choice equal to the league's default is stored in neither
  /// set, so toggling back to the default erases the override.
  SportsLeagueFilter withLeague(SportsLeague league, bool enabled) {
    if (enabled == league.enabledByDefault) {
      return SportsLeagueFilter(
        on: {...on}..remove(league.id),
        off: {...off}..remove(league.id),
      );
    }
    // Only this league's entry changes; every other choice is kept.
    if (league.enabledByDefault) {
      return SportsLeagueFilter(
        on: {...on}..remove(league.id),
        off: {...off, league.id},
      );
    }
    return SportsLeagueFilter(
      on: {...on, league.id},
      off: {...off}..remove(league.id),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsLeagueFilter &&
          setEquals(other.on, on) &&
          setEquals(other.off, off));

  @override
  // Order-independent, like the set equality above.
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(on), Object.hashAllUnordered(off));

  @override
  String toString() =>
      'SportsLeagueFilter(on: ${on.length}, off: ${off.length})';
}

/// The catalog leagues the filter keeps, in catalog order.
List<SportsLeague> enabledSportsLeagues(
  List<SportsLeague> catalog,
  SportsLeagueFilter filter,
) => [
  for (final league in catalog)
    if (filter.isEnabled(league)) league,
];
