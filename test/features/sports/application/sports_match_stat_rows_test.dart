// Which team stats the page compares: curated per sport and per game state,
// formatted for reading, with the feed's own stats as the fallback.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/application/sports_match_stat_rows.dart';
import 'package:debrify/features/sports/data/espn_summary_parser.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

List<SportsTeamStat> _stats(String fixture) => parseEspnSummary(
  jsonDecode(File('test/features/sports/fixtures/$fixture').readAsStringSync()),
)!.teamStats;

SportsStatRow _row(List<SportsStatRow> rows, String label) =>
    rows.firstWhere((r) => r.label == label);

SportsTeamStat _stat(String name, double home, double away) => SportsTeamStat(
  name: name,
  label: 'Feed $name',
  homeText: '$home',
  awayText: '$away',
  homeValue: home,
  awayValue: away,
);

void main() {
  test('a finished football match: curated, in order, with percentages', () {
    final rows = sportsStatRows(
      SportKind.soccer,
      _stats('espn_summary_epl_final.json'),
      season: false,
    );
    expect(rows.map((r) => r.label), [
      'Possession',
      'Shots',
      'Shots on target',
      'Corners',
      'Pass accuracy',
      'Passes',
      'Saves',
      'Fouls',
      'Offsides',
      'Yellow cards',
      'Red cards',
    ]);
    final possession = _row(rows, 'Possession');
    expect((possession.homeText, possession.awayText), ('29.8%', '70.2%'));
    // 135 of 242 passes: computed from the counts, not the feed's "0.6".
    final passing = _row(rows, 'Pass accuracy');
    expect(passing.homeText, '56%');
    expect(passing.homeValue, closeTo(55.79, 0.01));
  });

  test('before kick-off the season list is used', () {
    final rows = sportsStatRows(
      SportKind.basketball,
      _stats('espn_summary_nba_scheduled.json'),
      season: true,
    );
    expect(rows.first.label, 'Points per game');
    expect(_row(rows, 'Field goal %').homeText, '45%');
    final streak = _row(rows, 'Streak');
    expect(streak.hasBars, isFalse, reason: 'a streak is not a quantity');
    expect(streak.homeAhead, isNull);
  });

  test('football game totals and baseball groups map to their lists', () {
    final nfl = sportsStatRows(
      SportKind.americanFootball,
      _stats('espn_summary_nfl_final.json'),
      season: false,
    );
    expect(nfl.first.label, 'Total yards');
    expect(_row(nfl, 'Possession').homeText, '37:46');
    final mlb = sportsStatRows(
      SportKind.baseball,
      _stats('espn_summary_mlb_final.json'),
      season: false,
    );
    expect(mlb.first.label, 'Hits');
    expect(mlb.map((r) => r.label), contains('Errors'));
  });

  test('which side a stat favours, with lower-is-better stats inverted', () {
    final rows = sportsStatRows(SportKind.soccer, [
      _stat('totalShots', 11, 15),
      _stat('foulsCommitted', 7, 17),
      _stat('wonCorners', 4, 4),
    ], season: false);
    expect(_row(rows, 'Shots').homeAhead, isFalse);
    expect(_row(rows, 'Fouls').homeAhead, isTrue, reason: 'fewer fouls');
    expect(_row(rows, 'Corners').homeAhead, isNull, reason: 'level');
    final pitches = sportsStatRows(SportKind.baseball, [
      _stat('pitching.pitches', 140, 120),
    ], season: false);
    expect(pitches.single.homeAhead, isFalse, reason: 'fewer pitches');
  });

  test('a sport with no curated list shows the feed\'s first stats', () {
    final stats = [for (var i = 0; i < 12; i++) _stat('s$i', 1, 2)];
    final rows = sportsStatRows(SportKind.rugby, stats, season: false);
    expect(rows, hasLength(8));
    expect(rows.first.label, 'Feed s0');
  });

  test('renamed feed keys fall back rather than leaving the card empty', () {
    final rows = sportsStatRows(SportKind.soccer, [
      _stat('somethingNew', 3, 4),
    ], season: false);
    expect(rows.single.label, 'Feed somethingNew');
  });

  test('no stats, no rows', () {
    expect(sportsStatRows(SportKind.soccer, const [], season: false), isEmpty);
  });
}
