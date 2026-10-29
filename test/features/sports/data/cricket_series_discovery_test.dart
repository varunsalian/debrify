import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/data/cricket_series_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Real ESPN header feed recorded 2026-10-29: 13 running competitions, five
  // of them international (Test 1, ODI 2, T20I 3; domestic is 0).
  final header = jsonDecode(
    File(
      'test/features/sports/fixtures/espn_header_cricket.json',
    ).readAsStringSync(),
  );

  test('international series only, in feed order', () {
    final series = internationalCricketSeries(header);
    expect(series.map((s) => s.id), [
      '24756',
      '24203',
      '24799',
      '1550706',
      '19439',
    ]);
    expect(series[1].name, 'Australia tour of South Africa 2026/27');
    expect(series.map((s) => s.name), isNot(contains('Ranji Trophy')));
  });

  test('duplicates collapse to the first', () {
    final json = jsonDecode(jsonEncode(header)) as Map<String, dynamic>;
    final leagues = ((json['sports'] as List).first as Map)['leagues'] as List;
    leagues.add(jsonDecode(jsonEncode(leagues.first)));
    expect(
      internationalCricketSeries(json).where((s) => s.id == '24756'),
      hasLength(1),
    );
  });

  test('malformed input gives an empty list', () {
    for (final input in <Object?>[
      null,
      1,
      'x',
      <String, dynamic>{},
      {'sports': 'no'},
    ]) {
      expect(internationalCricketSeries(input), isEmpty);
    }
  });

  test('a league without events or class is skipped', () {
    final json = {
      'sports': [
        {
          'leagues': [
            {'id': '1', 'name': 'No events'},
            {
              'id': '2',
              'name': 'No class',
              'events': [
                {'id': 'e'},
              ],
            },
            {
              'id': '3',
              'name': 'Intl',
              'events': [
                {
                  'class': {'internationalClassId': '2'},
                },
              ],
            },
          ],
        },
      ],
    };
    expect(internationalCricketSeries(json).map((s) => s.id), ['3']);
  });
}
