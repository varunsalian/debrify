import 'dart:convert';

import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxWebFileDownloadsDeps = ({
  TorboxCatalogState catalogState,
  void Function(String message, {bool isError}) showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxWebFileDownloads {
  TorboxWebFileDownloads(this._deps);
  final TorboxWebFileDownloadsDeps _deps;

  Future<void> downloadWebDownloadFiles(TorboxWebDownload webDownload) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    if (webDownload.files.isEmpty) {
      _deps.showSnackBar('No files found in this download');
      return;
    }

    // Format files for FileSelectionDialog
    final formattedFiles = <Map<String, dynamic>>[];
    for (final file in webDownload.files) {
      formattedFiles.add({
        '_fullPath': file.name,
        'name': file.shortName.isNotEmpty
            ? file.shortName
            : FileUtils.getFileName(file.name),
        'size': file.size.toString(),
        '_torboxFile': file,
        '_webDownloadId': webDownload.id,
      });
    }

    if (!_deps.mounted()) return;

    await showDialog(
      context: _deps.context(),
      builder: (BuildContext context) {
        return FileSelectionDialog(
          files: formattedFiles,
          torrentName: webDownload.name,
          onDownload: (selectedFiles) {
            if (selectedFiles.isEmpty) return;
            downloadSelectedWebDownloadFiles(selectedFiles, webDownload);
          },
        );
      },
    );
  }

  Future<void> downloadSelectedWebDownloadFiles(
    List<Map<String, dynamic>> selectedFiles,
    TorboxWebDownload webDownload,
  ) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) return;

    if (!_deps.mounted()) return;

    try {
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

      for (final fileData in selectedFiles) {
        try {
          final file = fileData['_torboxFile'] as TorboxFile;
          final fileName =
              (fileData['_fullPath'] as String?) ??
              (fileData['name'] as String? ?? file.shortName);

          final meta = jsonEncode({
            'torboxWebDownloadId': webDownload.id,
            'torboxFileId': file.id,
            'torboxWebDownload': true,
          });

          await DownloadService.instance.enqueueDownload(
            credentialKey: 'torbox_api_key',
            url: '',
            fileName: fileName,
            meta: meta,
            torrentName: webDownload.name,
            context: _deps.mounted() ? _deps.context() : null,
          );

          successCount++;
        } catch (e) {
          failCount++;
        }
      }

      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

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
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to queue downloads: $e');
    }
  }
}
