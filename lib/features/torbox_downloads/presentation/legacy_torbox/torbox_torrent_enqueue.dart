import 'dart:convert';

import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxTorrentEnqueueDeps = ({
  TorboxCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxTorrentEnqueue {
  TorboxTorrentEnqueue(this._deps);
  final TorboxTorrentEnqueueDeps _deps;

  Future<bool> enqueueTorboxDownloads({
    required TorboxTorrent torrent,
    required List<TorboxFileEntry> entriesToDownload,
    required BuildContext sheetContext,
  }) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text(
              'Torbox API key is required. Please add it in Settings.',
            ),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return true;
    }

    if (entriesToDownload.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text('No files selected for download.'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
      return true;
    }

    Navigator.of(sheetContext).pop();

    if (!_deps.mounted()) {
      return true;
    }

    final count = entriesToDownload.length;
    debugPrint(
      'TorboxDownloadsScreen: Starting download for torrent ${torrent.id} ($count file(s)).',
    );

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(_deps.context());
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Preparing $count file${count == 1 ? '' : 's'} for download...',
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    int successCount = 0;
    int failureCount = 0;
    String? lastError;

    try {
      for (final entry in entriesToDownload) {
        try {
          final file = entry.file;
          final fileName = file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name);

          debugPrint(
            'TorboxDownloadsScreen: Requesting download link for file ${file.id} in torrent ${torrent.id}',
          );

          // Request download link
          final downloadUrl = await TorboxService.requestFileDownloadLink(
            apiKey: key,
            torrentId: torrent.id,
            fileId: file.id,
          );

          if (downloadUrl.isEmpty) {
            debugPrint(
              'TorboxDownloadsScreen: Got empty download URL for file ${file.id}',
            );
            failureCount++;
            lastError = 'Empty download URL returned';
            continue;
          }

          debugPrint(
            'TorboxDownloadsScreen: Got download URL for file ${file.id}, enqueueing...',
          );

          // Create meta JSON with Torbox-specific fields
          final meta = jsonEncode({
            'torboxTorrentId': torrent.id,
            'torboxFileId': file.id,
            'torboxDownload': true,
          });

          // Enqueue download
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'torbox_api_key',
            url: downloadUrl,
            fileName: fileName,
            meta: meta,
            torrentName: torrent.name,
          );

          successCount++;
          debugPrint(
            'TorboxDownloadsScreen: Successfully enqueued file ${file.id} ($fileName)',
          );
        } catch (e, stackTrace) {
          debugPrint(
            'TorboxDownloadsScreen: Failed to enqueue file ${entry.file.id}: $e',
          );
          debugPrint('Stack trace: $stackTrace');
          failureCount++;
          lastError = e.toString();
        }
      }

      if (!_deps.mounted()) return true;

      // Show result feedback
      if (successCount > 0 && failureCount == 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$successCount file${successCount == 1 ? '' : 's'} queued for download',
            ),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      } else if (successCount > 0 && failureCount > 0) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '$successCount file${successCount == 1 ? '' : 's'} queued, $failureCount failed',
            ),
            backgroundColor: const Color(0xFFF59E0B),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Failed to queue downloads${lastError != null ? ': ${lastError.replaceFirst('Exception: ', '')}' : ''}',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('TorboxDownloadsScreen: Error during batch download: $e');
      debugPrint('Stack trace: $stackTrace');
      if (_deps.mounted()) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }

    return true;
  }
}
