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
}

/// Helper function to extract year from title
int? _extractYear(String title) {
  final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(title);
  if (match != null) {
    return int.tryParse(match.group(0)!);
  }
  return null;
}
