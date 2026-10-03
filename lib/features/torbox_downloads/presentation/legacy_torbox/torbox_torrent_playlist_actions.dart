import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/debrify_tv_channel_add_bridge.dart';
import 'package:flutter/material.dart';

import 'torbox_torrent_search_state.dart';

typedef TorboxTorrentPlaylistActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  TorboxTorrentSearchState torrentSearchState,
  // TEMP(torbox): showSnackBar -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart at step 4.
  void Function(String message, {bool isError}) showSnackBar,
});

class TorboxTorrentPlaylistActions {
  TorboxTorrentPlaylistActions(this._deps);
  final TorboxTorrentPlaylistActionsDeps _deps;

  Future<void> handleAddToPlaylist(TorboxTorrent torrent) async {
    final videoFiles = torrent.files.where(torboxFileLooksLikeVideo).toList();
    if (videoFiles.isEmpty) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(content: Text('No playable Torbox video files found.')),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final displayName = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);
      final added = await PlaylistStorage.addPlaylistItemRaw({
        'provider': 'torbox',
        'title': FileUtils.cleanPlaylistTitle(
          displayName.isNotEmpty ? displayName : torrent.name,
        ),
        'kind': 'single',
        'torboxTorrentId': torrent.id,
        'torboxFileId': file.id,
        'torrent_hash': torrent.hash,
        'sizeBytes': file.size,
      });
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text(added ? 'Added to playlist' : 'Already in playlist'),
          backgroundColor: added ? null : const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final ids = videoFiles.map((file) => file.id).toList();
    final added = await PlaylistStorage.addPlaylistItemRaw({
      'provider': 'torbox',
      'title': FileUtils.cleanPlaylistTitle(torrent.name),
      'kind': 'collection',
      'torboxTorrentId': torrent.id,
      'torboxFileIds': ids,
      'torrent_hash': torrent.hash,
      'count': videoFiles.length,
    });
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added collection to playlist' : 'Already in playlist',
        ),
        backgroundColor: added ? null : const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> handleAddToDebrifyTv(TorboxTorrent torrent) async {
    try {
      final result = await DebrifyTvChannelAddBridge.addTorrentsToChannel(
        _deps.context(),
        torrents: [DebrifyTvChannelAddBridge.fromTorboxTorrent(torrent)],
        searchKeyword: _deps.torrentSearchState.torrentSearchQuery,
      );

      if (result == null || !_deps.mounted()) return;
      _deps.showSnackBar(result.successMessage, isError: false);
    } on DebrifyTvChannelAddException catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar(e.message);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Failed to add torrent to Debrify TV: $e');
    }
  }
}
