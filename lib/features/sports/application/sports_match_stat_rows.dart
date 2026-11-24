// Which team stats the stats page compares, in what order, under what label.
//
// Application layer, pure: the feed sends 4 to 28 stats per side depending on
// sport and game state, many of them noise on a TV ("Total technical fouls").
// Each sport gets a short curated list for game totals and one for season
// averages; when none of a list's stats are present (a league we have no list
// for, or a feed that renamed its keys) the feed's own first stats are shown
// under its own labels rather than an empty card.
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// One comparison row: both sides' text, and the numbers its bars draw
/// (null when the stat is not comparable, e.g. a streak).
class SportsStatRow {
  const SportsStatRow({
    required this.label,
    required this.homeText,
    required this.awayText,
    this.homeValue,
    this.awayValue,
    this.lowerIsBetter = false,
  });

  final String label;
  final String homeText;
  final String awayText;
  final double? homeValue;
  final double? awayValue;

  /// Fewer is the better side (turnovers, fouls, points allowed).
  final bool lowerIsBetter;

  bool get hasBars => homeValue != null && awayValue != null;

  /// The side this stat favours: true home, false away, null level or not
  /// comparable.
  bool? get homeAhead {
    final home = homeValue;
    final away = awayValue;
    if (home == null || away == null || home == away) return null;
    return lowerIsBetter ? home < away : home > away;
  }

  @override
  String toString() => 'SportsStatRow($label: $homeText | $awayText)';
}

/// The fallback shows at most this many of the feed's own stats.
const int _fallbackRows = 8;

enum _Format {
  /// As the feed writes it.
  plain,

  /// A percentage the feed writes as 0–100 without the sign: `48` → `48%`.
  percent,

  /// Text only: no bars (streaks, records).
  text,
}

typedef _Spec = (String name, String label, _Format format);

/// Pass accuracy is computed from the two pass counts: the feed's own
/// `passPct` is rounded to one decimal of a fraction (`0.6`).
const String _passAccuracy = '_passAccuracy';

/// Stats where the smaller figure is the better one.
const Set<String> _lowerIsBetter = {
  'foulsCommitted',
  'offsides',
  'yellowCards',
  'redCards',
  'goalsConceded',
  'turnovers',
  'totalPenaltiesYards',
  'totalTurnovers',
  'giveaways',
  'penaltyMinutes',
  'fielding.errors',
  'pitching.pitches',
  'batting.strikeouts',
  'totalPointsPerGameAllowed',
  'yardsPerGameAllowed',
  'avgPointsAgainst',
  'avgTotalTurnovers',
  'avgGoalsAgainst',
  'avgShotsAgainst',
};

const Map<SportKind, List<_Spec>> _gameSpecs = {
  SportKind.soccer: [
    ('possessionPct', 'Possession', _Format.percent),
    ('totalShots', 'Shots', _Format.plain),
    ('shotsOnTarget', 'Shots on target', _Format.plain),
    ('wonCorners', 'Corners', _Format.plain),
    (_passAccuracy, 'Pass accuracy', _Format.percent),
    ('totalPasses', 'Passes', _Format.plain),
    ('saves', 'Saves', _Format.plain),
    ('foulsCommitted', 'Fouls', _Format.plain),
    ('offsides', 'Offsides', _Format.plain),
    ('yellowCards', 'Yellow cards', _Format.plain),
    ('redCards', 'Red cards', _Format.plain),
  ],
  SportKind.americanFootball: [
    ('totalYards', 'Total yards', _Format.plain),
    ('netPassingYards', 'Passing', _Format.plain),
    ('rushingYards', 'Rushing', _Format.plain),
    ('firstDowns', 'First downs', _Format.plain),
    ('thirdDownEff', '3rd down', _Format.plain),
    ('redZoneAttempts', 'Red zone', _Format.plain),
    ('turnovers', 'Turnovers', _Format.plain),
    ('totalPenaltiesYards', 'Penalties', _Format.plain),
    ('possessionTime', 'Possession', _Format.plain),
  ],
  SportKind.basketball: [
    ('fieldGoalsMade-fieldGoalsAttempted', 'Field goals', _Format.plain),
    ('fieldGoalPct', 'Field goal %', _Format.percent),
    (
      'threePointFieldGoalsMade-threePointFieldGoalsAttempted',
      '3-pointers',
      _Format.plain,
    ),
    ('threePointFieldGoalPct', '3-point %', _Format.percent),
    ('freeThrowsMade-freeThrowsAttempted', 'Free throws', _Format.plain),
    ('totalRebounds', 'Rebounds', _Format.plain),
    ('assists', 'Assists', _Format.plain),
    ('steals', 'Steals', _Format.plain),
    ('blocks', 'Blocks', _Format.plain),
    ('totalTurnovers', 'Turnovers', _Format.plain),
    ('pointsInPaint', 'Points in paint', _Format.plain),
    ('largestLead', 'Largest lead', _Format.plain),
  ],
  SportKind.hockey: [
    ('shotsTotal', 'Shots', _Format.plain),
    ('faceoffPercent', 'Faceoffs won', _Format.percent),
    ('powerPlayGoals', 'Power-play goals', _Format.plain),
    ('powerPlayOpportunities', 'Power plays', _Format.plain),
    ('hits', 'Hits', _Format.plain),
    ('blockedShots', 'Blocked shots', _Format.plain),
    ('takeaways', 'Takeaways', _Format.plain),
    ('giveaways', 'Giveaways', _Format.plain),
    ('penaltyMinutes', 'Penalty minutes', _Format.plain),
  ],
  SportKind.baseball: [
    ('batting.hits', 'Hits', _Format.plain),
    ('batting.homeRuns', 'Home runs', _Format.plain),
    ('batting.RBIs', 'RBIs', _Format.plain),
    ('batting.walks', 'Walks', _Format.plain),
    ('batting.strikeouts', 'Strikeouts', _Format.plain),
    ('batting.stolenBases', 'Stolen bases', _Format.plain),
    ('fielding.errors', 'Errors', _Format.plain),
    ('pitching.pitches', 'Pitches thrown', _Format.plain),
  ],
};

const Map<SportKind, List<_Spec>> _seasonSpecs = {
  SportKind.soccer: [
    ('totalGoals', 'Goals', _Format.plain),
    ('goalsConceded', 'Goals conceded', _Format.plain),
    ('goalDifference', 'Goal difference', _Format.text),
    ('goalAssists', 'Assists', _Format.plain),
  ],
  SportKind.americanFootball: [
    ('totalPointsPerGame', 'Points per game', _Format.plain),
    ('totalPointsPerGameAllowed', 'Points allowed', _Format.plain),
    ('yardsPerGame', 'Yards per game', _Format.plain),
    ('yardsPerGameAllowed', 'Yards allowed', _Format.plain),
    ('passingYardsPerGame', 'Passing yards', _Format.plain),
    ('rushingYardsPerGame', 'Rushing yards', _Format.plain),
  ],
  SportKind.basketball: [
    ('avgPoints', 'Points per game', _Format.plain),
    ('avgPointsAgainst', 'Points allowed', _Format.plain),
    ('fieldGoalPct', 'Field goal %', _Format.percent),
    ('threePointFieldGoalPct', '3-point %', _Format.percent),
    ('avgRebounds', 'Rebounds', _Format.plain),
    ('avgAssists', 'Assists', _Format.plain),
    ('avgSteals', 'Steals', _Format.plain),
    ('avgBlocks', 'Blocks', _Format.plain),
    ('avgTotalTurnovers', 'Turnovers', _Format.plain),
    ('Last Ten Games', 'Last 10 games', _Format.text),
    ('streak', 'Streak', _Format.text),
  ],
  SportKind.hockey: [
    ('avgGoals', 'Goals per game', _Format.plain),
    ('avgGoalsAgainst', 'Goals allowed', _Format.plain),
    ('avgShots', 'Shots per game', _Format.plain),
    ('avgShotsAgainst', 'Shots allowed', _Format.plain),
    ('powerPlayPct', 'Power play', _Format.percent),
    ('penaltyKillPct', 'Penalty kill', _Format.percent),
  ],
};

/// The rows to compare for a [sport] match; [season] picks the pre-game
/// season-average list.
List<SportsStatRow> sportsStatRows(
  SportKind sport,
  List<SportsTeamStat> stats, {
  required bool season,
}) {
  if (stats.isEmpty) return const [];
  final byName = {for (final stat in stats) stat.name: stat};
  final specs = (season ? _seasonSpecs : _gameSpecs)[sport] ?? const [];
  final rows = <SportsStatRow>[
    for (final (name, label, format) in specs)
      if (_row(name, label, format, byName) case final row?) row,
  ];
  if (rows.isNotEmpty) return rows;
  return [
    for (final stat in stats.take(_fallbackRows))
      SportsStatRow(
        label: stat.label,
        homeText: stat.homeText,
        awayText: stat.awayText,
        homeValue: stat.homeValue,
        awayValue: stat.awayValue,
      ),
  ];
}

SportsStatRow? _row(
  String name,
  String label,
  _Format format,
  Map<String, SportsTeamStat> byName,
) {
  if (name == _passAccuracy) return _passAccuracyRow(label, byName);
  final stat = byName[name];
  if (stat == null) return null;
  final bars = format != _Format.text;
  return SportsStatRow(
    label: label,
    homeText: _format(stat.homeText, format),
    awayText: _format(stat.awayText, format),
    homeValue: bars ? stat.homeValue : null,
    awayValue: bars ? stat.awayValue : null,
    lowerIsBetter: _lowerIsBetter.contains(name),
  );
}

SportsStatRow? _passAccuracyRow(
  String label,
  Map<String, SportsTeamStat> byName,
) {
  final accurate = byName['accuratePasses'];
  final total = byName['totalPasses'];
  double? share(double? made, double? all) =>
      made == null || all == null || all <= 0 ? null : made / all * 100;
  final home = share(accurate?.homeValue, total?.homeValue);
  final away = share(accurate?.awayValue, total?.awayValue);
  if (home == null || away == null) return null;
  return SportsStatRow(
    label: label,
    homeText: '${home.round()}%',
    awayText: '${away.round()}%',
    homeValue: home,
    awayValue: away,
  );
}

String _format(String text, _Format format) {
  if (format != _Format.percent || text.endsWith('%')) return text;
  return double.tryParse(text) == null ? text : '$text%';
}
