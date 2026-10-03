import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/widgets/debrify_tv_channel_add_bridge.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_torrent_search_state.dart';

typedef DebridTorrentPlaylistActionsDeps = ({
  DebridCatalogState catalogState,
  bool Function() mounted,
  BuildContext Function() context,
  void Function(String message) showError,
  DebridTorrentSearchState torrentSearchState,
  void Function(String message) showSuccess,
});

class DebridTorrentPlaylistActions {
  DebridTorrentPlaylistActions(this._deps);
  final DebridTorrentPlaylistActionsDeps _deps;

  Future<void> handleAddTorrentToPlaylist(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;

    if (torrent.links.length == 1) {
      try {
        final unrestrictResult = await DebridService.unrestrictLink(
          _deps.catalogState.apiKey!,
          torrent.links[0],
        );
        final mimeType = unrestrictResult['mimeType']?.toString() ?? '';

        if (FileUtils.isVideoMimeType(mimeType)) {
          final ok = await PlaylistStorage.addPlaylistItemRaw({
            'title': FileUtils.cleanPlaylistTitle(torrent.filename),
            'url': '',
            'restrictedLink': torrent.links[0],
            'rdTorrentId': torrent.id,
            'kind': 'single',
          });
          if (!_deps.mounted()) return;
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(
              content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
            ),
          );
        } else {
          if (_deps.mounted()) {
            _deps.showError('This file is not a video (MIME type: $mimeType)');
          }
        }
      } catch (e) {
        if (_deps.mounted()) {
          _deps.showError('Failed to validate file: ${e.toString()}');
        }
      }
    } else {
      final ok = await PlaylistStorage.addPlaylistItemRaw({
        'title': FileUtils.cleanPlaylistTitle(torrent.filename),
        'kind': 'collection',
        'rdTorrentId': torrent.id,
        'count': torrent.links.length,
      });
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Added to playlist' : 'Already in playlist'),
        ),
      );
    }
  }

  Future<void> handleAddTorrentToDebrifyTv(RDTorrent torrent) async {
    try {
      final result = await DebrifyTvChannelAddBridge.addTorrentsToChannel(
        _deps.context(),
        torrents: [DebrifyTvChannelAddBridge.fromRealDebridTorrent(torrent)],
        searchKeyword: _deps.torrentSearchState.torrentSearchQuery,
      );

      if (result == null || !_deps.mounted()) return;
      _deps.showSuccess(result.successMessage);
    } on DebrifyTvChannelAddException catch (e) {
      if (!_deps.mounted()) return;
      _deps.showError(e.message);
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showError('Failed to add torrent to Debrify TV: $e');
    }
  }
}
