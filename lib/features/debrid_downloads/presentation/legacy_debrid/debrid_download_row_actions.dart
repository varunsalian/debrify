import 'dart:convert';

import 'package:debrify/models/debrid_download.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/services/download_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';

typedef DebridDownloadRowActionsDeps = ({
  DebridCatalogState catalogState,
  void Function(String text) copyToClipboard,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String message) showError,
});

// Download action methods
class DebridDownloadRowActions {
  DebridDownloadRowActions(this._deps);
  final DebridDownloadRowActionsDeps _deps;

  Future<void> handleDownloadAction(DebridDownload download) async {
    if (_deps.catalogState.apiKey == null) return;

    // Copy download link to clipboard
    _deps.copyToClipboard(download.download);
  }

  Future<void> handlePlayDownload(DebridDownload download) async {
    if (_deps.catalogState.apiKey == null) return;

    // Video by MIME **or** by name: the provider's MIME is often generic
    // (application/octet-stream) or absent for the less common containers, and
    // refusing on that alone left files the player handles perfectly with
    // "not a video" and no way to watch them.
    if (FileUtils.isVideoMimeType(download.mimeType) ||
        FileUtils.isVideoFile(download.filename)) {
      if (_deps.mounted()) {
        await VideoPlayerLauncher.push(
          _deps.context(),
          VideoPlayerLaunchArgs(
            videoUrl: download.download,
            title: download.filename,
            subtitle: Formatters.formatFileSize(download.filesize),
            viewMode: PlaylistViewMode.sorted, // Single file - not series
          ),
        );
      }
    } else {
      if (_deps.mounted()) {
        _deps.showError(
          'This file is not a video (MIME type: ${download.mimeType})',
        );
      }
    }
  }

  Future<void> handleQueueDownload(DebridDownload download) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      final meta = jsonEncode({
        'restrictedLink': download.link,
        'torrentHash': '',
        'fileIndex': '',
      });
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'real_debrid_api_key',
        url: download.link,
        fileName: download.filename,
        context: _deps.context(),
        torrentName: download.filename,
        meta: meta,
      );
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(const SnackBar(content: Text('Added to downloads')));
    } catch (e) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(
        _deps.context(),
      ).showSnackBar(SnackBar(content: Text('Failed to start download: $e')));
    }
  }
}
