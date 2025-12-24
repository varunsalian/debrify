import 'package:flutter/foundation.dart';
import '../screens/video_player/models/playlist_entry.dart';

/// Represents a group (folder) within a movie collection
class CollectionGroup {
  final String name; // Group name (e.g., "Main Movies", "Extras", "Behind the Scenes")
  final List<int> fileIndices; // Indices into the parent collection's files list

  const CollectionGroup({
    required this.name,
    required this.fileIndices,
  });

  int get fileCount => fileIndices.length;
}

/// Represents a collection of movie files organized into groups
class MovieCollection {
  final String? title; // Collection title
  final List<CollectionGroup> groups; // Dynamic groups (folders)
  final List<PlaylistEntry> allFiles; // All files in collection

  const MovieCollection({
    this.title,
    required this.groups,
    required this.allFiles,
  });

  int get totalFiles => allFiles.length;
  int get groupCount => groups.length;

  /// Factory to create MovieCollection with Main/Extras grouping (40% threshold)
  /// This maintains backward compatibility with existing behavior
  factory MovieCollection.fromPlaylistWithMainExtras({
    required List<PlaylistEntry> playlist,
    String? title,
  }) {
    final entries = playlist;
    final mainIndices = <int>[];
    final extrasIndices = <int>[];

    // Find the largest file size
    int maxSize = -1;
    for (int i = 0; i < entries.length; i++) {
      final s = entries[i].sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }

    // Calculate 40% threshold
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;

    // Group files by size threshold
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall = threshold > 0 &&
          (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (isSmall) {
        extrasIndices.add(i);
      } else {
        mainIndices.add(i);
      }
    }

    // Helper functions for sorting
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) => _extractYear(entries[idx].title);

    // Sort main group by year (if available) or size
    mainIndices.sort((a, b) {
      final ya = yearOf(a);
      final yb = yearOf(b);
      if (ya != null && yb != null) {
        return ya.compareTo(yb); // older first
      }
      return sizeOf(b).compareTo(sizeOf(a));
    });

    // Sort extras by size
    extrasIndices.sort((a, b) {
      final sa = entries[a].sizeBytes ?? 0;
      final sb = entries[b].sizeBytes ?? 0;
      return sa.compareTo(sb);
    });

    // Create groups
    final groups = <CollectionGroup>[
      CollectionGroup(name: 'Main', fileIndices: mainIndices),
      CollectionGroup(name: 'Extras', fileIndices: extrasIndices),
    ];

    return MovieCollection(
      title: title,
      groups: groups,
      allFiles: playlist,
    );
  }

  /// Creates a MovieCollection organized by actual folder structure
  /// Preserves original file order (no sorting)
  /// Used for raw/unsorted view mode
  factory MovieCollection.fromFolderStructure({
    required List<PlaylistEntry> playlist,
    String? title,
  }) {
    debugPrint('📁 MovieCollection.fromFolderStructure: Processing ${playlist.length} entries');

    final folderMap = <String, List<int>>{};

    // Group files by their top-level folder
    for (int i = 0; i < playlist.length; i++) {
      final entry = playlist[i];
      final path = entry.relativePath ?? '';
      final folderName = _extractTopLevelFolder(path);

      if (i < 5) {  // Log first 5 entries
        debugPrint('  Entry[$i]: title="${entry.title}"');
        debugPrint('    relativePath: "$path"');
        debugPrint('    extractedFolder: "$folderName"');
      }

      folderMap.putIfAbsent(folderName, () => []);
      folderMap[folderName]!.add(i);  // Store index in original order
    }

    debugPrint('📁 Extracted ${folderMap.length} folders: ${folderMap.keys.toList()}');
    for (final entry in folderMap.entries) {
      debugPrint('  - ${entry.key}: ${entry.value.length} files');
    }

    // Create collection groups (no sorting)
    final groups = folderMap.entries
        .map((entry) => CollectionGroup(
              name: entry.key,
              fileIndices: entry.value,
            ))
        .toList();

    return MovieCollection(
      title: title,
      groups: groups,
      allFiles: playlist,
    );
  }

  /// Creates a MovieCollection with files sorted alphabetically A-Z within folders
  /// Preserves folder structure like Raw mode but sorts files within each folder
  /// Files are already sorted in the playlist parameter (sorting happens in _playFile)
  /// Used for sortedAZ view mode
  factory MovieCollection.fromSortedPlaylist({
    required List<PlaylistEntry> playlist,
    String? title,
  }) {
    debugPrint('🔤 MovieCollection.fromSortedPlaylist: Processing ${playlist.length} entries (pre-sorted)');

    final folderMap = <String, List<int>>{};

    // Group files by their top-level folder (same as Raw mode)
    for (int i = 0; i < playlist.length; i++) {
      final entry = playlist[i];
      final path = entry.relativePath ?? '';
      final folderName = _extractTopLevelFolder(path);

      if (i < 5) {  // Log first 5 entries
        debugPrint('  Entry[$i]: title="${entry.title}"');
        debugPrint('    relativePath: "$path"');
        debugPrint('    extractedFolder: "$folderName"');
      }

      folderMap.putIfAbsent(folderName, () => []);
      folderMap[folderName]!.add(i);  // Files are already sorted in playlist
    }

    debugPrint('🔤 Extracted ${folderMap.length} folders: ${folderMap.keys.toList()}');
    for (final entry in folderMap.entries) {
      debugPrint('  - ${entry.key}: ${entry.value.length} files');
    }

    // Create collection groups with folder structure preserved
    // Files within each folder are already sorted (sorted in _playFile before passing here)
    final groups = folderMap.entries
        .map((entry) => CollectionGroup(
              name: entry.key,
              fileIndices: entry.value,
            ))
        .toList();

    return MovieCollection(
      title: title,
      groups: groups,
      allFiles: playlist,
    );
  }

  /// Extract top-level folder name from relative path
  /// Examples:
  ///   "Season 1/Episode 1.mkv" -> "Season 1"
  ///   "Extras/Behind The Scenes.mkv" -> "Extras"
  ///   "Movie.mkv" -> "Root"
  ///   "" -> "Root"
  static String _extractTopLevelFolder(String path) {
    if (path.isEmpty) return 'Root';

    final parts = path.split('/');
    if (parts.length > 1) {
      return parts[0];  // First folder
    }

    return 'Root';  // File in root directory
  }
}

/// Helper function to extract year from title
int? _extractYear(String title) {
  final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(title);
  if (match != null) {
    return int.tryParse(match.group(0)!);
  }
  return null;
}
