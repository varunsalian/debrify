/// How a cloud file browser filters, orders and groups a folder listing.
///
/// Provider-agnostic on purpose. All six cloud browsers — Real-Debrid, TorBox,
/// PikPak, Premiumize, AllDebrid, WebDAV — do the same three things to a
/// listing and each had written its own copy. Their file models cannot share an
/// interface (`TorboxFile.id` is an `int`, `RDFileNode` uses `bytes`,
/// `WebDavItem` uses `isDirectory`), so the shape is supplied as accessors
/// instead. Nothing here names a provider type, and no model has to change to
/// be usable through it.
///
/// Build one per provider and keep it:
///
/// ```dart
/// const pikpakListing = CloudListing<PikPakFile>(
///   isFolder: _isFolder, isVideo: _isVideo, sizeOf: _size, nameOf: _name,
/// );
/// ```
class CloudListing<T> {
  final bool Function(T) isFolder;
  final bool Function(T) isVideo;

  /// Bytes. 0 when the provider does not report a size.
  final int Function(T) sizeOf;

  /// The name to sort and group by — a bare filename, not a path.
  final String Function(T) nameOf;

  const CloudListing({
    required this.isFolder,
    required this.isVideo,
    required this.sizeOf,
    required this.nameOf,
  });

  /// Hide what the user asked not to see.
  ///
  /// Folders always survive both filters: a folder's own size says nothing
  /// about what is inside it, and hiding one would strand its contents.
  List<T> filter(
    List<T> items, {
    bool videosOnly = false,
    int minVideoBytes = 0,
  }) {
    if (!videosOnly && minVideoBytes <= 0) return items;
    return items.where((item) {
      if (isFolder(item)) return true;
      final video = isVideo(item);
      if (videosOnly && !video) return false;
      if (video && minVideoBytes > 0 && sizeOf(item) < minVideoBytes) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Folders first, then files, each ordered the way a person reads them:
  /// `2` before `10`, and numbered entries ahead of unnumbered ones.
  List<T> sorted(List<T> items) {
    final folders = items.where(isFolder).toList();
    final files = items.where((i) => !isFolder(i)).toList();

    folders.sort((a, b) => _compare(nameOf(a), nameOf(b), seasonAware: true));
    files.sort((a, b) => _compare(nameOf(a), nameOf(b), seasonAware: false));

    return [...folders, ...files];
  }

  int _compare(String a, String b, {required bool seasonAware}) {
    final aNum = seasonAware ? seasonNumberIn(a) : leadingNumberIn(a);
    final bNum = seasonAware ? seasonNumberIn(b) : leadingNumberIn(b);

    if (aNum != null && bNum != null && aNum != bNum)
      return aNum.compareTo(bNum);
    // A numbered entry sorts ahead of an unnumbered one, so "1. Intro" leads
    // "Appendix" rather than landing under A.
    if (aNum != null && bNum == null) return -1;
    if (aNum == null && bNum != null) return 1;
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  /// Split a listing into the parts a season grouping needs: existing folders
  /// (left alone), video files (grouped by the caller), and everything else.
  ({List<T> folders, List<T> videos, List<T> others}) partition(List<T> items) {
    final folders = <T>[];
    final videos = <T>[];
    final others = <T>[];
    for (final item in items) {
      if (isFolder(item)) {
        folders.add(item);
      } else if (isVideo(item)) {
        videos.add(item);
      } else {
        others.add(item);
      }
    }
    return (folders: folders, videos: videos, others: others);
  }

  /// Case-insensitive substring match on the name.
  List<T> search(List<T> items, String query) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return items;
    return items
        .where((item) => nameOf(item).toLowerCase().contains(needle))
        .toList();
  }
}

/// How a browser is currently ordering a folder.
enum CloudViewMode {
  /// The provider's own order, untouched.
  raw,

  /// Folders then files, each naturally ordered.
  sortedAZ,

  /// Loose episodes gathered into per-season folders.
  seriesArrange,
}

/// The season, chapter or part a folder name refers to, or null when it names
/// no number.
///
/// Deliberately broader than "season": these browsers show course modules and
/// numbered collections as often as television, and `Module-3` should sort with
/// `Module-10` for the same reason `Season 3` does.
int? seasonNumberIn(String name) {
  final lower = name.toLowerCase();
  for (final pattern in _seasonPatterns) {
    final match = pattern.firstMatch(lower);
    if (match != null && match.groupCount >= 1) {
      final value = int.tryParse(match.group(1)!);
      if (value != null) return value;
    }
  }
  return null;
}

/// The number a filename opens with — `10. Video.mp4`, `05_Episode.mp4` — or
/// null. Only a *leading* number counts, so a year or a resolution buried in
/// the title cannot hijack the order.
int? leadingNumberIn(String filename) {
  final match = _leadingNumber.firstMatch(filename);
  if (match == null || match.groupCount < 1) return null;
  return int.tryParse(match.group(1)!);
}

final _leadingNumber = RegExp(r'^(\d+)[\s._-]');

final _seasonPatterns = <RegExp>[
  _leadingNumber,
  RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
  RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
  RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
  RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
  // A word then a number: "Lesson_5", "Module-3". Last, so the specific
  // keywords above win when both could match.
  RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
];
