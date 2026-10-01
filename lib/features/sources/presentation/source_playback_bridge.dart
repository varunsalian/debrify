import '../data/source_download.dart';
import 'source_download_action.dart';
import '../application/sources_providers.dart';
import '../data/automatic_source_bindings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../../../models/playback_meta.dart';
import '../../../services/torrent_playback_service.dart'
    show TorrentPlaybackService;

/// Context-dependent legacy playback remains behind this presentation boundary.
/// The caller supplies the rendered list and its matching selected-row index.
final sourcePlaybackBridgeProvider = Provider<SourcePlaybackBridge>(
  (ref) => SourcePlaybackBridge(
    bindings: ref.watch(automaticSourceBindingsFactoryProvider),
    downloads: ref.watch(sourceDownloadProvider),
  ),
  dependencies: [
    automaticSourceBindingsFactoryProvider,
    sourceDownloadProvider,
  ],
);

class SourcePlaybackBridge {
  const SourcePlaybackBridge({
    SourceDownload downloads = const SourceDownload(),
    AutomaticSourceBindings Function() bindings =
        AutomaticSourceBindings.capture,
  }) : _bindings = bindings,
       _downloads = downloads;

  final SourceDownload _downloads;

  final AutomaticSourceBindings Function() _bindings;

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
    sourceBindings: _bindings(),
  );

  bool supportsDownload(Torrent torrent) => SourceDownload.supports(torrent);

  Future<void> download(BuildContext context, Torrent torrent) =>
      downloadSource(context, torrent, _downloads);
}
