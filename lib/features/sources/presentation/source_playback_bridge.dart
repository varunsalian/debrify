import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../../../models/playback_meta.dart';
import '../../../services/torrent_playback_service.dart'
    show TorrentPlaybackService;

/// Context-dependent legacy playback remains behind this presentation boundary.
/// The caller supplies the rendered list and its matching selected-row index.
final sourcePlaybackBridgeProvider = Provider<SourcePlaybackBridge>(
  (ref) => const SourcePlaybackBridge(),
);

class SourcePlaybackBridge {
  const SourcePlaybackBridge();

  Future<void> play(
    BuildContext context,
    Torrent torrent, {
    required bool forcePlay,
    required PlaybackMeta meta,
    required List<Torrent> sources,
    required int sourceIndex,
    required String searchKeyword,
  }) => TorrentPlaybackService.activateTorrent(
    context,
    torrent,
    forcePlay: forcePlay,
    meta: meta,
    sources: sources,
    sourceIndex: sourceIndex,
    searchKeyword: searchKeyword,
  );

  bool supportsDownload(Torrent torrent) =>
      TorrentPlaybackService.supportsDirectStreamDownload(torrent);

  Future<void> download(BuildContext context, Torrent torrent) =>
      TorrentPlaybackService.downloadDirectStream(context, torrent);
}
