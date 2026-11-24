// ESPN game summaries → match stats, against trimmed real payloads for each
// sport family and state, plus the malformed and edge shapes the feed can
// send.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/espn_summary_parser.dart';
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/features/sports/fixtures/$name').readAsStringSync());

SportsMatchStats _parse(String name) => parseEspnSummary(_fixture(name))!;

SportsTeamStat _stat(SportsMatchStats stats, String name) =>
    stats.teamStats.firstWhere((s) => s.name == name);

/// A minimal summary with the two sides and whatever [extra] adds.
Map<String, Object?> _summary([Map<String, Object?> extra = const {}]) => {
  'header': {
    'competitions': [
      {
        'status': {
          'type': {'state': 'in', 'name': 'STATUS_IN_PROGRESS'},
        },
        'competitors': [
          {
            'homeAway': 'home',
            'id': '1',
            'team': {'id': '1', 'abbreviation': 'HOM', 'displayName': 'Home'},
          },
          {
            'homeAway': 'away',
            'id': '2',
            'team': {'id': '2', 'abbreviation': 'AWY', 'displayName': 'Away'},
          },
        ],
      },
    ],
  },
  ...extra,
};

void main() {
  group('finished NFL game', () {
    final stats = _parse('espn_summary_nfl_final.json');

    test('reads both sides, the score, records and colours', () {
      expect(stats.status, SportsEventStatus.finished);
      expect(stats.statusDetail, 'Final');
      expect(stats.home.abbreviation, 'HOU');
      expect(stats.home.score, '26');
      expect(stats.home.record, '4-6');
      expect(stats.home.color, 0xFF021018);
      expect(stats.home.alternateColor, 0xFFEB0028);
      expect(stats.away.abbreviation, 'IND');
      expect(stats.away.score, '3');
      expect(stats.isPreview, isFalse);
    });

    test('keeps the win probability in play order, ending on the result', () {
      expect(stats.winProbability.length, greaterThan(10));
      expect(stats.winProbability.first, closeTo(0.7478, 1e-9));
      expect(stats.winProbability.last, 1.0);
    });

    test('pairs team stats by name, home first', () {
      final yards = _stat(stats, 'totalYards');
      expect(yards.label, 'Total Yards');
      expect((yards.homeText, yards.awayText), ('354', '167'));
      // `value` is "-" for this stat: the figure comes from the text.
      expect((yards.homeValue, yards.awayValue), (354, 167));
      final possession = _stat(stats, 'possessionTime');
      expect(possession.awayText, '22:14');
      expect(possession.awayValue, 1334);
    });

    test('keeps the first of a repeated stat name', () {
      final names = stats.teamStats.map((s) => s.name).toList();
      expect(names.where((n) => n == 'interceptions'), hasLength(1));
    });

    test('pairs leaders per category across the two sides', () {
      final passing = stats.leaders.first;
      expect(passing.category, 'Passing Yards');
      expect(passing.home!.name, 'C.J. Stroud');
      expect(passing.home!.summary, '21/27, 194 YDS, 3 TD, 1 INT');
      expect(passing.home!.headshotUrl, contains('4432577'));
      expect(passing.away!.shortName, 'D. Jones');
      expect(stats.leaders.map((l) => l.category), [
        'Passing Yards',
        'Rushing Yards',
        'Receiving Yards',
        'Sacks',
        'Tackles',
      ]);
    });

    test('is started, with its kick-off time', () {
      expect(stats.started, isTrue);
      expect(stats.start, DateTime.utc(2026, 11, 20, 1, 15));
    });

    test('has no form or predictor once the game is over', () {
      expect(stats.homeForm, isEmpty);
      expect(stats.awayForm, isEmpty);
      expect(stats.prediction, isNull);
      expect(stats.hasContent, isTrue);
    });
  });

  group('NBA preview', () {
    final stats = _parse('espn_summary_nba_scheduled.json');

    test('is a season preview with the matchup predictor', () {
      expect(stats.status, SportsEventStatus.scheduled);
      expect(stats.isPreview, isTrue);
      expect(stats.started, isFalse);
      expect(stats.start, DateTime.utc(2026, 11, 25));
      expect(stats.home.score, isNull);
      expect(
        stats.prediction,
        const SportsMatchPrediction(home: 46.1, away: 53.9),
      );
      expect(stats.winProbability, isEmpty);
    });

    test('reads each side\'s last five games, oldest first', () {
      expect(stats.homeForm, hasLength(5));
      expect(stats.awayForm, hasLength(5));
      final first = stats.homeForm.first;
      expect(first.result, SportsFormResult.win);
      expect(first.score, '107-99');
      expect(first.home, isTrue);
      expect(first.opponentAbbreviation, 'MIL');
      expect(stats.homeForm[1].home, isFalse, reason: 'atVs "@"');
    });

    test('season averages keep text-only stats without a number', () {
      expect(_stat(stats, 'streak').homeValue, isNull);
      expect(_stat(stats, 'avgPoints').homeValue, 108.8);
    });
  });

  test('a finished football match reads all 28 stats and both forms', () {
    final stats = _parse('espn_summary_epl_final.json');
    expect(stats.teamStats, hasLength(28));
    final possession = _stat(stats, 'possessionPct');
    expect((possession.homeText, possession.awayText), ('29.8', '70.2'));
    expect(possession.homeValue, 29.8);
    expect(stats.leaders, hasLength(4));
    expect(stats.homeForm.first.result, SportsFormResult.draw);
    expect(stats.winProbability, isEmpty);
  });

  test('baseball groups its stats under the group name', () {
    final stats = _parse('espn_summary_mlb_final.json');
    final hits = _stat(stats, 'batting.hits');
    expect(hits.label, 'Hits');
    expect(_stat(stats, 'pitching.hits').name, 'pitching.hits');
    // ".125": a batting average without its leading zero.
    final average = _stat(stats, 'batting.avg');
    expect(average.homeText, startsWith('.'));
    expect(average.homeValue, double.parse('0${average.homeText}'));
    expect(stats.leaders, isEmpty);
    expect(stats.winProbability, isNotEmpty);
  });

  test('hockey has stats and leaders but no win probability', () {
    final stats = _parse('espn_summary_nhl_final.json');
    expect(stats.winProbability, isEmpty);
    expect(_stat(stats, 'shotsTotal').homeText, isNotEmpty);
    expect(stats.leaders, isNotEmpty);
  });

  test('a rugby preview has form only; a blank colour is no colour', () {
    final stats = _parse('espn_summary_rugby_scheduled.json');
    expect(stats.teamStats, isEmpty);
    expect(stats.leaders, isEmpty);
    expect(stats.homeForm, isNotEmpty);
    expect(stats.away.color, isNull);
    expect(stats.hasContent, isTrue);
  });

  group('malformed and edge payloads', () {
    test('anything without two sides is not a match', () {
      expect(parseEspnSummary(null), isNull);
      expect(parseEspnSummary('nope'), isNull);
      expect(parseEspnSummary(const {'header': {}}), isNull);
      final oneSide = _summary();
      ((oneSide['header'] as Map)['competitions'] as List).first['competitors']
          .removeLast();
      expect(parseEspnSummary(oneSide), isNull);
    });

    test('a delayed start is still scheduled, like on the board', () {
      final delayed = _summary();
      final competition =
          ((delayed['header'] as Map)['competitions'] as List).first as Map;
      competition['status'] = {
        'type': {'state': 'pre', 'name': 'STATUS_DELAYED'},
      };
      final stats = parseEspnSummary(delayed)!;
      expect(stats.status, SportsEventStatus.scheduled);
      expect(stats.isPreview, isTrue);

      // The shape ESPN really sends (MLB 401695026): "post", not completed,
      // with a "0" score.
      competition['status'] = {
        'type': {
          'state': 'post',
          'name': 'STATUS_POSTPONED',
          'completed': false,
        },
      };
      final postponed = parseEspnSummary(delayed)!;
      expect(postponed.status, SportsEventStatus.postponed);
      expect(postponed.started, isFalse, reason: 'it never kicked off');
      expect(postponed.isPreview, isTrue);
    });

    test('one win-probability point is not a chart', () {
      final stats = parseEspnSummary(
        _summary({
          'winprobability': [
            {'homeWinPercentage': 0.6},
          ],
        }),
      )!;
      expect(stats.hasWinProbability, isFalse);
      expect(stats.hasContent, isFalse);
    });

    test('a bare match has no content but still parses', () {
      final stats = parseEspnSummary(_summary())!;
      expect(stats.status, SportsEventStatus.live);
      expect(stats.hasContent, isFalse);
    });

    test('long win-probability series are thinned, keeping the last point', () {
      final points = [
        for (var i = 0; i < 1000; i++) {'homeWinPercentage': i / 999},
      ];
      final stats = parseEspnSummary(_summary({'winprobability': points}))!;
      expect(stats.winProbability, hasLength(maxWinProbabilityPoints));
      expect(stats.winProbability.first, 0);
      expect(stats.winProbability.last, 1);
    });

    test('a predictor naming the sides the other way round is swapped', () {
      final stats = parseEspnSummary(
        _summary({
          'predictor': {
            'homeTeam': {'id': '2', 'gameProjection': '70'},
            'awayTeam': {'id': '1', 'gameProjection': '30'},
          },
        }),
      )!;
      expect(stats.prediction, const SportsMatchPrediction(home: 30, away: 70));
    });

    test('stat figures come from the text when the value is missing', () {
      Map<String, Object?> team(String id, String text) => {
        'team': {'id': id},
        'statistics': [
          {'name': 'comp', 'label': 'Comp', 'displayValue': text, 'value': '-'},
        ],
      };
      Object? value(String text) => parseEspnSummary(
        _summary({
          'boxscore': {
            'teams': [team('1', text), team('2', text)],
          },
        }),
      )!.teamStats.single.homeValue;
      expect(value('12/29'), 12);
      expect(value('30-68'), 30);
      expect(value('.250'), 0.25);
      expect(value('5:07'), 307);
      expect(value('W3'), isNull);
    });

    test('a leader category with no player on either side is dropped', () {
      final stats = parseEspnSummary(
        _summary({
          'leaders': [
            {
              'team': {'id': '1'},
              'leaders': [
                {'name': 'points', 'displayName': 'Points', 'leaders': []},
              ],
            },
          ],
        }),
      )!;
      expect(stats.leaders, isEmpty);
    });
  });
}
