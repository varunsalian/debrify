import 'dart:convert';

import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxFileDownloadsDeps = ({
  TorboxCatalogState catalogState,
  TorboxNavigationState navigationState,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String message, {bool isError}) showSnackBar,
});

class TorboxFileDownloads {
  TorboxFileDownloads(this._deps);
  final TorboxFileDownloadsDeps _deps;

  /// Helper: Download a single file
  Future<void> downloadSingleFile(TorboxFile file) async {
    final key = _deps.catalogState.apiKey;
    if (key == null ||
        key.isEmpty ||
        (_deps.navigationState.currentTorrent == null &&
            _deps.navigationState.currentWebDownload == null)) {
      print('❌ _downloadSingleFile: Missing requirements');
      return;
    }

    final isWebDownload = _deps.navigationState.currentWebDownload != null;
    print('🔽 _downloadSingleFile called:');
    print(
      '   File: id=${file.id}, name=${file.name}, shortName=${file.shortName}',
    );
    print('   isWebDownload: $isWebDownload');
    print('   API Key: ${key.substring(0, 8)}...');

    try {
      final fileName = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);

      print('   Using fileName: $fileName');

      // Pass metadata for lazy URL fetching (download service will fetch URL when ready)
      final Map<String, dynamic> metaMap;
      if (isWebDownload) {
        metaMap = {
          'torboxWebDownloadId': _deps.navigationState.currentWebDownload!.id,
          'torboxFileId': file.id,
          'torboxWebDownload': true,
        };
      } else {
        metaMap = {
          'torboxTorrentId': _deps.navigationState.currentTorrent!.id,
          'torboxFileId': file.id,
          'torboxDownload': true,
        };
      }
      final meta = jsonEncode(metaMap);

      print(
        '   📥 Enqueueing download with DownloadService (lazy URL fetching)...',
      );
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'torbox_api_key',
        url: '', // Empty URL - will be fetched by download service
        fileName: fileName,
        meta: meta,
        context: _deps.mounted() ? _deps.context() : null,
      );

      print('   ✅ Download queued successfully!');
      _deps.showSnackBar('Download queued: $fileName', isError: false);
    } catch (e, stackTrace) {
      print('   ❌ Error in _downloadSingleFile:');
      print('   Error: $e');
      print('   StackTrace: $stackTrace');
      _deps.showSnackBar('Failed to queue download: ${formatTorboxError(e)}');
    }
  }

  /// Helper: Download multiple files
  Future<void> downloadMultipleFiles(
    List<TorboxFile> files,
    String folderName,
  ) async {
    final key = _deps.catalogState.apiKey;
    if (key == null ||
        key.isEmpty ||
        (_deps.navigationState.currentTorrent == null &&
            _deps.navigationState.currentWebDownload == null)) {
      print('❌ _downloadMultipleFiles: Missing requirements');
      return;
    }

    print(
      '📦 _downloadMultipleFiles called: folderName=$folderName, fileCount=${files.length}',
    );

    if (files.isEmpty) {
      print('   ❌ No files to download (empty list)');
      _deps.showSnackBar('No files to download');
      return;
    }

    // Show confirmation
    final confirmed = await showDialog<bool>(
      context: _deps.context(),
      builder: (context) => AlertDialog(
        title: const Text('Download Files'),
        content: Text(
          'Download ${files.length} file${files.length == 1 ? '' : 's'} from "$folderName"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (confirmed != true || !_deps.mounted()) {
      print('   User cancelled or context not mounted');
      return;
    }

    print('   User confirmed download, processing ${files.length} files...');

    final isWebDownload = _deps.navigationState.currentWebDownload != null;
    int successCount = 0;
    int failCount = 0;

    // CRITICAL: Following the SAME pattern as Real-Debrid
    // We DON'T request download URLs upfront - we queue with metadata for lazy fetching
    // The DownloadService will request the URL when it's ready to download (lazy loading)
    for (final file in files) {
      print(
        '   Processing file ${successCount + failCount + 1}/${files.length}: ${file.name}',
      );
      try {
        final fileName = file.shortName.isNotEmpty
            ? file.shortName
            : FileUtils.getFileName(file.name);

        // Pass metadata for lazy URL fetching (no API call - instant!)
        // The download service will request the URL when ready
        final Map<String, dynamic> metaMap;
        if (isWebDownload) {
          metaMap = {
            'torboxWebDownloadId': _deps.navigationState.currentWebDownload!.id,
            'torboxFileId': file.id,
            'torboxWebDownload': true,
          };
        } else {
          metaMap = {
            'torboxTorrentId': _deps.navigationState.currentTorrent!.id,
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
  }
}
