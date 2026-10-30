import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/espn_scoreboard_parser.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Real ESPN responses recorded 2026-10-29.
Object? _fixture(String name) =>
    jsonDecode(File('test/features/sports/fixtures/$name').readAsStringSync());

SportsEvent _byId(List<SportsEvent> events, String id) =>
    events.singleWhere((e) => e.id == id);

void main() {
  group('Test match (international series)', () {
    final events = parseEspnScoreboard(
      _fixture('espn_cricket_test.json'),
      leagueId: 'intl-cricket',
    );

    test('text scores, no numeric scores', () {
      final e = _byId(events, '1525661');
      expect(e.home!.name, 'South Africa');
      expect(e.away!.name, 'Australia');
      expect(e.homeScoreText, '329');
      expect(e.awayScoreText, '330/4 (90 ov)');
      expect(e.homeScore, isNull);
      expect(e.awayScore, isNull);
    });

    test('format, note, subtitle and series group', () {
      final e = _byId(events, '1525661');
      expect(e.format, 'TEST');
      expect(e.note, 'Australia lead by 1 run');
      expect(e.subtitle, '3rd Test');
      expect(e.group, 'Australia tour of South Africa 2026/27');
      expect(e.status, SportsEventStatus.live);
      expect(e.homeWon, isNull);
      expect(e.start, DateTime.utc(2026, 10, 27, 8, 30));
      expect(e.leagueId, 'intl-cricket');
    });

    test('the clock is the match state, not the bare word "Live"', () {
      // ESPN: shortDetail "Live", description "Stumps", displayClock "0'".
      expect(_byId(events, '1525661').clock, 'Stumps');
    });
  });

  group('Ranji Trophy', () {
    final events = parseEspnScoreboard(
      _fixture('espn_cricket_ranji.json'),
      leagueId: 'ranji',
    );

    test('every fixture parses', () {
      expect(events, hasLength(18));
      expect(events.every((e) => e.isTeamEvent), isTrue);
      expect(events.every((e) => e.group == 'Ranji Trophy'), isTrue);
    });

    test('two-innings scores keep their text', () {
      final e = _byId(events, '1546580');
      expect(e.home!.name, 'Sikkim');
      expect(e.away!.name, 'Nagaland');
      expect(e.homeScoreText, '184 & 117/5 (46 ov, target 212)');
      expect(e.awayScoreText, '187 & 208');
      expect(e.format, 'FIRST-CLASS');
      expect(e.note, 'Sikkim require 95 runs');
      expect(e.subtitle, 'Plate Group');
      expect(e.clock, 'Match delayed - Rain');
    });

    test('sorted by start, then id', () {
      for (var i = 1; i < events.length; i++) {
        final a = events[i - 1], b = events[i];
        final byStart = a.start.compareTo(b.start);
        expect(
          byStart < 0 || (byStart == 0 && a.id.compareTo(b.id) <= 0),
          isTrue,
        );
      }
    });
  });

  group('winner of a finished match', () {
    Map<String, dynamic> finished({Object? homeWinner, Object? awayWinner}) {
      final json =
          jsonDecode(jsonEncode(_fixture('espn_cricket_test.json')))
              as Map<String, dynamic>;
      final event = (json['events'] as List).first as Map<String, dynamic>;
      for (final target in [
        event,
        (event['competitions'] as List).first as Map<String, dynamic>,
      ]) {
        final status = target['status'] as Map<String, dynamic>?;
        if (status == null) continue;
        final type = status['type'] as Map<String, dynamic>;
        type['state'] = 'post';
        type['completed'] = true;
        type['name'] = 'STATUS_FINAL';
      }
      final competitors =
          ((event['competitions'] as List).first as Map)['competitors'] as List;
      for (final c in competitors.cast<Map<String, dynamic>>()) {
        c['winner'] = c['homeAway'] == 'home' ? homeWinner : awayWinner;
      }
      return json;
    }

    SportsEvent parse(Map<String, dynamic> json) =>
        parseEspnScoreboard(json, leagueId: 'intl-cricket').single;

    test('home win, as bool or string', () {
      expect(
        parse(finished(homeWinner: true, awayWinner: false)).homeWon,
        isTrue,
      );
      expect(
        parse(finished(homeWinner: 'true', awayWinner: 'false')).homeWon,
        isTrue,
      );
    });

    test('away win', () {
      expect(
        parse(finished(homeWinner: 'false', awayWinner: 'true')).homeWon,
        isFalse,
      );
    });

    test('draw or unknown stays null', () {
      expect(
        parse(finished(homeWinner: false, awayWinner: false)).homeWon,
        isNull,
      );
      expect(parse(finished()).homeWon, isNull);
    });
  });

  test('team sports are untouched', () {
    final events = parseEspnScoreboard(
      _fixture('espn_prem_rugby.json'),
      leagueId: 'prem-rugby',
    );
    expect(events, isNotEmpty);
    for (final e in events) {
      expect(e.homeScoreText, isNull);
      expect(e.awayScoreText, isNull);
      expect(e.format, isNull);
      expect(e.group, isNull);
      expect(e.homeWon, isNull);
    }
    final isl = parseEspnScoreboard(_fixture('espn_isl.json'), leagueId: 'isl');
    expect(isl, hasLength(2));
    expect(
      isl.every((e) => e.homeScoreText == null && e.group == null),
      isTrue,
    );
  });

  test('unknown league ids keep the team behaviour', () {
    final events = parseEspnScoreboard(
      _fixture('espn_cricket_test.json'),
      leagueId: 'not-a-league',
    );
    expect(events.single.homeScoreText, isNull);
    expect(events.single.format, isNull);
  });
}
