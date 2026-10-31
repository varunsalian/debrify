// Whether a guide title or a channel's own name is the live game: the recap
// words both share, and the stream-name rules (both sides around a "vs",
// no other team or sport, no replay, dated the game's day).
//
// Application layer: pure Dart over normalized text, like sports_names.dart.
import 'package:debrify/features/sports/application/sports_names.dart';
import 'package:debrify/features/sports/models/sports_models.dart';

/// Programme titles containing one of these are recap shows, not the live game.
const List<String> kSportsNonLiveWords = [
  'highlights',
  'replay',
  'review',
  'preview',
  'classics',
  'rewind',
  'magazine',
  'reaction',
  'analysis',
  'goals show',
  // Fox Sports' 20-minute highlights packages: "South Africa v Australia Mini".
  'mini',
  // Listing shorthand for highlights: "Int CRI HL '26: RSA v AUS",
  // "Sri Lanka v England Hlts".
  'hl',
  'hlts',
];

/// Separators between the two sides in a stream name ("A vs B", "A v B",
/// "A x B", "A at B"; `-` and `@` are turned into `vs` first).
const Set<String> _sideSeparators = {'v', 'vs', 'x', 'at', 'versus'};

/// A word right after a side that makes it a different team of the same
/// name: "India Women", "Pakistan U19", "England A", "Australia XI".
const Set<String> _teamQualifiers = {
  'women',
  'womens',
  'w',
  'ladies',
  'frauen',
  'damen',
  'dames',
  'femenil',
  'femenino',
  'femenina',
  'feminine',
  'feminino',
  'u17',
  'u19',
  'u20',
  'u21',
  'u23',
  'a',
  'b',
  'xi',
  'legends',
  'masters',
  'reserves',
};

/// The same, as a label before the teams ("Soccer (W): Purdue at Penn
/// State", "U19: India vs Australia"); "A" and "B" are left out there, as in
/// "Serie A: Inter vs Milan".
const Set<String> _labelQualifiers = {
  'women',
  'womens',
  'w',
  'ladies',
  'frauen',
  'damen',
  'dames',
  'femenil',
  'femenino',
  'femenina',
  'feminine',
  'feminino',
  'u17',
  'u19',
  'u20',
  'u21',
  'u23',
};

/// Channel-name words that mark replays, a 24/7 loop or a studio show, not
/// the live game (on top of the guide's recap words).
const List<String> kSportsChannelNonLiveWords = [
  'classic',
  '24 7',
  'best of',
  'full match',
  'encore',
  'rerun',
  'goal rush',
  'press conference',
  'persconferentie',
  'pregame',
  'postgame',
];

/// Sport labels a stream name may carry before the teams, by the sport they
/// name; null for sports the board does not cover. "Football" is left out:
/// it names a different sport depending on the country.
const Map<String, SportKind?> _sportLabels = {
  'soccer': SportKind.soccer,
  'futbol': SportKind.soccer,
  'basketball': SportKind.basketball,
  'nba': SportKind.basketball,
  'wnba': SportKind.basketball,
  'ncaab': SportKind.basketball,
  'nfl': SportKind.americanFootball,
  'ncaaf': SportKind.americanFootball,
  'hockey': SportKind.hockey,
  'nhl': SportKind.hockey,
  'baseball': SportKind.baseball,
  'mlb': SportKind.baseball,
  'cricket': SportKind.cricket,
  'tennis': SportKind.tennis,
  'rugby': SportKind.rugby,
  'golf': SportKind.golf,
  'ufc': SportKind.combat,
  'mma': SportKind.combat,
  'boxing': SportKind.combat,
  'nascar': SportKind.motorsport,
  'indycar': SportKind.motorsport,
  'volleyball': null,
  'softball': null,
  'swimming': null,
  'diving': null,
  'handball': null,
  'lacrosse': null,
  'wrestling': null,
  'gymnastics': null,
  'rowing': null,
  'polo': null,
};

/// Words that say a name is about a women's game, in any listed language.
const Set<String> _womenWords = {
  'women',
  'womens',
  'w',
  'ladies',
  'frauen',
  'damen',
  'dames',
  'femenil',
  'femenino',
  'femenina',
  'feminine',
  'feminino',
};

/// What may follow the second side's "A" in other languages' kick-off
/// times ("Barcelona a las 21:00"), so the "A" is not England A's.
const Set<String> _timeWords = {'las', 'la', 'les', 'el', 'partir'};

/// In tennis, what may sit between a player and the separator: a country
/// code or a seed ("Sinner (ITA) vs Alcaraz", "[1] Sinner vs [2] Alcaraz").
final RegExp _tennisFiller = RegExp(r'^(?:[a-z]{3}|[0-9]{1,2})$');

final RegExp _rawSideSeparator = RegExp(r'\s[-–—]\s|@');

/// Whether a channel's own name is a stream of the game between [home] and
/// [away] (normalized name variants of each side): both sides named, in
/// either order, separated by nothing but a "vs"-style word, with no
/// qualifier after the second side or women's/youth label before the
/// first, no other sport's label before the first, no replay word, not an
/// ended stream ("End | ..."), and no date in the name more than a day from
/// [around].
///
/// "Cricket 03: Bangladesh vs West Indies" matches; "Inter Milan TV" (one
/// club's name holding both "inter" and "milan"), "India Women vs Australia
/// Women", "Arsenal v Chelsea Classic", "Volleyball: Temple vs East
/// Carolina" and "Chelsea vs Man Utd // Sun 18 May" (in October) do not.
bool sportsChannelNamesMatch(
  String rawName,
  List<String> home,
  List<String> away, {
  DateTime? around,
  SportKind? sport,
}) {
  final name = normalizeSportsText(
    rawName.replaceAll(_rawSideSeparator, ' vs '),
  );
  if (name.isEmpty || name.startsWith('end ')) return false;
  for (final word in [...kSportsNonLiveWords, ...kSportsChannelNonLiveWords]) {
    if (sportsTextContains(name, word)) return false;
  }
  final gap = around == null ? null : sportsChannelNameDayGap(rawName, around);
  if (gap != null && gap > 1) return false;
  final padded = ' $name ';
  final homeSpans = _spans(padded, _forName(home, name));
  if (homeSpans.isEmpty) return false;
  final awaySpans = _spans(padded, _forName(away, name));
  final teamWords = {
    for (final variant in [...home, ...away]) ...variant.split(' '),
  };
  // A women's fixture's own "Women", in any language, is not a qualifier
  // marking another team.
  bool ownWord(String w) =>
      teamWords.contains(w) ||
      (teamWords.contains('women') && _womenWords.contains(w));
  for (final h in homeSpans) {
    for (final a in awaySpans) {
      final first = h.start < a.start ? h : a;
      final second = identical(first, h) ? a : h;
      if (first.end > second.start) continue;
      final between = padded.substring(first.end, second.start).trim();
      if (!_separatedBy(between, tennis: sport == SportKind.tennis)) continue;
      final rest = padded.substring(second.end).trim().split(' ');
      final after = rest.first;
      final spanishTime =
          (after == 'a' || after == 'b') &&
          rest.length > 1 &&
          _timeWords.contains(rest[1]);
      // A women's event's own "Women" is not another team's qualifier.
      if (_teamQualifiers.contains(after) && !ownWord(after) && !spanishTime) {
        continue;
      }
      final label = padded.substring(0, first.start).trim().split(' ');
      if (label.any((w) => _labelQualifiers.contains(w) && !ownWord(w))) {
        continue;
      }
      if (sport != null &&
          label.any(
            (w) => _sportLabels.containsKey(w) && _sportLabels[w] != sport,
          )) {
        continue;
      }
      return true;
    }
  }
  return false;
}

/// [variants], plus each "... women" variant without "Women" when [name]
/// itself says it is a women's game ("Sydney Thunder vs Melbourne Renegades
/// _ Women's Cricket"); a name that does not say so keeps the full names,
/// so the men's "Australia vs India" never matches the women's fixture.
List<String> _forName(List<String> variants, String name) {
  final words = name.split(' ');
  if (!words.any(_womenWords.contains)) return variants;
  return [
    ...variants,
    for (final v in variants)
      if (v.endsWith(' women') && v.length > ' women'.length + 3)
        v.substring(0, v.length - ' women'.length),
  ];
}

/// Whether [between] (the text between the two sides) is one separator; in
/// tennis also allowing country codes and seeds around it.
bool _separatedBy(String between, {required bool tennis}) {
  if (_sideSeparators.contains(between)) return true;
  if (!tennis) return false;
  final words = between.split(' ');
  final separators = words.where(_sideSeparators.contains).length;
  return separators == 1 &&
      words.every(
        (w) =>
            _sideSeparators.contains(w) ||
            (_tennisFiller.hasMatch(w) && !_teamQualifiers.contains(w)),
      );
}

/// Days between [around] and the date a stream name carries closest to it
/// ("(2026-10-31 22:30)", "29-10-2026", "Sun 18 May", "Oct 28 21:25"), or
/// null when the name has no date. Names give local dates, so a gap of one
/// day is still the same game.
int? sportsChannelNameDayGap(String rawName, DateTime around) {
  final text = rawName.toLowerCase();
  final day = DateTime.utc(around.year, around.month, around.day);
  int? best;
  void consider(int year, int month, int date) {
    if (month < 1 || month > 12 || date < 1 || date > 31) return;
    final gap = DateTime.utc(year, month, date).difference(day).inDays.abs();
    if (best == null || gap < best!) best = gap;
  }

  void considerYearless(int month, int date) {
    for (final year in [day.year - 1, day.year, day.year + 1]) {
      consider(year, month, date);
    }
  }

  for (final m in _isoDate.allMatches(text)) {
    consider(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  // "11/01/2026" is 11 January in Europe and 1 November in the US: either
  // reading counts.
  for (final m in _dmyDate.allMatches(text)) {
    consider(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    consider(int.parse(m[3]!), int.parse(m[1]!), int.parse(m[2]!));
  }
  for (final m in _dayMonth.allMatches(text)) {
    considerYearless(_months[m[2]!.substring(0, 3)]!, int.parse(m[1]!));
  }
  for (final m in _monthDay.allMatches(text)) {
    considerYearless(_months[m[1]!.substring(0, 3)]!, int.parse(m[2]!));
  }
  return best;
}

const Map<String, int> _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

final RegExp _isoDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b');
final RegExp _dmyDate = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b');

/// A month as its full name or exact abbreviation only, so team names that
/// start like one ("Augsburg", "Marlins", "Marseille") are not dates.
const String _month =
    r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|'
    r'aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';
final RegExp _dayMonth = RegExp(r'\b(\d{1,2})\s+' + _month + r'\b');
final RegExp _monthDay = RegExp(r'\b' + _month + r'\.?\s+(\d{1,2})\b');

/// Where each variant occurs in [padded] (" name "), as the span of the
/// variant itself without its padding spaces.
List<({int start, int end})> _spans(String padded, List<String> variants) {
  final spans = <({int start, int end})>[];
  for (final variant in variants) {
    if (variant.isEmpty) continue;
    final needle = ' $variant ';
    var from = 0;
    while (true) {
      final at = padded.indexOf(needle, from);
      if (at < 0) break;
      spans.add((start: at + 1, end: at + 1 + variant.length));
      from = at + 1;
    }
  }
  return spans;
}

/// Words that mark a listing as cricket, so a code pair ("RSA v AUS") is
/// not a rugby, hockey or netball game between the same countries.
const Set<String> _cricketWords = {
  'cri',
  'cricket',
  'test',
  'odi',
  'odis',
  't20',
  't20i',
  't20is',
};

/// Whether a guide title (normalized) names a men's cricket game by one of
/// its country-code [pairs]: the pair, a cricket word, and no women's or
/// youth marker ("Int CRI W '26: RSA v AUS", "IND v ENG U19").
bool sportsTitleNamesCodePair(String normalized, List<String> pairs) {
  if (pairs.isEmpty) return false;
  if (!pairs.any((pair) => sportsTextContains(normalized, pair))) return false;
  final words = normalized.split(' ');
  if (!words.any(_cricketWords.contains)) return false;
  return !words.any((w) => _labelQualifiers.contains(w) || w == 'xi');
}
