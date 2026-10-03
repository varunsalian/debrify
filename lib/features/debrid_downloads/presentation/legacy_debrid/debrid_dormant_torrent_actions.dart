import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'debrid_catalog_state.dart';

typedef DebridDormantTorrentActionsDeps = ({
  DebridCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String message) showError,
  Future<void> Function(RDTorrent torrent) navigateIntoTorrent,
  void Function(String message) showSuccess,
});

class DebridDormantTorrentActions {
  DebridDormantTorrentActions(this._deps);
  final DebridDormantTorrentActionsDeps _deps;

  Future<void> _handlePlayVideo(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single file - check MIME type after unrestricting
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _deps.catalogState.apiKey!,
          torrent.links[0],
        );
        final downloadLink = unrestrictResult['download'];
        final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

        // Check if it's actually a video using MIME type
        if (FileUtils.isVideoMimeType(mimeType)) {
          if (_deps.mounted()) {
            await VideoPlayerLauncher.push(
              _deps.context(),
              VideoPlayerLaunchArgs(
                videoUrl: downloadLink,
                title: torrent.filename,
                subtitle: Formatters.formatFileSize(torrent.bytes),
                viewMode: PlaylistViewMode.sorted, // Single file - not series
              ),
            );
          }
        } else {
          if (_deps.mounted()) {
            _deps.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (_deps.mounted()) {
          _deps.showError('Failed to load video: ${e.toString()}');
        }
      }
    } else {
      // Multiple files - navigate into torrent folder view
      if (_deps.mounted()) {
        await _deps.navigateIntoTorrent(torrent);
      }
    }
  }

  /// Copy download link for torrent to clipboard
  Future<void> _copyDownloadLink(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

    try {
      // Get torrent info
      final info = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        torrent.id,
      );
      final links = (info['links'] as List).cast<String>();

      if (links.isEmpty) {
        _deps.showError('No links available');
        return;
      }

      // Unrestrict the first link
      final unrestrictedData = await DebridService.unrestrictLink(
        _deps.catalogState.apiKey!,
        links[0],
      );
      final downloadUrl = unrestrictedData['download'] as String;

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _deps.showSuccess('Download link copied to clipboard');
    } catch (e) {
      _deps.showError('Failed to get download link: $e');
    }
  }
}
