// Shared inputs for the match stats tests (data, application and page): the
// trimmed ESPN summary fixtures, board events that match them, and a fake
// fetch that records its calls.
import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/sports/models/sports_models.dart';

/// Decoded `test/features/sports/fixtures/<name>`.
Object? readSummaryFixture(String name) =>
    jsonDecode(File('test/features/sports/fixtures/$name').readAsStringSync());

const _artworkKeys = {'logo', 'logos', 'headshot', 'opponentLogo'};

/// [json] without logo and headshot URLs, so widget tests never reach for
/// network images.
Object? withoutArtwork(Object? json) {
  if (json is Map) {
    return {
      for (final entry in json.entries)
        if (!_artworkKeys.contains(entry.key))
          entry.key: withoutArtwork(entry.value),
    };
  }
  if (json is List) return [for (final item in json) withoutArtwork(item)];
  return json;
}

SportsTeam _team(String id, String abbreviation, String name) =>
    SportsTeam(id: id, name: name, shortName: name, abbreviation: abbreviation);

final nflFinalEvent = SportsEvent(
  id: '401873066',
  leagueId: 'nfl',
  start: DateTime.utc(2030, 3, 3, 18),
  status: SportsEventStatus.finished,
  statusLabel: 'Final',
  home: _team('34', 'HOU', 'Houston Texans'),
  away: _team('11', 'IND', 'Indianapolis Colts'),
  homeScore: 26,
  awayScore: 3,
);

final nbaScheduledEvent = SportsEvent(
  id: '401909314',
  leagueId: 'nba',
  start: DateTime.utc(2030, 3, 7, 0, 30),
  status: SportsEventStatus.scheduled,
  home: _team('19', 'ORL', 'Orlando Magic'),
  away: _team('8', 'DET', 'Detroit Pistons'),
);

final eplFinalEvent = SportsEvent(
  id: '401879234',
  leagueId: 'epl',
  start: DateTime.utc(2030, 3, 2, 15),
  status: SportsEventStatus.finished,
  statusLabel: 'FT',
  home: _team('306', 'HUL', 'Hull City'),
  away: _team('331', 'BHA', 'Brighton & Hove Albion'),
  homeScore: 2,
  awayScore: 0,
);

final atpEvent = SportsEvent(
  id: 'atp-1',
  leagueId: 'atp',
  start: DateTime.utc(2030, 3, 2, 15),
  status: SportsEventStatus.live,
  home: _team('p1', 'SIN', 'Jannik Sinner'),
  away: _team('p2', 'ALC', 'Carlos Alcaraz'),
);

/// A fetch that answers with [body] and records every requested URL.
class FakeSummaryFetch {
  FakeSummaryFetch(this.body);

  /// The next answer; a thrown [Object] fails the fetch instead.
  Object body;
  final List<Uri> calls = [];

  Future<String> call(Uri uri) async {
    calls.add(uri);
    final answer = body;
    if (answer is String) return answer;
    throw answer;
  }
}

/// [name]'s fixture, artwork removed, as a response body.
String summaryBody(String name) =>
    jsonEncode(withoutArtwork(readSummaryFixture(name)));
