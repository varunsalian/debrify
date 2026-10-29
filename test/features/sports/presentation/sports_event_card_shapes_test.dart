// One card frame, one body per sport shape: cricket text scores, tennis sets,
// fight cards, golf leaders and races, each built from a constructed
// SportsEvent and checked with the Scores toggle both ways. No logo urls, so
// nothing reaches the network.
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:debrify/features/sports/presentation/sports_event_card.dart';
import 'package:debrify/features/sports/presentation/sports_event_card_bodies.dart';
import 'package:debrify/features/sports/presentation/sports_team_crest.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = IptvStyleTokens.spotlight;

SportsTeam _side(String id, String name, String abbreviation) =>
    SportsTeam(id: id, name: name, shortName: name, abbreviation: abbreviation);

final _start = DateTime.utc(2026, 10, 29, 9);

final _cricket = SportsEvent(
  id: 'c1',
  leagueId: 'intl-cricket',
  start: _start,
  status: SportsEventStatus.live,
  clock: 'Day 3',
  home: _side('sa', 'South Africa', 'SA'),
  away: _side('aus', 'Australia', 'AUS'),
  homeScoreText: '329 & 0/0',
  awayScoreText: '330/4 (90 ov)',
  format: 'TEST',
  note: 'Australia lead by 1 run',
  group: 'Australia tour of South Africa',
);

SportsEvent _tennis({
  SportsEventStatus status = SportsEventStatus.live,
  bool? homeWon,
}) => SportsEvent(
  id: 't1',
  leagueId: 'wta',
  start: _start,
  status: status,
  clock: 'Set 3',
  home: _side('pi', 'Polina Iatcenko', 'Iatcenko'),
  away: _side('as', 'Alexandra Shubladze', 'Shubladze'),
  homeLines: const [6, 2, 4],
  awayLines: const [3, 6, 3],
  homeWon: homeWon,
  format: 'R16',
  group: 'Guangzhou Open',
);

final _fightCard = SportsEvent(
  id: 'u1',
  leagueId: 'ufc',
  start: _start,
  status: SportsEventStatus.scheduled,
  title: 'UFC Fight Night: Moicano vs. Nolan',
  format: 'Lightweight',
  itemCount: 12,
  subtitle: 'UFC APEX',
);

final _golf = SportsEvent(
  id: 'g1',
  leagueId: 'pga',
  start: _start,
  status: SportsEventStatus.live,
  clock: 'Round 1',
  title: 'VidantaWorld Mexico Open',
  subtitle: 'Vidanta Vallarta',
  leaderName: 'Patton Kizzire',
  leaderScore: '-6',
);

final _race = SportsEvent(
  id: 'r1',
  leagueId: 'nascar',
  start: _start,
  status: SportsEventStatus.scheduled,
  title: 'Xfinity 500',
  subtitle: 'Martinsville Speedway',
);

final _football = SportsEvent(
  id: 'f1',
  leagueId: 'seriea',
  start: _start,
  status: SportsEventStatus.finished,
  home: _side('fio', 'Fiorentina', 'FIO'),
  away: _side('ata', 'Atalanta', 'ATA'),
  homeScore: 2,
  awayScore: 1,
);

Future<void> _mount(
  WidgetTester tester,
  SportsEvent event, {
  bool hideScores = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SportsEventCard(
            event: event,
            hideScores: hideScores,
            followed: false,
            watch: SportsWatchOptions.empty,
            onPressed: () {},
            width: 300,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  group('cricket', () {
    testWidgets('text scores, format badge, series and match situation', (
      tester,
    ) async {
      await _mount(tester, _cricket);

      expect(sportsCardShapeOf(_cricket), SportsEventShape.innings);
      expect(find.text('Australia tour of South Africa'), findsOneWidget);
      expect(find.text('TEST'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('South Africa'), findsOneWidget);
      expect(find.text('329 & 0/0'), findsOneWidget);
      expect(find.text('330/4 (90 ov)'), findsOneWidget);
      expect(find.text('Australia lead by 1 run'), findsOneWidget);
    });

    testWidgets('hidden scores hide the totals and the situation', (
      tester,
    ) async {
      await _mount(tester, _cricket, hideScores: true);

      expect(find.text('South Africa'), findsOneWidget);
      expect(find.text('329 & 0/0'), findsNothing);
      expect(find.text('330/4 (90 ov)'), findsNothing);
      // The situation names the leader, so it is a spoiler too.
      expect(find.text('Australia lead by 1 run'), findsNothing);
      expect(find.byType(SportsHiddenScore), findsNWidgets(2));
    });
  });

  group('tennis', () {
    testWidgets('players with flags and games per set', (tester) async {
      await _mount(tester, _tennis());

      expect(sportsCardShapeOf(_tennis()), SportsEventShape.sets);
      expect(find.text('Guangzhou Open'), findsOneWidget);
      expect(find.text('R16'), findsOneWidget);
      expect(find.byType(SportsFlagPlate), findsNWidgets(2));
      expect(find.text('Polina Iatcenko'), findsOneWidget);
      expect(find.text('Alexandra Shubladze'), findsOneWidget);
      expect(find.text('6'), findsNWidgets(2));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3'), findsNWidgets(2));
      // The current set reads in full ink, earlier sets dimmed.
      expect(
        tester.widget<Text>(find.text('4')).style?.fontWeight,
        FontWeight.w600,
      );
    });

    testWidgets('a finished match dims the loser unless scores are hidden', (
      tester,
    ) async {
      final done = _tennis(status: SportsEventStatus.finished, homeWon: true);
      await _mount(tester, done);
      expect(_colorOf(tester, 'Alexandra Shubladze'), _tokens.fgDim);
      expect(_colorOf(tester, 'Polina Iatcenko'), _tokens.fg);

      await _mount(tester, done, hideScores: true);
      expect(_colorOf(tester, 'Alexandra Shubladze'), _tokens.fg);
      expect(find.text('6'), findsNothing);
      expect(find.byType(SportsHiddenScore), findsNWidgets(2));
    });
  });

  testWidgets('a fight card names the card, the main event and its bouts', (
    tester,
  ) async {
    await _mount(tester, _fightCard);

    expect(sportsCardShapeOf(_fightCard), SportsEventShape.card);
    expect(find.text('UFC Fight Night'), findsOneWidget);
    expect(find.text('Moicano vs. Nolan'), findsOneWidget);
    expect(find.text('Lightweight main event · 12 bouts'), findsOneWidget);
    expect(find.text('UFC APEX'), findsOneWidget);
    // The weight class lives in the body, not in a header badge.
    expect(find.text('Lightweight'), findsNothing);
  });

  group('golf and racing', () {
    testWidgets('golf shows the tournament and its leader', (tester) async {
      await _mount(tester, _golf);

      expect(sportsCardShapeOf(_golf), SportsEventShape.event);
      expect(find.text('PGA Tour'), findsOneWidget);
      expect(find.text('Round 1'), findsOneWidget);
      expect(find.text('VidantaWorld Mexico Open'), findsOneWidget);
      expect(find.text('Leader · Patton Kizzire'), findsOneWidget);
      expect(find.text('-6'), findsOneWidget);
    });

    testWidgets('hidden scores keep the leader but not the score', (
      tester,
    ) async {
      await _mount(tester, _golf, hideScores: true);

      expect(find.text('Leader · Patton Kizzire'), findsOneWidget);
      expect(find.text('-6'), findsNothing);
      expect(find.byType(SportsHiddenScore), findsOneWidget);
    });

    testWidgets('a race shows its title and venue', (tester) async {
      await _mount(tester, _race);

      expect(find.text('NASCAR Cup Series'), findsOneWidget);
      expect(find.text('Xfinity 500'), findsOneWidget);
      expect(find.text('Martinsville Speedway'), findsOneWidget);
      expect(find.text('Leader · Patton Kizzire'), findsNothing);
    });
  });

  testWidgets('a team result dims the loser only while scores show', (
    tester,
  ) async {
    await _mount(tester, _football);
    expect(find.text('Serie A'), findsOneWidget);
    expect(find.text('FT'), findsOneWidget);
    expect(_colorOf(tester, 'Atalanta'), _tokens.fgDim);
    expect(_colorOf(tester, 'Fiorentina'), _tokens.fg);

    await _mount(tester, _football, hideScores: true);
    expect(_colorOf(tester, 'Atalanta'), _tokens.fg);
    expect(find.byType(SportsHiddenScore), findsNWidgets(2));
  });

  testWidgets('every shape fits the shared card height', (tester) async {
    for (final event in [
      _cricket,
      _tennis(),
      _fightCard,
      _golf,
      _race,
      _football,
    ]) {
      await _mount(tester, event);
      expect(tester.takeException(), isNull, reason: event.id);
      final body = tester.getSize(find.byType(SportsEventCardBody));
      final slot = tester.getSize(
        find
            .ancestor(
              of: find.byType(SportsEventCardBody),
              matching: find.byType(ClipRect),
            )
            .first,
      );
      expect(tester.getSize(find.byType(SportsEventCard)).height, 178);
      // The tallest body still fits the slot between header and footer.
      expect(body.height, lessThanOrEqualTo(slot.height), reason: event.id);
    }
  });
}
