import 'webdav_folder_names.dart';
import 'webdav_release_name.dart';

/// The title a Sources search is looking for on a WebDAV server.
final class WebDavMatchTarget {
  WebDavMatchTarget({
    required String title,
    String? year,
    required this.isSeries,
    this.season,
    this.episode,
    this.requireYear = false,
    String? imdbId,
  }) : titleKey = WebDavReleaseName.fold(title),
       year = int.tryParse(RegExp(r'\d{4}').stringMatch(year ?? '') ?? ''),
       imdbId = imdbId != null && imdbId.startsWith('tt')
           ? imdbId.toLowerCase()
           : null;

  final String titleKey;
  final int? year;
  final bool isSeries;
  final int? season;
  final int? episode;

  /// Matches a Plex/Jellyfin `{imdb-tt…}` folder tag exactly.
  final String? imdbId;

  /// Automatic picks must not choose a remake: a movie folder or loose file
  /// then has to state the year. Manual Sources lists yearless matches too.
  final bool requireYear;

  /// A series needs a concrete episode; a title needs searchable words.
  bool get searchable =>
      titleKey.isNotEmpty && (!isSeries || (season != null && episode != null));
}

enum WebDavFolderKind {
  /// Not worth a request.
  skip,

  /// A library or index folder that may hold the title further down.
  browse,

  /// The title's own folder (or a season/pack folder inside it).
  title,

  /// An unrecognised folder that may group titles by language, drive, user
  /// or collection ("Hollywood", "English", "HDD1"). Opened after every
  /// recognised folder, and only from folders that look like categories.
  guess,
}

final class WebDavFolderDecision {
  const WebDavFolderDecision(this.kind, {this.season});

  static const skip = WebDavFolderDecision(WebDavFolderKind.skip);
  static const browse = WebDavFolderDecision(WebDavFolderKind.browse);
  static const guess = WebDavFolderDecision(WebDavFolderKind.guess);

  final WebDavFolderKind kind;

  /// Season implied by the folder name, carried down to bare episode files.
  final int? season;
}

/// Pure keyword rules deciding which folders to open and which files match.
/// WebDAV can only list one folder at a time and has no search, so folders
/// are ranked: the title's own first, then library folders, then folders
/// that may be categories. Other titles' release folders are never opened.
final class WebDavTitleMatcher {
  WebDavTitleMatcher(this.target)
    : _needle = _needleFor(target.titleKey),
      _initials = {
        if (target.titleKey.isNotEmpty) target.titleKey[0],
        if (_withoutArticle(target.titleKey).isNotEmpty)
          _withoutArticle(target.titleKey)[0],
      };

  final WebDavMatchTarget target;

  /// The title's longest word, for a cheap substring prefilter.
  final String? _needle;
  final Set<String> _initials;

  /// Words that mark a library folder anywhere in its name ("Movies 4K",
  /// "Kids Movies", "TV Shows").
  static const _libraryWords = {
    'all',
    'anime',
    'bollywood',
    'cartoons',
    'cinema',
    'collections',
    'complete',
    'completed',
    'content',
    'data',
    'debrid',
    'documentaries',
    'download',
    'downloads',
    'docs',
    'documentary',
    'film',
    'filme',
    'filmes',
    'films',
    'peliculas',
    'serien',
    'history',
    'hollywood',
    'homes',
    'kids',
    'library',
    'links',
    'magnets',
    'media',
    'movie',
    'movies',
    'multimedia',
    'plex',
    'jellyfin',
    'emby',
    'kodi',
    'public',
    'series',
    'share',
    'shared',
    'show',
    'shows',
    'storage',
    'television',
    'torrents',
    'tv',
    'tvshows',
    'usenet',
    'video',
    'videos',
  };

  /// Quality words that name library folders ("4K", "Movies (UHD)") but on
  /// their own never make a release folder a library.
  static const _qualityWords = {
    '4k',
    'uhd',
    'hd',
    'hdr',
    '1080p',
    '2160p',
    'webdl',
  };
  static const _connectors = {'and', 'the', 'my', 'of', 'new', 'all'};

  static const _extrasFolders = {
    'sample',
    'samples',
    'extras',
    'extra',
    'featurettes',
    'featurette',
    'behind the scenes',
    'deleted scenes',
    'interviews',
    'trailers',
    'trailer',
    'subs',
    'subtitles',
    'artwork',
    'covers',
    'screens',
    'screenshots',
    'proof',
  };

  static const _minimumMovieBytes = 40 * 1024 * 1024;
  static final _regionSuffix = RegExp(r' (?:us|uk|au|nz|ca)$');

  static String _withoutArticle(String key) =>
      key.startsWith('the ') ? key.substring(4) : key;

  /// Edition words that may sit between a title and its year
  /// ("Inception.Extended.Cut.2010", "Blade Runner The Final Cut").
  static const _editionWords = {
    'anniversary',
    'collectors',
    'criterion',
    'cut',
    'dc',
    'director',
    'directors',
    'edition',
    'enhanced',
    'extended',
    'final',
    'imax',
    'remaster',
    'remastered',
    'restored',
    'special',
    'the',
    'theatrical',
    'ultimate',
    'uncensored',
    'uncut',
    'unrated',
    'version',
  };

  static String _withoutEdition(String key) {
    final words = key.split(' ');
    var end = words.length;
    while (end > 1 && _editionWords.contains(words[end - 1])) {
      end--;
    }
    return words.take(end).join(' ');
  }

  static final _leadingYear = RegExp(r'^((?:19|20)\d{2}) (.+)$');

  static String? _needleFor(String key) {
    // "and" may stand for "&" in the raw name; "the" is often dropped.
    final words =
        key
            .split(' ')
            .where((w) => w.length >= 3 && w != 'and' && w != 'the')
            .toList()
          ..sort((a, b) => b.length.compareTo(a.length));
    return words.isEmpty ? null : words.first;
  }

  static final _ascii = RegExp(r'^[\x00-\x7f]*$');

  /// Cheap test before the full parse: false only when [name] cannot be the
  /// title (it lacks the title's longest word). Non-ASCII names always pass.
  bool mayName(String name) {
    final needle = _needle;
    if (needle == null || !_ascii.hasMatch(name)) return true;
    // Folding drops apostrophes ("Ocean's" → "oceans"); do the same here.
    return name.toLowerCase().replaceAll(_apostrophes, '').contains(needle);
  }

  /// Whether an ASCII [name] holds the title's longest word ("Games" in
  /// "The Hunger Games Collection").
  bool _namesTitle(String name) =>
      _needle != null && _ascii.hasMatch(name) && mayName(name);

  static final _apostrophes = RegExp(r"['`]");

  static final _nonWord = RegExp(r'[^a-z0-9]+');
  static final _numbersOnly = RegExp(r'^[\d\s._()\[\]–-]+s?$');

  /// Cheap test for folders while still looking for the title: one split and
  /// set lookups, so a flat folder of thousands of release names stays fast.
  bool mayBeLibraryOrTitle(String name) {
    if (name.length <= 5) return true; // Index folders: "A", "A-F", "#".
    if (_numbersOnly.hasMatch(name)) return true; // "2010-2019"
    if (mayName(name)) return true;
    final words = name.toLowerCase().split(_nonWord);
    if (words.any(_libraryWords.contains)) return true;
    return words.length <= 4 && words.any(_qualityWords.contains);
  }

  /// "The Office (US)" names "The Office": a trailing region is dropped
  /// unless the title itself ends with it.
  String _comparable(String key) => _withoutArticle(
    _regionSuffix.hasMatch(target.titleKey)
        ? key
        : key.replaceFirst(_regionSuffix, ''),
  );

  bool _sameTitle(WebDavReleaseName name) {
    final wanted = target.imdbId;
    if (wanted != null && name.imdbId != null) return name.imdbId == wanted;
    if (name.titleKey.isEmpty) return false;
    var titleMatches = _titleKeyMatches(name.titleKey);
    // "Free.for.All.S01E01": a trailing "All"/"Complete" read as a pack word
    // may still end the title.
    if (!titleMatches &&
        (target.titleKey == '${name.titleKey} all' ||
            target.titleKey == '${name.titleKey} complete')) {
      titleMatches = true;
    }
    var year = name.year;
    // "Blade Runner 2049.mkv": the "year" is part of the title.
    if (!titleMatches &&
        year != null &&
        '${name.titleKey} $year' == target.titleKey) {
      titleMatches = true;
      year = null;
    }
    // "Star Wars Special Edition" alone could be any "Star Wars"; an
    // edition name needs its year.
    if (!titleMatches && !target.isSeries && year != null) {
      final trimmed = _withoutEdition(name.titleKey);
      titleMatches = trimmed != name.titleKey && _titleKeyMatches(trimmed);
    }
    if (!titleMatches) return !target.isSeries && _looseMatch(name);
    final targetYear = target.year;
    if (targetYear == null) return true;
    // Series packs are often dated by their season ("The.Bear.2024.S03"),
    // so a series name only rules itself out by year without season info.
    if (target.isSeries && name.hasSeasonInfo) return true;
    if (year == null) return !(target.requireYear && !target.isSeries);
    // One year of slack covers festival-versus-release dating.
    return (year - targetYear).abs() <= 1;
  }

  bool _titleKeyMatches(String key) =>
      key == target.titleKey ||
      _comparable(key) == _withoutArticle(target.titleKey);

  /// Looser movie forms, accepted only when the name states the target's
  /// year: a leading year ("2010 - Inception") and run-together words
  /// ("IronMan.2008", "Spiderman.No.Way.Home.2021"). Both need the exact
  /// year, and run-together words a longer title ("I.T." 2016 is not "It").
  /// A leading year counts only when no other year follows, since some
  /// titles start with one ("2010: Moby Dick (2010)").
  bool _looseMatch(WebDavReleaseName name) {
    final targetYear = target.year;
    if (targetYear == null) return false;
    var key = name.titleKey;
    var year = name.year;
    if (year == null) {
      final lead = _leadingYear.firstMatch(key);
      if (lead == null || int.parse(lead[1]!) != targetYear) return false;
      year = targetYear;
      key = lead[2]!;
    }
    if ((year - targetYear).abs() > 1) return false;
    key = _withoutEdition(key);
    if (_titleKeyMatches(key)) return true;
    final squashed = _comparable(key).replaceAll(' ', '');
    return year == targetYear &&
        squashed.length >= 5 &&
        squashed == _comparable(target.titleKey).replaceAll(' ', '');
  }

  static bool _isLetterIndex(String key) =>
      key.length == 1 || RegExp(r'^[a-z0-9] [a-z0-9]$').hasMatch(key);

  bool _letterIndexFits(String key) {
    if (key.length == 1) return _initials.contains(key);
    final range = RegExp(r'^([a-z0-9]) ([a-z0-9])$').firstMatch(key);
    if (range == null) return false;
    return _initials.any(
      (initial) =>
          initial.compareTo(range.group(1)!) >= 0 &&
          initial.compareTo(range.group(2)!) <= 0,
    );
  }

  /// A folder seen while still looking for the title.
  WebDavFolderDecision libraryFolder(String name) {
    if (!mayBeLibraryOrTitle(name)) return _unrecognised(name);
    final key = WebDavReleaseName.fold(name);
    if (key.isEmpty) return WebDavFolderDecision.browse; // "#", "__"
    final parsed = WebDavReleaseName.parse(name);
    if (_sameTitle(parsed)) return _titleFolder(parsed);
    if (_letterIndexFits(key) || _isLibraryName(key, parsed)) {
      return WebDavFolderDecision.browse;
    }
    if (_isLetterIndex(key)) return WebDavFolderDecision.skip;
    // "Movies A-L": an index under a library name.
    final words = key.split(' ');
    final index = words.skipWhile(_isLibraryWord).join(' ');
    if (index != key && _isLetterIndex(index)) {
      return _letterIndexFits(index)
          ? WebDavFolderDecision.browse
          : WebDavFolderDecision.skip;
    }
    // "2010", "Movies 2010", "2010-2019", "2010s".
    if (WebDavFolderNames.yearSpan(key, _isLibraryWord) case (
      final from,
      final to,
    )) {
      final year = target.year;
      return year != null && year >= from - 1 && year <= to + 1
          ? WebDavFolderDecision.browse
          : WebDavFolderDecision.skip;
    }
    if (parsed.year != null || parsed.hasSeasonInfo) {
      return WebDavFolderDecision.skip;
    }
    return _unrecognised(name);
  }

  static bool _isLibraryWord(String word) =>
      _libraryWords.contains(word) ||
      _qualityWords.contains(word) ||
      _connectors.contains(word);

  WebDavFolderDecision _unrecognised(String name) {
    // The cheap marker test first: a flat debrid folder lists thousands.
    if (!WebDavFolderNames.mayBeCategory(name) ||
        WebDavFolderNames.isNeverMedia(name, namesTitle: _namesTitle(name)) ||
        _extrasFolders.contains(WebDavReleaseName.fold(name))) {
      return WebDavFolderDecision.skip;
    }
    return WebDavFolderDecision.guess;
  }

  /// "Movies", "Kids Movies", "Movies (4K)", "TV Shows - English": library
  /// and quality words with at most one other word. A release folder
  /// ("Some.Show.2023.1080p") never qualifies.
  static bool _isLibraryName(String key, WebDavReleaseName parsed) {
    if (parsed.year != null || parsed.hasSeasonInfo) return false;
    var library = false;
    var quality = false;
    var other = 0;
    for (final word in key.split(' ')) {
      if (_libraryWords.contains(word)) {
        library = true;
      } else if (_qualityWords.contains(word)) {
        quality = true;
      } else if (!_connectors.contains(word)) {
        other++;
      }
    }
    return (library && other <= 1) || (quality && !library && other == 0);
  }

  WebDavFolderDecision _titleFolder(WebDavReleaseName parsed) {
    if (!target.isSeries) {
      return parsed.season == null
          ? const WebDavFolderDecision(WebDavFolderKind.title)
          : WebDavFolderDecision.skip;
    }
    // "Show.S02.1080p", "Show.S01-S05", or a single-episode folder.
    if (!parsed.coversSeason(target.season!)) return WebDavFolderDecision.skip;
    if (parsed.episode != null && !parsed.coversEpisode(target.episode!)) {
      return WebDavFolderDecision.skip;
    }
    return WebDavFolderDecision(
      WebDavFolderKind.title,
      season: parsed.season == parsed.seasonEnd ? parsed.season : null,
    );
  }

  /// A folder inside the title's folder: seasons, packs, or extras.
  WebDavFolderDecision innerFolder(String name, {int? season}) {
    final key = WebDavReleaseName.fold(name);
    if (_extrasFolders.contains(key)) return WebDavFolderDecision.skip;
    if (!target.isSeries) {
      return const WebDavFolderDecision(WebDavFolderKind.title);
    }
    if (key == 'specials') {
      return target.season == 0
          ? const WebDavFolderDecision(WebDavFolderKind.title, season: 0)
          : WebDavFolderDecision.skip;
    }
    final parsed = WebDavReleaseName.parse(name);
    if (parsed.hasSeasonInfo) {
      if (!parsed.coversSeason(target.season!)) {
        return WebDavFolderDecision.skip;
      }
    } else if (season != null && season != target.season) {
      return WebDavFolderDecision.skip;
    }
    if (parsed.episode != null && !parsed.coversEpisode(target.episode!)) {
      return WebDavFolderDecision.skip;
    }
    final single = parsed.season != null && parsed.season == parsed.seasonEnd;
    return WebDavFolderDecision(
      WebDavFolderKind.title,
      season: single ? parsed.season : (parsed.hasSeasonInfo ? null : season),
    );
  }

  /// Whether a video file is the requested title. [insideTitle] means a parent
  /// folder already matched, so a bare `S01E03.mkv` or `03 - Pilot.mkv` counts.
  bool matchesFile(
    String name, {
    required bool insideTitle,
    int? season,
    int? sizeBytes,
  }) {
    if (!insideTitle && !mayName(name)) return false;
    if (target.isSeries) {
      if (_isSample(name)) return false;
      final parsed = WebDavReleaseName.parse(
        name,
        isFile: true,
        bareEpisodes: insideTitle,
      );
      if (!insideTitle && !_sameTitle(parsed)) return false;
      final fileSeason = parsed.season ?? season;
      if (fileSeason != target.season) return false;
      return parsed.coversEpisode(target.episode!);
    }
    if (_isSample(name) || _isTooSmall(sizeBytes)) return false;
    if (insideTitle) return true;
    final parsed = WebDavReleaseName.parse(name, isFile: true);
    return parsed.season == null &&
        parsed.episode == null &&
        _sameTitle(parsed);
  }

  static bool _isSample(String name) {
    final words = WebDavReleaseName.fold(name).split(' ');
    return words.contains('sample') || words.contains('trailer');
  }

  static bool _isTooSmall(int? sizeBytes) =>
      sizeBytes != null && sizeBytes > 0 && sizeBytes < _minimumMovieBytes;
}
