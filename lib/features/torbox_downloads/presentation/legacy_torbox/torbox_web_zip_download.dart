import 'dart:convert';

import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxWebZipDownloadDeps = ({
  TorboxCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxWebZipDownload {
  TorboxWebZipDownload(this._deps);
  final TorboxWebZipDownloadDeps _deps;

  /// Enqueue a ZIP download for a web download
  Future<void> enqueueWebDownloadZipDownload({
    required TorboxWebDownload webDownload,
    required BuildContext sheetContext,
  }) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
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
      'TorboxDownloadsScreen: Starting ZIP download for web download ${webDownload.id}',
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
      final zipUrl = TorboxService.createWebDownloadZipPermalink(
        key,
        webDownload.id,
      );

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
        'torboxWebDownloadId': webDownload.id,
        'torboxWebDownload': true,
        'torboxZip': true,
      });

      // Enqueue ZIP download
      final zipFileName = '${webDownload.name}.zip';
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'torbox_api_key',
        url: zipUrl,
        fileName: zipFileName,
        meta: meta,
        torrentName: webDownload.name,
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
