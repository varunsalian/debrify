import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/torrent_playback_service.dart';
import '../application/source_binding_controller.dart';

/// Stateless compatibility boundary for context-dependent legacy pickers.
/// Persistence must use the calling Sources session's guarded writer.
final sourceBindingBridgeProvider = Provider<SourceBindingBridge>(
  (ref) => const SourceBindingBridge(),
);

class SourceBindingBridge {
  const SourceBindingBridge();

  bool get localBindingAvailable =>
      TorrentPlaybackService.localBindingAvailable;

  Future<bool> pin(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    String? addonCatalogId,
    String? addonCatalogKey,
  }) => IptvSourceSearch.owns(torrent)
      ? TorrentPlaybackService.bindIptvSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
        )
      : torrent.isDirectStream
      ? TorrentPlaybackService.bindDirectSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
          addonCatalogId: addonCatalogId,
          addonCatalogKey: addonCatalogKey,
        )
      : TorrentPlaybackService.bindSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
          addonCatalogId: addonCatalogId,
          addonCatalogKey: addonCatalogKey,
        );

  Future<bool> pinLocal(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    required String title,
    String? year,
  }) => TorrentPlaybackService.bindLocalSource(
    context,
    imdbId: imdbId,
    isMovie: isMovie,
    saveBinding: saveBinding,
    title: title,
    year: year,
  );
}
