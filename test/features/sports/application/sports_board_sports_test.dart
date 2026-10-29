// Sport chips and the league picker's grouping: pure functions, no Riverpod.
import 'package:debrify/features/sports/application/sports_board_sections.dart';
import 'package:debrify/features/sports/application/sports_board_sports.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

SportsEvent _ev(String id, String leagueId) => SportsEvent(
  id: id,
  leagueId: leagueId,
  start: DateTime.utc(2026, 10, 29, 19),
  status: SportsEventStatus.scheduled,
  title: id,
);

SportsBoardSection _section(String id, List<SportsEvent> events) =>
    SportsBoardSection(id: id, title: id, events: events);

void main() {
  final epl = _ev('epl-1', 'epl');
  final ucl = _ev('ucl-1', 'ucl');
  final ipl = _ev('ipl-1', 'ipl');
  final nba = _ev('nba-1', 'nba');
  final unknown = _ev('x-1', 'not-a-league');

  final sections = [
    _section('live', [ucl, ipl]),
    // "Your teams" repeats a fixture shown below it.
    _section('your-teams', [ucl]),
    _section('day-1', [epl, nba, unknown]),
  ];

  test('chips count distinct fixtures per sport, in catalog rank order', () {
    expect(sportsBoardSportCounts(sections), [
      (sport: SportKind.soccer, count: 2),
      (sport: SportKind.cricket, count: 1),
      (sport: SportKind.basketball, count: 1),
    ]);
  });

  test('narrowing to a sport keeps order and drops emptied rows', () {
    final cricket = sportsBoardSectionsForSport(sections, SportKind.cricket);
    expect(cricket.map((s) => s.id), ['live']);
    expect(cricket.single.events, [ipl]);

    final soccer = sportsBoardSectionsForSport(sections, SportKind.soccer);
    expect(soccer.map((s) => s.id), ['live', 'your-teams', 'day-1']);
    expect(soccer.last.events, [epl]);

    expect(sportsBoardSectionsForSport(sections, null), same(sections));
    expect(sportsBoardSectionsForSport(sections, SportKind.golf), isEmpty);
  });

  test('the picker groups every catalog league once, by sport rank', () {
    final groups = sportsLeagueGroups(kSportsLeagues);
    expect(groups.first.sport, SportKind.soccer);
    expect(groups[1].sport, SportKind.cricket);
    expect(
      groups.expand((g) => g.leagues).map((l) => l.id).toSet(),
      kSportsLeagues.map((l) => l.id).toSet(),
    );
    expect(groups.expand((g) => g.leagues), hasLength(kSportsLeagues.length));
    final soccer = groups.first.leagues.map((l) => l.id).toList();
    expect(soccer.take(3), ['ucl', 'epl', 'laliga']);
    for (final group in groups) {
      final importance = [for (final l in group.leagues) l.importance];
      expect(importance, [...importance]..sort((a, b) => b - a));
    }
  });
}
