import 'dart:convert';

import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxTorrentZipDownloadDeps = ({
  TorboxCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxTorrentZipDownload {
  TorboxTorrentZipDownload(this._deps);
  final TorboxTorrentZipDownloadDeps _deps;

  Future<void> enqueueTorboxZipDownload({
    required TorboxTorrent torrent,
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
      return;
    }

    Navigator.of(sheetContext).pop();

    if (!_deps.mounted()) {
      return;
    }

    debugPrint(
      'TorboxDownloadsScreen: Starting ZIP download for torrent ${torrent.id}',
    );

    // Show loading indicator
    final messenger = ScaffoldMessenger.of(_deps.context());
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Preparing ZIP download...'),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Generate ZIP permalink
      final zipUrl = TorboxService.createZipPermalink(key, torrent.id);

      if (zipUrl.isEmpty) {
        debugPrint('TorboxDownloadsScreen: Failed to generate ZIP permalink');
        if (_deps.mounted()) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to generate ZIP download link'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
        return;
      }

      debugPrint('TorboxDownloadsScreen: Generated ZIP permalink: $zipUrl');

      // Create meta JSON with Torbox-specific fields for ZIP
      final meta = jsonEncode({
        'torboxTorrentId': torrent.id,
        'torboxDownload': true,
        'torboxZip': true,
      });

      // Enqueue ZIP download
      final zipFileName = '${torrent.name}.zip';
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'torbox_api_key',
        url: zipUrl,
        fileName: zipFileName,
        meta: meta,
        torrentName: torrent.name,
      );

      debugPrint('TorboxDownloadsScreen: Successfully enqueued ZIP download');

      if (_deps.mounted()) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('ZIP download queued successfully'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('TorboxDownloadsScreen: Error during ZIP download: $e');
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
  }
}
