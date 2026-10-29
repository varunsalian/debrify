// Parses ESPN scoreboard feeds for leagues whose cards are not team v team
// (tennis draws, UFC fight cards, golf tournaments, races) into immutable
// [SportsEvent]s.
//
// Data layer: pure Dart, no UI and no network access. The feed is untrusted,
// so every accessor is defensive and this library never throws; a malformed
// entry is dropped while its siblings survive. Status mapping matches the
// team parser in `espn_scoreboard_parser.dart`.
import 'package:debrify/features/sports/models/sports_models.dart';

/// ESPN status names that mean "will not be played as scheduled".
const Set<String> _postponedStatusNames = {
  'STATUS_POSTPONED',
  'STATUS_CANCELED',
};

/// The draw an individual tennis league follows in its feed; other leagues
/// accept any draw whose slug mentions singles.
const Map<String, String> _tennisDrawSlug = {
  'atp': 'mens-singles',
  'wta': 'womens-singles',
};

/// Converts a non-team scoreboard payload into events sorted by start, then id.
///
/// [shape] selects the layout: [SportsEventShape.sets] yields one event per
/// singles match, [SportsEventShape.card] one event per fight card, and
/// [SportsEventShape.event] one event per race or tournament. Anything that
/// is not a map with an `events` list yields an empty result.
List<SportsEvent> parseEspnIndividual(
  Object? json, {
  required String leagueId,
  required SportsEventShape shape,
}) {
  final events = _list(_map(json)?['events']);
  if (events == null) return const [];
  switch (shape) {
    case SportsEventShape.teams:
    case SportsEventShape.innings:
      return const [];
    case SportsEventShape.sets:
    case SportsEventShape.card:
    case SportsEventShape.event:
      break;
  }
  final parsed = <SportsEvent>[];
  for (final raw in events) {
    final event = _map(raw);
    if (event == null) continue;
    switch (shape) {
      case SportsEventShape.sets:
        parsed.addAll(_parseMatches(event, leagueId));
      case SportsEventShape.card:
        final card = _parseCard(event, leagueId);
        if (card != null) parsed.add(card);
      case SportsEventShape.event:
        final single = _parseTournament(event, leagueId);
        if (single != null) parsed.add(single);
      case SportsEventShape.teams:
      case SportsEventShape.innings:
        break;
    }
  }
  parsed.sort(_compareByStartThenId);
  return parsed;
}

int _compareByStartThenId(SportsEvent a, SportsEvent b) {
  final byStart = a.start.compareTo(b.start);
  if (byStart != 0) return byStart;
  return a.id.compareTo(b.id);
}

// ---------------------------------------------------------------------------
// sets (tennis)
// ---------------------------------------------------------------------------

/// Every singles competition of every grouping becomes one event; unplayed
/// placeholder matches (fake times, TBD competitors) are dropped.
List<SportsEvent> _parseMatches(Map<String, dynamic> event, String leagueId) {
  final tournament = _trimmed(event['name']);
  final matches = <SportsEvent>[];
  for (final raw in _list(event['groupings']) ?? const <Object?>[]) {
    final grouping = _map(raw);
    final slug = _text(_dig(grouping, const ['grouping', 'slug'])) ?? '';
    if (!_isLeagueDraw(slug, leagueId)) continue;
    for (final rawMatch
        in _list(grouping?['competitions']) ?? const <Object?>[]) {
      final match = _parseMatch(_map(rawMatch), leagueId, tournament);
      if (match != null) matches.add(match);
    }
  }
  return matches;
}

/// The draw the league follows (`mens-singles` for ATP, `womens-singles` for
/// WTA), plus any other draw whose slug mentions singles.
bool _isLeagueDraw(String slug, String leagueId) {
  if (!slug.contains('singles')) return false;
  final draw = _tennisDrawSlug[leagueId];
  return draw == null || slug == draw;
}

SportsEvent? _parseMatch(
  Map<String, dynamic>? match,
  String leagueId,
  String? tournament,
) {
  if (match == null) return null;
  final id = _id(match['id']);
  if (id == null || id.isEmpty) return null;
  final start = _parseUtc(match['date']);
  if (start == null) return null;
  // "TBD v TBD at 4 AM" placeholders carry no valid time and no real athlete.
  if (match['timeValid'] == false) return null;
  final competitors = <Map<String, dynamic>>[];
  for (final raw in _list(match['competitors']) ?? const <Object?>[]) {
    final competitor = _map(raw);
    if (competitor == null) continue;
    if (_map(competitor['athlete']) == null) return null;
    competitors.add(competitor);
  }
  if (competitors.length != 2) return null;
  competitors.sort(_compareByOrder);
  final home = competitors.first;
  final away = competitors.last;
  final homeTeam = _athleteTeam(home);
  final awayTeam = _athleteTeam(away);
  if (homeTeam == null || awayTeam == null) return null;

  final status = _statusOf(match);
  final type =
      _map(_map(match['status'])?['type']) ?? const <String, dynamic>{};
  return SportsEvent(
    id: id,
    leagueId: leagueId,
    start: start,
    status: status,
    home: homeTeam,
    away: awayTeam,
    clock: status == SportsEventStatus.live
        ? _nonEmpty(type['shortDetail'])
        : null,
    statusLabel: _text(type['shortDetail']) ?? _text(type['detail']) ?? '',
    broadcasts: _broadcasts(match),
    homeLines: _lines(home),
    awayLines: _lines(away),
    homeWon: _matchWinner(
      finished: status == SportsEventStatus.finished,
      home: home,
      away: away,
    ),
    format: _trimmed(_dig(match, const ['round', 'displayName'])),
    group: tournament,
  );
}

int _compareByOrder(Map<String, dynamic> a, Map<String, dynamic> b) {
  final byOrder = _order(a).compareTo(_order(b));
  if (byOrder != 0) return byOrder;
  return (_id(a['id']) ?? '').compareTo(_id(b['id']) ?? '');
}

int _order(Map<String, dynamic> competitor) {
  final raw = competitor['order'];
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? 0}'.trim()) ?? 0;
}

/// Per-set games; ESPN sends whole numbers such as `4.0` in JSON.
List<int> _lines(Map<String, dynamic> competitor) {
  final lines = <int>[];
  for (final raw in _list(competitor['linescores']) ?? const <Object?>[]) {
    final value = _map(raw)?['value'];
    final line = value is num
        ? value.toInt()
        : int.tryParse('${value ?? ''}'.trim());
    if (line != null) lines.add(line);
  }
  return lines;
}

/// True when home won, false when away won; unfinished or undecided is null.
bool? _matchWinner({
  required bool finished,
  required Map<String, dynamic> home,
  required Map<String, dynamic> away,
}) {
  if (!finished) return null;
  if (_isWinner(home['winner'])) return true;
  if (_isWinner(away['winner'])) return false;
  return null;
}

/// ESPN sends `winner` as a bool or as the strings `"true"`/`"false"`.
bool _isWinner(Object? raw) =>
    raw == true || (raw is String && raw.trim().toLowerCase() == 'true');

/// One athlete rendered as a [SportsTeam] so shared card widgets can show
/// both sides; null when the athlete carries no name.
SportsTeam? _athleteTeam(Map<String, dynamic> competitor) {
  final athlete = _map(competitor['athlete']);
  if (athlete == null) return null;
  final id = _id(competitor['id']) ?? _id(athlete['id']);
  if (id == null || id.isEmpty) return null;
  final name = _trimmed(athlete['displayName']) ?? '';
  if (name.isEmpty) return null;
  return SportsTeam(
    id: id,
    name: name,
    shortName: _trimmed(athlete['shortName']) ?? name,
    abbreviation: _lastWord(name),
    logoUrl: _nonEmpty(_dig(athlete, const ['flag', 'href'])),
  );
}

String _lastWord(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  return words.isEmpty ? name : words.last;
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

// ---------------------------------------------------------------------------
// card (UFC) and event (golf, racing)
// ---------------------------------------------------------------------------

/// One fight card: bout count plus the main event's weight class, taken from
/// the last competition, and the venue when the feed names one.
SportsEvent? _parseCard(Map<String, dynamic> event, String leagueId) {
  final competitions = _list(event['competitions']) ?? const <Object?>[];
  final last = competitions.isEmpty ? null : _map(competitions.last);
  return _fromEvent(
    event,
    leagueId,
    subtitle: _venueName(_list(event['venues'])?.first),
    format: _trimmed(_dig(last, const ['type', 'abbreviation'])),
    itemCount: competitions.length,
  );
}

/// One race or tournament. Golf-style entries (a competition that lists
/// ranked athletes) additionally expose their current leader once the round
/// is live or done; races, which carry no competitors, never do.
SportsEvent? _parseTournament(Map<String, dynamic> event, String leagueId) {
  Map<String, dynamic>? first;
  for (final raw in _list(event['competitions']) ?? const <Object?>[]) {
    final competition = _map(raw);
    if (competition != null) {
      first = competition;
      break;
    }
  }
  String? leaderName;
  String? leaderScore;
  // The leaderboard follows the card's own status: some feeds keep
  // `competitions[0].status` at "Scheduled" while the round is running.
  final status = _statusOf(event);
  final hasField =
      _list(first?['competitors'])?.any((c) => _map(c)?['athlete'] is Map) ==
      true;
  if (first != null &&
      hasField &&
      (status == SportsEventStatus.live ||
          status == SportsEventStatus.finished)) {
    final leader = _lowestOrder(first);
    if (leader != null) {
      leaderName = _trimmed(_dig(leader, const ['athlete', 'displayName']));
      leaderScore = _trimmed(leader['score']);
    }
  }
  final competitionVenue = _nonEmpty(_dig(first, const ['venue', 'fullName']));
  return _fromEvent(
    event,
    leagueId,
    subtitle: competitionVenue ?? _venueName(_list(event['venues'])?.first),
    leaderName: leaderName,
    leaderScore: leaderScore,
  );
}

/// `venues[0].fullName` of a feed entry.
String? _venueName(Object? venue) => _nonEmpty(_dig(venue, const ['fullName']));

/// The competitor with the lowest `order` (golf ranks the field 1..n).
Map<String, dynamic>? _lowestOrder(Map<String, dynamic> competition) {
  Map<String, dynamic>? leader;
  for (final raw in _list(competition['competitors']) ?? const <Object?>[]) {
    final competitor = _map(raw);
    if (competitor == null) continue;
    if (_map(competitor['athlete']) == null) continue;
    if (leader == null || _order(competitor) < _order(leader)) {
      leader = competitor;
    }
  }
  return leader;
}

/// Builds a non-team event from the feed entry's own `id`, `date`, `name` and
/// `status`; null when the entry has no id or no parseable start.
SportsEvent? _fromEvent(
  Map<String, dynamic> event,
  String leagueId, {
  String? subtitle,
  String? format,
  int? itemCount,
  String? leaderName,
  String? leaderScore,
}) {
  final id = _id(event['id']);
  if (id == null || id.isEmpty) return null;
  final start = _parseUtc(event['date']);
  if (start == null) return null;
  final status = _statusOf(event);
  final type =
      _map(_map(event['status'])?['type']) ?? const <String, dynamic>{};
  return SportsEvent(
    id: id,
    leagueId: leagueId,
    start: start,
    status: status,
    title: _trimmed(event['name']),
    subtitle: subtitle,
    clock: status == SportsEventStatus.live
        ? _nonEmpty(type['shortDetail'])
        : null,
    statusLabel: _text(type['shortDetail']) ?? _text(type['detail']) ?? '',
    format: format,
    itemCount: itemCount,
    leaderName: leaderName,
    leaderScore: leaderScore,
  );
}

// ---------------------------------------------------------------------------
// Shared defensive helpers (identical behaviour to the team parser)
// ---------------------------------------------------------------------------

/// Status of a feed entry's own `status` node.
SportsEventStatus _statusOf(Map<String, dynamic> source) {
  final status = _map(source['status']);
  final type = _map(status?['type']) ?? const <String, dynamic>{};
  return _statusFor(
    state: _text(type['state']) ?? '',
    name: _text(type['name']) ?? '',
    completed: type['completed'] == true,
  );
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

/// Text that survives trimming; whitespace-only or empty becomes null.
String? _trimmed(Object? raw) {
  final text = _text(raw)?.trim();
  return (text == null || text.isEmpty) ? null : text;
}
