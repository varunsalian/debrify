import 'webdav_release_name.dart';

/// Name rules for folders a title search does not recognise: whether one can
/// never hold video, whether it may be a category worth a look ("Hollywood",
/// "English", "HDD1"), and which years a year folder covers.
final class WebDavFolderNames {
  const WebDavFolderNames._();

  /// Folded words that mark a folder as holding something other than video.
  static const _nonMediaWords = {
    'appdata',
    'applications',
    'apps',
    'audio',
    'audiobooks',
    'books',
    'cache',
    'comics',
    'config',
    'dcim',
    'documents',
    'ebooks',
    'extras',
    'fonts',
    'games',
    'music',
    'photo',
    'photos',
    'pictures',
    'podcasts',
    'roms',
    'scans',
    'software',
    'songs',
    'specials',
    'templates',
    'thumbnails',
    'trash',
    'wallpapers',
  };

  /// Whole folded names of system and app folders.
  static const _systemNames = {
    'lost found',
    'recycle bin',
    'recycle',
    'recycler',
    'system volume information',
    'time machine',
    'timemachine',
    'tmp',
    'temp',
    'talk',
    'notes',
    'node modules',
    'program files',
    'windows',
    'web',
    'www',
  };

  /// A release marker: a year, season or episode code, resolution or source
  /// tag. A folder carrying one is another title's release, not a category.
  static final _releaseMarker = RegExp(
    r'(?<![a-z0-9])(?:(?:19|20)\d{2}|s\d{1,2}(?:e\d{1,3})?|\d{3,4}[pi]|'
    r'x26[45]|h\.?26[45]|hevc|web-?dl|web-?rip|blu-?ray|remux|hdtv|'
    r'dvdrip|brrip|bdrip|season|complete)(?![a-z0-9])',
    caseSensitive: false,
  );
  static final _wordSplit = RegExp(r'[\s._-]+');

  /// Parts of one release: "Disc 1", "CD2", "Part 2", "Vol. 3".
  static final _releasePart = RegExp(
    r'^(?:disc|disk|cd|dvd|part|pt|vol|volume)[\s._-]*\d{1,2}$',
    caseSensitive: false,
  );

  /// Words that mark a title's own bonus material ("Inception Extras").
  static const _bonusWords = {'extras', 'specials'};

  /// NAS, sync and OS folders (`@eaDir`, `#recycle`, `$RECYCLE.BIN`,
  /// `.snapshot`, `~tmp`) and folders named for photos, music or documents.
  /// A folder that [namesTitle] ("The Hunger Games Collection") is judged
  /// by its bonus words only.
  static bool isNeverMedia(String name, {bool namesTitle = false}) {
    final trimmed = name.trim();
    if (trimmed.length > 1 && r'.@#$~'.contains(trimmed[0])) return true;
    final key = WebDavReleaseName.fold(trimmed);
    if (_systemNames.contains(key)) return true;
    final words = namesTitle ? _bonusWords : _nonMediaWords;
    return key.split(' ').any(words.contains);
  }

  /// A short name with no release marker, which may group titles by
  /// language, drive, user or collection.
  static bool mayBeCategory(String name) {
    if (_releaseMarker.hasMatch(name) || _releasePart.hasMatch(name.trim())) {
      return false;
    }
    final words = name.trim().split(_wordSplit).where((w) => w.isNotEmpty);
    return words.isNotEmpty && words.length <= 5;
  }

  static final _yearWord = RegExp(r'^(?:19|20)\d{2}$');
  static final _decadeWord = RegExp(r'^((?:19|20)\d)0s$');

  /// The years a folder such as "2010", "Movies 2010", "2010-2019" or
  /// "2010s" covers, when every other word is in [otherWords]. Null for
  /// anything else.
  static (int, int)? yearSpan(String key, bool Function(String) otherWords) {
    final years = <int>[];
    for (final word in key.split(' ')) {
      if (_yearWord.hasMatch(word)) {
        years.add(int.parse(word));
      } else if (_decadeWord.firstMatch(word) case final decade?) {
        final start = int.parse(decade[1]!) * 10;
        years.addAll([start, start + 9]);
      } else if (!otherWords(word)) {
        return null;
      }
    }
    if (years.isEmpty || years.length > 2) return null;
    years.sort();
    return (years.first, years.last);
  }
}
