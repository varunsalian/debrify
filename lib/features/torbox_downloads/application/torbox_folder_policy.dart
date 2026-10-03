import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/foundation.dart';

/// Detect if current folder contains series episodes
/// Checks recursively in subfolders as well
bool detectSeriesPattern(List<RDFileNode> nodes) {
  // Collect video files recursively from current level and subfolders
  final videoFiles = collectVideoFilesRecursively(nodes);

  if (videoFiles.length < 3) return false;

  final filenames = videoFiles.map((n) => n.name).toList();
  final analysis = SeriesParser.analyzePlaylistConfidence(filenames);
  return analysis.classification == PlaylistClassification.SERIES;
}

/// Recursively collect all video files from nodes and their subfolders
List<RDFileNode> collectVideoFilesRecursively(List<RDFileNode> nodes) {
  final videoFiles = <RDFileNode>[];

  for (final node in nodes) {
    if (node.isFolder) {
      // Recursively collect from subfolder
      videoFiles.addAll(collectVideoFilesRecursively(node.children));
    } else if (FileUtils.isVideoFile(node.name)) {
      // Add video file
      videoFiles.add(node);
    }
  }

  return videoFiles;
}

/// Apply sorted view (folders first A-Z, then files A-Z)
/// Special handling for numbered folders and files to sort numerically
List<RDFileNode> applySortedView(List<RDFileNode> nodes) {
  final folders = nodes.where((n) => n.isFolder).toList();
  final files = nodes.where((n) => !n.isFolder).toList();

  // Sort folders with special handling for numbered folders
  folders.sort((a, b) {
    // Extract numbers if folders are named "Season X", "Chapter X", etc.
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

  // Sort files with special handling for files starting with numbers
  files.sort((a, b) {
    // Extract leading numbers from filenames (e.g., "10. Video.mp4" -> 10)
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
/// Returns null if no number pattern found
int? extractSeasonNumber(String folderName) {
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
int? extractLeadingNumber(String filename) {
  // Match numbers at the start of filename (before any separator like . - _ space)
  // Examples: "10.", "9 -", "05_", "123-"
  final pattern = RegExp(r'^(\d+)[\s._-]');
  final match = pattern.firstMatch(filename);

  if (match != null && match.groupCount >= 1) {
    return int.tryParse(match.group(1)!);
  }

  return null;
}

/// Apply series arranged view (create virtual Season folders)
List<RDFileNode> applySeriesArrangedView(List<RDFileNode> nodes) {
  final folders = nodes.where((n) => n.isFolder).toList();
  final files = nodes.where((n) => !n.isFolder).toList();

  // Parse files for series info
  final videoFiles = files.where((f) => FileUtils.isVideoFile(f.name)).toList();
  final nonVideoFiles = files
      .where((f) => !FileUtils.isVideoFile(f.name))
      .toList();

  if (videoFiles.isEmpty) return nodes;

  final filenames = videoFiles.map((f) => f.name).toList();

  try {
    final parsedInfos = SeriesParser.parsePlaylist(filenames);

    // Group by season
    final Map<int, List<RDFileNode>> seasonMap = {};
    for (int i = 0; i < videoFiles.length; i++) {
      final info = parsedInfos[i];
      if (info.isSeries && info.season != null) {
        seasonMap.putIfAbsent(info.season!, () => []);
        seasonMap[info.season!]!.add(videoFiles[i]);
      } else {
        // If not parsed as series, default to Season 1
        seasonMap.putIfAbsent(1, () => []);
        seasonMap[1]!.add(videoFiles[i]);
      }
    }

    // Create virtual season folders
    final seasonFolders = seasonMap.entries.map((entry) {
      final seasonNum = entry.key;
      final seasonFiles = entry.value;

      // Sort episodes within season by episode number
      seasonFiles.sort((a, b) {
        final aInfo = SeriesParser.parseFilename(a.name);
        final bInfo = SeriesParser.parseFilename(b.name);
        final aEp = aInfo.episode ?? 0;
        final bEp = bInfo.episode ?? 0;
        return aEp.compareTo(bEp);
      });

      return RDFileNode.folder(
        name: seasonNum == 0 ? 'Season 0 - Specials' : 'Season $seasonNum',
        children: seasonFiles,
      );
    }).toList();

    // Sort season folders by season number
    seasonFolders.sort((a, b) {
      final aNum = int.tryParse(a.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final bNum = int.tryParse(b.name.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });

    return [...folders, ...seasonFolders, ...nonVideoFiles];
  } catch (e) {
    debugPrint('Series arrangement failed: $e');
    return applySortedView(nodes); // Fallback to sorted view
  }
}
