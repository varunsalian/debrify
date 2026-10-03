import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:flutter/services.dart';

import 'debrid_catalog_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridNodePlaylistLinksDeps = ({
  DebridNavigationState navigationState,
  bool Function() mounted,
  void Function(String message) showSuccess,
  void Function(String message) showError,
  DebridCatalogState catalogState,
});

class DebridNodePlaylistLinks {
  DebridNodePlaylistLinks(this._deps);
  final DebridNodePlaylistLinksDeps _deps;
  DebridCatalogState get _catalog => _deps.catalogState;
  DebridNavigationState get _nav => _deps.navigationState;

  /// Add a single file to playlist
  Future<void> addNodeFileToPlaylist(RDFileNode file) async {
    if (_nav.currentTorrentId == null) return;

    try {
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(file.name),
        'kind': 'single',
        'rdTorrentId': _nav.currentTorrentId,
        'rdLinkIndex': file.linkIndex,
        'sizeBytes': file.bytes,
      });

      if (_deps.mounted()) {
        _deps.showSuccess(added ? 'Added to playlist' : 'Already in playlist');
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to add to playlist: ${e.toString()}');
      }
    }
  }

  /// Add all videos in a folder to playlist
  Future<void> addFolderToPlaylist(RDFileNode folder) async {
    if (_nav.currentTorrentId == null) return;

    try {
      // Collect video files
      final videoFiles = RDFolderTreeBuilder.collectVideoFiles(folder);
      if (videoFiles.isEmpty) {
        _deps.showError('No video files to add');
        return;
      }

      // Add as a collection to playlist
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'rd',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'rdTorrentId': _nav.currentTorrentId,
        'rdFileNodes': videoFiles.map((f) => f.toJson()).toList(),
        'fileCount': videoFiles.length,
        'totalBytes': folder.totalBytes,
      });

      if (_deps.mounted()) {
        _deps.showSuccess(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
        );
      }
    } catch (e) {
      if (_deps.mounted()) {
        _deps.showError('Failed to add to playlist: ${e.toString()}');
      }
    }
  }

  /// Copy download link for file node to clipboard
  Future<void> copyNodeDownloadLink(RDFileNode node) async {
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) return;

    try {
      // Unrestrict the file's link
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _catalog.apiKey!,
        _nav.currentTorrentId!,
        node.linkIndex,
      );

      // Copy to clipboard
      await Clipboard.setData(ClipboardData(text: downloadUrl));
      _deps.showSuccess('Download link copied to clipboard');
    } catch (e) {
      _deps.showError('Failed to get download link: $e');
    }
  }
}
