// Text normalization and comparison rules shared by sports matching.
//
// Application layer: pure Dart, no UI, no data sources. Every function here is
// a total, allocation-light pure function over strings so guide titles, feed
// team names and user channel names can be compared on the same footing.
import 'package:debrify/features/sports/models/sports_models.dart';

/// Accented/ligature characters folded to their ASCII form before the
/// `[a-z0-9]` filter runs. Keys must be lowercase (input is lowercased first).
const Map<String, String> _accentFolds = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ā': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ø': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
};

final RegExp _spaces = RegExp(' +');

/// Leading region tag on a raw channel name: `UK:`, `UK |`, `|UK|`, `[UK]`,
/// `US -` and similar decorations before the actual name.
final RegExp _regionTag = RegExp(
  r'^\s*[\[\(|┃]?\s*[A-Za-z]{2,3}\s*[\]\)|┃:\-]\s*',
);

/// Quality/technical tokens stripped from a channel base name.
const Set<String> _qualityTokens = {
  'hd',
  'fhd',
  'uhd',
  'sd',
  '4k',
  '8k',
  'hevc',
  'h265',
  'h264',
  '1080p',
  '720p',
  '2160p',
  '50fps',
  '60fps',
  'raw',
  'backup',
};

const Set<String> _ultraHdTokens = {'4k', 'uhd', '2160p'};
const Set<String> _fullHdTokens = {'fhd', '1080p'};
const Set<String> _hdTokens = {'hd', '720p'};

/// Generic club tokens removed from a team name to get a shorter variant.
const Set<String> _clubTokens = {
  'fc',
  'afc',
  'cf',
  'sc',
  'ac',
  'ssc',
  'as',
  'club',
  'cd',
};

/// A variant shorter than this is too ambiguous to match a listing title.
const int _minVariantLength = 4;

/// Well-known short names, keyed by [normalizeSportsText]ed team name.
const Map<String, List<String>> kSportsTeamAliases = {
  'manchester united': ['man utd', 'man united'],
  'manchester city': ['man city'],
  'tottenham hotspur': ['spurs', 'tottenham'],
  'paris saint germain': ['psg', 'paris sg'],
  'bayern munich': ['bayern', 'bayern munchen', 'fc bayern'],
  'internazionale': ['inter', 'inter milan'],
  'ac milan': ['milan'],
  'atletico madrid': ['atletico', 'atleti'],
  'borussia dortmund': ['dortmund', 'bvb'],
  'wolverhampton wanderers': ['wolves'],
  'brighton hove albion': ['brighton'],
  'newcastle united': ['newcastle'],
  'west ham united': ['west ham'],
  'nottingham forest': ['nottm forest', 'forest'],
  'afc bournemouth': ['bournemouth'],
  'leeds united': ['leeds'],
  'bayer leverkusen': ['leverkusen'],
  'real betis': ['betis'],
  'sporting cp': ['sporting lisbon', 'sporting'],
};

/// Lowercases, folds accents, then keeps only `a-z`/`0-9` (everything else
/// becomes a space), collapses runs of spaces and trims.
String normalizeSportsText(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    final folded = _accentFolds[char];
    if (folded != null) {
      buffer.write(folded);
    } else if (_isAsciiLetterOrDigit(char)) {
      buffer.write(char);
    } else {
      buffer.write(' ');
    }
  }
  return _collapseSpaces(buffer.toString());
}

bool _isAsciiLetterOrDigit(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 0x61 && code <= 0x7a) || (code >= 0x30 && code <= 0x39);
}

String _collapseSpaces(String text) => text.replaceAll(_spaces, ' ').trim();

/// Whole-word `contains`: both sides are padded with a space so `'new'` never
/// matches `'newcastle'`. An empty needle never matches.
bool sportsTextContains(String normalizedHaystack, String normalizedNeedle) {
  if (normalizedNeedle.isEmpty) return false;
  return ' $normalizedHaystack '.contains(' $normalizedNeedle ');
}

/// Matchable team names in priority order: full name, short name, known
/// aliases, then the full name without generic club tokens.
///
/// Every variant is normalized; variants shorter than 4 characters and
/// duplicates (first spelling wins) are dropped.
List<String> teamNameVariants(SportsTeam team) {
  final normalized = normalizeSportsText(team.name);
  final variants = <String>[];
  void add(String value) {
    final variant = normalizeSportsText(value);
    if (variant.length < _minVariantLength) return;
    if (!variants.contains(variant)) variants.add(variant);
  }

  add(team.name);
  add(team.shortName);
  for (final alias in kSportsTeamAliases[normalized] ?? const <String>[]) {
    add(alias);
  }
  add(_withoutClubTokens(normalized));
  return variants;
}

String _withoutClubTokens(String normalizedName) => _collapseSpaces(
  normalizedName
      .split(' ')
      .where((token) => !_clubTokens.contains(token))
      .join(' '),
);

/// Comparison key of a channel name: region tag and quality tokens removed.
///
/// `'UK: Sky Sports Main Event FHD'` and `'Sky Sports Main Event 4K'` share the
/// base name `'sky sports main event'`.
String channelBaseName(String channelName) {
  final stripped = channelName.replaceFirst(_regionTag, '');
  final normalized = normalizeSportsText(stripped);
  if (normalized.isEmpty) return '';
  return _collapseSpaces(
    normalized
        .split(' ')
        .where((token) => !_qualityTokens.contains(token))
        .join(' '),
  );
}

/// Higher means better picture: 3 for 4K/UHD, 2 for FHD/1080p, 1 for HD/720p.
int channelQualityRank(String channelName) {
  final tokens = normalizeSportsText(channelName).split(' ');
  if (tokens.any(_ultraHdTokens.contains)) return 3;
  if (tokens.any(_fullHdTokens.contains)) return 2;
  if (tokens.any(_hdTokens.contains)) return 1;
  return 0;
}

/// The full channel names behind the short broadcaster names the feed uses,
/// keyed by [channelBaseName] of the short form: "Golf Chnl" is the channel
/// every playlist calls "Golf Channel".
const Map<String, List<String>> _broadcasterAliases = {
  'golf chnl': ['golf channel', 'nbc golf'],
  'tennis chnl': ['tennis channel'],
  'usa net': ['usa network'],
  'btn': ['big ten network'],
  'msgsn': ['msg sportsnet', 'msg sports network'],
  'tele': ['telemundo'],
  'nfl net': ['nfl network'],
  'mlb net': ['mlb network'],
  'nhl net': ['nhl network'],
  'cbssn': ['cbs sports network'],
};

/// Channel base names to look for when the feed names [broadcaster]: its own
/// base name plus the full names of a known short form.
List<String> sportsBroadcasterNeedles(String broadcaster) {
  final base = channelBaseName(broadcaster);
  if (base.isEmpty) return const [];
  return [base, ...?_broadcasterAliases[base]];
}

/// Country codes cricket listings use for national sides ("Int CRI '26: RSA
/// v AUS 3rd Test"), keyed by [normalizeSportsText]ed team name.
const Map<String, List<String>> kCricketCountryCodes = {
  'south africa': ['rsa', 'sa'],
  'australia': ['aus'],
  'india': ['ind'],
  'england': ['eng'],
  'new zealand': ['nz', 'nzl'],
  'pakistan': ['pak'],
  'sri lanka': ['sl', 'slk'],
  'bangladesh': ['ban'],
  'west indies': ['wi'],
  'afghanistan': ['afg'],
  'zimbabwe': ['zim'],
  'ireland': ['ire'],
  'netherlands': ['ned'],
  'united arab emirates': ['uae'],
  'scotland': ['sco'],
  'namibia': ['nam'],
  'nepal': ['nep'],
  'oman': ['oma'],
  'united states': ['usa'],
  'canada': ['can'],
};
