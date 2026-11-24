// Immutable models for one match's stats page: win probability, team stat
// comparison, leaders and recent form.
//
// Pure Dart: only `package:flutter/foundation.dart` is allowed here (for
// `@immutable` and `listEquals`). No UI, data or application imports. Value
// equality lets a live refresh that brings nothing new skip the rebuild.
import 'package:flutter/foundation.dart';

import 'sports_models.dart';

/// Which match a stats request is for: the league picks the feed path, the
/// event id picks the game. Stable equality, so it can key a provider family.
@immutable
class SportsMatchKey {
  const SportsMatchKey({required this.leagueId, required this.eventId});

  final String leagueId;
  final String eventId;

  @override
  bool operator ==(Object other) =>
      other is SportsMatchKey &&
      other.leagueId == leagueId &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(leagueId, eventId);

  @override
  String toString() => 'SportsMatchKey($leagueId, $eventId)';
}

/// One side of the match as the summary reports it.
@immutable
class SportsMatchSide {
  const SportsMatchSide({
    required this.teamId,
    required this.abbreviation,
    required this.name,
    this.logoUrl,
    this.color,
    this.alternateColor,
    this.score,
    this.record,
  });

  final String teamId;
  final String abbreviation;
  final String name;
  final String? logoUrl;

  /// ARGB, e.g. `0xFF0076B6`.
  final int? color;
  final int? alternateColor;

  /// Text as the feed sends it; null before kick-off.
  final String? score;

  /// Overall record, e.g. `'8-2'`.
  final String? record;

  @override
  bool operator ==(Object other) =>
      other is SportsMatchSide &&
      other.teamId == teamId &&
      other.abbreviation == abbreviation &&
      other.name == name &&
      other.logoUrl == logoUrl &&
      other.color == color &&
      other.alternateColor == alternateColor &&
      other.score == score &&
      other.record == record;

  @override
  int get hashCode => Object.hash(
    teamId,
    abbreviation,
    name,
    logoUrl,
    color,
    alternateColor,
    score,
    record,
  );
}

/// One team statistic for both sides, paired by the feed's stat name.
@immutable
class SportsTeamStat {
  const SportsTeamStat({
    required this.name,
    required this.label,
    required this.homeText,
    required this.awayText,
    this.homeValue,
    this.awayValue,
  });

  /// Feed key, e.g. `'totalYards'`; grouped feeds prefix the group
  /// (`'batting.hits'`).
  final String name;

  /// The feed's own label, e.g. `'Total Yards'`.
  final String label;
  final String homeText;
  final String awayText;

  /// Numeric reading for comparison bars; null when the text has none.
  final double? homeValue;
  final double? awayValue;

  @override
  bool operator ==(Object other) =>
      other is SportsTeamStat &&
      other.name == name &&
      other.label == label &&
      other.homeText == homeText &&
      other.awayText == awayText &&
      other.homeValue == homeValue &&
      other.awayValue == awayValue;

  @override
  int get hashCode =>
      Object.hash(name, label, homeText, awayText, homeValue, awayValue);
}

/// The top player of one side in one category.
@immutable
class SportsLeader {
  const SportsLeader({
    required this.name,
    required this.summary,
    this.shortName,
    this.headshotUrl,
  });

  final String name;
  final String? shortName;

  /// The stat line, e.g. `'21/27, 194 YDS, 3 TD'`.
  final String summary;
  final String? headshotUrl;

  @override
  bool operator ==(Object other) =>
      other is SportsLeader &&
      other.name == name &&
      other.shortName == shortName &&
      other.summary == summary &&
      other.headshotUrl == headshotUrl;

  @override
  int get hashCode => Object.hash(name, shortName, summary, headshotUrl);
}

/// One leader category with each side's leader (either may be missing).
@immutable
class SportsLeaderPair {
  const SportsLeaderPair({required this.category, this.home, this.away});

  /// e.g. `'Passing Yards'`.
  final String category;
  final SportsLeader? home;
  final SportsLeader? away;

  @override
  bool operator ==(Object other) =>
      other is SportsLeaderPair &&
      other.category == category &&
      other.home == home &&
      other.away == away;

  @override
  int get hashCode => Object.hash(category, home, away);
}

enum SportsFormResult { win, loss, draw }

/// One recent game of a side, newest last.
@immutable
class SportsFormGame {
  const SportsFormGame({
    required this.result,
    required this.score,
    required this.home,
    required this.opponentAbbreviation,
    this.opponentLogoUrl,
  });

  final SportsFormResult result;

  /// As the feed writes it, e.g. `'20-17'`.
  final String score;

  /// True when the side was at home ("vs"), false away ("@").
  final bool home;
  final String opponentAbbreviation;
  final String? opponentLogoUrl;

  @override
  bool operator ==(Object other) =>
      other is SportsFormGame &&
      other.result == result &&
      other.score == score &&
      other.home == home &&
      other.opponentAbbreviation == opponentAbbreviation &&
      other.opponentLogoUrl == opponentLogoUrl;

  @override
  int get hashCode =>
      Object.hash(result, score, home, opponentAbbreviation, opponentLogoUrl);
}

/// Pre-game chances from the feed's matchup predictor, in percent.
@immutable
class SportsMatchPrediction {
  const SportsMatchPrediction({required this.home, required this.away});

  final double home;
  final double away;

  @override
  bool operator ==(Object other) =>
      other is SportsMatchPrediction &&
      other.home == home &&
      other.away == away;

  @override
  int get hashCode => Object.hash(home, away);
}

/// Everything the stats page shows for one match. Sections the feed does not
/// carry for this sport or state are empty (or null), never invented.
@immutable
class SportsMatchStats {
  const SportsMatchStats({
    required this.status,
    required this.statusDetail,
    required this.home,
    required this.away,
    this.started = true,
    this.start,
    this.winProbability = const [],
    this.prediction,
    this.teamStats = const [],
    this.leaders = const [],
    this.homeForm = const [],
    this.awayForm = const [],
  });

  final SportsEventStatus status;

  /// Whether play has begun (ESPN state past `pre`). A delayed or postponed
  /// match that never kicked off is not started.
  final bool started;

  /// Scheduled kick-off, UTC; null when the feed does not say.
  final DateTime? start;

  /// e.g. `'Final'`, `'Q3 5:12'`, `'Thu, November 26th at 12:30 PM EST'`.
  final String statusDetail;
  final SportsMatchSide home;
  final SportsMatchSide away;

  /// The home side's chance to win after each play, 0–1, oldest first.
  final List<double> winProbability;
  final SportsMatchPrediction? prediction;

  /// Game totals once play starts; season averages before it.
  final List<SportsTeamStat> teamStats;
  final List<SportsLeaderPair> leaders;
  final List<SportsFormGame> homeForm;
  final List<SportsFormGame> awayForm;

  /// Whether the stats describe the season so far rather than this game.
  bool get isPreview => !started;

  /// A chart needs two points; a predictor stands in before kick-off.
  bool get hasWinProbability =>
      winProbability.length >= 2 || prediction != null;

  bool get hasContent =>
      hasWinProbability ||
      teamStats.isNotEmpty ||
      leaders.isNotEmpty ||
      homeForm.isNotEmpty ||
      awayForm.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SportsMatchStats &&
          other.status == status &&
          other.started == started &&
          other.start == start &&
          other.statusDetail == statusDetail &&
          other.home == home &&
          other.away == away &&
          listEquals(other.winProbability, winProbability) &&
          other.prediction == prediction &&
          listEquals(other.teamStats, teamStats) &&
          listEquals(other.leaders, leaders) &&
          listEquals(other.homeForm, homeForm) &&
          listEquals(other.awayForm, awayForm));

  @override
  int get hashCode => Object.hash(
    status,
    started,
    start,
    statusDetail,
    home,
    away,
    Object.hashAll(winProbability),
    prediction,
    Object.hashAll(teamStats),
    Object.hashAll(leaders),
    Object.hashAll(homeForm),
    Object.hashAll(awayForm),
  );
}
