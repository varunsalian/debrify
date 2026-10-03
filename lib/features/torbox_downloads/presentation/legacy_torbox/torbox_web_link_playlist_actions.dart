import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:flutter/services.dart';

import 'torbox_catalog_state.dart';

typedef TorboxWebLinkPlaylistActionsDeps = ({
  TorboxCatalogState catalogState,
  void Function(String message, {bool isError}) showSnackBar,
  bool Function() mounted,
});

class TorboxWebLinkPlaylistActions {
  TorboxWebLinkPlaylistActions(this._deps);
  final TorboxWebLinkPlaylistActionsDeps _deps;

  Future<void> copyWebDownloadLink(TorboxWebDownload webDownload) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    if (webDownload.files.isEmpty) {
      _deps.showSnackBar('No files available');
      return;
    }

    if (webDownload.files.length == 1) {
      // Single file - get direct link
      try {
        final link = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: webDownload.id,
          fileId: webDownload.files.first.id,
        );
        if (!_deps.mounted()) return;
        await Clipboard.setData(ClipboardData(text: link));
        _deps.showSnackBar(
          'Download link copied to clipboard.',
          isError: false,
        );
      } catch (e) {
        if (!_deps.mounted()) return;
        _deps.showSnackBar('Failed to copy link: ${formatTorboxError(e)}');
      }
    } else {
      // Multiple files - get ZIP link
      final zipLink = TorboxService.createWebDownloadZipPermalink(
        key,
        webDownload.id,
      );
      await Clipboard.setData(ClipboardData(text: zipLink));
      if (!_deps.mounted()) return;
      _deps.showSnackBar(
        'ZIP download link copied to clipboard.',
        isError: false,
      );
    }
  }

  Future<void> handleAddWebDownloadToPlaylist(
    TorboxWebDownload webDownload,
  ) async {
    final videoFiles = webDownload.files.where((file) {
      if (file.zipped) return false;
      return torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _deps.showSnackBar('No video files found in this download.');
      return;
    }

    if (videoFiles.length == 1) {
      // Single video - add as single item
      final file = videoFiles.first;
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'torbox_webdl',
        'title': FileUtils.cleanPlaylistTitle(webDownload.name),
        'kind': 'single',
        'torboxWebDownloadId': webDownload.id,
        'torboxFileId': file.id,
        'webdl_hash': webDownload.hash,
        'sizeBytes': file.size,
      });

      _deps.showSnackBar(
        added ? 'Added to playlist' : 'Already in playlist',
        isError: !added,
      );
    } else {
      // Multiple videos - add as collection
      final ids = videoFiles.map((f) => f.id).toList();
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'torbox_webdl',
        'title': FileUtils.cleanPlaylistTitle(webDownload.name),
        'kind': 'collection',
        'torboxWebDownloadId': webDownload.id,
        'torboxFileIds': ids,
        'webdl_hash': webDownload.hash,
        'count': videoFiles.length,
      });

      _deps.showSnackBar(
        added
            ? 'Added ${videoFiles.length} videos to playlist'
            : 'Already in playlist',
        isError: !added,
      );
    }
  }
}
