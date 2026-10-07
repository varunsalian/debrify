import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';

import 'premiumize_catalog_state.dart';

typedef PremiumizePlaylistActionsDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  PremiumizeCatalogState catalogState,
  void Function(String message) showLoadingDialog,
  void Function() dismissDialog,
  bool Function() mounted,
});

class PremiumizePlaylistActions {
  PremiumizePlaylistActions(this._deps);
  final PremiumizePlaylistActionsDeps _deps;

  // ── Add to playlist ──────────────────────────────────────────────────────────

  Future<void> addToPlaylist(PremiumizeFolderItem item) async {
    if (item.isFolder) {
      await addFolderToPlaylist(item);
    } else {
      await addFileToPlaylist(item);
    }
  }

  Future<void> addFileToPlaylist(PremiumizeFolderItem file) async {
    if (!file.isVideo) {
      _deps.showSnackBar(
        'Only video files can be added to playlist',
        isError: true,
      );
      return;
    }
    final added = await PlaylistStorage.addPlaylistItemRaw({
      'provider': 'premiumize',
      'title': FileUtils.cleanPlaylistTitle(file.name),
      'kind': 'single',
      'premiumizeItemId': file.id,
      'premiumizeFile': {'id': file.id, 'name': file.name, 'size': file.size},
      'sizeBytes': file.size > 0 ? file.size : null,
    });
    _deps.showSnackBar(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  Future<void> addFolderToPlaylist(PremiumizeFolderItem folder) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;

    _deps.showLoadingDialog('Scanning folder for videos...');
    try {
      final all = await PremiumizeService.listFolderRecursive(
        apiKey,
        folder.id,
      );
      _deps.dismissDialog();
      if (!_deps.mounted()) return;

      final videos = all.where((f) => f.isVideo).toList();
      if (videos.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }

      if (videos.length == 1) {
        final v = videos.first;
        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'premiumize',
          'title': FileUtils.cleanPlaylistTitle(v.name),
          'kind': 'single',
          'premiumizeItemId': v.id,
          'premiumizeFile': {'id': v.id, 'name': v.name, 'size': v.size},
          'sizeBytes': v.size > 0 ? v.size : null,
        });
        _deps.showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
        return;
      }

      final fileIds = videos.map((v) => v.id).toList();
      final filesMeta = videos
          .map((v) => {'id': v.id, 'name': v.name, 'size': v.size})
          .toList();
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'premiumize',
        'title': FileUtils.cleanPlaylistTitle(folder.name),
        'kind': 'collection',
        'premiumizeItemId': folder.id,
        'premiumizeFiles': filesMeta,
        'premiumizeItemIds': fileIds,
        'count': videos.length,
      });
      _deps.showSnackBar(
        added
            ? 'Added ${videos.length} videos to playlist'
            : 'Already in playlist',
        isError: !added,
      );
    } catch (e) {
      _deps.dismissDialog();
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }
}
