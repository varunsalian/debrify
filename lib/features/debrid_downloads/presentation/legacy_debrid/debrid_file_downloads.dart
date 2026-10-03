import 'dart:convert';

import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridFileDownloadsDeps = ({
  DebridCatalogState catalogState,
  DebridNavigationState navigationState,
  void Function(String message) showError,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(String message) showSuccess,
});

class DebridFileDownloads {
  DebridFileDownloads(this._deps);
  final DebridFileDownloadsDeps _deps;

  /// Download a single file
  Future<void> downloadFile(RDFileNode file) async {
    if (_deps.catalogState.apiKey == null ||
        _deps.navigationState.currentTorrentId == null) {
      _deps.showError('No API key or torrent ID available');
      return;
    }

    try {
      // Show loading
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Preparing download...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get the torrent info to access the restricted link
      final torrentInfo = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        _deps.navigationState.currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      // Validate linkIndex
      if (file.linkIndex >= links.length) {
        if (_deps.mounted()) Navigator.of(_deps.context()).pop();
        _deps.showError('Invalid file link index');
        return;
      }

      // Get restricted link (no unrestriction - download service will do it lazily)
      final restrictedLink = links[file.linkIndex];

      // Use file name from node (download service will get RD filename when unrestricting)
      final fileName = file.name;

      // Close loading dialog
      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      // Pass metadata for lazy unrestriction
      final meta = jsonEncode({
        'restrictedLink': restrictedLink,
        'torrentHash': _deps.navigationState.currentTorrent?.hash,
        'fileIndex': file.linkIndex,
      });

      // Pass restricted link as URL (download service will replace it)
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'real_debrid_api_key',
        url: restrictedLink,
        fileName: fileName,
        meta: meta,
        torrentName: _deps.navigationState.currentTorrent?.filename,
        context: _deps.mounted() ? _deps.context() : null,
      );

      _deps.showSuccess('Download queued: $fileName');
    } catch (e) {
      // Close loading dialog if still open
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showError('Failed to download: $e');
    }
  }

  /// Download files from a folder with file selection dialog
  Future<void> downloadFolder(RDFileNode folder) async {
    if (_deps.catalogState.apiKey == null ||
        _deps.navigationState.currentTorrentId == null) {
      _deps.showError('No API key or torrent ID available');
      return;
    }

    try {
      // Show loading
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Scanning folder...', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );

      // Collect all files recursively
      final allFiles = RDFolderTreeBuilder.collectAllFiles(folder);

      // Get torrent info to access links
      final torrentInfo = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        _deps.navigationState.currentTorrentId!,
      );
      final links = (torrentInfo['links'] as List).cast<String>();

      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      if (allFiles.isEmpty) {
        _deps.showError('No files found in folder');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (final file in allFiles) {
        // Build relative path from folder name
        final fullPath = file.path ?? file.name;
        // Remove the parent folder name from the path if present
        final relativePath = fullPath.contains('/')
            ? fullPath.substring(fullPath.indexOf('/') + 1)
            : fullPath;

        formattedFiles.add({
          '_fullPath': relativePath,
          'name': file.name,
          'size': (file.bytes ?? 0).toString(),
          '_linkIndex': file.linkIndex,
          '_rdFileNode': file, // Store original node for download
        });
      }

      // Show file selection dialog
      if (!_deps.mounted()) return;
      await showDialog(
        context: _deps.context(),
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: folder.name,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              downloadSelectedRealDebridFiles(
                selectedFiles: selectedFiles,
                links: links,
                folderName: folder.name,
              );
            },
          );
        },
      );
    } catch (e) {
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showError('Failed to load folder: $e');
    }
  }

  /// Download selected Real-Debrid files from file selection dialog
  Future<void> downloadSelectedRealDebridFiles({
    required List<Map<String, dynamic>> selectedFiles,
    required List<String> links,
    required String folderName,
  }) async {
    if (!_deps.mounted()) return;

    try {
      // Show progress
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => Center(
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

      // Queue downloads for each selected file
      int successCount = 0;
      int failCount = 0;

      for (final fileData in selectedFiles) {
        try {
          // Extract link index and file name
          final linkIndex = fileData['_linkIndex'] as int;
          final fileName =
              (fileData['_fullPath'] as String?) ??
              (fileData['name'] as String? ?? 'download');

          // Validate linkIndex
          if (linkIndex >= links.length) {
            failCount++;
            continue;
          }

          // Get restricted link (no API call - instant!)
          final restrictedLink = links[linkIndex];

          // Pass metadata for lazy unrestriction
          final meta = jsonEncode({
            'restrictedLink': restrictedLink,
            'torrentHash': _deps.navigationState.currentTorrent?.hash,
            'fileIndex': linkIndex,
          });

          // Queue download instantly (download service will unrestrict when ready)
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'real_debrid_api_key',
            url:
                restrictedLink, // Pass restricted link (will be replaced by download service)
            fileName: fileName,
            meta: meta,
            torrentName:
                _deps.navigationState.currentTorrent?.filename ?? folderName,
            context: _deps.mounted() ? _deps.context() : null,
          );

          successCount++;
        } catch (e) {
          // Silently handle individual file failures during batch operations
          failCount++;
        }
      }

      // Close progress dialog
      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      // Show result
      if (successCount > 0 && failCount == 0) {
        _deps.showSuccess(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        );
      } else if (successCount > 0 && failCount > 0) {
        _deps.showError(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _deps.showError('Failed to queue any files for download');
      }
    } catch (e) {
      // Close any open dialogs
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showError('Failed to queue downloads: $e');
    }
  }
}
