import '../../models/rd_file_node.dart';

/// Shared ordering for Real-Debrid and TorBox folder views.
/// Returns a new list of the existing nodes; raw order and children stay intact.
class CloudFolderSort {
  CloudFolderSort._();

  /// Apply sorted view (folders first A-Z, then files A-Z)
  /// Special handling for numbered folders and files to sort numerically
  static List<RDFileNode> sortedView(List<RDFileNode> nodes) {
    final folders = nodes.where((n) => n.isFolder).toList();
    final files = nodes.where((n) => !n.isFolder).toList();

    // Sort folders with special handling for numbered folders
    folders.sort((a, b) {
      // Extract numbers if folders are named "Season X", "Chapter X", etc.
      final aNum = _extractSeasonNumber(a.name);
      final bNum = _extractSeasonNumber(b.name);

      // If both have numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one has a number, numbered folders come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    // Sort files with special handling for files starting with numbers
    files.sort((a, b) {
      // Extract leading numbers from filenames (e.g., "10. Video.mp4" -> 10)
      final aNum = _extractLeadingNumber(a.name);
      final bNum = _extractLeadingNumber(b.name);

      // If both start with numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one starts with a number, numbered files come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return [...folders, ...files];
  }

  /// Extract number from folder name for numerical sorting
  /// Handles: "1. Introduction", "10. Chapter", "Season 10", "Chapter_12", "Episode 5", "Part 3", etc.
  /// Returns null if no number pattern found
  static int? _extractSeasonNumber(String folderName) {
    // Try multiple patterns in order of specificity
    final patterns = [
      // Leading numbers: "1. ", "10-", "5_", etc.
      RegExp(r'^(\d+)[\s._-]'),
      // Season X, Season_X, Season-X
      RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
      // Chapter X, Chapter_X, Chapter-X
      RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
      // Episode X, Episode_X, Episode-X
      RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
      // Part X, Part_X, Part-X
      RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
      // Any word followed by number at the start (e.g., "Lesson_5", "Module-3")
      RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
    ];

    final lowerName = folderName.toLowerCase();

    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerName);
      if (match != null && match.groupCount >= 1) {
        return int.tryParse(match.group(1)!);
      }
    }

    return null;
  }

  /// Extract leading number from filename for numerical sorting
  /// Handles: "10. Video.mp4", "9 - Title.mkv", "05_Episode.mp4", etc.
  /// Returns null if filename doesn't start with a number
  static int? _extractLeadingNumber(String filename) {
    // Match numbers at the start of filename (before any separator like . - _ space)
    // Examples: "10.", "9 -", "05_", "123-"
    final pattern = RegExp(r'^(\d+)[\s._-]');
    final match = pattern.firstMatch(filename);

    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }

    return null;
  }
}
