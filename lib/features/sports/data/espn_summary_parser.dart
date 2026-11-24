// Parses ESPN's per-game summary (`.../summary?event=<id>`) into
// [SportsMatchStats].
//
// Data layer, pure: JSON in, immutable model out, no I/O. Runs inside a worker
// isolate for big bodies (a finished NFL or MLB summary is 400–900 KB), so it
// stays top-level and synchronous. Every section is optional: the feed omits
// win probability for soccer and hockey, leaders for rugby, recent form after
// a game ends, and sends season averages instead of game totals before
// kick-off. Missing or malformed pieces drop that section, never the page.
import 'package:debrify/features/sports/models/sports_match_stats.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// Most win-probability points kept; a long NBA game sends ~500.
const int maxWinProbabilityPoints = 240;

/// The same "will not be played as scheduled" names the board uses, so the
/// page and the board never disagree about a match's state.
const Set<String> _postponedStatusNames = {
  'STATUS_POSTPONED',
  'STATUS_CANCELED',
};

/// The stats in [json], or null when it does not describe a two-team match.
SportsMatchStats? parseEspnSummary(Object? json) {
  final root = _map(json);
  final competition = _map(
    (_list(_dig(root, const ['header', 'competitions'])) ?? const [])
        .firstOrNull,
  );
  if (root == null || competition == null) return null;
  Map<String, dynamic>? homeRaw;
  Map<String, dynamic>? awayRaw;
  for (final raw in _list(competition['competitors']) ?? const <Object?>[]) {
    final competitor = _map(raw);
    switch (_text(competitor?['homeAway'])) {
      case 'home':
        homeRaw ??= competitor;
      case 'away':
        awayRaw ??= competitor;
    }
  }
  final home = _side(homeRaw);
  final away = _side(awayRaw);
  if (home == null || away == null) return null;

  final type = _map(_dig(competition, const ['status', 'type'])) ?? const {};
  final state = _text(type['state']) ?? '';
  final status = _status(
    state: state,
    name: _text(type['name']) ?? '',
    completed: type['completed'] == true,
  );
  final form = _form(root['lastFiveGames'], home.teamId, away.teamId);
  return SportsMatchStats(
    status: status,
    statusDetail: _text(type['shortDetail']) ?? _text(type['detail']) ?? '',
    home: home,
    away: away,
    // ESPN marks a postponed game `post` but not completed (with a "0"
    // score): it never kicked off.
    started: state == 'in' || (state == 'post' && type['completed'] == true),
    start: _utc(competition['date']),
    winProbability: _winProbability(root['winprobability']),
    prediction: _prediction(root['predictor'], home.teamId, away.teamId),
    teamStats: _teamStats(_dig(root, const ['boxscore', 'teams']), home, away),
    leaders: _leaders(root['leaders'], home.teamId, away.teamId),
    homeForm: form.home,
    awayForm: form.away,
  );
}

SportsMatchSide? _side(Map<String, dynamic>? competitor) {
  final team = _map(competitor?['team']);
  final id = _id(team?['id']);
  if (team == null || id == null || id.isEmpty) return null;
  final name = _text(team['displayName']) ?? '';
  final logos = _list(team['logos']);
  final records = _list(competitor?['record']) ?? const <Object?>[];
  final total =
      records.map(_map).where((r) => r?['type'] == 'total').firstOrNull ??
      _map(records.firstOrNull);
  return SportsMatchSide(
    teamId: id,
    abbreviation: _text(team['abbreviation']) ?? name,
    name: name,
    logoUrl:
        _nonEmpty(_dig(logos?.firstOrNull, const ['href'])) ??
        _nonEmpty(team['logo']),
    color: _color(team['color']),
    alternateColor: _color(team['alternateColor']),
    score: _nonEmpty(competitor?['score']),
    record: _nonEmpty(total?['summary']),
  );
}

SportsEventStatus _status({
  required String state,
  required String name,
  required bool completed,
}) {
  if (state == 'in') return SportsEventStatus.live;
  if (state == 'post') {
    return completed ? SportsEventStatus.finished : SportsEventStatus.postponed;
  }
  if (_postponedStatusNames.contains(name)) return SportsEventStatus.postponed;
  return SportsEventStatus.scheduled;
}

/// Home chances in play order, thinned evenly to [maxWinProbabilityPoints]
/// while always keeping the latest point.
List<double> _winProbability(Object? raw) {
  final points = <double>[
    for (final entry in _list(raw) ?? const <Object?>[])
      if (_num(_map(entry)?['homeWinPercentage']) case final p?)
        p.clamp(0.0, 1.0),
  ];
  if (points.length <= maxWinProbabilityPoints) return points;
  final last = points.length - 1;
  return [
    for (var i = 0; i < maxWinProbabilityPoints; i++)
      points[(i * last / (maxWinProbabilityPoints - 1)).round()],
  ];
}

SportsMatchPrediction? _prediction(Object? raw, String homeId, String awayId) {
  final predictor = _map(raw);
  final first = _map(predictor?['homeTeam']);
  final second = _map(predictor?['awayTeam']);
  var home = _num(first?['gameProjection']);
  var away = _num(second?['gameProjection']);
  if (home == null || away == null) return null;
  // Trust the ids over the labels: a swapped predictor must not flip the bar.
  if (_id(first?['id']) == awayId && _id(second?['id']) == homeId) {
    (home, away) = (away, home);
  }
  if (home < 0 || away < 0 || home + away <= 0) return null;
  return SportsMatchPrediction(home: home, away: away);
}

List<SportsTeamStat> _teamStats(
  Object? raw,
  SportsMatchSide home,
  SportsMatchSide away,
) {
  Map<String, _Stat>? homeStats;
  Map<String, _Stat>? awayStats;
  for (final entry in _list(raw) ?? const <Object?>[]) {
    final team = _map(entry);
    if (team == null) continue;
    final id = _id(_dig(team, const ['team', 'id']));
    final side = _text(team['homeAway']);
    final stats = _flatStats(team['statistics']);
    if (id == home.teamId || (id == null && side == 'home')) {
      homeStats ??= stats;
    } else if (id == away.teamId || (id == null && side == 'away')) {
      awayStats ??= stats;
    }
  }
  if (homeStats == null || awayStats == null) return const [];
  return [
    for (final MapEntry(key: name, value: h) in homeStats.entries)
      if (awayStats[name] case final a?)
        SportsTeamStat(
          name: name,
          label: h.label,
          homeText: h.text,
          awayText: a.text,
          homeValue: h.value,
          awayValue: a.value,
        ),
  ];
}

/// One side's stats by name, in feed order, first spelling of a repeated
/// name kept. Grouped feeds (baseball) prefix the group: `batting.hits`.
Map<String, _Stat> _flatStats(Object? raw) {
  final out = <String, _Stat>{};
  void add(Object? entry, {String? group}) {
    final stat = _map(entry);
    final name = _nonEmpty(stat?['name']);
    final text = _text(stat?['displayValue'])?.trim();
    if (stat == null || name == null || text == null || text.isEmpty) return;
    final key = group == null ? name : '$group.$name';
    out.putIfAbsent(
      key,
      () => _Stat(
        label:
            _nonEmpty(stat['label']) ?? _nonEmpty(stat['displayName']) ?? name,
        text: text,
        value: _statValue(stat['value'], text),
      ),
    );
  }

  for (final entry in _list(raw) ?? const <Object?>[]) {
    final group = _map(entry);
    final inner = _list(group?['stats']);
    if (inner == null) {
      add(entry);
    } else {
      final name = _nonEmpty(group?['name']);
      for (final stat in inner) {
        add(stat, group: name);
      }
    }
  }
  return out;
}

class _Stat {
  const _Stat({required this.label, required this.text, this.value});

  final String label;
  final String text;
  final double? value;
}

final RegExp _clock = RegExp(r'^(\d+):(\d{2})$');
final RegExp _leadingNumber = RegExp(r'^-?\d+(?:\.\d+)?');

/// The feed's number when it sends one; otherwise read from the text:
/// `22:14` → seconds, `12/29` or `30-68` → the first figure, `.250` → 0.25.
double? _statValue(Object? value, String text) {
  if (value is num) return value.toDouble();
  final clock = _clock.firstMatch(text);
  if (clock != null) {
    return int.parse(clock.group(1)!) * 60.0 + int.parse(clock.group(2)!);
  }
  final normalized = text.startsWith('.') ? '0$text' : text;
  final match = _leadingNumber.firstMatch(normalized);
  return match == null ? null : double.tryParse(match.group(0)!);
}

/// Categories in the home side's order, then any only the away side has.
List<SportsLeaderPair> _leaders(Object? raw, String homeId, String awayId) {
  Map<String, (String, SportsLeader?)>? homeLeaders;
  Map<String, (String, SportsLeader?)>? awayLeaders;
  for (final entry in _list(raw) ?? const <Object?>[]) {
    final team = _map(entry);
    final id = _id(_dig(team, const ['team', 'id']));
    final categories = <String, (String, SportsLeader?)>{};
    for (final rawCategory in _list(team?['leaders']) ?? const <Object?>[]) {
      final category = _map(rawCategory);
      final key =
          _nonEmpty(category?['name']) ?? _nonEmpty(category?['displayName']);
      if (key == null) continue;
      categories.putIfAbsent(
        key,
        () => (
          _nonEmpty(category?['displayName']) ?? key,
          _leader(_list(category?['leaders'])?.firstOrNull),
        ),
      );
    }
    if (id == homeId) homeLeaders ??= categories;
    if (id == awayId) awayLeaders ??= categories;
  }
  final home = homeLeaders ?? const {};
  final away = awayLeaders ?? const {};
  return [
    for (final key in {...home.keys, ...away.keys})
      if (home[key]?.$2 != null || away[key]?.$2 != null)
        SportsLeaderPair(
          category: (home[key] ?? away[key])!.$1,
          home: home[key]?.$2,
          away: away[key]?.$2,
        ),
  ];
}

SportsLeader? _leader(Object? raw) {
  final entry = _map(raw);
  final athlete = _map(entry?['athlete']);
  final name =
      _nonEmpty(athlete?['displayName']) ?? _nonEmpty(athlete?['fullName']);
  final summary = _text(entry?['displayValue'])?.trim();
  if (name == null || summary == null || summary.isEmpty) return null;
  return SportsLeader(
    name: name,
    shortName: _nonEmpty(athlete?['shortName']),
    summary: summary,
    headshotUrl: _nonEmpty(_dig(athlete, const ['headshot', 'href'])),
  );
}

({List<SportsFormGame> home, List<SportsFormGame> away}) _form(
  Object? raw,
  String homeId,
  String awayId,
) {
  var home = const <SportsFormGame>[];
  var away = const <SportsFormGame>[];
  for (final entry in _list(raw) ?? const <Object?>[]) {
    final team = _map(entry);
    final id = _id(_dig(team, const ['team', 'id']));
    final games = [
      for (final game in _list(team?['events']) ?? const <Object?>[])
        if (_formGame(game) case final parsed?) parsed,
    ];
    if (id == homeId && home.isEmpty) home = games;
    if (id == awayId && away.isEmpty) away = games;
  }
  return (home: home, away: away);
}

SportsFormGame? _formGame(Object? raw) {
  final game = _map(raw);
  final result = switch (_text(game?['gameResult'])?.toUpperCase()) {
    'W' => SportsFormResult.win,
    'L' => SportsFormResult.loss,
    'D' || 'T' => SportsFormResult.draw,
    _ => null,
  };
  final score = _text(game?['score'])?.trim();
  final opponent = _map(game?['opponent']);
  final abbreviation =
      _nonEmpty(opponent?['abbreviation']) ??
      _nonEmpty(opponent?['displayName']);
  if (result == null || score == null || score.isEmpty) return null;
  if (abbreviation == null) return null;
  return SportsFormGame(
    result: result,
    score: score,
    home: _text(game?['atVs']) != '@',
    opponentAbbreviation: abbreviation,
    opponentLogoUrl:
        _nonEmpty(game?['opponentLogo']) ?? _nonEmpty(opponent?['logo']),
  );
}

final RegExp _hexColor = RegExp(r'^#?([0-9a-fA-F]{6})$');

int? _color(Object? raw) {
  final match = _hexColor.firstMatch(_text(raw)?.trim() ?? '');
  if (match == null) return null;
  return 0xFF000000 | int.parse(match.group(1)!, radix: 16);
}

DateTime? _utc(Object? raw) {
  final text = _text(raw)?.trim();
  if (text == null || text.isEmpty) return null;
  return DateTime.tryParse(text)?.toUtc();
}

double? _num(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

List<Object?>? _list(Object? value) => value is List ? value : null;

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

String? _id(Object? value) {
  if (value is String) return value.trim();
  if (value is num) return '$value';
  return null;
}

String? _nonEmpty(Object? value) {
  final text = _text(value)?.trim();
  return (text == null || text.isEmpty) ? null : text;
}
