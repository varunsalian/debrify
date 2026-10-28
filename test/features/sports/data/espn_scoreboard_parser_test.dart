import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/espn_scoreboard_parser.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtureDir = 'test/features/sports/fixtures';

Object? fixture(String name) =>
    jsonDecode(File('$_fixtureDir/$name').readAsStringSync());

Map<String, dynamic> homeTeamJson({
  Object id = '1',
  String displayName = 'Home FC',
  String? shortDisplayName,
  String? abbreviation,
  String? logo,
  Object? color,
}) => {
  'id': id,
  'displayName': displayName,
  if (shortDisplayName != null) 'shortDisplayName': shortDisplayName,
  if (abbreviation != null) 'abbreviation': abbreviation,
  if (logo != null) 'logo': logo,
  if (color != null) 'color': color,
};

Map<String, dynamic> awayTeamJson({
  Object id = '2',
  String displayName = 'Away FC',
  String? shortDisplayName,
  String? abbreviation,
}) => {
  'id': id,
  'displayName': displayName,
  if (shortDisplayName != null) 'shortDisplayName': shortDisplayName,
  if (abbreviation != null) 'abbreviation': abbreviation,
};

Map<String, dynamic> competitorJson(
  Map<String, dynamic> team, {
  required String homeAway,
  String? score,
}) => {'homeAway': homeAway, 'team': team, if (score != null) 'score': score};

Map<String, dynamic> statusJson({
  String? state,
  String? name,
  bool? completed,
  String? detail,
  String? shortDetail,
  String? displayClock,
}) => {
  if (displayClock != null) 'displayClock': displayClock,
  'type': {
    if (state != null) 'state': state,
    if (name != null) 'name': name,
    if (completed != null) 'completed': completed,
    if (detail != null) 'detail': detail,
    if (shortDetail != null) 'shortDetail': shortDetail,
  },
};

Map<String, dynamic> eventJson({
  Object id = 'e1',
  String? date = '2026-10-31T12:30Z',
  Map<String, dynamic>? status,
  List<Map<String, dynamic>>? competitors,
  Map<String, dynamic>? competitionExtra,
  Object? competitions,
}) => {
  'id': id,
  if (date != null) 'date': date,
  if (status != null) 'status': status,
  'competitions': [
    if (competitions == null) ...[
      {
        'competitors':
            competitors ??
            [
              competitorJson(homeTeamJson(), homeAway: 'home'),
              competitorJson(awayTeamJson(), homeAway: 'away'),
            ],
        if (competitionExtra != null) ...competitionExtra,
      },
    ] else ...[
      competitions,
    ],
  ],
};

/// One well-formed event wrapping [body] in a scoreboard envelope.
Map<String, dynamic> scoreboard(Map<String, dynamic> event) => {
  'events': [event],
};

List<SportsEvent> parseOne(
  Map<String, dynamic> event, {
  String leagueId = 'ucl',
}) => parseEspnScoreboard(scoreboard(event), leagueId: leagueId);

void main() {
  group('shape guards', () {
    test('non-map payloads yield no events', () {
      for (final bad in <Object?>[
        null,
        'not json',
        42,
        <Object?>[],
        <Object?>['a'],
      ]) {
        expect(
          parseEspnScoreboard(bad, leagueId: 'ucl'),
          isEmpty,
          reason: 'payload $bad must not produce events',
        );
      }
    });

    test('missing or non-list events yield no events', () {
      expect(parseEspnScoreboard({}, leagueId: 'ucl'), isEmpty);
      expect(parseEspnScoreboard({'events': 'nope'}, leagueId: 'ucl'), isEmpty);
      expect(
        parseEspnScoreboard({
          'events': {'id': 'e1'},
        }, leagueId: 'ucl'),
        isEmpty,
      );
      expect(parseEspnScoreboard({'events': []}, leagueId: 'ucl'), isEmpty);
    });

    test('the parser never throws on structurally wrong feeds', () {
      final weird = <Object?>[
        {
          'events': [
            'string event',
            7,
            null,
            {'id': 'e1', 'date': '2026-10-31T12:30Z', 'competitions': 'nope'},
            {
              'id': 'e2',
              'date': '2026-10-31T12:30Z',
              'competitions': [
                {
                  'competitors': {'homeAway': 'home'},
                },
              ],
            },
            {
              'id': 'e3',
              'date': <Object?>[],
              'competitions': [
                {
                  'competitors': [null, 3],
                },
              ],
            },
            {
              'id': 'e4',
              'date': '2026-10-31T12:30Z',
              'status': 'nope',
              'competitions': [
                {
                  'competitors': [
                    competitorJson(homeTeamJson(), homeAway: 'home'),
                    competitorJson(awayTeamJson(), homeAway: 'away'),
                  ],
                  'broadcasts': 'nope',
                  'geoBroadcasts': [
                    {'media': 'nope'},
                  ],
                  'venue': 'nope',
                },
              ],
            },
          ],
        },
      ];
      for (final payload in weird) {
        final events = parseEspnScoreboard(payload, leagueId: 'epl');
        expect(events.map((e) => e.id), ['e4']);
        expect(events.single.broadcasts, isEmpty);
        expect(events.single.statusLabel, '');
        expect(events.single.subtitle, isNull);
      }
    });
  });

  group('espn_ucl_live.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseEspnScoreboard(
        fixture('espn_ucl_live.json'),
        leagueId: 'ucl',
      );
    });

    test('keeps both events in feed order', () {
      expect(events, hasLength(2));
      expect(events.map((e) => e.id), ['401915395', '401915396']);
      expect(events.every((e) => e.leagueId == 'ucl'), isTrue);
    });

    test('first event is live with scores and a clock', () {
      final event = events.first;
      expect(event.status, SportsEventStatus.live);
      expect(event.start, DateTime.utc(2026, 10, 21, 16, 45));
      expect(event.start.isUtc, isTrue);
      expect(event.homeScore, 1);
      expect(event.awayScore, 0);
      expect(event.clock, "41'");
      expect(event.statusLabel, "41'");
      expect(event.subtitle, 'Giuseppe Sinigaglia');
      expect(event.title, isNull);
      expect(event.isTeamEvent, isTrue);
      expect(event.displayTitle, 'Como v Manchester United');
      expect(event.broadcasts, ['Paramount+']);
      expect(event.involvesTeam('ucl:2572'), isTrue);
      expect(event.involvesTeam('ucl:360'), isTrue);
      expect(event.involvesTeam('epl:360'), isFalse);
    });

    test('maps both teams completely', () {
      final home = events.first.home!;
      expect(home.id, '2572');
      expect(home.name, 'Como');
      expect(home.shortName, 'Como');
      expect(home.abbreviation, 'COMO');
      expect(
        home.logoUrl,
        'https://a.espncdn.com/i/teamlogos/soccer/500/2572.png',
      );
      expect(home.color, 0xFF4169E1);

      final away = events.first.away!;
      expect(away.id, '360');
      expect(away.name, 'Manchester United');
      expect(away.shortName, 'Man Utd');
      expect(away.abbreviation, 'MAN');
      expect(away.color, 0xFFDA020E, reason: 'lowercase hex still parses');
      expect(away.keyIn('ucl'), 'ucl:360');
    });

    test('second event is postponed with no scores or clock', () {
      final event = events[1];
      expect(event.status, SportsEventStatus.postponed);
      expect(event.homeScore, isNull);
      expect(event.awayScore, isNull);
      expect(event.clock, isNull);
      expect(event.statusLabel, 'Postponed');
      expect(event.home!.name, 'Lille');
      expect(event.away!.name, 'Galatasaray');
    });
  });

  group('espn_ucl_finished.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseEspnScoreboard(
        fixture('espn_ucl_finished.json'),
        leagueId: 'ucl',
      );
    });

    test('first event is finished with FT and both scores', () {
      final event = events.first;
      expect(event.id, '401915395');
      expect(event.status, SportsEventStatus.finished);
      expect(event.home!.name, 'Como');
      expect(event.homeScore, 4);
      expect(event.away!.abbreviation, 'MAN');
      expect(event.awayScore, 1);
      expect(event.statusLabel, 'FT');
      expect(event.clock, isNull, reason: 'only live events carry a clock');
    });

    test('sorts by start then id', () {
      expect(events, hasLength(4));
      expect(events.map((e) => e.id), [
        '401915395',
        '401915396',
        '401915312',
        '401915394',
      ]);
      expect(events[1].start, DateTime.utc(2026, 10, 21, 16, 45));
      expect(events[2].subtitle, 'Allianz Arena');
      expect(events[2].start, DateTime.utc(2026, 10, 21, 19));
    });

    test('every finished event keeps its result', () {
      expect(events.map((e) => '${e.homeScore}-${e.awayScore}'), [
        '4-1',
        '2-4',
        '2-2',
        '3-1',
      ]);
      expect(
        events.every((e) => e.status == SportsEventStatus.finished),
        isTrue,
      );
    });
  });

  group('espn_epl_scheduled.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseEspnScoreboard(
        fixture('espn_epl_scheduled.json'),
        leagueId: 'epl',
      );
    });

    test('first event is a scheduled kickoff without scores', () {
      final event = events.first;
      expect(event.id, '401879248');
      expect(event.status, SportsEventStatus.scheduled);
      expect(event.home!.name, 'Chelsea');
      expect(event.away!.name, 'Manchester United');
      expect(event.start, DateTime.utc(2026, 10, 31, 12, 30));
      expect(event.homeScore, isNull, reason: 'feed seeds 0-0 before kickoff');
      expect(event.awayScore, isNull);
      expect(event.clock, isNull);
      expect(event.statusLabel, 'Scheduled');
      expect(event.subtitle, 'Stamford Bridge');
      expect(event.broadcasts, ['USA Net', 'Tele']);
    });

    test('four events, tied starts ordered by id', () {
      expect(events, hasLength(4));
      expect(events.map((e) => e.id), [
        '401879248',
        '401879247',
        '401879249',
        '401879251',
      ]);
      expect(
        events.skip(1).every((e) => e.start == DateTime.utc(2026, 10, 31, 15)),
        isTrue,
      );
    });

    test('team-only broadcasters are deduped against geoBroadcasts', () {
      expect(events[1].broadcasts, ['Peacock']);
      expect(events[2].broadcasts, ['USA Net', 'Universo']);
    });
  });

  group('espn_nba.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseEspnScoreboard(fixture('espn_nba.json'), leagueId: 'nba');
    });

    test('first event is a finished game with both scores', () {
      final event = events.first;
      expect(event.status, SportsEventStatus.finished);
      expect(event.home!.name, 'Boston Celtics');
      expect(event.home!.shortName, 'Celtics');
      expect(event.homeScore, 125);
      expect(event.away!.name, 'Brooklyn Nets');
      expect(event.awayScore, 124);
      expect(event.statusLabel, 'Final/OT');
      expect(event.clock, isNull);
      expect(event.subtitle, 'TD Garden');
      expect(event.displayTitle, 'Boston Celtics v Brooklyn Nets');
    });

    test('dedupes a broadcaster spelled identically in both lists', () {
      expect(events.first.broadcasts, ['NBA League Pass', 'DAZN (YES)']);
    });

    test('three events sorted by start then id', () {
      expect(events.map((e) => e.id), ['401909877', '401909878', '401909879']);
      expect(events[2].broadcasts, ['NBA League Pass']);
    });
  });

  group('espn_nfl_scheduled.json', () {
    late List<SportsEvent> events;

    setUpAll(() {
      events = parseEspnScoreboard(
        fixture('espn_nfl_scheduled.json'),
        leagueId: 'nfl',
      );
    });

    test('all three games are scheduled with date-ish shortDetail', () {
      expect(events, hasLength(3));
      expect(events.map((e) => e.id), ['401873023', '401873026', '401873031']);
      expect(
        events.map((e) => e.status),
        everyElement(SportsEventStatus.scheduled),
      );
      expect(events.first.start, DateTime.utc(2026, 10, 30, 0, 15));
      expect(events.first.home!.name, 'Green Bay Packers');
      expect(events.first.statusLabel, '10/29 - 8:15 PM EDT');
      expect(events.first.subtitle, 'Lambeau Field');
      expect(events.first.broadcasts, ['Prime Video']);
      expect(events.first.homeScore, isNull);
      expect(events[1].broadcasts, ['CBS']);
      expect(events[1].statusLabel, '11/1 - 1:00 PM EST');
    });
  });

  group('malformed events', () {
    test('are skipped while their siblings survive', () {
      final good = eventJson(id: 'good');
      final events = parseEspnScoreboard({
        'events': [
          'not a map',
          42,
          null,
          const <String, dynamic>{},
          eventJson(id: 'no-date', date: null),
          eventJson(id: 'bad-date', date: 'tomorrow'),
          eventJson(id: 'blank-date', date: '   '),
          eventJson(id: 'no-competitions', competitions: <Object?>[]),
          eventJson(
            id: 'no-competitors',
            competitors: <Map<String, dynamic>>[],
          ),
          eventJson(
            id: 'home-only',
            competitors: [competitorJson(homeTeamJson(), homeAway: 'home')],
          ),
          eventJson(
            id: 'team-missing',
            competitors: [
              {'homeAway': 'home'},
              competitorJson(awayTeamJson(), homeAway: 'away'),
            ],
          ),
          eventJson(
            id: 'team-without-id',
            competitors: [
              competitorJson({'displayName': 'No Id'}, homeAway: 'home'),
              competitorJson(awayTeamJson(), homeAway: 'away'),
            ],
          ),
          eventJson(
            id: 'wrong-home-away',
            competitors: [
              competitorJson(homeTeamJson(), homeAway: 'H'),
              competitorJson(awayTeamJson(), homeAway: 'A'),
            ],
          ),
          good,
        ],
      }, leagueId: 'ucl');

      expect(events.map((e) => e.id), ['good']);
      expect(events.single.leagueId, 'ucl');
    });

    test('numeric ids become strings', () {
      final events = parseOne(eventJson(id: 401915395));
      expect(events.single.id, '401915395');
      expect(events.single.home!.id, '1');
    });

    test('a numeric team id becomes a string', () {
      final events = parseOne(
        eventJson(
          competitors: [
            competitorJson(homeTeamJson(id: 2572), homeAway: 'home'),
            competitorJson(awayTeamJson(), homeAway: 'away'),
          ],
        ),
      );
      expect(events.single.home!.id, '2572');
    });
  });

  group('team mapping', () {
    test('falls back to displayName, empty abbreviation and null logo', () {
      final events = parseOne(
        eventJson(
          competitors: [
            competitorJson(homeTeamJson(id: '10'), homeAway: 'home'),
            competitorJson(
              awayTeamJson(id: '20', displayName: 'Away Athletic'),
              homeAway: 'away',
            ),
          ],
        ),
      );
      final home = events.single.home!;
      expect(home.name, 'Home FC');
      expect(home.shortName, 'Home FC');
      expect(home.abbreviation, '');
      expect(home.logoUrl, isNull);
      expect(home.color, isNull);
      expect(events.single.away!.shortName, 'Away Athletic');
    });

    test('parses 6-digit hex colors with an optional #', () {
      final events = parseOne(
        eventJson(
          competitors: [
            competitorJson(
              homeTeamJson(color: 'EF0107', logo: 'https://logo/home.png'),
              homeAway: 'home',
            ),
            competitorJson(awayTeamJson(), homeAway: 'away'),
          ],
        ),
      );
      expect(events.single.home!.color, 0xFFEF0107);
      expect(events.single.home!.logoUrl, 'https://logo/home.png');
    });

    test('rejects malformed colors', () {
      for (final color in <Object>[
        'FFF',
        'GGGGGG',
        '1234567',
        '#12345',
        '',
        'ff00',
        0xFF0000,
        true,
      ]) {
        final events = parseOne(
          eventJson(
            competitors: [
              competitorJson(homeTeamJson(color: color), homeAway: 'home'),
              competitorJson(awayTeamJson(), homeAway: 'away'),
            ],
          ),
        );
        expect(
          events.single.home!.color,
          isNull,
          reason: 'color $color is not 6 hex digits',
        );
      }
      final hashed = parseOne(
        eventJson(
          competitors: [
            competitorJson(homeTeamJson(color: '#da020e'), homeAway: 'home'),
            competitorJson(awayTeamJson(), homeAway: 'away'),
          ],
        ),
      );
      expect(hashed.single.home!.color, 0xFFDA020E);
    });
  });

  group('status mapping', () {
    test('state in is live even when marked completed', () {
      final events = parseOne(
        eventJson(
          status: statusJson(
            state: 'in',
            completed: true,
            shortDetail: '41\'',
            displayClock: '41\'',
          ),
          competitors: [
            competitorJson(homeTeamJson(), homeAway: 'home', score: '2'),
            competitorJson(awayTeamJson(), homeAway: 'away', score: '1'),
          ],
        ),
      );
      expect(events.single.status, SportsEventStatus.live);
      expect(events.single.homeScore, 2);
      expect(events.single.awayScore, 1);
    });

    test('state post splits on completed', () {
      SportsEventStatus status(bool completed) => parseOne(
        eventJson(
          status: statusJson(state: 'post', completed: completed),
        ),
      ).single.status;
      expect(status(true), SportsEventStatus.finished);
      expect(status(false), SportsEventStatus.postponed);
      expect(status(true), SportsEventStatus.finished);
    });

    test('a postponed or canceled pre-game status is postponed', () {
      for (final name in ['STATUS_POSTPONED', 'STATUS_CANCELED']) {
        final events = parseOne(
          eventJson(
            status: statusJson(state: 'pre', name: name, completed: false),
          ),
        );
        expect(events.single.status, SportsEventStatus.postponed, reason: name);
      }
    });

    test('everything else is scheduled', () {
      for (final status in <Map<String, dynamic>>[
        statusJson(state: 'pre', name: 'STATUS_SCHEDULED', completed: false),
        statusJson(state: 'pre', name: 'STATUS_IN_PROGRESS'),
        statusJson(state: 'after', completed: true),
        statusJson(state: 'unknown'),
        statusJson(),
        const <String, dynamic>{},
      ]) {
        final events = parseOne(eventJson(status: status));
        expect(
          events.single.status,
          SportsEventStatus.scheduled,
          reason: '$status',
        );
        expect(events.single.clock, isNull);
        expect(events.single.homeScore, isNull);
      }
    });

    test('scores are parsed only for live and finished events', () {
      List<SportsEvent> withScore(String state, {bool completed = false}) =>
          parseEspnScoreboard({
            'events': [
              eventJson(
                status: statusJson(state: state, completed: completed),
                competitors: [
                  competitorJson(homeTeamJson(), homeAway: 'home', score: '3'),
                  competitorJson(awayTeamJson(), homeAway: 'away', score: '2'),
                ],
              ),
            ],
          }, leagueId: 'ucl');

      expect(withScore('in').single.homeScore, 3);
      expect(withScore('in').single.awayScore, 2);
      expect(withScore('post', completed: true).single.homeScore, 3);
      expect(withScore('post').single.homeScore, isNull);
      expect(withScore('pre').single.homeScore, isNull);

      final unparsable = parseEspnScoreboard({
        'events': [
          eventJson(
            status: statusJson(state: 'in'),
            competitors: [
              competitorJson(homeTeamJson(), homeAway: 'home', score: 'ABC'),
              competitorJson(awayTeamJson(), homeAway: 'away', score: '7.5'),
            ],
          ),
        ],
      }, leagueId: 'ucl');
      expect(unparsable.single.homeScore, isNull);
      expect(unparsable.single.awayScore, isNull);

      final numericScore = parseEspnScoreboard({
        'events': [
          eventJson(
            status: statusJson(state: 'in'),
            competitors: [
              {'homeAway': 'home', 'score': 4, 'team': homeTeamJson()},
              competitorJson(awayTeamJson(), homeAway: 'away'),
            ],
          ),
        ],
      }, leagueId: 'ucl');
      expect(numericScore.single.homeScore, isNull);
    });
  });

  group('clock and statusLabel', () {
    test('live clock prefers shortDetail, then displayClock', () {
      expect(
        parseOne(
          eventJson(
            status: statusJson(
              state: 'in',
              shortDetail: "41'",
              displayClock: '41:02',
            ),
          ),
        ).single.clock,
        "41'",
      );
      expect(
        parseOne(
          eventJson(
            status: statusJson(
              state: 'in',
              shortDetail: '',
              displayClock: '12:00',
            ),
          ),
        ).single.clock,
        '12:00',
      );
      expect(
        parseOne(
          eventJson(
            status: statusJson(state: 'in', displayClock: '12:00'),
          ),
        ).single.clock,
        '12:00',
      );
      expect(
        parseOne(eventJson(status: statusJson(state: 'in'))).single.clock,
        isNull,
      );
      expect(
        parseOne(
          eventJson(
            status: statusJson(state: 'in', displayClock: ''),
          ),
        ).single.clock,
        isNull,
      );
    });

    test('statusLabel uses shortDetail, then detail, then empty', () {
      expect(
        parseOne(
          eventJson(
            status: statusJson(
              state: 'post',
              shortDetail: 'FT',
              detail: 'Full Time',
            ),
          ),
        ).single.statusLabel,
        'FT',
      );
      expect(
        parseOne(
          eventJson(
            status: statusJson(state: 'post', detail: 'Full Time'),
          ),
        ).single.statusLabel,
        'Full Time',
      );
      expect(
        parseOne(
          eventJson(
            status: statusJson(
              state: 'in',
              shortDetail: '',
              detail: 'Second Half',
              displayClock: '55:00',
            ),
          ),
        ).single.statusLabel,
        '',
        reason: 'an empty shortDetail is still a present value',
      );
      expect(
        parseOne(
          eventJson(status: statusJson(state: 'pre')),
        ).single.statusLabel,
        '',
      );
    });
  });

  group('broadcasts', () {
    test('lists names first, then geo media, trimmed and deduped', () {
      final events = parseOne(
        eventJson(
          competitionExtra: {
            'broadcasts': [
              {
                'names': [
                  '  Sky Sports Main Event ',
                  '',
                  '   ',
                  'TNT Sports 1',
                ],
              },
              {'names': 'not a list'},
              {'names': null},
              'not a map',
            ],
            'geoBroadcasts': [
              {
                'media': {'shortName': 'sky sports main event'},
              },
              {
                'media': {'shortName': 'Paramount+'},
              },
              {
                'media': {'other': 'x'},
              },
              {'media': null},
              'not a map',
              {
                'media': {'shortName': 12},
              },
            ],
          },
        ),
      );
      expect(events.single.broadcasts, [
        'Sky Sports Main Event',
        'TNT Sports 1',
        'Paramount+',
      ]);
    });

    test('keeps the first spelling of a duplicate', () {
      final events = parseOne(
        eventJson(
          competitionExtra: {
            'broadcasts': [
              {
                'names': ['Viaplayer SPORT', 'viaplayer sport', 'Sport TV'],
              },
            ],
          },
        ),
      );
      expect(events.single.broadcasts, ['Viaplayer SPORT', 'Sport TV']);
    });

    test('geo media only broadcasters are kept', () {
      final events = parseOne(
        eventJson(
          competitionExtra: {
            'geoBroadcasts': [
              {
                'media': {'shortName': 'Disney+'},
              },
            ],
          },
        ),
      );
      expect(events.single.broadcasts, ['Disney+']);
    });

    test('absent broadcasts yield an empty list', () {
      expect(parseOne(eventJson()).single.broadcasts, isEmpty);
    });
  });

  group('venue, title and start', () {
    test('subtitle comes from venue.fullName and is null when absent', () {
      expect(
        parseOne(
          eventJson(
            competitionExtra: {
              'venue': {'fullName': 'Anfield'},
            },
          ),
        ).single.subtitle,
        'Anfield',
      );
      expect(
        parseOne(eventJson(competitionExtra: {'venue': {}})).single.subtitle,
        isNull,
      );
      expect(parseOne(eventJson()).single.subtitle, isNull);
      expect(parseOne(eventJson()).single.title, isNull);
    });

    test('ESPN minute-precision dates become UTC instants', () {
      final events = parseOne(eventJson(date: '2026-10-31T12:30Z'));
      expect(events.single.start, DateTime.utc(2026, 10, 31, 12, 30));
      expect(events.single.start.isUtc, isTrue);
    });

    test('offset dates are normalised to UTC', () {
      final events = parseOne(eventJson(date: '2026-11-01T20:00:00+05:30'));
      expect(events.single.start, DateTime.utc(2026, 11, 1, 14, 30));
    });

    test('leagueId is applied to every event', () {
      final events = parseEspnScoreboard({
        'events': [eventJson(id: 'a'), eventJson(id: 'b')],
      }, leagueId: 'mls');
      expect(events.map((e) => e.leagueId), ['mls', 'mls']);
    });
  });
}
