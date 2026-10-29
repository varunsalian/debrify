// Discovers the international cricket competitions running right now.
//
// Data layer: pure Dart over a decoded ESPN scoreboard *header* body. The
// header lists every competition currently running under a sport; a league
// is an international series when its first event carries a
// `class.internationalClassId` above zero (Test 1, ODI 2, T20I 3; domestic
// competitions report 0). Nothing here throws: malformed entries are simply
// dropped.

/// One discoverable cricket competition (an ESPN "league").
typedef CricketSeries = ({String id, String name});

/// The international series in [headerJson], in feed order, de-duplicated by
/// id (a repeat collapses to its first occurrence). Anything malformed —
/// a non-map body, a missing `sports` list, junk leagues — yields an empty
/// list rather than an error.
List<CricketSeries> internationalCricketSeries(Object? headerJson) {
  final root = _asMap(headerJson);
  if (root == null) return const [];
  final series = <CricketSeries>[];
  final seen = <String>{};
  for (final rawSport in _asList(root['sports'])) {
    final sport = _asMap(rawSport);
    if (sport == null) continue;
    for (final rawLeague in _asList(sport['leagues'])) {
      final league = _asMap(rawLeague);
      if (league == null) continue;
      final id = _text(league['id']);
      final name = _text(league['name']);
      if (id == null || id.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      if (!seen.add(id)) continue;
      if (_isInternational(league)) series.add((id: id, name: name));
    }
  }
  return series;
}

/// True when the league's *first* event is an international one
/// (`class.internationalClassId` parses to 1, 2 or 3). A league without
/// events, or whose first event carries no class or class 0, is domestic.
bool _isInternational(Map<Object?, Object?> league) {
  final events = _asList(league['events']);
  if (events.isEmpty) return false;
  final Object? firstEvent = _asMap(events.first)?['class'];
  final matchClass = _asMap(firstEvent);
  if (matchClass == null) return false;
  final raw = matchClass['internationalClassId'];
  final classId = raw is int ? raw : int.tryParse('$raw');
  return classId != null && classId > 0;
}

Map<Object?, Object?>? _asMap(Object? raw) =>
    raw is Map ? raw.cast<Object?, Object?>() : null;

List<Object?> _asList(Object? raw) => raw is List ? raw : const <Object?>[];

String? _text(Object? raw) => raw is String ? raw : null;
