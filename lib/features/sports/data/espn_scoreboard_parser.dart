// Parses an ESPN scoreboard feed (`site.api.espn.com/.../scoreboard`) into
// immutable [SportsEvent]s.
//
// Data layer: pure Dart, no UI and no network access. The feed is untrusted,
// so every accessor is defensive and this library never throws; a malformed
// event is dropped while its siblings survive.
import 'package:debrify/features/sports/data/espn_individual_parser.dart';
import 'package:debrify/features/sports/models/sports_leagues.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// ESPN status names that mean "will not be played as scheduled".
const Set<String> _postponedStatusNames = {
  'STATUS_POSTPONED',
  'STATUS_CANCELED',
};

/// Six hex digits with an optional leading `#`, e.g. `EF0107` or `#da020e`.
final RegExp _hexColor = RegExp(r'^#?([0-9a-fA-F]{6})$');

/// Converts an ESPN scoreboard payload into events sorted by start, then id.
///
/// [json] is the decoded feed body. Anything that is not a map with an
/// `events` list yields an empty result.
List<SportsEvent> parseEspnScoreboard(
  Object? json, {
  required String leagueId,
}) {
  final events = _list(_map(json)?['events']);
  if (events == null) return const [];
  final league = sportsLeagueById(leagueId);
  final shape = league == null
      ? SportsEventShape.teams
      : sportsEventShapeOf(league);
  // Cards that are not team v team (tennis draws, fight cards, golf and
  // racing) are laid out per competitor, not per team; F1 stays on Jolpica
  // and never reaches this parser.
  if (shape == SportsEventShape.sets ||
      shape == SportsEventShape.card ||
      shape == SportsEventShape.event) {
    return parseEspnIndividual(json, leagueId: leagueId, shape: shape);
  }
  // Cricket cards carry text scores and a match situation instead of numbers;
  // unknown league ids keep the team (numeric score) behaviour.
  final innings = shape == SportsEventShape.innings;
  final series = innings ? _seriesName(json) : null;
  final parsed = <SportsEvent>[];
  for (final raw in events) {
    final event = _parseEvent(raw, leagueId, innings: innings, series: series);
    if (event != null) parsed.add(event);
  }
  parsed.sort(_compareByStartThenId);
  return parsed;
}

int _compareByStartThenId(SportsEvent a, SportsEvent b) {
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return a.id.compareTo(b.id);
}

SportsEvent? _parseEvent(
  Object? raw,
  String leagueId, {
  bool innings = false,
  String? series,
}) {
  final event = _map(raw);
  if (event == null) return null;
  final id = _id(event['id']);
  if (id == null || id.isEmpty) return null;
  final start = _parseUtc(event['date']);
  if (start == null) return null;
  final competitions = _list(event['competitions']);
  if (competitions == null || competitions.isEmpty) return null;
  final competition = _map(competitions.first);
  if (competition == null) return null;

  final competitors = _splitHomeAway(competition['competitors']);
  final home = competitors.home;
  final away = competitors.away;
  if (home == null || away == null) return null;
  final homeTeam = _team(home);
  final awayTeam = _team(away);
  if (homeTeam == null || awayTeam == null) return null;

  final status = _map(event['status']);
  final type = _map(status?['type']) ?? const <String, dynamic>{};
  final eventStatus = _statusFor(
    state: _text(type['state']) ?? '',
    name: _text(type['name']) ?? '',
    completed: type['completed'] == true,
  );
  final scoring =
      eventStatus == SportsEventStatus.live ||
      eventStatus == SportsEventStatus.finished;

  var subtitle = _nonEmpty(_dig(competition, const ['venue', 'fullName']));
  String? format;
  String? note;
  bool? homeWon;
  if (innings) {
    // Cricket shows the match name ("3rd Test") where football shows a venue.
    final description = _trimmed(competition['description']);
    if (description != null) subtitle = description;
    format = _upper(_dig(competition, const ['class', 'generalClassCard']));
    note = _trimmed(_dig(competition, const ['status', 'summary']));
    homeWon = _inningsWinner(
      finished: eventStatus == SportsEventStatus.finished,
      home: home,
      away: away,
    );
  }

  return SportsEvent(
    id: id,
    leagueId: leagueId,
    start: start,
    status: eventStatus,
    home: homeTeam,
    away: awayTeam,
    homeScore: innings || !scoring ? null : _score(home['score']),
    awayScore: innings || !scoring ? null : _score(away['score']),
    subtitle: subtitle,
    clock: eventStatus == SportsEventStatus.live
        ? _liveClock(status: status, type: type)
        : null,
    statusLabel: _text(type['shortDetail']) ?? _text(type['detail']) ?? '',
    broadcasts: _broadcasts(competition),
    homeScoreText: innings ? _trimmed(home['score']) : null,
    awayScoreText: innings ? _trimmed(away['score']) : null,
    homeWon: homeWon,
    format: format,
    note: note,
    group: series,
  );
}

/// The payload's `leagues[0].name`: the series or tournament hosting the day.
String? _seriesName(Object? json) {
  final leagues = _list(_map(json)?['leagues']);
  if (leagues == null || leagues.isEmpty) return null;
  return _trimmed(_map(leagues.first)?['name']);
}

/// Cricket has no winner unless the match finished: a drawn match, and a
/// match whose `winner` flags are missing or both false, stays undecided.
bool? _inningsWinner({
  required bool finished,
  required Map<String, dynamic>? home,
  required Map<String, dynamic>? away,
}) {
  if (!finished) return null;
  if (_isWinner(home?['winner'])) return true;
  if (_isWinner(away?['winner'])) return false;
  return null;
}

/// ESPN sends `winner` as a bool or as the strings `"true"`/`"false"`.
bool _isWinner(Object? raw) =>
    raw == true || (raw is String && raw.trim().toLowerCase() == 'true');

/// Text that survives trimming; whitespace-only or empty becomes null.
String? _trimmed(Object? raw) {
  final text = _text(raw)?.trim();
  return (text == null || text.isEmpty) ? null : text;
}

String? _upper(Object? raw) => _trimmed(raw)?.toUpperCase();

/// The two `competitions[0].competitors` entries located by `homeAway`.
typedef _CompetitorPair = ({
  Map<String, dynamic>? home,
  Map<String, dynamic>? away,
});

_CompetitorPair _splitHomeAway(Object? raw) {
  Map<String, dynamic>? home;
  Map<String, dynamic>? away;
  for (final entry in _list(raw) ?? const <Object?>[]) {
    final competitor = _map(entry);
    if (competitor == null) continue;
    final homeAway = _text(competitor['homeAway']);
    if (homeAway == 'home' && home == null) {
      home = competitor;
    } else if (homeAway == 'away' && away == null) {
      away = competitor;
    }
  }
  return (home: home, away: away);
}

SportsEventStatus _statusFor({
  required String state,
  required String name,
  required bool completed,
}) {
  if (state == 'in') return SportsEventStatus.live;
  if (state == 'post') {
    return completed ? SportsEventStatus.finished : SportsEventStatus.postponed;
  }
  if (state == 'pre' && _postponedStatusNames.contains(name)) {
    return SportsEventStatus.postponed;
  }
  return SportsEventStatus.scheduled;
}

SportsTeam? _team(Map<String, dynamic>? competitor) {
  final team = _map(competitor?['team']);
  if (team == null) return null;
  final id = _id(team['id']);
  if (id == null || id.isEmpty) return null;
  final name = _text(team['displayName']) ?? '';
  return SportsTeam(
    id: id,
    name: name,
    shortName: _text(team['shortDisplayName']) ?? name,
    abbreviation: _text(team['abbreviation']) ?? '',
    logoUrl: _nonEmpty(team['logo']),
    color: _color(team['color']),
  );
}

/// Live clock only: `status.type.shortDetail`, else `status.displayClock`.
///
/// Cricket sends the bare word `Live` as its short detail and keeps the real
/// state (`Stumps`, `Lunch`, `Match delayed - Rain`) in `description`, with a
/// meaningless `0'` clock; the card already says LIVE, so the clock is the
/// description, or nothing.
String? _liveClock({
  required Map<String, dynamic>? status,
  required Map<String, dynamic> type,
}) {
  final shortDetail = _text(type['shortDetail']);
  if (shortDetail != null && shortDetail.toLowerCase() == 'live') {
    final description = _nonEmpty(type['description']);
    if (description == null) return null;
    const bare = {'live', 'in progress'};
    return bare.contains(description.toLowerCase()) ? null : description;
  }
  if (shortDetail != null && shortDetail.isNotEmpty) return shortDetail;
  return _nonEmpty(status?['displayClock']);
}

/// `broadcasts[*].names[*]` then `geoBroadcasts[*].media.shortName`, trimmed,
/// empty dropped, de-duplicated case-insensitively (first spelling wins).
List<String> _broadcasts(Map<String, dynamic> competition) {
  final names = <String>[];
  final seen = <String>{};
  void add(Object? value) {
    final name = _text(value)?.trim();
    if (name == null || name.isEmpty) return;
    if (!seen.add(name.toLowerCase())) return;
    names.add(name);
  }

  for (final entry in _list(competition['broadcasts']) ?? const <Object?>[]) {
    for (final name in _list(_map(entry)?['names']) ?? const <Object?>[]) {
      add(name);
    }
  }
  for (final entry
      in _list(competition['geoBroadcasts']) ?? const <Object?>[]) {
    add(_dig(entry, const ['media', 'shortName']));
  }
  return names;
}

int? _score(Object? raw) => int.tryParse((_text(raw) ?? '').trim());

int? _color(Object? raw) {
  final value = _text(raw)?.trim();
  if (value == null) return null;
  final match = _hexColor.firstMatch(value);
  if (match == null) return null;
  final rgb = int.tryParse(match.group(1)!, radix: 16);
  return rgb == null ? null : 0xFF000000 | rgb;
}

DateTime? _parseUtc(Object? raw) {
  final value = _text(raw)?.trim();
  if (value == null || value.isEmpty) return null;
  try {
    return DateTime.parse(value).toUtc();
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

List<Object?>? _list(Object? value) => value is List ? value : null;

/// Walks a nested JSON path, stopping at the first missing/non-map node.
Object? _dig(Object? value, List<String> path) {
  Object? current = value;
  for (final key in path) {
    final node = _map(current);
    if (node == null) return null;
    current = node[key];
  }
  return current;
}

String? _text(Object? value) => value is String ? value : null;

/// Identifiers arrive as strings but tolerate numeric JSON ids.
String? _id(Object? value) {
  if (value is String) return value.trim();
  if (value is num) return '$value';
  return null;
}

String? _nonEmpty(Object? value) {
  final text = _text(value);
  return (text == null || text.isEmpty) ? null : text;
}
