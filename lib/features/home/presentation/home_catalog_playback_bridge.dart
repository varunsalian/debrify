import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/playback_meta.dart';
import '../../../services/main_page_bridge.dart';
import '../../../services/torrent_playback_service.dart'
    show TorrentPlaybackService;

typedef CatalogPlayerLaunch =
    Future<void> Function(
      BuildContext context, {
      required String imdbId,
      required bool isMovie,
      int? season,
      int? episode,
      required PlaybackMeta meta,
      VoidCallback? openSourcePicker,
    });

final homeCatalogPlaybackBridgeProvider = Provider<HomeCatalogPlaybackBridge>(
  (ref) => const HomeCatalogPlaybackBridge(),
);

/// The legacy catalog player requires context and owns its native teardown.
/// This stateless bridge owns only each call's temporary launch listener and
/// the choice of immediate UI refresh; deferred return refresh stays with Home.
class HomeCatalogPlaybackBridge {
  const HomeCatalogPlaybackBridge({
    CatalogPlayerLaunch launch = TorrentPlaybackService.playFromSelection,
    void Function(VoidCallback) addExternalListener =
        MainPageBridge.addExternalPlayerLaunchListener,
    void Function(VoidCallback) removeExternalListener =
        MainPageBridge.removeExternalPlayerLaunchListener,
  }) : _launch = launch,
       _addExternalListener = addExternalListener,
       _removeExternalListener = removeExternalListener;

  final CatalogPlayerLaunch _launch;
  final void Function(VoidCallback) _addExternalListener;
  final void Function(VoidCallback) _removeExternalListener;

  Future<void> play(
    BuildContext context, {
    required AdvancedSearchSelection selection,
    required PlaybackMeta Function() buildMeta,
    required VoidCallback openSourcePicker,
    required bool Function() isCurrent,
    required Future<void> Function() refreshBoundSources,
    required Future<void> Function() refreshAfterPlayback,
  }) async {
    if (!context.mounted || !isCurrent()) return;
    var external = false;
    void onExternal() => external = true;
    _addExternalListener(onExternal);
    try {
      await _launch(
        context,
        imdbId: selection.imdbId,
        isMovie: !selection.isSeries,
        season: selection.season,
        episode: selection.episode,
        meta: buildMeta(),
        openSourcePicker: openSourcePicker,
      );
    } finally {
      _removeExternalListener(onExternal);
    }
    if (!context.mounted || !isCurrent()) return;
    // In-app playback completes after its route pops. External playback returns
    // during launch; a covered board also defers its full refresh to route return.
    // Auto-bound movie badges still refresh immediately in either deferred case.
    final boardOnTop = ModalRoute.of(context)?.isCurrent ?? false;
    if (external || !boardOnTop) {
      await refreshBoundSources();
      return;
    }
    await refreshAfterPlayback();
  }
}
