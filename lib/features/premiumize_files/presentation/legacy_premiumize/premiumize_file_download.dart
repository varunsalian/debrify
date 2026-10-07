import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/download_service.dart';
import 'package:flutter/material.dart';

typedef PremiumizeFileDownloadDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
});

class PremiumizeFileDownload {
  PremiumizeFileDownload(this._deps);
  final PremiumizeFileDownloadDeps _deps;

  // ── Download ───────────────────────────────────────────────────────────────

  Future<void> downloadFile(PremiumizeFolderItem file) async {
    final url = file.link;
    if (url == null || url.isEmpty) {
      _deps.showSnackBar('No download URL for this file', isError: true);
      return;
    }
    try {
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'premiumize_api_key',
        url: url,
        fileName: file.name,
        context: _deps.mounted() ? _deps.context() : null,
      );
      _deps.showSnackBar('Download queued: ${file.name}', isError: false);
    } catch (e) {
      _deps.showSnackBar('Failed to download: $e', isError: true);
    }
  }
}
