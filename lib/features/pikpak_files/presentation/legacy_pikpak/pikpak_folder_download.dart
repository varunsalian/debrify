import 'dart:convert';

import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

typedef PikpakFolderDownloadDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class PikpakFolderDownload {
  PikpakFolderDownload(this._deps);
  final PikpakFolderDownloadDeps _deps;

  /// Download all files in a folder with file selection dialog
  /// Works for both root folders and subfolders
  /// When downloading a subfolder, only shows that subfolder's contents (not parent structure)
  Future<void> downloadFolder(Map<String, dynamic> folder) async {
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
              'Scanning folder for files...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files WITH path tracking
      // This ensures the dialog shows folder structure starting from this folder
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true, // Enable path tracking for folder structure
      );

      // Close loading dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }

      if (!_deps.mounted()) return;

      // Filter out folders, keep only files
      final filesOnly = allFiles.where((file) {
        final kind = file['kind'] ?? '';
        return kind != 'drive#folder';
      }).toList();

      if (filesOnly.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any files',
          isError: true,
        );
        return;
      }

      // Show file selection dialog
      await showDialog(
        context: _deps.context(),
        builder: (context) => FileSelectionDialog(
          files: filesOnly,
          torrentName: folderName,
          onDownload: (selectedFiles) {
            downloadSelectedPikPakFiles(selectedFiles, folderName);
          },
        ),
      );
    } catch (e) {
      print('Error downloading folder: $e');
      if (_deps.mounted()) {
        // Close loading dialog if still open
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  /// Download selected PikPak files from the file selection dialog
  /// Handles error reporting and uses folder name for download organization
  Future<void> downloadSelectedPikPakFiles(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  ) async {
    if (selectedFiles.isEmpty) {
      _deps.showSnackBar('No files selected', isError: true);
      return;
    }

    int successCount = 0;
    int failCount = 0;

    // Show progress indicator
    if (!_deps.mounted()) return;
    showDialog(
      context: _deps.context(),
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Queuing ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      for (final file in selectedFiles) {
        try {
          final fileId = file['id'] as String?;
          // Use _fullPath if available (from path tracking), otherwise use original name
          final fileName =
              (file['_fullPath'] as String?) ?? file['name'] ?? 'download';

          if (fileId == null) {
            failCount++;
            continue;
          }

          // Get fresh file details with download URLs
          final freshFileData = await PikPakApiService.instance.getFileDetails(
            fileId,
          );
          final downloadUrl = freshFileData['web_content_link'] as String?;

          if (downloadUrl == null || downloadUrl.isEmpty) {
            failCount++;
            continue;
          }

          // Prepare metadata for download service
          final meta = jsonEncode({
            'pikpakDownload': true,
            'pikpakFileId': fileId,
            'pikpakFileName': fileName,
          });

          // Enqueue download with folder name for organization
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'pikpak_email',
            url: downloadUrl,
            fileName: fileName,
            meta: meta,
            torrentName: folderName, // Use folder name for organization
            context: _deps.mounted() ? _deps.context() : null,
          );

          successCount++;
        } catch (e) {
          print('Error queuing file for download: $e');
          failCount++;
        }
      }
    } finally {
      // Close progress dialog
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
    }

    if (!_deps.mounted()) return;

    // Show result
    if (successCount > 0 && failCount == 0) {
      _deps.showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        isError: false,
      );
    } else if (successCount > 0 && failCount > 0) {
      _deps.showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        isError: true,
      );
    } else {
      _deps.showSnackBar(
        'Failed to queue any files for download',
        isError: true,
      );
    }
  }
}
