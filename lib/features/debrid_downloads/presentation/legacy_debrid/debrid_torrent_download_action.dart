import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';

typedef DebridTorrentDownloadActionDeps = ({
  DebridCatalogState catalogState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(String message) showError,
  Future<void> Function({
    required List<Map<String, dynamic>> selectedFiles,
    required List<String> links,
    required String folderName,
  })
  downloadSelectedRealDebridFiles,
});

class DebridTorrentDownloadAction {
  DebridTorrentDownloadAction(this._deps);
  final DebridTorrentDownloadActionDeps _deps;
  bool get mounted => _deps.mounted();

  Future<void> handleDownloadTorrent(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

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
                'Loading torrent files...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get torrent info to access files and links
      final torrentInfo = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        torrent.id,
      );
      final allFiles =
          (torrentInfo['files'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final links = (torrentInfo['links'] as List).cast<String>();

      // Filter to only selected files (files that were selected when adding to RD)
      // Only selected files have corresponding links and can be downloaded
      final files = allFiles.where((file) => file['selected'] == 1).toList();

      if (mounted) Navigator.of(_deps.context()).pop();

      if (files.isEmpty || links.isEmpty) {
        _deps.showError('No files available for download');
        return;
      }

      // Format files for FileSelectionDialog
      final formattedFiles = <Map<String, dynamic>>[];
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        final path = (file['path'] as String?) ?? '';
        final bytes = file['bytes'] as int? ?? 0;

        formattedFiles.add({
          '_fullPath': path, // Use path field for full path
          'name': path,
          'size': bytes.toString(),
          '_linkIndex': i, // Store the link index for later use
        });
      }

      // Show file selection dialog
      if (!mounted) return;
      await showDialog(
        context: _deps.context(),
        builder: (BuildContext context) {
          return FileSelectionDialog(
            files: formattedFiles,
            torrentName: torrent.filename,
            onDownload: (selectedFiles) {
              if (selectedFiles.isEmpty) return;
              _deps.downloadSelectedRealDebridFiles(
                selectedFiles: selectedFiles,
                links: links,
                folderName: torrent.filename,
              );
            },
          );
        },
      );
    } catch (e) {
      if (mounted) Navigator.of(_deps.context(), rootNavigator: true).pop();
      _deps.showError('Failed to load torrent: $e');
    }
  }
}
