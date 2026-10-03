import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';

typedef PikpakPlaylistActionsDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
  PikpakCatalogState catalogState,
});

class PikpakPlaylistActions {
  PikpakPlaylistActions(this._deps);
  final PikpakPlaylistActionsDeps _deps;

  /// Handle adding a file or folder to playlist
  Future<void> handleAddToPlaylist(Map<String, dynamic> file) async {
    final kind = file['kind'] ?? '';
    final isFolder = kind == 'drive#folder';

    if (isFolder) {
      await addFolderToPlaylist(file);
    } else {
      await addSingleFileToPlaylist(file);
    }
  }

  /// Add a single video file to playlist
  Future<void> addSingleFileToPlaylist(Map<String, dynamic> file) async {
    final mimeType = file['mime_type'] ?? '';
    final isVideo = mimeType.startsWith('video/');

    if (!isVideo) {
      _deps.showSnackBar(
        'Only video files can be added to playlist',
        isError: true,
      );
      return;
    }

    final added = await PlaylistStorage.addPlaylistItemRaw({
      'provider': 'pikpak',
      'title': FileUtils.cleanPlaylistTitle(file['name'] ?? 'Video'),
      'kind': 'single',
      'pikpakFileId': file['id'],
      // Store full metadata for instant playback
      'pikpakFile': {
        'id': file['id'],
        'name': file['name'],
        'size': file['size'],
        'mime_type': file['mime_type'],
      },
      'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
    });

    _deps.showSnackBar(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  /// Add all videos in a folder to playlist (recursively scans subfolders)
  Future<void> addFolderToPlaylist(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _deps.showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!_deps.mounted()) return;
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning folder for videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files (includePaths for auxiliary folder detection)
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true,
      );

      // Close loading dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }

      if (!_deps.mounted()) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_deps.catalogState.ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }

      // Add to playlist
      if (videoFiles.length == 1) {
        // Single video file - store full metadata for instant playback
        final file = videoFiles.first;
        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(file['name'] ?? folderName),
          'kind': 'single',
          'pikpakFileId': file['id'],
          'pikpakFile': {
            'id': file['id'],
            'name': file['name'],
            'size': file['size'],
            'mime_type': file['mime_type'],
          },
          'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
        });
        _deps.showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
      } else {
        // Multiple videos - save as collection with full metadata for instant playback
        // Store both pikpakFiles (new format) and pikpakFileIds (for dedupe compatibility)
        final fileIds = videoFiles.map((f) => f['id'] as String).toList();
        final filesMetadata = videoFiles
            .map(
              (f) => {
                'id': f['id'],
                'name': f['name'],
                'size': f['size'],
                'mime_type': f['mime_type'],
              },
            )
            .toList();

        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(folderName),
          'kind': 'collection',
          'pikpakFileId': folderId, // Store the folder ID for folder structure
          'pikpakFiles':
              filesMetadata, // NEW: Full metadata for instant playback
          'pikpakFileIds':
              fileIds, // KEEP: For backward compatibility and deduplication
          'count': videoFiles.length,
        });
        _deps.showSnackBar(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
          isError: !added,
        );
      }
    } catch (e) {
      print('Error adding folder to playlist: $e');
      if (_deps.mounted()) {
        // Close loading dialog if still open
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }
}
