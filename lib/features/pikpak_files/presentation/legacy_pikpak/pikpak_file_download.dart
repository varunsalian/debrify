import 'dart:convert';

import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:flutter/material.dart';

typedef PikpakFileDownloadDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class PikpakFileDownload {
  PikpakFileDownload(this._deps);
  final PikpakFileDownloadDeps _deps;

  /// Download a single file
  Future<void> downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String?;
    final fileName = file['name'] ?? 'download';

    if (fileId == null) {
      _deps.showSnackBar('Invalid file ID', isError: true);
      return;
    }

    // Check if it's a folder
    final kind = file['kind'];
    if (kind == 'drive#folder') {
      _deps.showSnackBar(
        'Cannot download folders directly. Use Download button on folder.',
        isError: true,
      );
      return;
    }

    try {
      // Show loading indicator
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
                'Preparing download...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get fresh file details with download URLs
      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } catch (e) {
        // Close loading indicator
        if (_deps.mounted()) {
          Navigator.of(_deps.context(), rootNavigator: true).pop();
        }
        _deps.showSnackBar('Failed to get download URL: $e', isError: true);
        return;
      }

      // Extract download URL (use web_content_link for all files)
      final downloadUrl = freshFileData['web_content_link'] as String?;

      // Close loading indicator
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        _deps.showSnackBar(
          'No download URL available for this file',
          isError: true,
        );
        return;
      }

      // Prepare metadata for download service
      final meta = jsonEncode({
        'pikpakDownload': true,
        'pikpakFileId': fileId,
        'pikpakFileName': fileName,
      });

      // Enqueue download
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'pikpak_email',
        url: downloadUrl,
        fileName: fileName,
        meta: meta,
        context: _deps.mounted() ? _deps.context() : null,
      );

      _deps.showSnackBar('Download queued: $fileName', isError: false);
    } catch (e) {
      print('Error downloading file: $e');
      // Close loading indicator if still open
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to download: $e', isError: true);
    }
  }
}
