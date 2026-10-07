import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizeSourceBindingDeps = ({
  PremiumizeCatalogState catalogState,
  void Function(String message) showLoadingDialog,
  void Function() dismissDialog,
  bool Function() mounted,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  Future<void> Function(SeriesSource)? Function() onSourceSelected,
  BuildContext Function() context,
});

class PremiumizeSourceBinding {
  PremiumizeSourceBinding(this._deps);
  final PremiumizeSourceBindingDeps _deps;

  // ── Playback ───────────────────────────────────────────────────────────────

  Future<void> selectBoundSource(PremiumizeFolderItem item) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _deps.showLoadingDialog(
      item.isFolder ? 'Checking folder for videos...' : 'Checking file...',
    );
    var checkingDialogOpen = true;
    void closeCheckingDialog() {
      if (!checkingDialogOpen) return;
      checkingDialogOpen = false;
      _deps.dismissDialog();
    }

    try {
      if (item.isFolder) {
        final files = await PremiumizeService.listFolderRecursive(
          apiKey,
          item.id,
        );
        if (!_deps.mounted()) return;
        final videos = files.where((f) => f.isVideo).toList();
        if (videos.isEmpty) {
          closeCheckingDialog();
          _deps.showSnackBar(
            'This folder has no playable videos',
            isError: true,
          );
          return;
        }
        final first = videos.first;
        final firstReady =
            first.playableUrl?.isNotEmpty == true ||
            await PremiumizeService.resolveItemById(apiKey, first.id) != null;
        if (!_deps.mounted()) return;
        if (!firstReady) {
          closeCheckingDialog();
          _deps.showSnackBar(
            'This folder has no ready video streams',
            isError: true,
          );
          return;
        }
      } else {
        if (!item.isVideo) {
          closeCheckingDialog();
          _deps.showSnackBar('Only video files can be bound', isError: true);
          return;
        }
        final resolved = await PremiumizeService.resolveItemById(
          apiKey,
          item.id,
        );
        if (resolved == null || resolved.link.isEmpty) {
          closeCheckingDialog();
          _deps.showSnackBar('This file is not ready to stream', isError: true);
          return;
        }
      }

      closeCheckingDialog();
      await _deps.onSourceSelected()?.call(
        SeriesSource(
          torrentHash: '',
          torrentName: item.name,
          debridService: 'premiumize',
          debridTorrentId: item.id,
          cloudSourceKind: item.isFolder
              ? SeriesSource.cloudKindFolder
              : SeriesSource.cloudKindFile,
          boundAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (!_deps.mounted()) return;
      Navigator.of(_deps.context()).pop();
    } catch (e) {
      closeCheckingDialog();
      if (_deps.mounted()) {
        _deps.showSnackBar(
          'Could not bind this Premiumize source: $e',
          isError: true,
        );
      }
    }
  }
}
