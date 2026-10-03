import 'dart:convert';

import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxFileActionsDeps = ({
  TorboxNavigationState navigationState,
  void Function(String message, {bool isError}) showSnackBar,
  Future<void> Function(List<TorboxFile> files, String collectionName)
  playTorboxFiles,
  TorboxCatalogState catalogState,
  Future<String> Function({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  })
  requestTorboxStreamUrl,
  bool Function() mounted,
  BuildContext Function() context,
  Future<void> Function(TorboxFile file) downloadSingleFile,
});

class TorboxFileActions {
  TorboxFileActions(this._deps);
  final TorboxFileActionsDeps _deps;
  TorboxNavigationState get _nav => _deps.navigationState;

  /// Get files list from current torrent or web download
  List<TorboxFile> get currentFiles {
    return _nav.currentTorrent?.files ?? _nav.currentWebDownload?.files ?? [];
  }

  /// Play all videos in a folder
  Future<void> playFolderVideos(RDFileNode folderNode) async {
    if (_nav.currentTorrent == null && _nav.currentWebDownload == null) return;

    final files = currentFiles;
    final videoFiles = TorboxFolderTreeBuilder.collectVideoFiles(folderNode);
    if (videoFiles.isEmpty) {
      _deps.showSnackBar('No video files found in this folder');
      return;
    }

    // Convert RDFileNodes to TorboxFiles for playback
    final torboxFiles = videoFiles
        .map((node) {
          // Find corresponding TorboxFile by linkIndex
          if (node.linkIndex >= 0 && node.linkIndex < files.length) {
            return files[node.linkIndex];
          }
          return null;
        })
        .where((f) => f != null)
        .cast<TorboxFile>()
        .toList();

    if (torboxFiles.isEmpty) {
      _deps.showSnackBar('Could not load video files');
      return;
    }

    // Use existing play logic
    await _deps.playTorboxFiles(torboxFiles, folderNode.name);
  }

  /// Play a single video file
  Future<void> playVideoFile(RDFileNode fileNode) async {
    if ((_nav.currentTorrent == null && _nav.currentWebDownload == null) ||
        fileNode.isFolder) {
      return;
    }

    final files = currentFiles;
    // Find corresponding TorboxFile
    if (fileNode.linkIndex < 0 || fileNode.linkIndex >= files.length) {
      _deps.showSnackBar('File not found');
      return;
    }

    final torboxFile = files[fileNode.linkIndex];

    try {
      final key = _deps.catalogState.apiKey;
      if (key == null || key.isEmpty) {
        _deps.showSnackBar('Torbox API key not configured');
        return;
      }

      String streamUrl;
      if (_nav.currentTorrent != null) {
        streamUrl = await _deps.requestTorboxStreamUrl(
          apiKey: key,
          torrent: _nav.currentTorrent!,
          file: torboxFile,
        );
      } else {
        streamUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: _nav.currentWebDownload!.id,
          fileId: torboxFile.id,
        );
      }

      if (!_deps.mounted()) return;

      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: streamUrl,
          title: fileNode.name,
          subtitle: Formatters.formatFileSize(fileNode.bytes ?? 0),
        ),
      );
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Failed to play file: ${formatTorboxError(e)}');
    }
  }

  /// Download a file or folder
  Future<void> downloadFileOrFolder(RDFileNode node) async {
    if (_nav.currentTorrent == null && _nav.currentWebDownload == null) {
      print('❌ Download: No current torrent or web download');
      return;
    }

    final files = currentFiles;
    print(
      '📥 Download requested: isFolder=${node.isFolder}, name=${node.name}',
    );
    print(
      '   Node details: fileId=${node.fileId}, linkIndex=${node.linkIndex}, bytes=${node.bytes}',
    );
    print('   Current files count: ${files.length}');

    if (node.isFolder) {
      // Show file selection dialog for folder
      final allFiles = TorboxFolderTreeBuilder.collectAllFiles(node);
      print('   Collected ${allFiles.length} files from folder');

      final torboxFiles = allFiles
          .map((n) {
            print(
              '   Mapping file: name=${n.name}, linkIndex=${n.linkIndex}, fileId=${n.fileId}',
            );
            if (n.linkIndex >= 0 && n.linkIndex < files.length) {
              final torboxFile = files[n.linkIndex];
              print(
                '   ✅ Mapped to TorboxFile: id=${torboxFile.id}, name=${torboxFile.name}',
              );
              return torboxFile;
            }
            print(
              '   ❌ linkIndex out of bounds: ${n.linkIndex} >= ${files.length}',
            );
            return null;
          })
          .where((f) => f != null)
          .cast<TorboxFile>()
          .toList();

      print('   Mapped to ${torboxFiles.length} TorboxFiles');

      if (torboxFiles.isEmpty) {
        _deps.showSnackBar('No files found in folder');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (final file in torboxFiles) {
        // Use shortName for file name, fullName for path structure
        final fullPath = file.name; // Full path with folders
        final relativePath = fullPath.contains('/')
            ? fullPath.substring(fullPath.indexOf('/') + 1)
            : fullPath;

        formattedFiles.add({
          '_fullPath': relativePath,
          'name': file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name),
          'size': file.size.toString(),
          '_torboxFile': file, // Store original TorboxFile for download
        });
      }

      // Show file selection dialog
      if (!_deps.mounted()) return;
      await showDialog(
        context: _deps.context(),
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: node.name,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              downloadSelectedTorboxFiles(selectedFiles, node.name);
            },
          );
        },
      );
    } else {
      // Download single file
      print('   Attempting single file download');
      print(
        '   Bounds check: ${node.linkIndex} >= 0 && ${node.linkIndex} < ${files.length}',
      );

      if (node.linkIndex >= 0 && node.linkIndex < files.length) {
        final torboxFile = files[node.linkIndex];
        print('   ✅ Found TorboxFile at index ${node.linkIndex}:');
        print('      TorboxFile.id=${torboxFile.id}, name=${torboxFile.name}');
        print('      Node.fileId=${node.fileId}');
        print('      IDs match: ${torboxFile.id == node.fileId}');
        await _deps.downloadSingleFile(torboxFile);
      } else {
        print(
          '   ❌ linkIndex out of bounds! linkIndex=${node.linkIndex}, filesLength=${files.length}',
        );
        _deps.showSnackBar('Download failed: File index out of bounds');
      }
    }
  }

  /// Download selected Torbox files from file selection dialog
  Future<void> downloadSelectedTorboxFiles(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  ) async {
    final key = _deps.catalogState.apiKey;
    if (key == null ||
        key.isEmpty ||
        (_nav.currentTorrent == null && _nav.currentWebDownload == null)) {
      print('❌ _downloadSelectedTorboxFiles: Missing requirements');
      return;
    }

    // CRITICAL: Capture reference before async operations
    final torrent = _nav.currentTorrent;
    final webDownload = _nav.currentWebDownload;
    final isWebDownload = webDownload != null;

    if (!_deps.mounted()) return;

    print(
      '📦 _downloadSelectedTorboxFiles called: folderName=$folderName, selectedCount=${selectedFiles.length}',
    );

    try {
      // Show progress dialog
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

      int successCount = 0;
      int failCount = 0;

      // CRITICAL: Following the SAME pattern as Real-Debrid
      // We DON'T request download URLs upfront - we queue with metadata for lazy fetching
      // The DownloadService will request the URL when it's ready to download (lazy loading)
      for (final fileData in selectedFiles) {
        try {
          // Extract TorboxFile from the formatted data
          final file = fileData['_torboxFile'] as TorboxFile;
          final fileName =
              (fileData['_fullPath'] as String?) ??
              (fileData['name'] as String? ?? file.shortName);

          print('   Processing file: ${file.name}');

          // Pass metadata for lazy URL fetching (no API call - instant!)
          // The download service will request the URL when ready
          final Map<String, dynamic> metaMap;
          if (isWebDownload) {
            metaMap = {
              'torboxWebDownloadId': webDownload.id,
              'torboxFileId': file.id,
              'torboxWebDownload': true,
            };
          } else {
            metaMap = {
              'torboxTorrentId': torrent!.id,
              'torboxFileId': file.id,
              'torboxDownload': true,
            };
          }
          final meta = jsonEncode(metaMap);

          // Queue download instantly (download service will fetch URL when ready)
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'torbox_api_key',
            url: '', // Empty URL - will be fetched by download service
            fileName: fileName,
            meta: meta,
            torrentName: folderName,
            context: _deps.mounted() ? _deps.context() : null,
          );

          print('     ✅ Enqueued successfully');
          successCount++;
        } catch (e) {
          print('     ❌ Error: $e');
          failCount++;
        }
      }

      // Close progress dialog
      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      // Show result
      if (successCount > 0 && failCount == 0) {
        _deps.showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
          isError: false,
        );
      } else if (successCount > 0 && failCount > 0) {
        _deps.showSnackBar(
          'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        );
      } else {
        _deps.showSnackBar('Failed to queue any files for download');
      }
    } catch (e) {
      // Close any open dialogs
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to queue downloads: $e');
    }
  }
}
