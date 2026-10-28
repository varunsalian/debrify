// Persisted follow choices for the sports board.
//
// Data layer: the store owns the serialized shape (two string lists plus one
// bool) and nothing else. Persistence is reached through the narrow
// [SportsPrefs] contract, which is resolved per operation so the composition
// boundary can hand over the storage of the currently active profile instead
// of letting a stale reference write into the wrong one.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter/foundation.dart';

/// Leagues, teams and score-hiding the user opted into.
///
/// Team keys are `'<leagueId>:<teamId>'` (see [SportsTeam.keyIn]), so the same
/// club followed in two competitions is two independent keys.
@immutable
class SportsFollows {
  const SportsFollows({
    this.leagueIds = const {},
    this.teamKeys = const {},
    this.hideScores = false,
  });

  /// Followed league ids, e.g. `{'ucl', 'nba'}`.
  final Set<String> leagueIds;

  /// Followed team keys, e.g. `{'ucl:1'}`.
  final Set<String> teamKeys;

  /// Whether scores stay hidden on the board.
  final bool hideScores;

  /// True when the event's league is followed, or either competitor is.
  bool followsEvent(SportsEvent event) {
    if (leagueIds.contains(event.leagueId)) return true;
    if (teamKeys.isEmpty) return false;
    final home = event.home;
    if (home != null && teamKeys.contains(home.keyIn(event.leagueId))) {
      return true;
    }
    final away = event.away;
    return away != null && teamKeys.contains(away.keyIn(event.leagueId));
  }

  /// A copy with the supplied fields replaced; null fields keep their value.
  SportsFollows copyWith({
    Set<String>? leagueIds,
    Set<String>? teamKeys,
    bool? hideScores,
  }) => SportsFollows(
    leagueIds: leagueIds ?? this.leagueIds,
    teamKeys: teamKeys ?? this.teamKeys,
    hideScores: hideScores ?? this.hideScores,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsFollows &&
          setEquals(other.leagueIds, leagueIds) &&
          setEquals(other.teamKeys, teamKeys) &&
          other.hideScores == hideScores);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(_sorted(leagueIds)),
    Object.hashAll(_sorted(teamKeys)),
    hideScores,
  );

  @override
  String toString() =>
      'SportsFollows(leagues: ${leagueIds.length}, '
      'teams: ${teamKeys.length}, hideScores: $hideScores)';
}

/// The key/value slice [SportsFollowStore] needs from local storage.
abstract interface class SportsPrefs {
  /// Stored list, or null when the key was never written.
  List<String>? getStringList(String key);

  Future<bool> setStringList(String key, List<String> value);

  /// Stored flag, or null when the key was never written.
  bool? getBool(String key);

  Future<bool> setBool(String key, bool value);
}

/// Reads and writes the board's follow state.
///
/// [read] never fails on missing keys: an untouched device reads back as
/// "follows nothing, show scores". [write] stores lists sorted ascending so
/// the stored bytes do not churn when a follow is toggled.
final class SportsFollowStore {
  SportsFollowStore(this._prefs);

  final Future<SportsPrefs> Function() _prefs;

  static const leaguesKey = 'sports_followed_leagues';
  static const teamsKey = 'sports_followed_teams';
  static const hideScoresKey = 'sports_hide_scores';

  Future<SportsFollows> read() async {
    final prefs = await _prefs();
    return SportsFollows(
      leagueIds: {...?prefs.getStringList(leaguesKey)},
      teamKeys: {...?prefs.getStringList(teamsKey)},
      hideScores: prefs.getBool(hideScoresKey) ?? false,
    );
  }

  Future<void> write(SportsFollows follows) async {
    final prefs = await _prefs();
    await prefs.setStringList(leaguesKey, _sorted(follows.leagueIds));
    await prefs.setStringList(teamsKey, _sorted(follows.teamKeys));
    await prefs.setBool(hideScoresKey, follows.hideScores);
  }
}

List<String> _sorted(Iterable<String> values) => [...values]..sort();
