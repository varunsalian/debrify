import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/torbox_folder_tree_builder.dart';
import 'package:flutter/services.dart';

import 'torbox_catalog_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxFilePlaylistLinksDeps = ({
  TorboxNavigationState navigationState,
  List<TorboxFile> Function() currentFiles,
  void Function(String message, {bool isError}) showSnackBar,
  Future<void> Function(TorboxTorrent torrent, TorboxFile file)
  copyTorboxFileLink,
  TorboxCatalogState catalogState,
  bool Function() mounted,
});

class TorboxFilePlaylistLinks {
  TorboxFilePlaylistLinks(this._deps);
  final TorboxFilePlaylistLinksDeps _deps;
  TorboxNavigationState get _nav => _deps.navigationState;

  /// Add file or folder to playlist
  Future<void> addFileOrFolderToPlaylist(RDFileNode node) async {
    if (_nav.currentTorrent == null && _nav.currentWebDownload == null) return;

    final files = _deps.currentFiles();
    final isWebDownload = _nav.currentWebDownload != null;

    if (node.isFolder) {
      // Add all video files in folder
      final videoFiles = TorboxFolderTreeBuilder.collectVideoFiles(node);
      final torboxFiles = videoFiles
          .map((n) {
            if (n.linkIndex >= 0 && n.linkIndex < files.length) {
              return files[n.linkIndex];
            }
            return null;
          })
          .where((f) => f != null)
          .cast<TorboxFile>()
          .toList();

      if (torboxFiles.isEmpty) {
        _deps.showSnackBar('No video files found in folder');
        return;
      }

      // Add as collection
      final ids = torboxFiles.map((f) => f.id).toList();
      final Map<String, dynamic> playlistData;
      if (isWebDownload) {
        playlistData = {
          'provider': 'torbox_webdl',
          'title': FileUtils.cleanPlaylistTitle(node.name),
          'kind': 'collection',
          'torboxWebDownloadId': _nav.currentWebDownload!.id,
          'torboxFileIds': ids,
          'webdl_hash': _nav.currentWebDownload!.hash,
          'count': torboxFiles.length,
        };
      } else {
        playlistData = {
          'provider': 'torbox',
          'title': FileUtils.cleanPlaylistTitle(node.name),
          'kind': 'collection',
          'torboxTorrentId': _nav.currentTorrent!.id,
          'torboxFileIds': ids,
          'torrent_hash': _nav.currentTorrent!.hash,
          'count': torboxFiles.length,
        };
      }
      final added = await PlaylistStorage.addPlaylistItemRaw(playlistData);

      _deps.showSnackBar(
        added
            ? 'Added ${torboxFiles.length} videos to playlist'
            : 'Already in playlist',
        isError: !added,
      );
    } else {
      // Add single file
      if (node.linkIndex >= 0 && node.linkIndex < files.length) {
        final torboxFile = files[node.linkIndex];
        final Map<String, dynamic> playlistData;
        if (isWebDownload) {
          playlistData = {
            'provider': 'torbox_webdl',
            'title': FileUtils.cleanPlaylistTitle(node.name),
            'kind': 'single',
            'torboxWebDownloadId': _nav.currentWebDownload!.id,
            'torboxFileId': torboxFile.id,
            'webdl_hash': _nav.currentWebDownload!.hash,
            'sizeBytes': torboxFile.size,
          };
        } else {
          playlistData = {
            'provider': 'torbox',
            'title': FileUtils.cleanPlaylistTitle(node.name),
            'kind': 'single',
            'torboxTorrentId': _nav.currentTorrent!.id,
            'torboxFileId': torboxFile.id,
            'torrent_hash': _nav.currentTorrent!.hash,
            'sizeBytes': torboxFile.size,
          };
        }
        final added = await PlaylistStorage.addPlaylistItemRaw(playlistData);

        _deps.showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
      }
    }
  }

  /// Copy file download link
  Future<void> copyFileLink(RDFileNode node) async {
    if ((_nav.currentTorrent == null && _nav.currentWebDownload == null) ||
        node.isFolder) {
      return;
    }

    final files = _deps.currentFiles();
    if (node.linkIndex >= 0 && node.linkIndex < files.length) {
      final torboxFile = files[node.linkIndex];
      if (_nav.currentTorrent != null) {
        await _deps.copyTorboxFileLink(_nav.currentTorrent!, torboxFile);
      } else if (_nav.currentWebDownload != null) {
        await copyWebDownloadFileLink(_nav.currentWebDownload!, torboxFile);
      }
    }
  }

  /// Copy web download file link
  Future<void> copyWebDownloadFileLink(
    TorboxWebDownload webDownload,
    TorboxFile file,
  ) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showSnackBar('Torbox API key not configured');
      return;
    }

    try {
      final link = await TorboxService.requestWebDownloadFileLink(
        apiKey: key,
        webId: webDownload.id,
        fileId: file.id,
      );
      await Clipboard.setData(ClipboardData(text: link));
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Download link copied to clipboard.', isError: false);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Failed to copy link: ${formatTorboxError(e)}');
    }
  }
}
