import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';

typedef PlaylistContentPlaylistOrderDeps = ({
  PlaylistContentNavigationState navigationState,
  Map<String, dynamic> Function() playlistItem,
});

class PlaylistContentPlaylistOrder {
  PlaylistContentPlaylistOrder(this._deps);
  final PlaylistContentPlaylistOrderDeps _deps;

  /// Apply Sort A-Z ordering to a list of video files for playback
  /// This ensures the playlist plays files in the same order as displayed in the UI
  /// Only applies sorting if _currentViewMode == FolderViewMode.sortedAZ
  ///
  /// The sorting logic MUST match _applySortedView to maintain UI/playback consistency:
  /// 1. Groups files by their folder path
  /// 2. Sorts files within each folder (numerically aware, then alphabetically)
  /// 3. Sorts folders by their top-level folder name (numerically aware, then alphabetically)
  /// 4. Rebuilds the list with sorted folders containing sorted files
  void applySortedPlaylistOrder(List<RDFileNode> videoFiles) {
    if (_deps.navigationState.currentViewMode != FolderViewMode.sortedAZ) {
      return; // Only apply sorting in sortedAZ mode
    }

    // Group files by their folder path (everything before the filename)
    final folderGroups = <String, List<RDFileNode>>{};
    for (final node in videoFiles) {
      // Extract folder path from relativePath (or use path as fallback)
      final fullPath = (node.relativePath ?? node.path) ?? '';
      final lastSlashIndex = fullPath.lastIndexOf('/');
      final folderPath = lastSlashIndex >= 0
          ? fullPath.substring(0, lastSlashIndex)
          : '';

      folderGroups.putIfAbsent(folderPath, () => []);
      folderGroups[folderPath]!.add(node);
    }

    // Sort files within each folder group (SAME LOGIC AS UI)
    for (final group in folderGroups.values) {
      group.sort((a, b) {
        final aNum = extractLeadingNumber(a.name);
        final bNum = extractLeadingNumber(b.name);

        // If both start with numbers, sort numerically
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }

        // If only one starts with a number, numbered files come first
        if (aNum != null) return -1;
        if (bNum != null) return 1;

        // Otherwise sort alphabetically (case-insensitive)
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    // Sort folder paths using SAME LOGIC AS UI (_applySortedView sorts folders)
    // Extract the top-level folder name from each path for sorting
    final provider =
        ((_deps.playlistItem()['provider'] as String?) ?? 'realdebrid')
            .toLowerCase();
    final folderPathsList = folderGroups.keys.toList();
    folderPathsList.sort((a, b) {
      // Extract the top-level folder name from the path
      // Handle empty paths (root directory) and nested paths correctly
      String aFolderName;
      String bFolderName;

      if (a.isEmpty) {
        aFolderName = 'Root';
      } else {
        final aParts = a.split('/');
        // For Torbox: skip first folder level (torrent name), use second level
        // For others: use first folder level
        if (provider == 'torbox' && aParts.length > 1) {
          aFolderName = aParts[1]; // Second folder (skip torrent name)
        } else {
          aFolderName = aParts[0]; // First folder (top-level)
        }
      }

      if (b.isEmpty) {
        bFolderName = 'Root';
      } else {
        final bParts = b.split('/');
        // For Torbox: skip first folder level (torrent name), use second level
        // For others: use first folder level
        if (provider == 'torbox' && bParts.length > 1) {
          bFolderName = bParts[1]; // Second folder (skip torrent name)
        } else {
          bFolderName = bParts[0]; // First folder (top-level)
        }
      }

      // Use _extractSeasonNumber for numerical awareness (SAME AS UI)
      final aNum = extractSeasonNumber(aFolderName);
      final bNum = extractSeasonNumber(bFolderName);

      // If both have numbers, sort numerically
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }

      // If only one has a number, numbered folders come first
      if (aNum != null) return -1;
      if (bNum != null) return 1;

      // Otherwise sort alphabetically (case-insensitive)
      return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
    });

    // Rebuild videoFiles list with sorted folders and sorted files within
    videoFiles.clear();
    for (final folderPath in folderPathsList) {
      videoFiles.addAll(folderGroups[folderPath]!);
    }
  }
}
