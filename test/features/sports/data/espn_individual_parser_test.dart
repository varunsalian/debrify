import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/espn_individual_parser.dart';
import 'package:debrify/features/sports/data/espn_scoreboard_parser.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Real ESPN responses recorded 2026-10-29.
Object? _fixture(String name) =>
    jsonDecode(File('test/features/sports/fixtures/$name').readAsStringSync());

Map<String, dynamic> _copy(String name) =>
    jsonDecode(jsonEncode(_fixture(name))) as Map<String, dynamic>;

SportsEvent _byId(List<SportsEvent> events, String id) =>
    events.singleWhere((e) => e.id == id);

void main() {
  group('tennis (sets)', () {
    final events = parseEspnIndividual(
      _fixture('espn_atp.json'),
      leagueId: 'atp',
      shape: SportsEventShape.sets,
    );

    test('every real singles match of both tournaments, no doubles', () {
      // 86 men's singles in the feed; 14 are unplayed placeholders.
      expect(events, hasLength(72));
      expect(events.map((e) => e.group).toSet(), {
        'Erste Bank Open',
        'Swiss Indoors Basel',
      });
      // Doubles competitors have rosters, never single athletes.
      expect(events.every((e) => e.isTeamEvent), isTrue);
    });

    test('a finished match: players by order, set games, winner, round', () {
      final e = _byId(events, '185198');
      expect(e.home!.name, 'Learner Tien');
      expect(e.away!.name, 'Alex de Minaur');
      expect(e.homeLines, [4, 2]);
      expect(e.awayLines, [6, 6]);
      expect(e.homeWon, isFalse);
      expect(e.status, SportsEventStatus.finished);
      expect(e.format, 'Round 2');
      expect(e.group, 'Erste Bank Open');
      expect(e.start, DateTime.utc(2026, 10, 28, 19, 15));
      expect(e.away!.logoUrl, endsWith('/aus.png'));
      expect(e.away!.abbreviation, 'Minaur');
      expect(e.leagueId, 'atp');
    });

    test('a three-set win for the second player', () {
      final e = _byId(events, '185146');
      expect(e.home!.name, 'Hubert Hurkacz');
      expect(e.away!.name, 'Holger Rune');
      expect(e.homeLines, [6, 3, 6]);
      expect(e.awayLines, [3, 6, 7]);
      expect(e.homeWon, isFalse);
    });

    test('a scheduled match has no winner and starts at its own time', () {
      final e = _byId(events, '185187');
      expect(e.status, SportsEventStatus.scheduled);
      expect(e.homeWon, isNull);
      expect(e.start, DateTime.utc(2026, 10, 29, 12, 30));
      expect(
        {e.home!.name, e.away!.name},
        {'Daniil Medvedev', 'Cameron Norrie'},
      );
    });

    test('sorted by start, then id; first and last match', () {
      expect(events.first.id, '187149');
      expect(events.first.start, DateTime.utc(2026, 10, 24, 9));
      expect(events.last.id, '185196');
    });

    test('unplayed placeholders (TBD players, no valid time) are dropped', () {
      final ids = events.map((e) => e.id).toSet();
      expect(ids, isNot(contains('185199'))); // TBD v TBD
      expect(ids, isNot(contains('185156'))); // Borges v TBD
      expect(
        events.any((e) => e.home!.name == 'TBD' || e.away!.name == 'TBD'),
        isFalse,
      );
    });

    test('the league picks its own draw (men for ATP, women for WTA)', () {
      final json = _copy('espn_atp.json');
      // Rename the men's draw so it looks like a women's one.
      for (final e in (json['events'] as List).cast<Map<String, dynamic>>()) {
        for (final g in (e['groupings'] as List).cast<Map<String, dynamic>>()) {
          final grouping = g['grouping'] as Map<String, dynamic>;
          if (grouping['slug'] == 'mens-singles') {
            grouping['slug'] = 'womens-singles';
          }
        }
      }
      expect(
        parseEspnIndividual(
          json,
          leagueId: 'atp',
          shape: SportsEventShape.sets,
        ),
        isEmpty,
      );
      expect(
        parseEspnIndividual(
          json,
          leagueId: 'wta',
          shape: SportsEventShape.sets,
        ),
        hasLength(72),
      );
    });
  });

  group('fight card', () {
    test('one event per card with bout count and main-event class', () {
      final events = parseEspnIndividual(
        _fixture('espn_ufc.json'),
        leagueId: 'ufc',
        shape: SportsEventShape.card,
      );
      final e = events.single;
      expect(e.id, '600061420');
      expect(e.title, 'UFC Fight Night: Moicano vs. Nolan');
      expect(e.itemCount, 12);
      expect(e.format, 'Lightweight');
      expect(e.subtitle, 'Meta APEX');
      expect(e.start, DateTime.utc(2026, 10, 31, 21));
      expect(e.status, SportsEventStatus.scheduled);
      expect(e.isTeamEvent, isFalse);
    });
  });

  group('golf and racing (event)', () {
    test('a golf tournament before it starts has no leader', () {
      final e = parseEspnIndividual(
        _fixture('espn_pga.json'),
        leagueId: 'pga',
        shape: SportsEventShape.event,
      ).single;
      expect(e.id, '401850978');
      expect(e.title, 'VidantaWorld Mexico Open');
      expect(e.status, SportsEventStatus.scheduled);
      expect(e.leaderName, isNull);
      expect(e.leaderScore, isNull);
      expect(e.start, DateTime.utc(2026, 10, 29, 4));
    });

    test('a live golf tournament names the leader by order', () {
      final json = _copy('espn_pga.json');
      final event = (json['events'] as List).first as Map<String, dynamic>;
      final type = (event['status'] as Map)['type'] as Map<String, dynamic>;
      type['state'] = 'in';
      type['name'] = 'STATUS_IN_PROGRESS';
      final e = parseEspnIndividual(
        json,
        leagueId: 'pga',
        shape: SportsEventShape.event,
      ).single;
      expect(e.status, SportsEventStatus.live);
      expect(e.leaderName, 'Patton Kizzire');
      expect(e.leaderScore, 'E');
    });

    test('a race', () {
      final e = parseEspnIndividual(
        _fixture('espn_nascar.json'),
        leagueId: 'nascar',
        shape: SportsEventShape.event,
      ).single;
      expect(e.id, '202611010020');
      expect(e.title, 'NASCAR Cup Series at Martinsville');
      expect(e.start, DateTime.utc(2026, 11, 1, 19));
      expect(e.leaderName, isNull);
    });
  });

  group('dispatch from parseEspnScoreboard', () {
    test('tennis, UFC, golf and racing leagues use the individual parser', () {
      expect(
        parseEspnScoreboard(_fixture('espn_atp.json'), leagueId: 'atp'),
        hasLength(72),
      );
      expect(
        parseEspnScoreboard(
          _fixture('espn_ufc.json'),
          leagueId: 'ufc',
        ).single.itemCount,
        12,
      );
      expect(
        parseEspnScoreboard(
          _fixture('espn_pga.json'),
          leagueId: 'pga',
        ).single.title,
        'VidantaWorld Mexico Open',
      );
      expect(
        parseEspnScoreboard(
          _fixture('espn_nascar.json'),
          leagueId: 'nascar',
        ).single.title,
        'NASCAR Cup Series at Martinsville',
      );
    });
  });

  group('never throws', () {
    for (final input in <Object?>[
      null,
      42,
      'x',
      <String, dynamic>{},
      {'events': 'no'},
    ]) {
      test('input $input', () {
        for (final shape in [
          SportsEventShape.sets,
          SportsEventShape.card,
          SportsEventShape.event,
        ]) {
          expect(
            parseEspnIndividual(input, leagueId: 'atp', shape: shape),
            isEmpty,
          );
        }
      });
    }

    test('a broken match is dropped, its siblings survive', () {
      final json = _copy('espn_atp.json');
      final event = (json['events'] as List).first as Map<String, dynamic>;
      final singles = (event['groupings'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere(
            (g) => '${(g['grouping'] as Map)['slug']}'.contains('singles'),
          );
      final first =
          (singles['competitions'] as List).first as Map<String, dynamic>;
      first['competitors'] = 'broken';
      final events = parseEspnIndividual(
        json,
        leagueId: 'atp',
        shape: SportsEventShape.sets,
      );
      expect(events, hasLength(71));
    });
  });
}
