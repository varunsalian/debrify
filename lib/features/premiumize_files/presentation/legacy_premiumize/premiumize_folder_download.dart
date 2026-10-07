import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/widgets/file_selection_dialog.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeFolderDownloadDeps = ({
  PremiumizeCatalogState catalogState,
  void Function(String message) showLoadingDialog,
  void Function() dismissDialog,
  bool Function() mounted,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  BuildContext Function() context,
});

class PremiumizeFolderDownload {
  PremiumizeFolderDownload(this._deps);
  final PremiumizeFolderDownloadDeps _deps;

  Future<void> downloadFolder(PremiumizeFolderItem folder) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _deps.showLoadingDialog('Scanning folder for files...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
      _deps.dismissDialog();
      if (!_deps.mounted()) return;

      final files = all.where((f) => !f.isFolder).toList();
      if (files.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any files',
          isError: true,
        );
        return;
      }

      final dialogFiles = <Map<String, dynamic>>[];
      for (int i = 0; i < files.length; i++) {
        dialogFiles.add({
          'name': files[i].relativePath ?? files[i].name,
          '_fullPath': files[i].relativePath ?? files[i].name,
          'size': files[i].size.toString(),
          '_premiumizeIndex': i,
        });
      }

      await showDialog(
        context: _deps.context(),
        builder: (context) => FileSelectionDialog(
          files: dialogFiles,
          torrentName: folder.name,
          onDownload: (selected) =>
              downloadSelectedFiles(selected, files, folder.name),
        ),
      );
    } catch (e) {
      _deps.dismissDialog();
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  Future<void> downloadSelectedFiles(
    List<Map<String, dynamic>> selected,
    List<PremiumizeFolderItem> allFiles,
    String folderName,
  ) async {
    if (selected.isEmpty) return;
    int success = 0, fail = 0;
    for (final f in selected) {
      try {
        final idx = f['_premiumizeIndex'] as int? ?? -1;
        if (idx < 0 || idx >= allFiles.length) {
          fail++;
          continue;
        }
        final target = allFiles[idx];
        final url = target.link;
        if (url == null || url.isEmpty) {
          fail++;
          continue;
        }
        await DownloadService.instance.enqueueDownload(
          credentialKey: 'premiumize_api_key',
          url: url,
          fileName: target.name,
          torrentName: folderName,
          context: _deps.mounted() ? _deps.context() : null,
        );
        success++;
      } catch (_) {
        fail++;
      }
    }
    if (!_deps.mounted()) return;
    if (success > 0 && fail == 0) {
      _deps.showSnackBar(
        'Queued $success file${success == 1 ? '' : 's'}',
        isError: false,
      );
    } else if (success > 0) {
      _deps.showSnackBar('Queued $success, $fail failed', isError: true);
    } else {
      _deps.showSnackBar('Failed to queue any files', isError: true);
    }
  }
}
