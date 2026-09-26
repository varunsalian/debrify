import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/torrent_playback_service.dart';
import '../application/source_binding_controller.dart';
import 'local_source_binding.dart';
import 'local_source_picker.dart';
import 'local_source_picker_composition.dart';

/// Stateless compatibility boundary for context-dependent legacy pickers.
/// Persistence must use the calling Sources session's guarded writer.
final sourceBindingBridgeProvider = Provider<SourceBindingBridge>(
  (ref) =>
      SourceBindingBridge(localPicker: ref.watch(localSourcePickerProvider)),
  dependencies: [localSourcePickerProvider],
);

class SourceBindingBridge {
  const SourceBindingBridge({LocalSourcePicker? localPicker})
    : _localPicker = localPicker;

  final LocalSourcePicker? _localPicker;
  LocalSourcePicker get _picker => _localPicker ?? localSourcePicker;

  bool get localBindingAvailable => _picker.disabledReason == null;

  Future<bool> pin(
    BuildContext context,
    Torrent torrent, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    required bool Function() canContinue,
    String? addonCatalogId,
    String? addonCatalogKey,
  }) => IptvSourceSearch.owns(torrent)
      ? TorrentPlaybackService.bindIptvSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
          canContinue: canContinue,
        )
      : torrent.isDirectStream
      ? TorrentPlaybackService.bindDirectSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
          canContinue: canContinue,
          addonCatalogId: addonCatalogId,
          addonCatalogKey: addonCatalogKey,
        )
      : TorrentPlaybackService.bindSource(
          context,
          torrent,
          imdbId: imdbId,
          isMovie: isMovie,
          saveBinding: saveBinding,
          canContinue: canContinue,
          addonCatalogId: addonCatalogId,
          addonCatalogKey: addonCatalogKey,
        );

  Future<bool> pinLocal(
    BuildContext context, {
    required String imdbId,
    required bool isMovie,
    required SourceBindingWriter saveBinding,
    required bool Function() canContinue,
    required String title,
    String? year,
  }) => presentLocalSourceBinding(
    context,
    imdbId: imdbId,
    canContinue: canContinue,
    pick: () => isMovie
        ? _picker.pickMovieSource(
            context,
            title: title,
            year: year,
            canContinue: canContinue,
          )
        : _picker.pickSeriesSource(
            context,
            title: title,
            canContinue: canContinue,
          ),
    // Preserve the compatibility writer's asynchronous completion boundary.
    save: (source) async => saveBinding(source),
  );
}
