// Parses a Jolpica (Ergast-compatible) F1 season feed into immutable
// [SportsEvent]s.
//
// Data layer: pure Dart, no UI and no network access. The feed is untrusted,
// so every accessor is defensive and this library never throws; a race that
// cannot produce a start time is dropped while the others survive.
import 'package:debrify/features/sports/models/sports_models.dart';

/// League identifier these events belong to.
const String _f1LeagueId = 'f1';

/// A race stays "live" for this long after its start time; the feed carries no
/// finishing status.
const Duration _liveWindow = Duration(hours: 2);

/// Converts a Jolpica season payload (`MRData.RaceTable.Races`) into events.
///
/// [json] is the decoded feed body. Anything that is not a map with a `Races`
/// list yields an empty result. Events keep the feed's round order; the feed
/// client owns the final sort.
List<SportsEvent> parseJolpicaSeason(Object? json, {required DateTime now}) {
  final races = _list(_dig(json, const ['MRData', 'RaceTable', 'Races']));
  if (races == null) return const [];
  final events = <SportsEvent>[];
  for (final raw in races) {
    final event = _parseRace(raw, now);
    if (event != null) events.add(event);
  }
  return events;
}

SportsEvent? _parseRace(Object? raw, DateTime now) {
  final race = _map(raw);
  if (race == null) return null;
  final season = _id(race['season']);
  final round = _id(race['round']);
  if (season == null || season.isEmpty || round == null || round.isEmpty) {
    return null;
  }
  final date = _text(race['date'])?.trim();
  final time = _text(race['time'])?.trim();
  if (date == null || date.isEmpty || time == null || time.isEmpty) {
    return null;
  }
  final start = _parseStart('${date}T$time');
  if (start == null) return null;

  final status = _statusFor(start: start, now: now);
  return SportsEvent(
    id: '$_f1LeagueId-$season-$round',
    leagueId: _f1LeagueId,
    start: start,
    status: status,
    title: _nonEmpty(race['raceName']),
    subtitle: _nonEmpty(_dig(race, const ['Circuit', 'circuitName'])),
    statusLabel: _labelFor(status),
  );
}

/// Compare in UTC: before the light is scheduled, the first two hours are
/// live, anything later counts as finished.
SportsEventStatus _statusFor({required DateTime start, required DateTime now}) {
  final beginning = start.toUtc();
  final moment = now.toUtc();
  if (moment.isBefore(beginning)) return SportsEventStatus.scheduled;
  if (moment.isBefore(beginning.add(_liveWindow))) {
    return SportsEventStatus.live;
  }
  return SportsEventStatus.finished;
}

String _labelFor(SportsEventStatus status) {
  switch (status) {
    case SportsEventStatus.live:
      return 'Live';
    case SportsEventStatus.finished:
      return 'Finished';
    case SportsEventStatus.scheduled:
    case SportsEventStatus.postponed:
      return '';
  }
}

DateTime? _parseStart(String iso) {
  try {
    return DateTime.parse(iso).toUtc();
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

/// Season/round arrive as strings but tolerate numeric JSON values.
String? _id(Object? value) {
  if (value is String) return value.trim();
  if (value is num) return '$value';
  return null;
}

String? _nonEmpty(Object? value) {
  final text = _text(value);
  return (text == null || text.isEmpty) ? null : text;
}
