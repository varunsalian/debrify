import '../../../utils/iptv_title.dart';

/// What a WebDAV folder or file name says about its content. Every field is
/// optional: release names, library folders and bare episode files each carry
/// a different subset.
final class WebDavReleaseName {
  const WebDavReleaseName({
    required this.titleKey,
    this.year,
    this.season,
    this.seasonEnd,
    this.completeSeries = false,
    this.episode,
    this.episodeEnd,
    this.imdbId,
  });

  /// Folded title words before the first year, season or quality marker.
  /// Empty when the name starts with such a marker (`S01E02.mkv`).
  final String titleKey;
  final int? year;
  final int? season;

  /// Last season of a multi-season pack (`S01-S05`), else [season].
  final int? seasonEnd;

  /// "Complete Series" packs hold every season.
  final bool completeSeries;
  final int? episode;

  /// Last episode of a multi-episode file (`S01E01E02`), else [episode].
  final int? episodeEnd;

  /// A Plex/Jellyfin id tag such as `{imdb-tt1160419}`, when present.
  final String? imdbId;

  bool coversEpisode(int value) =>
      episode != null && value >= episode! && value <= (episodeEnd ?? episode!);

  /// Whether this name can hold [value]; unknown seasons count as possible.
  bool coversSeason(int value) {
    if (completeSeries) return true;
    if (season == null) return true;
    return value >= season! && value <= (seasonEnd ?? season!);
  }

  bool get hasSeasonInfo => season != null || completeSeries;

  static final _leadingGroup = RegExp(r'^\s*\[[^\]]*\]\s*');
  static final _extension = RegExp(r'\.[A-Za-z0-9]{2,4}$');
  static final _idTag = RegExp(
    r'[\[{]\s*(imdb|tmdb|tvdb)(?:id)?\s*[-=]\s*([a-z0-9]+)\s*[\]}]',
    caseSensitive: false,
  );
  static final _braces = RegExp(r'\{[^}]*\}');
  static final _seasonEpisode = RegExp(
    r'(?<![A-Za-z0-9])[Ss](\d{1,2})[\s._-]*[Ee][Pp]?(\d{1,3})'
    // Further episodes: "E02", or "-02" when no letter follows ("-10bit").
    r'(?:[\s._-]*[Ee](\d{1,3})|-(\d{1,3})(?![\dA-Za-z]))*(?!\d)',
  );
  static final _crossEpisode = RegExp(
    r'(?<![A-Za-z0-9])(\d{1,2})[xX](\d{2,3})(?!\d)',
  );
  static final _wordsSeasonEpisode = RegExp(
    r'\bseason[\s._-]*(\d{1,2})[\s._-]*episode[\s._-]*(\d{1,3})\b',
    caseSensitive: false,
  );
  static final _seasonRange = RegExp(
    r'(?<![A-Za-z0-9])(?:[Ss](\d{1,2})[\s._]*(?:-|to)[\s._]*[Ss]?(\d{1,2})|'
    r'(?:seasons?|series|staffel|saison|temporada)[\s._-]*(\d{1,2})'
    r'[\s._]*(?:-|to|&)[\s._]*(\d{1,2}))(?![\dkKpPbB])',
    caseSensitive: false,
  );
  static final _seasonOnly = RegExp(
    r'(?<![A-Za-z0-9])(?:[Ss](\d{1,2})(?![A-Za-z0-9])|'
    r'(?:season|series|staffel|saison|temporada|stagione)[\s._-]*(\d{1,2})(?!\d))',
    caseSensitive: false,
  );
  static final _complete = RegExp(
    r'\bcomplete[\s._-]*(?:series|collection|seasons|box[\s._-]*set)\b|'
    r'\b(?:all|complete)[\s._-]*seasons\b',
    caseSensitive: false,
  );
  static final _episodeOnly = RegExp(
    r'(?<![A-Za-z0-9])(?:[Ee][Pp]?|episode|folge|episodio)[\s._-]*(\d{1,3})(?![\dpP])',
    caseSensitive: false,
  );
  static final _leadingNumber = RegExp(r'^(\d{1,3})(?![\dpPxX])');
  static final _dashNumber = RegExp(r'\s-\s(\d{1,3})(?![\dpP])');

  /// Folded words that end a release title. Only technical tokens: ordinary
  /// words such as "complete" or "series" also begin real titles.
  static final _stopWord = RegExp(
    r'^(?:s\d{1,2}(?:e\d{1,3})*|s\d{1,2}e\d{1,3}e\d{1,3}|\d{1,2}x\d{2,3}|'
    r'2160p|1080p|1080i|720p|576p|480p|4k|uhd|hdr10|bluray|bdrip|brrip|'
    r'webrip|webdl|hdtv|remux|dvdrip|hdrip|x264|x265|h264|h265|hevc)$',
  );

  /// A season word ends the title only when a number follows it.
  static const _seasonWords = {
    'season',
    'seasons',
    'series',
    'staffel',
    'saison',
    'temporada',
    'stagione',
  };

  /// "Complete" ends the title only before a pack word or the name's end.
  static const _packWords = {'series', 'seasons', 'collection', 'box', 'pack'};
  static final _yearWord = RegExp(r'^(?:19|20)\d{2}$');
  static final _number = RegExp(r'^\d{1,2}$');

  /// Latin letters with marks, folded to plain letters ("Shōgun",
  /// "Amélie", "Łódź", "Čapek"). Other scripts are kept as they are.
  static const _accents = {
    'à': 'a',
    'á': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'ă': 'a',
    'ą': 'a',
    'æ': 'ae',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ď': 'd',
    'đ': 'd',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ė': 'e',
    'ę': 'e',
    'ě': 'e',
    'ğ': 'g',
    'ì': 'i',
    'í': 'i',
    'î': 'i',
    'ï': 'i',
    'ī': 'i',
    'į': 'i',
    'ı': 'i',
    'ł': 'l',
    'ľ': 'l',
    'ñ': 'n',
    'ń': 'n',
    'ň': 'n',
    'ò': 'o',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ø': 'o',
    'ō': 'o',
    'ő': 'o',
    'œ': 'oe',
    'ř': 'r',
    'ś': 's',
    'š': 's',
    'ș': 's',
    'ş': 's',
    'ß': 'ss',
    'ť': 't',
    'ț': 't',
    'ţ': 't',
    'ù': 'u',
    'ú': 'u',
    'û': 'u',
    'ü': 'u',
    'ū': 'u',
    'ů': 'u',
    'ű': 'u',
    'ų': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ź': 'z',
    'ż': 'z',
    'ž': 'z',
    'þ': 'th',
    'ð': 'd',
  };
  static final _combiningMarks = RegExp('[\u0300-\u036f]');
  static final _accented = RegExp('[${_accents.keys.join()}]');

  /// Comparison key shared by targets and names: case, accents and
  /// punctuation fold away, apostrophes vanish (`Grey's` = `Greys`) and `&`
  /// reads as `and`.
  static String fold(String value) {
    // Decomposed marks ("o" + combining macron, common from macOS) first.
    var text = value.toLowerCase().replaceAll(_combiningMarks, '');
    if (_accented.hasMatch(text)) {
      text = text.replaceAllMapped(_accented, (m) => _accents[m[0]!]!);
    }
    return IptvTitle.comparisonKey(
      text.replaceAll(RegExp(r"['’`]"), '').replaceAll('&', ' and '),
    );
  }

  /// Parses [name]; [isFile] drops a file extension first. [bareEpisodes]
  /// also reads `03 - Pilot.mkv` or `Show - 05.mkv` as episode numbers, which
  /// only makes sense inside a series' own folder ("300.mkv" is a movie).
  static WebDavReleaseName parse(
    String name, {
    bool isFile = false,
    bool bareEpisodes = false,
  }) {
    var raw = name.trim();
    if (isFile) raw = raw.replaceFirst(_extension, '');
    raw = raw.replaceFirst(_leadingGroup, '');
    String? imdbId;
    for (final tag in _idTag.allMatches(raw)) {
      final value = tag.group(2)!.toLowerCase();
      if (tag.group(1)!.toLowerCase() == 'imdb' && value.startsWith('tt')) {
        imdbId = value;
      }
    }
    raw = raw.replaceAll(_idTag, ' ').replaceAll(_braces, ' ');

    int? season;
    int? seasonEnd;
    int? episode;
    int? episodeEnd;
    var titleText = raw;
    final complete = _complete.hasMatch(raw);
    final full = _seasonEpisode.firstMatch(raw);
    if (full != null) {
      season = int.parse(full.group(1)!);
      episode = int.parse(full.group(2)!);
      final ends = [
        full.group(3),
        full.group(4),
      ].whereType<String>().map(int.parse);
      final end = ends.isEmpty ? null : ends.reduce((a, b) => a > b ? a : b);
      if (end != null && end > episode && end - episode <= 9) episodeEnd = end;
    } else if (_wordsSeasonEpisode.firstMatch(raw) case final match?) {
      season = int.parse(match.group(1)!);
      episode = int.parse(match.group(2)!);
    } else if (_crossEpisode.firstMatch(raw) case final match?) {
      season = int.parse(match.group(1)!);
      episode = int.parse(match.group(2)!);
    } else if (_seasonRange.firstMatch(raw) case final match?) {
      season = int.parse(match.group(1) ?? match.group(3)!);
      final end = int.parse(match.group(2) ?? match.group(4)!);
      if (end >= season) seasonEnd = end;
    } else {
      final seasonMatch = _seasonOnly.firstMatch(raw);
      if (seasonMatch != null) {
        season = int.parse(seasonMatch.group(1) ?? seasonMatch.group(2)!);
      }
      final episodeMatch = _episodeOnly.firstMatch(raw);
      if (episodeMatch != null) {
        episode = int.parse(episodeMatch.group(1)!);
      } else if (isFile && bareEpisodes) {
        final leading = _leadingNumber.firstMatch(raw.trim());
        final dashed = _dashNumber.firstMatch(raw);
        final value = leading?.group(1) ?? dashed?.group(1);
        if (value != null) episode = int.parse(value);
        // "Show - 05 (1080p)": the number ends the title.
        if (leading == null && dashed != null) {
          titleText = raw.substring(0, dashed.start);
        }
      }
    }

    final words = fold(titleText.replaceAll(RegExp(r'[._]'), ' ')).split(' ')
      ..removeWhere((word) => word.isEmpty);
    final title = <String>[];
    int? year;
    for (var i = 0; i < words.length; i++) {
      final word = words[i];
      // A leading year is a title ("1917", "2012"); so is a year followed by
      // another year ("Blade Runner 2049 (2017)").
      if (_yearWord.hasMatch(word) && i > 0) {
        final later = words
            .skip(i + 1)
            .takeWhile((w) => !_stopWord.hasMatch(w));
        if (!later.any(_yearWord.hasMatch)) {
          year = int.parse(word);
          break;
        }
      }
      if (_stopWord.hasMatch(word)) break;
      final next = i + 1 < words.length ? words[i + 1] : null;
      if (_seasonWords.contains(word) &&
          next != null &&
          _number.hasMatch(next)) {
        break;
      }
      if ((word == 'complete' || word == 'all') &&
          i > 0 &&
          (next == null ||
              _packWords.contains(next) ||
              _stopWord.hasMatch(next))) {
        break;
      }
      title.add(word);
    }
    return WebDavReleaseName(
      titleKey: title.join(' '),
      year: year,
      season: season,
      seasonEnd: seasonEnd ?? season,
      completeSeries: complete && full == null,
      episode: episode,
      episodeEnd: episodeEnd ?? episode,
      imdbId: imdbId,
    );
  }
}
