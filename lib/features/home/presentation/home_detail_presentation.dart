import 'package:flutter/widgets.dart';

import '../../../models/advanced_search_selection.dart';
import '../../../models/play_loader_art.dart';
import '../../../models/stremio_addon.dart';
import '../../../screens/catalog_item_detail_screen.dart';
import '../../../screens/merged_series_detail_screen.dart';
import '../../../services/trakt/trakt_service.dart' show TraktTitleStatus;
import '../../../services/simkl/simkl_service.dart' show SimklTitleStatus;
import '../../../services/mdblist/mdblist_models.dart' show MdblistTitleStatus;
import '../../../services/simkl/simkl_menu_helpers.dart'
    show SimklMenuOption, SimklItemMenuAction;
import '../../../services/mdblist/mdblist_menu_helpers.dart'
    show MdblistMenuOption, MdblistItemMenuAction;
import '../../../widgets/trakt/trakt_menu_helpers.dart'
    show TraktMenuOption, TraktItemMenuAction;

typedef HomeDetailPromise = ({bool started, int season, int episode});
typedef HomeDetailPlay =
    Future<void> Function({
      bool startFromBeginning,
      bool preferTraktResume,
      bool skipEpisodeFallback,
      bool browseSourcesOnly,
      HomeDetailPromise? promisedTarget,
    });

/// Compose the two existing detail layouts from explicit, borrowed callbacks.
/// This builder owns no request, profile state, focus node or playback service.
Widget buildHomeDetail({
  required StremioMeta item,
  required StremioAddon addon,
  required bool merged,
  required bool isTelevision,
  required bool pikpakOnly,
  required bool Function() hasBoundSource,
  required bool isTraktSource,
  required bool isMdblistSource,
  String? heroTag,
  int? initialSeason,
  int? initialEpisode,
  required Future<({bool started, int? season, int? episode})> Function()
  resumeInfo,
  required HomeDetailPlay play,
  required VoidCallback browse,
  required void Function(AdvancedSearchSelection) browseSelection,
  required Future<void> Function(AdvancedSearchSelection) playSelection,
  required int Function(StremioMeta) boundSourceCount,
  required Future<void> Function(StremioMeta) selectSource,
  required ValueChanged<PlayLoaderArt> adoptArtwork,
  required List<TraktMenuOption> traktOptions,
  required List<TraktMenuOption> Function(TraktTitleStatus?) traktMenu,
  required Future<void> Function(TraktItemMenuAction, {int? rating})
  traktAction,
  Future<TraktTitleStatus?> Function()? traktStatus,
  required List<SimklMenuOption> simklOptions,
  required List<SimklMenuOption> Function(SimklTitleStatus?) simklMenu,
  required Future<void> Function(SimklItemMenuAction, {int? rating})
  simklAction,
  Future<SimklTitleStatus?> Function()? simklStatus,
  required List<MdblistMenuOption> mdblistOptions,
  required List<MdblistMenuOption> Function(MdblistTitleStatus?) mdblistMenu,
  required Future<void> Function(MdblistItemMenuAction, {int? rating})
  mdblistAction,
  Future<MdblistTitleStatus?> Function()? mdblistStatus,
  Future<List<StremioMeta>> Function()? recommendations,
  required ValueChanged<StremioMeta> openRecommendation,
  required Future<StremioMeta?> Function(String, String) enrich,
}) {
  if (merged && (item.type == 'series' || item.type == 'movie')) {
    return MergedDetailScreen(
      item: item,
      addon: addon,
      isTelevision: isTelevision,
      // The merged page supports PikPak through the existing player bridge.
      showQuickPlay: true,
      isTraktSource: isTraktSource,
      isMdblistSource: isMdblistSource,
      heroTag: heroTag,
      initialSeason: initialSeason,
      initialEpisode: initialEpisode,
      resumeInfoLoader: resumeInfo,
      // Preserve the episode promised by the merged page's own watched frontier.
      onResume: (promised) => play(
        skipEpisodeFallback: true,
        preferTraktResume: true,
        promisedTarget: promised,
      ),
      onRewatch: () => play(startFromBeginning: true),
      onBrowse: item.type == 'movie' ? browse : null,
      onItemSelected: browseSelection,
      onQuickPlay: playSelection,
      onBrowsePrimaryEpisodeSources: (promised) => play(
        skipEpisodeFallback: true,
        preferTraktResume: true,
        promisedTarget: promised,
        browseSourcesOnly: true,
      ),
      boundSourceCount: boundSourceCount,
      onSelectSource: selectSource,
      traktMenuOptions: traktOptions,
      traktMenuBuilder: traktMenu,
      traktStatusLoader: traktStatus,
      onTraktAction: (action) => traktAction(action),
      onTraktRate: (rating) =>
          traktAction(TraktItemMenuAction.rate, rating: rating),
      simklMenuOptions: simklOptions,
      simklMenuBuilder: simklMenu,
      simklStatusLoader: simklStatus,
      onSimklAction: (action) => simklAction(action),
      onSimklRate: (rating) =>
          simklAction(SimklItemMenuAction.rate, rating: rating),
      mdblistMenuOptions: mdblistOptions,
      mdblistMenuBuilder: mdblistMenu,
      mdblistStatusLoader: mdblistStatus,
      onMdblistAction: (action) => mdblistAction(action),
      onMdblistRate: (rating) =>
          mdblistAction(MdblistItemMenuAction.rate, rating: rating),
      recommendationsLoader: recommendations,
      onRecommendationTap: openRecommendation,
      metaEnricher: enrich,
    );
  }
  return CatalogItemDetailScreen(
    // Preserve the original addon on locally saved Watchlist items.
    item: item.sourceAddon == null ? item.withSourceAddon(addon) : item,
    isTelevision: isTelevision,
    showQuickPlay: !pikpakOnly,
    hasBoundSource: hasBoundSource(),
    resumeInfoLoader: resumeInfo,
    // The legacy label is also Trakt-authoritative.
    onPlay: () => play(preferTraktResume: true),
    onRewatch: () => play(startFromBeginning: true),
    onLoaderArt: adoptArtwork,
    onBrowse: browse,
    onBrowsePrimaryEpisodeSources: item.type == 'series'
        ? () => play(
            skipEpisodeFallback: true,
            preferTraktResume: true,
            browseSourcesOnly: true,
          )
        : null,
    traktMenuOptions: traktOptions,
    onTraktAction: (action) => traktAction(action),
    simklMenuOptions: simklOptions,
    onSimklAction: (action) => simklAction(action),
    mdblistMenuOptions: mdblistOptions,
    onMdblistAction: (action) => mdblistAction(action),
    simklStatusLoader: simklStatus,
    recommendationsLoader: recommendations,
    onRecommendationTap: openRecommendation,
    metaEnricher: enrich,
  );
}
