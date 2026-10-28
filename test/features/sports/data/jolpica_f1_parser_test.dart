import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/jolpica_f1_parser.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

/// Fixed reference instant: 2026-10-28 20:00 UTC.
final DateTime _now = DateTime.utc(2026, 10, 28, 20);

Object? fixture(String name) =>
    jsonDecode(File('$_fixtureDir/$name').readAsStringSync());

Map<String, dynamic> circuitJson(String name) => {
  'circuitName': name,
  'Location': {'locality': 'Testville'},
};

Map<String, dynamic> raceJson({
  Object season = '2026',
  Object round = '1',
  String raceName = 'Test Grand Prix',
  String date = '2026-11-08',
  String? time = '17:00:00Z',
  String? circuitName = 'Test Circuit',
}) => {
  'season': season,
  'round': round,
  'raceName': raceName,
  'date': date,
  if (time != null) 'time': time,
  if (circuitName != null) 'Circuit': circuitJson(circuitName),
};

Map<String, dynamic> seasonJson(List<Object?> races) => {
  'MRData': {
    'RaceTable': {'season': '2026', 'Races': races},
  },
};

List<SportsEvent> parseRaces(List<Object?> races, {DateTime? now}) =>
    parseJolpicaSeason(seasonJson(races), now: now ?? _now);

void main() {
  group('shape guards', () {
    test('non-map payloads yield no events', () {
      for (final bad in <Object?>[
        null,
        'nope',
        7,
        <Object?>[],
        <Object?>{'a'},
      ]) {
        expect(
          parseJolpicaSeason(bad, now: _now),
          isEmpty,
          reason: 'payload $bad must not produce events',
        );
      }
    });

    test('a missing or malformed Races list yields no events', () {
      expect(parseJolpicaSeason({}, now: _now), isEmpty);
      expect(parseJolpicaSeason({'MRData': {}}, now: _now), isEmpty);
      expect(
        parseJolpicaSeason({
          'MRData': {
            'RaceTable': {'Races': 'nope'},
          },
        }, now: _now),
        isEmpty,
      );
      expect(
        parseJolpicaSeason({
          'MRData': {
            'RaceTable': {'Races': <Object?>[]},
          },
        }, now: _now),
        isEmpty,
      );
    });

    test('the parser never throws on structurally wrong races', () {
      final events = parseRaces([
        'string race',
        7,
        null,
        const <String, dynamic>{},
        {'season': '2026', 'raceName': 'No round yet'},
        {
          'season': '2026',
          'round': '5',
          'date': 'not-a-date',
          'time': '17:00:00Z',
        },
        {
          'season': '2026',
          'round': '6',
          'date': '2026-11-08',
          'time': 'whenever',
          'Circuit': 'nope',
        },
        raceJson(),
      ]);
      expect(events, hasLength(1));
      expect(events.single.id, 'f1-2026-1');
      expect(events.single.subtitle, 'Test Circuit');
    });
  });

  group('jolpica_f1_season.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseJolpicaSeason(fixture('jolpica_f1_season.json'), now: _now);
    });

    test('drops the untimed race and keeps four in round order', () {
      expect(events, hasLength(4));
      expect(events.map((e) => e.id), [
        'f1-2026-20',
        'f1-2026-21',
        'f1-2026-22',
        'f1-2026-23',
      ]);
      expect(events.every((e) => e.leagueId == 'f1'), isTrue);
    });

    test('maps title, circuit and UTC start', () {
      final brazil = events.first;
      expect(brazil.title, 'Brazilian Grand Prix');
      expect(brazil.displayTitle, 'Brazilian Grand Prix');
      expect(brazil.subtitle, 'Autódromo José Carlos Pace');
      expect(brazil.start, DateTime.utc(2026, 11, 8, 17));
      expect(brazil.start.isUtc, isTrue);
      expect(events[1].start, DateTime.utc(2026, 11, 22, 4));
      expect(events[1].subtitle, 'Las Vegas Strip Street Circuit');
      expect(events[2].title, 'Qatar Grand Prix');
      expect(events[3].subtitle, 'Yas Marina Circuit');
      expect(events[3].start, DateTime.utc(2026, 12, 6, 13));
    });

    test('all four are upcoming relative to the reference now', () {
      for (final event in events) {
        expect(event.status, SportsEventStatus.scheduled);
        expect(event.statusLabel, '');
        expect(event.clock, isNull);
        expect(event.home, isNull);
        expect(event.away, isNull);
        expect(event.homeScore, isNull);
        expect(event.awayScore, isNull);
        expect(event.broadcasts, isEmpty);
        expect(event.isTeamEvent, isFalse);
        expect(event.involvesTeam('f1:20'), isFalse);
      }
    });
  });

  group('status from now', () {
    final start = DateTime.utc(2026, 11, 8, 17);

    SportsEvent statusAt(DateTime now) => parseRaces([
      raceJson(date: '2026-11-08', time: '17:00:00Z'),
    ], now: now).single;

    test('before the start it is scheduled', () {
      for (final now in [
        start.subtract(const Duration(days: 30)),
        start.subtract(const Duration(milliseconds: 1)),
      ]) {
        final event = statusAt(now);
        expect(event.status, SportsEventStatus.scheduled, reason: '$now');
        expect(event.statusLabel, '');
      }
    });

    test('the start instant itself is live', () {
      final event = statusAt(start);
      expect(event.status, SportsEventStatus.live);
      expect(event.statusLabel, 'Live');
      expect(event.clock, isNull);
    });

    test('the two hours after the start are live', () {
      final inside = statusAt(
        start.add(const Duration(hours: 1, minutes: 59, seconds: 59)),
      );
      expect(inside.status, SportsEventStatus.live);
      expect(inside.statusLabel, 'Live');
    });

    test('from start + 2h on it is finished', () {
      for (final now in [
        start.add(const Duration(hours: 2)),
        start.add(const Duration(hours: 2, milliseconds: 1)),
        start.add(const Duration(days: 5)),
      ]) {
        final event = statusAt(now);
        expect(event.status, SportsEventStatus.finished, reason: '$now');
        expect(event.statusLabel, 'Finished');
      }
    });

    test('a local now compares as the same instant', () {
      final event = statusAt(start.toLocal());
      expect(event.status, SportsEventStatus.live);
      expect(
        statusAt(start.subtract(const Duration(hours: 3)).toLocal()).status,
        SportsEventStatus.scheduled,
      );
      expect(
        statusAt(start.add(const Duration(hours: 6)).toLocal()).status,
        SportsEventStatus.finished,
      );
    });
  });

  group('race mapping', () {
    test('id combines league, season and round', () {
      final events = parseRaces([
        raceJson(season: '2027', round: '3'),
        raceJson(season: 2026, round: 5),
      ]);
      expect(events.map((e) => e.id), ['f1-2027-3', 'f1-2026-5']);
    });

    test('races without time, date, season or round are skipped', () {
      final events = parseRaces([
        raceJson(round: '10', time: null),
        raceJson(round: '11', time: ''),
        raceJson(round: '12', date: ''),
        raceJson(round: '13', season: ''),
        raceJson(round: '14', season: '   '),
        raceJson(round: '15'),
      ]);
      expect(events.map((e) => e.id), ['f1-2026-15']);
    });

    test('missing raceName and Circuit produce null title and subtitle', () {
      final events = parseRaces([
        {
          'season': '2026',
          'round': '7',
          'date': '2026-11-08',
          'time': '17:00:00Z',
        },
      ]);
      expect(events.single.title, isNull);
      expect(events.single.subtitle, isNull);
      expect(events.single.id, 'f1-2026-7');
    });

    test('an empty raceName or circuit name is treated as absent', () {
      final events = parseRaces([
        raceJson(round: '8', raceName: '', circuitName: ''),
      ]);
      expect(events.single.title, isNull);
      expect(events.single.subtitle, isNull);
    });

    test('minute-precision times still parse', () {
      final events = parseRaces([
        raceJson(round: '9', date: '2026-11-08', time: '17:00Z'),
      ]);
      expect(events.single.start, DateTime.utc(2026, 11, 8, 17));
    });

    test('a time with an explicit offset becomes UTC', () {
      final events = parseRaces([
        raceJson(round: '9', date: '2026-11-08', time: '18:00:00+01:00'),
      ]);
      expect(events.single.start, DateTime.utc(2026, 11, 8, 17));
    });

    test('events keep the feed round order', () {
      final events = parseRaces([
        raceJson(round: '2', date: '2026-12-01', time: '12:00:00Z'),
        raceJson(round: '1', date: '2026-11-01', time: '12:00:00Z'),
      ]);
      expect(events.map((e) => e.id), ['f1-2026-2', 'f1-2026-1']);
    });
  });
}
