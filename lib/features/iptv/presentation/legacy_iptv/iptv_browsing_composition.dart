import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_facades.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_presentation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_categories.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_guide_context.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_load_status.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_browse.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_payload.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_focus.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_virtual_results.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';

typedef IptvBrowsingCompositionExternalSections = ({
  IptvCatalogFacades Function() catalogFacades,
  IptvCatalogLoading Function() catalogLoading,
  IptvCatalogPresentation Function() catalogPresentation,
  IptvLoadStatus Function() loadStatus,
  IptvPreviewTuning Function() previewTuning,
  IptvRowProjection Function() rowProjection,
  IptvSpotlightFocus Function() spotlightFocus,
  IptvStatusChip Function() statusChip,
});

/// Constructs the browsing sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvBrowsingComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvBrowsingCompositionExternalSections _external;

  IptvBrowsingComposition(this._view, this._states, this._external);

  late final IptvFiltersSection filtersSection = IptvFiltersSection((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    beginLoadStatus: () => _external.loadStatus().beginLoadStatus(),
    clearPreview: () => _external.previewTuning().clearPreview(),
    focusNodeFor: (IptvChannel channel) =>
        _external.rowProjection().focusNodeFor(channel),
    focusSpotlightContentEntry: () =>
        _external.spotlightFocus().focusSpotlightContentEntry(),
    isTelevision: () => _view.isTelevision(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) =>
        _external.catalogLoading().loadPlaylist(
          playlist,
          userRequested: userRequested,
        ),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) =>
        _external.catalogFacades().makeDbList(
          snap,
          group: group,
          search: search,
        ),
    mounted: () => _view.mounted(),
    searchQuery: () => _view.searchQuery(),
    setState: _view.setState,
  ));

  late final IptvGuideContext guideContext = IptvGuideContext((
    catalogState: _states.catalogState,
    settingsState: _states.settingsState,
    statusState: _states.statusState,
    context: () => _view.context(),
    hideChipIfOwned: (ChipOwner owner) =>
        _external.statusChip().hideChipIfOwned(owner),
    mounted: () => _view.mounted(),
    onGuidePhase: (int ticket, int? bytes, int? totalBytes) =>
        _external.statusChip().onGuidePhase(ticket, bytes, totalBytes),
    setState: _view.setState,
  ));

  late final IptvVirtualResults virtualResults = IptvVirtualResults((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    applyFilters: () => filtersSection.applyFilters(),
    consumeContentFocusRequest: () =>
        filtersSection.consumeContentFocusRequest(),
    endLoadStatus: () => _external.loadStatus().endLoadStatus(),
    mounted: () => _view.mounted(),
    setState: _view.setState,
  ));

  late final IptvCategories categoryActions = IptvCategories((
    catalogState: _states.catalogState,
    applyFilters: () => filtersSection.applyFilters(),
    categoryCounts: () => _external.rowProjection().categoryCounts,
    context: () => _view.context(),
    deriveCategories: (CatalogSnapshot snap, List<CatalogGroup> groups) =>
        _external.catalogPresentation().deriveCategories(snap, groups),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) =>
        _external.catalogFacades().makeDbList(
          snap,
          group: group,
          search: search,
        ),
    mounted: () => _view.mounted(),
    setState: _view.setState,
    showChip:
        (
          CatalogChipState state,
          String message, {
          Duration? autoHide,
          ChipOwner owner = ChipOwner.refresh,
        }) => _external.statusChip().showChip(
          state,
          message,
          autoHide: autoHide,
          owner: owner,
        ),
  ));

  late final IptvPlayerPayload playerPayload = IptvPlayerPayload((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    settingsState: _states.settingsState,
    withoutHidden: (String catalogKey, List<String> categories) =>
        _external.catalogPresentation().withoutHidden(catalogKey, categories),
  ));

  late final IptvPlayerBrowse playerBrowse = IptvPlayerBrowse((
    catalogState: _states.catalogState,
    playerState: _states.playerState,
    settingsState: _states.settingsState,
    fullCategoryList: () => playerPayload.fullCategoryList(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) =>
        _external.catalogLoading().loadPlaylist(
          playlist,
          userRequested: userRequested,
        ),
    mounted: () => _view.mounted(),
    playerChannelPayload:
        (List<({IptvChannel channel, IptvPlaylist source})> entries) =>
            playerPayload.playerChannelPayload(entries),
    playerSourcePayload: () => playerPayload.playerSourcePayload(),
    setState: _view.setState,
  ));
}
