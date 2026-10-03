import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxTorrentDownloadActionDeps = ({
  TorboxCatalogState catalogState,
  // TEMP(torbox): showSnackBar -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart at step 4.
  void Function(String message, {bool isError}) showSnackBar,
  TorboxNavigationState navigationState,
  bool Function() mounted,
  BuildContext Function() context,
  // TEMP(torbox): downloadSelectedTorboxFiles -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_file_actions.dart at step 4.
  Future<void> Function(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  )
  downloadSelectedTorboxFiles,
});

class TorboxTorrentDownloadAction {
  TorboxTorrentDownloadAction(this._deps);
  final TorboxTorrentDownloadActionDeps _deps;

  /// Download files from a torrent with file selection dialog
  Future<void> downloadAllTorrentFiles(TorboxTorrent torrent) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    print('📦 Showing file selection for torrent: ${torrent.name}');
    print('   File count: ${torrent.files.length}');

    if (torrent.files.isEmpty) {
      _deps.showSnackBar('No files found in torrent');
      return;
    }

    // Temporarily set _currentTorrent for the download process
    final previousTorrent = _deps.navigationState.currentTorrent;
    _deps.navigationState.currentTorrent = torrent;

    // Format files for FileSelectionDialog
    final formattedFiles = <Map<String, dynamic>>[];
    for (final file in torrent.files) {
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
    if (!_deps.mounted()) {
      _deps.navigationState.currentTorrent = previousTorrent;
      return;
    }

    await showDialog(
      context: _deps.context(),
      builder: (BuildContext context) {
        return FileSelectionDialog(
          files: formattedFiles,
          torrentName: torrent.name,
          onDownload: (selectedFiles) {
            if (selectedFiles.isEmpty) return;
            _deps.downloadSelectedTorboxFiles(selectedFiles, torrent.name);
          },
        );
      },
    );

    // Restore previous torrent
    _deps.navigationState.currentTorrent = previousTorrent;
  }
}
