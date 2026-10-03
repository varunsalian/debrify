import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_facades.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_maintenance.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_network.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_presentation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_guide_context.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_load_status.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_source_counts.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_virtual_results.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_media_store.dart' show IptvListMeta;

typedef IptvCatalogCompositionExternalSections = ({
  IptvFiltersSection Function() filtersSection,
  IptvGuideContext Function() guideContext,
  IptvPlaybackRefresh Function() playbackRefresh,
  IptvPreviewTuning Function() previewTuning,
  IptvRowProjection Function() rowProjection,
  IptvSourceCounts Function() sourceStatistics,
  IptvVirtualResults Function() virtualResults,
});

/// Constructs the catalog sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvCatalogComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvCatalogCompositionExternalSections _external;

  IptvCatalogComposition(this._view, this._states, this._external);

  late final IptvFavorites favorites = IptvFavorites((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    settingsState: _states.settingsState,
    context: () => _view.context(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) =>
        catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => _view.mounted(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    refreshListShelfPresence: () =>
        _external.playbackRefresh().refreshListShelfPresence(),
    setState: _view.setState,
  ));

  late final IptvSettingsLoading settingsLoading = IptvSettingsLoading((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    listPlaylist: (IptvListMeta list) => IptvFavorites.listPlaylist(list),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) =>
        catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => _view.mounted(),
    retunePreview: (IptvChannel channel) =>
        _external.previewTuning().retunePreview(channel),
    setState: _view.setState,
    stopPreviewPlayback: () => _external.previewTuning().stopPreviewPlayback(),
  ));

  late final IptvCatalogLoading catalogLoading = IptvCatalogLoading((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    statusState: _states.statusState,
    applyProgressiveBatch:
        (int ticket, List<IptvChannel> channels, List<String> categories) =>
            _external.virtualResults().applyProgressiveBatch(
              ticket,
              channels,
              categories,
            ),
    beginLoadStatus: () => loadStatus.beginLoadStatus(),
    buildContinueResult: () => _external.virtualResults().buildContinueResult(),
    buildListResult: (String listId) =>
        _external.virtualResults().buildListResult(listId),
    clearPreview: () => _external.previewTuning().clearPreview(),
    consumeContentFocusRequest: () =>
        _external.filtersSection().consumeContentFocusRequest(),
    endLoadStatus: () => loadStatus.endLoadStatus(),
    fetchCatalogFromNetwork:
        (IptvPlaylist playlist, String contentType, int ticket) =>
            catalogNetwork.fetchCatalogFromNetwork(
              playlist,
              contentType,
              ticket,
            ),
    mounted: () => _view.mounted(),
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) =>
        loadStatus.onLoadPhase(
          ticket,
          phase,
          bytes: bytes,
          totalBytes: totalBytes,
        ),
    presentCatalog:
        (
          IptvPlaylist playlist,
          int ticket,
          IptvParseResult result, {
          bool migrateFavorites = true,
          String? cacheKey,
        }) => catalogPresentation.presentCatalog(
          playlist,
          ticket,
          result,
          migrateFavorites: migrateFavorites,
          cacheKey: cacheKey,
        ),
    presentDbCatalog:
        (
          IptvPlaylist playlist,
          int ticket,
          CatalogSnapshot snap, {
          String? warning,
          bool migrateFavorites = false,
        }) => catalogPresentation.presentDbCatalog(
          playlist,
          ticket,
          snap,
          warning: warning,
          migrateFavorites: migrateFavorites,
        ),
    runCatalogMaintenance:
        (
          IptvPlaylist playlist,
          String contentType,
          String cacheKey,
          int ticket, {
          required bool userRequested,
        }) => catalogMaintenance.runCatalogMaintenance(
          playlist,
          contentType,
          cacheKey,
          ticket,
          userRequested: userRequested,
        ),
    runPendingMigrations: (String cacheKey, int ticket) =>
        catalogMaintenance.runPendingMigrations(cacheKey, ticket),
    setState: _view.setState,
  ));

  late final IptvCatalogPresentation catalogPresentation =
      IptvCatalogPresentation((
        catalogState: _states.catalogState,
        applyFilters: () => _external.filtersSection().applyFilters(),
        consumeContentFocusRequest: () =>
            _external.filtersSection().consumeContentFocusRequest(),
        context: () => _view.context(),
        endLoadStatus: () => loadStatus.endLoadStatus(),
        landingCategory: (String? orderKey, List<String> categories) =>
            _external.filtersSection().landingCategory(orderKey, categories),
        loadFavorites: () => favorites.loadFavorites(),
        loadProgress: (int ticket, List<IptvChannel> channels) =>
            _external.virtualResults().loadProgress(ticket, channels),
        makeDbList: (CatalogSnapshot snap, {String? group, String? search}) =>
            catalogFacades.makeDbList(snap, group: group, search: search),
        mounted: () => _view.mounted(),
        recomputeSourceCounts: () =>
            _external.sourceStatistics().recomputeSourceCounts(),
        setState: _view.setState,
        updateEpgContext:
            (
              IptvPlaylist playlist,
              IptvParseResult result,
              int ticket, {
              bool quiet = false,
            }) => _external.guideContext().updateEpgContext(
              playlist,
              result,
              ticket,
              quiet: quiet,
            ),
      ));

  late final IptvCatalogFacades catalogFacades = IptvCatalogFacades((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    settingsState: _states.settingsState,
    applyFilters: () => _external.filtersSection().applyFilters(),
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));

  late final IptvCatalogMaintenance catalogMaintenance =
      IptvCatalogMaintenance((
        catalogState: _states.catalogState,
        finishMaintenanceChip:
            ({required bool narrate, required bool numbersMoved}) =>
                statusChip.finishMaintenanceChip(
                  narrate: narrate,
                  numbersMoved: numbersMoved,
                ),
        mounted: () => _view.mounted(),
        rebuildDbFacades: (CatalogSnapshot snap) =>
            catalogFacades.rebuildDbFacades(snap),
        revalidateDbCatalog:
            (
              IptvPlaylist playlist,
              String contentType,
              String cacheKey,
              int ticket,
            ) => catalogRefresh.revalidateDbCatalog(
              playlist,
              contentType,
              cacheKey,
              ticket,
            ),
        revalidateSuperseded:
            (IptvPlaylist playlist, String contentType, int ticket) =>
                catalogFacades.revalidateSuperseded(
                  playlist,
                  contentType,
                  ticket,
                ),
        scheduleMaintenanceChip: (int ticket) =>
            statusChip.scheduleMaintenanceChip(ticket),
      ));

  late final IptvStatusChip statusChip = IptvStatusChip((
    catalogState: _states.catalogState,
    statusState: _states.statusState,
    mounted: () => _view.mounted(),
    recomputeSourceCounts: () =>
        _external.sourceStatistics().recomputeSourceCounts(),
    setState: _view.setState,
  ));

  late final IptvCatalogRefresh catalogRefresh = IptvCatalogRefresh((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    settingsState: _states.settingsState,
    statusState: _states.statusState,
    applyFilters: () => _external.filtersSection().applyFilters(),
    deriveCategories: (CatalogSnapshot snap, List<CatalogGroup> groups) =>
        catalogPresentation.deriveCategories(snap, groups),
    loadFavorites: () => favorites.loadFavorites(),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) =>
        catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => _view.mounted(),
    presentCatalog:
        (
          IptvPlaylist playlist,
          int ticket,
          IptvParseResult result, {
          bool migrateFavorites = true,
          String? cacheKey,
        }) => catalogPresentation.presentCatalog(
          playlist,
          ticket,
          result,
          migrateFavorites: migrateFavorites,
          cacheKey: cacheKey,
        ),
    revalidateSuperseded:
        (IptvPlaylist playlist, String contentType, int ticket) =>
            catalogFacades.revalidateSuperseded(playlist, contentType, ticket),
    rowAttached: (IptvChannel channel) =>
        _external.rowProjection().rowAttached(channel),
    setState: _view.setState,
    showChip:
        (
          CatalogChipState state,
          String message, {
          Duration? autoHide,
          ChipOwner owner = ChipOwner.refresh,
        }) => statusChip.showChip(
          state,
          message,
          autoHide: autoHide,
          owner: owner,
        ),
    updateEpgContext:
        (
          IptvPlaylist playlist,
          IptvParseResult result,
          int ticket, {
          bool quiet = false,
        }) => _external.guideContext().updateEpgContext(
          playlist,
          result,
          ticket,
          quiet: quiet,
        ),
  ));

  late final IptvCatalogNetwork catalogNetwork = IptvCatalogNetwork((
    catalogState: _states.catalogState,
    settingsState: _states.settingsState,
    mounted: () => _view.mounted(),
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) =>
        loadStatus.onLoadPhase(
          ticket,
          phase,
          bytes: bytes,
          totalBytes: totalBytes,
        ),
  ));

  late final IptvLoadStatus loadStatus = IptvLoadStatus((
    catalogState: _states.catalogState,
    statusState: _states.statusState,
    context: () => _view.context(),
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));
}
