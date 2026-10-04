import 'package:debrify/models/rd_file_node.dart';

/// Apply sorted A-Z view
List<RDFileNode> applySortedView(List<RDFileNode> nodes) {
  final folders = nodes.where((n) => n.isFolder).toList();
  final files = nodes.where((n) => !n.isFolder).toList();

  // Sort folders with numerical handling (same logic as PikPak/RD/Torbox)
  folders.sort((a, b) {
    final aNum = extractSeasonNumber(a.name);
    final bNum = extractSeasonNumber(b.name);

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

  // Sort files with numerical handling (same logic as PikPak/RD/Torbox)
  files.sort((a, b) {
    final aNum = extractLeadingNumber(a.name);
    final bNum = extractLeadingNumber(b.name);

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
int? extractSeasonNumber(String folderName) {
  final patterns = [
    // Leading numbers: "1. ", "10-", "5_", etc.
    RegExp(r'^(\d+)[\s._-]'),
    // Season/Chapter/Episode/Part keywords: "Season 10", "Chapter_12", etc.
    RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
    // Generic word followed by number: "Lesson_5", "Module-3"
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
int? extractLeadingNumber(String filename) {
  final pattern = RegExp(r'^(\d+)[\s._-]');
  final match = pattern.firstMatch(filename);

  if (match != null && match.groupCount >= 1) {
    return int.tryParse(match.group(1)!);
  }

  return null;
}
