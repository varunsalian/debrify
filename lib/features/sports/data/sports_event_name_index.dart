// Whether a guide title or a channel name is about one of the board's events.
//
// Data layer helper for the guide query: plain functions over normalized
// text (see `normalizeSportsText`), so the scan stays a pure computation that
// can run in a background isolate.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/application/sports_stream_names.dart';
import 'package:debrify/features/sports/models/sports_guide_contract.dart';

class SportsEventNameIndex {
  SportsEventNameIndex(this._events) : _byWord = _teamEventsByWord(_events);

  final List<SportsEventNeedles> _events;

  /// Team events by the longest word of each of their variants, so a name
  /// only checks the events it shares a word with.
  final Map<String, Set<int>> _byWord;

  bool get hasTeamEvents => _byWord.isNotEmpty;

  /// A guide title naming every side of some event, and not a recap.
  bool namesEvent(String normalized) =>
      !kSportsNonLiveWords.any((w) => sportsTextContains(normalized, w)) &&
      _events.any((event) => _namesAllSides(event, normalized));

  /// The team events (indexes into the query's events) whose stream
  /// [rawName] is, by [sportsChannelNamesMatch]. A single-side event
  /// ("Mexico Open") never names a channel: it is too likely to be part of
  /// an ordinary channel's name.
  Iterable<int> teamEventsNamedBy(String rawName, String normalized) {
    final candidates = <int>{
      for (final word in normalized.split(' ')) ...?_byWord[word],
    };
    return candidates.where((i) {
      final event = _events[i];
      return sportsChannelNamesMatch(
        rawName,
        event.sides[0],
        event.sides[1],
        around: event.around,
        sport: event.sport,
      );
    });
  }
}

bool _namesAllSides(SportsEventNeedles event, String normalized) =>
    event.sides.isNotEmpty &&
    event.sides.every(
      (variants) => variants.any((v) => sportsTextContains(normalized, v)),
    );

Map<String, Set<int>> _teamEventsByWord(List<SportsEventNeedles> events) {
  final byWord = <String, Set<int>>{};
  for (var i = 0; i < events.length; i++) {
    final sides = events[i].sides;
    if (sides.length < 2) continue;
    for (final variants in sides) {
      for (final variant in variants) {
        var longest = '';
        for (final word in variant.split(' ')) {
          if (word.length > longest.length) longest = word;
        }
        if (longest.isNotEmpty) byWord.putIfAbsent(longest, () => {}).add(i);
      }
    }
  }
  return byWord;
}
