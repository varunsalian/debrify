import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catchup.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_desktop_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_navigation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_handoff.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_record_now.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_source_counts.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_startup_launch.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_startup_resolution.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_categories.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_guide_context.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_browse.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_payload.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_virtual_results.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_facades.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_maintenance.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_network.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_presentation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_category_order.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_load_status.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_status_state.dart';
import 'package:debrify/features/iptv/application/iptv_layout_policy.dart';
import 'package:debrify/features/iptv/application/iptv_load_status_policy.dart';
import 'package:debrify/features/iptv/application/iptv_rail_resolution.dart';
import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/iptv_stage_chip.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_stage_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_rail_info.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_stage_floor.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_identity.dart';
import 'package:debrify/features/iptv/presentation/spotlight_category_picker_dialog.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/iptv_playlist.dart';
import '../../services/debrify_image_cache.dart';
import '../browse/brand_accent.dart';
import '../browse/browse_results_focus.dart';
import '../browse/browse_search_header.dart';
import '../../services/iptv_channel_order.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_refresh_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_iptv_service.dart';
import '../../services/stremio_service.dart';
import '../../utils/tv_keys.dart' show TvHeldKeyGuard, isActivateOrSpaceKey;
import '../hero_trailer_backdrop.dart';
import '../../theme/app_theme_scope.dart';
import '../see_all/see_all_filter_bar.dart';
import '../see_all/stremio_dropdown.dart';
import '../../services/iptv_epg_service.dart';
import 'db_channel_list.dart';
import 'iptv_centered_selector.dart';
import 'iptv_filters.dart';
import 'iptv_channel_row.dart';
import 'iptv_empty_state.dart';
import 'iptv_epg_panel.dart';
import 'iptv_command_rail.dart';
import 'iptv_stage_panel.dart';
import 'styles/iptv_console_widgets.dart';
import 'styles/iptv_edition_hero.dart';
import 'styles/iptv_style.dart';
import 'spotlight/iptv_spotlight_layout.dart';
import 'spotlight/spotlight_category_control.dart';
import 'spotlight/spotlight_content_type_control.dart';
import 'spotlight/spotlight_live_timeline.dart';
import 'spotlight/spotlight_programme_hero.dart';
import 'spotlight/spotlight_rail.dart';
import 'spotlight/spotlight_shell.dart';
import '../../services/desktop_recording_service.dart';
import '../../services/profiles/profile_preferences.dart';

import '../../services/live_recording_service.dart';









/// Main view for IPTV M3U results, to be embedded in TorrentSearchScreen
class IptvResultsView extends StatefulWidget {
  final String searchQuery;
  final bool isTelevision;
  final Widget? searchHeader;

  /// Test hook fired only after a startup row has reached Spotlight's logical
  /// cursor. Production callers leave this null.
  @visibleForTesting
  final ValueChanged<int>? debugOnSpotlightStartupFocus;

  /// Clock for deterministic Spotlight paint characterization.
  @visibleForTesting
  final DateTime Function() debugSpotlightNow;

  /// Callback when up arrow is pressed from filters (to go back to source dropdown)
  final VoidCallback? onUpArrowFromFilters;

  const IptvResultsView({
    super.key,
    required this.searchQuery,
    this.isTelevision = false,
    this.onUpArrowFromFilters,
    this.searchHeader,
    this.debugOnSpotlightStartupFocus,
    this.debugSpotlightNow = DateTime.now,
  });

  @override
  State<IptvResultsView> createState() => IptvResultsViewState();
}

class IptvResultsViewState extends State<IptvResultsView>
    with WidgetsBindingObserver
    implements
        BrowseResultsFocusController,
        BrowseSearchResultsFocusController {
  late final IptvScheduleActions _scheduleActions = IptvScheduleActions((
    focusState: _focusState,
    recordingState: _recordingState,
    selectionState: _selectionState,
    context: () => context,
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    playCatchup: (IptvChannel channel, EpgProgramme programme) => _catchup.playCatchup(channel, programme),
    recordingResourceFor: (IptvChannel channel) => _recordNow.recordingResourceFor(channel),
    refreshScheduledCount: () => _recordingSupport.refreshScheduledCount(),
    setState: setState,
  ));
  late final IptvRecordingSupport _recordingSupport = IptvRecordingSupport((
    recordingState: _recordingState,
    context: () => context,
    mounted: () => mounted,
    refreshAndroidRecordingState: () => _androidRecording.refreshAndroidRecordingState(),
    setState: setState,
  ));
  late final IptvRecordNow _recordNow = IptvRecordNow((
    recordingState: _recordingState,
    settingsState: _settingsState,
    context: () => context,
    mounted: () => mounted,
    originPlaylistIdFor: (IptvChannel channel) => _favorites.originPlaylistIdFor(channel),
    setState: setState,
    stageRecordingFileName: (String channelName) => _recordingSupport.stageRecordingFileName(channelName),
  ));
  late final IptvPlayback _playback = IptvPlayback((
    catalogState: _catalogState,
    playerState: _playerState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    adoptStartupCategoryValue: (String? group) => _startupResolution.adoptStartupCategoryValue(group),
    context: () => context,
    effectiveCategory: () => _filtersSection.effectiveCategory,
    flushPreviewRearm: () => _previewHandoff.flushPreviewRearm(),
    fullCategoryList: () => _playerPayload.fullCategoryList(),
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    normalizedName: (String value) => IptvStartupResolution.normalizedName(value),
    openSeriesDetail: (IptvChannel channel) => _playbackActions.openSeriesDetail(channel),
    originPlaylistIdFor: (IptvChannel channel) => _favorites.originPlaylistIdFor(channel),
    playerChannelWithOrigin: (IptvChannel channel, IptvPlaylist source) => _playerPayload.playerChannelWithOrigin(channel, source),
    playerListsPayload: () => _playerPayload.playerListsPayload(),
    playerSourcePayload: () => _playerPayload.playerSourcePayload(),
    providePlayerIptvBrowse: (Map<String, dynamic> request) => _playerBrowse.providePlayerIptvBrowse(request),
    refreshAfterPlayback: () => _playbackRefresh.refreshAfterPlayback(),
  ));
  late final IptvStartupLaunch _startupLaunch = IptvStartupLaunch((
    catalogState: _catalogState,
    focusState: _focusState,
    playerState: _playerState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    context: () => context,
    debugOnSpotlightStartupFocus: () => widget.debugOnSpotlightStartupFocus,
    mounted: () => mounted,
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    resolveStartupRow: (Map<String, dynamic> payload, bool Function() cancelled) => _startupResolution.resolveStartupRow(payload, cancelled),
    selectTabletChannel: (int index, IptvChannel channel) => _selectTabletChannel(index, channel),
    setState: setState,
    spotlightRequestedForDevice: () => _spotlightRequestedForDevice,
    spotlightUsesTimeline: () => _spotlightUsesTimeline,
  ));
  late final IptvStartupResolution _startupResolution = IptvStartupResolution((
    catalogState: _catalogState,
    settingsState: _settingsState,
    applyFilters: () => _filtersSection.applyFilters(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    residentDbRow: (({int position, IptvChannel channel}) entry, String url, String name, int? storedNumber) => _playback.residentDbRow(entry, url, name, storedNumber),
    setState: setState,
    startupPlaylistFor: (Map<String, dynamic> payload) => _startupLaunch.startupPlaylistFor(payload),
  ));
  late final IptvCatchup _catchup = IptvCatchup((
    catalogState: _catalogState,
    playerState: _playerState,
    previewState: _previewState,
    selectionState: _selectionState,
    context: () => context,
    flushPreviewRearm: () => _previewHandoff.flushPreviewRearm(),
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    originPlaylistIdFor: (IptvChannel channel) => _favorites.originPlaylistIdFor(channel),
    refreshAfterPlayback: () => _playbackRefresh.refreshAfterPlayback(),
  ));
  late final IptvPlaybackActions _playbackActions = IptvPlaybackActions((
    settingsState: _settingsState,
    clearPreview: () => _clearPreview(),
    context: () => context,
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    originPlaylistIdFor: (IptvChannel channel) => _favorites.originPlaylistIdFor(channel),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    refreshAfterPlayback: () => _playbackRefresh.refreshAfterPlayback(),
  ));
  late final IptvPlaybackRefresh _playbackRefresh = IptvPlaybackRefresh((
    catalogState: _catalogState,
    membershipState: _membershipState,
    recordingState: _recordingState,
    settingsState: _settingsState,
    armAndroidRecStateRefresh: () => _androidRecording.armAndroidRecStateRefresh(),
    customLists: () => _favorites.customLists,
    loadFavorites: () => _favorites.loadFavorites(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    loadProgress: (int ticket, List<IptvChannel> channels) => _virtualResults.loadProgress(ticket, channels),
    mounted: () => mounted,
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    setState: setState,
  ));
  late final IptvPreviewHandoff _previewHandoff = IptvPreviewHandoff((
    playerState: _playerState,
    previewState: _previewState,
    clearPreview: () => _clearPreview(),
    mounted: () => mounted,
    refreshAfterPlayback: () => _playbackRefresh.refreshAfterPlayback(),
    setSpotlightSourcesExpanded: (bool expanded) => _setSpotlightSourcesExpanded(expanded),
  ));
  late final IptvSourceCounts _sourceStatistics = IptvSourceCounts((
    recordingState: _recordingState,
    settingsState: _settingsState,
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvAndroidRecording _androidRecording = IptvAndroidRecording((
    recordingState: _recordingState,
    context: () => context,
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvDesktopRecording _desktopRecording = IptvDesktopRecording((
    context: () => context,
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvNavigation _navigation = IptvNavigation((
    catalogState: _catalogState,
    focusState: _focusState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    context: () => context,
    focusNodeFor: (IptvChannel channel) => _focusNodeFor(channel),
    initRecordingSupport: () => _recordingSupport.initRecordingSupport(),
    loadSettings: ({bool forceReload = false}) => _settingsLoading.loadSettings(forceReload: forceReload),
    mounted: () => mounted,
    refreshAfterHiddenChange: () => _categoryActions.refreshAfterHiddenChange(),
    updateEpgContext: (IptvPlaylist playlist, IptvParseResult result, int ticket, {bool quiet = false}) => _guideContext.updateEpgContext(playlist, result, ticket, quiet: quiet),
  ));

  late final IptvFiltersSection _filtersSection = IptvFiltersSection((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    beginLoadStatus: () => _loadStatus.beginLoadStatus(),
    clearPreview: () => _clearPreview(),
    focusNodeFor: (IptvChannel channel) => _focusNodeFor(channel),
    focusSpotlightContentEntry: () => _focusSpotlightContentEntry(),
    isTelevision: () => widget.isTelevision,
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    searchQuery: () => widget.searchQuery,
    setState: setState,
  ));
  late final IptvGuideContext _guideContext = IptvGuideContext((
    catalogState: _catalogState,
    settingsState: _settingsState,
    statusState: _statusState,
    context: () => context,
    hideChipIfOwned: (ChipOwner owner) => _statusChip.hideChipIfOwned(owner),
    mounted: () => mounted,
    onGuidePhase: (int ticket, int? bytes, int? totalBytes) => _statusChip.onGuidePhase(ticket, bytes, totalBytes),
    setState: setState,
  ));
  late final IptvVirtualResults _virtualResults = IptvVirtualResults((
    catalogState: _catalogState,
    membershipState: _membershipState,
    applyFilters: () => _filtersSection.applyFilters(),
    consumeContentFocusRequest: () => _filtersSection.consumeContentFocusRequest(),
    endLoadStatus: () => _loadStatus.endLoadStatus(),
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvCategories _categoryActions = IptvCategories((
    catalogState: _catalogState,
    applyFilters: () => _filtersSection.applyFilters(),
    categoryCounts: () => _categoryCounts,
    context: () => context,
    deriveCategories: (CatalogSnapshot snap, List<CatalogGroup> groups) => _catalogPresentation.deriveCategories(snap, groups),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    setState: setState,
    showChip: (CatalogChipState state, String message, {Duration? autoHide, ChipOwner owner = ChipOwner.refresh}) => _statusChip.showChip(state, message, autoHide: autoHide, owner: owner),
  ));
  late final IptvPlayerPayload _playerPayload = IptvPlayerPayload((
    catalogState: _catalogState,
    membershipState: _membershipState,
    settingsState: _settingsState,
    withoutHidden: (String catalogKey, List<String> categories) => _catalogPresentation.withoutHidden(catalogKey, categories),
  ));
  late final IptvPlayerBrowse _playerBrowse = IptvPlayerBrowse((
    catalogState: _catalogState,
    playerState: _playerState,
    settingsState: _settingsState,
    fullCategoryList: () => _playerPayload.fullCategoryList(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => mounted,
    playerChannelPayload: (List<({IptvChannel channel, IptvPlaylist source})> entries) => _playerPayload.playerChannelPayload(entries),
    playerSourcePayload: () => _playerPayload.playerSourcePayload(),
    setState: setState,
  ));

  late final IptvFavorites _favorites = IptvFavorites((
    catalogState: _catalogState,
    membershipState: _membershipState,
    settingsState: _settingsState,
    context: () => context,
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => mounted,
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    refreshListShelfPresence: () => _playbackRefresh.refreshListShelfPresence(),
    setState: setState,
  ));
  late final IptvSettingsLoading _settingsLoading = IptvSettingsLoading((
    catalogState: _catalogState,
    membershipState: _membershipState,
    previewState: _previewState,
    recordingState: _recordingState,
    settingsState: _settingsState,
    listPlaylist: (IptvListMeta list) => IptvFavorites.listPlaylist(list),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) => _catalogLoading.loadPlaylist(playlist, userRequested: userRequested),
    mounted: () => mounted,
    retunePreview: (IptvChannel channel) => _retunePreview(channel),
    setState: setState,
    stopPreviewPlayback: () => _stopPreviewPlayback(),
  ));
  late final IptvCatalogLoading _catalogLoading = IptvCatalogLoading((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    statusState: _statusState,
    applyProgressiveBatch: (int ticket, List<IptvChannel> channels, List<String> categories) => _virtualResults.applyProgressiveBatch(ticket, channels, categories),
    beginLoadStatus: () => _loadStatus.beginLoadStatus(),
    buildContinueResult: () => _virtualResults.buildContinueResult(),
    buildListResult: (String listId) => _virtualResults.buildListResult(listId),
    clearPreview: () => _clearPreview(),
    consumeContentFocusRequest: () => _filtersSection.consumeContentFocusRequest(),
    endLoadStatus: () => _loadStatus.endLoadStatus(),
    fetchCatalogFromNetwork: (IptvPlaylist playlist, String contentType, int ticket) => _catalogNetwork.fetchCatalogFromNetwork(playlist, contentType, ticket),
    mounted: () => mounted,
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) => _loadStatus.onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes),
    presentCatalog: (IptvPlaylist playlist, int ticket, IptvParseResult result, {bool migrateFavorites = true, String? cacheKey}) => _catalogPresentation.presentCatalog(playlist, ticket, result, migrateFavorites: migrateFavorites, cacheKey: cacheKey),
    presentDbCatalog: (IptvPlaylist playlist, int ticket, CatalogSnapshot snap, {String? warning, bool migrateFavorites = false}) => _catalogPresentation.presentDbCatalog(playlist, ticket, snap, warning: warning, migrateFavorites: migrateFavorites),
    runCatalogMaintenance: (IptvPlaylist playlist, String contentType, String cacheKey, int ticket, {required bool userRequested}) => _catalogMaintenance.runCatalogMaintenance(playlist, contentType, cacheKey, ticket, userRequested: userRequested),
    runPendingMigrations: (String cacheKey, int ticket) => _catalogMaintenance.runPendingMigrations(cacheKey, ticket),
    setState: setState,
  ));
  late final IptvCatalogPresentation _catalogPresentation = IptvCatalogPresentation((
    catalogState: _catalogState,
    applyFilters: () => _filtersSection.applyFilters(),
    consumeContentFocusRequest: () => _filtersSection.consumeContentFocusRequest(),
    context: () => context,
    endLoadStatus: () => _loadStatus.endLoadStatus(),
    landingCategory: (String? orderKey, List<String> categories) => _filtersSection.landingCategory(orderKey, categories),
    loadFavorites: () => _favorites.loadFavorites(),
    loadProgress: (int ticket, List<IptvChannel> channels) => _virtualResults.loadProgress(ticket, channels),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    recomputeSourceCounts: () => _sourceStatistics.recomputeSourceCounts(),
    setState: setState,
    updateEpgContext: (IptvPlaylist playlist, IptvParseResult result, int ticket, {bool quiet = false}) => _guideContext.updateEpgContext(playlist, result, ticket, quiet: quiet),
  ));
  late final IptvCatalogFacades _catalogFacades = IptvCatalogFacades((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    settingsState: _settingsState,
    applyFilters: () => _filtersSection.applyFilters(),
    mounted: () => mounted,
    setState: setState,
  ));
  late final IptvCatalogMaintenance _catalogMaintenance = IptvCatalogMaintenance((
    catalogState: _catalogState,
    finishMaintenanceChip: ({required bool narrate, required bool numbersMoved}) => _statusChip.finishMaintenanceChip(narrate: narrate, numbersMoved: numbersMoved),
    mounted: () => mounted,
    rebuildDbFacades: (CatalogSnapshot snap) => _catalogFacades.rebuildDbFacades(snap),
    revalidateDbCatalog: (IptvPlaylist playlist, String contentType, String cacheKey, int ticket) => _catalogRefresh.revalidateDbCatalog(playlist, contentType, cacheKey, ticket),
    revalidateSuperseded: (IptvPlaylist playlist, String contentType, int ticket) => _catalogFacades.revalidateSuperseded(playlist, contentType, ticket),
    scheduleMaintenanceChip: (int ticket) => _statusChip.scheduleMaintenanceChip(ticket),
  ));
  late final IptvStatusChip _statusChip = IptvStatusChip((
    catalogState: _catalogState,
    statusState: _statusState,
    mounted: () => mounted,
    recomputeSourceCounts: () => _sourceStatistics.recomputeSourceCounts(),
    setState: setState,
  ));
  late final IptvCatalogRefresh _catalogRefresh = IptvCatalogRefresh((
    catalogState: _catalogState,
    focusState: _focusState,
    settingsState: _settingsState,
    statusState: _statusState,
    applyFilters: () => _filtersSection.applyFilters(),
    deriveCategories: (CatalogSnapshot snap, List<CatalogGroup> groups) => _catalogPresentation.deriveCategories(snap, groups),
    loadFavorites: () => _favorites.loadFavorites(),
    makeDbList: (CatalogSnapshot snap, {String? group, String? search}) => _catalogFacades.makeDbList(snap, group: group, search: search),
    mounted: () => mounted,
    presentCatalog: (IptvPlaylist playlist, int ticket, IptvParseResult result, {bool migrateFavorites = true, String? cacheKey}) => _catalogPresentation.presentCatalog(playlist, ticket, result, migrateFavorites: migrateFavorites, cacheKey: cacheKey),
    revalidateSuperseded: (IptvPlaylist playlist, String contentType, int ticket) => _catalogFacades.revalidateSuperseded(playlist, contentType, ticket),
    rowAttached: (IptvChannel channel) => _rowAttached(channel),
    setState: setState,
    showChip: (CatalogChipState state, String message, {Duration? autoHide, ChipOwner owner = ChipOwner.refresh}) => _statusChip.showChip(state, message, autoHide: autoHide, owner: owner),
    updateEpgContext: (IptvPlaylist playlist, IptvParseResult result, int ticket, {bool quiet = false}) => _guideContext.updateEpgContext(playlist, result, ticket, quiet: quiet),
  ));
  late final IptvCatalogNetwork _catalogNetwork = IptvCatalogNetwork((
    catalogState: _catalogState,
    settingsState: _settingsState,
    mounted: () => mounted,
    onLoadPhase: (int ticket, String phase, {int? bytes, int? totalBytes}) => _loadStatus.onLoadPhase(ticket, phase, bytes: bytes, totalBytes: totalBytes),
  ));
  late final IptvLoadStatus _loadStatus = IptvLoadStatus((
    catalogState: _catalogState,
    statusState: _statusState,
    context: () => context,
    mounted: () => mounted,
    setState: setState,
  ));

  final _catalogState = IptvCatalogState();
  final _focusState = IptvFocusState();
  final _membershipState = IptvMembershipState();
  final _playerState = IptvPlayerState();
  final _previewState = IptvPreviewState();
  final _recordingState = IptvRecordingState();
  final _selectionState = IptvSelectionState();
  final _settingsState = IptvSettingsState();
  final _statusState = IptvStatusState();




  // ---- Startup channel -----------------------------------------------------
  // Grid metrics, published from the LayoutBuilder so the startup launch can
  // scroll to a not-yet-built row.







  // Playlists and settings


  // ---- Command Center (rail + stage cockpit) ------------------------------





















  bool get _spotlightRequestedForDevice =>
      _settingsState.iptvStyle == IptvStyle.spotlight && (widget.isTelevision || IptvSettingsState.isDesktop);

  static const double tabletTwoPaneMinWidth = IptvLayoutPolicy.tabletTwoPaneMinWidth;
  static const double tabletTwoPaneMinHeight = IptvLayoutPolicy.tabletTwoPaneMinHeight;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) => IptvLayoutPolicy.shouldUseTouchTabletTwoPane(isTelevision: isTelevision, isWeb: isWeb, platform: platform, availableSize: availableSize);

  /// Mount the parent-owned Browse search field in the shipped position. The
  /// Spotlight shell takes the same widget as a rail slot instead, so each
  /// build mounts exactly one instance while BrowseScreen retains its query,
  /// controller, IME and TV focus-handoff state.
  Widget _withBrowseSearch(Widget child) {
    final search = widget.searchHeader;
    if (search == null) return child;
    return Column(
      children: [
        search,
        Expanded(child: child),
      ],
    );
  }

  // Current playlist data





  // Search spans the current source; retain the browse category for clearing.


















  // Content type for Xtream Codes playlists


  // Loading state



  // Background catalog refresh (stale-while-revalidate) status chip.
  // `updating` appears only when the revalidate is genuinely slow (a real
  // network fetch), so instant in-memory-cache revalidates never flash it.


  // ── Blocking-load status ────────────────────────────────────────────────
  // A first load of a big panel is several seconds behind a spinner, and
  // silence reads as "frozen". These carry what is happening plus a real
  // number when one exists.
  //
  // Deliberately NOT setState-ed per update: byte callbacks fire per network
  // chunk, and repainting on each would be exactly the UI-isolate churn this
  // page has spent so long shedding. They are plain fields, and [_loadTicker]
  // repaints once a second — which also makes the elapsed clock tick.













  // Progressive (Stremio-addon) loads: [_loadTicket] orphans a superseded
  // load's batches AND its final result, and doubles as the cancel signal
  // that stops its catalog walk; [_isLoadingMore] is true from the first
  // streamed batch until the walk completes — every "N channels" readout and
  // empty state must stay honest while it's set (the list is still growing,
  // so a search can have matches on the way).








  // Favorites — the built-in list, kept as its own set because every row's
  // star icon reads it on each build.


















  /// Whether the current view shows on-demand items, which are drawn as 2:3
  /// posters in taller rows. Derived from the selected view rather than by
  /// scanning the channels: the grid needs one answer for every tile, and
  /// scanning tens of thousands of rows per build to get it isn't free.
  ///
  /// M3U playlists keep the logo layout even for their VOD entries — their
  /// content type is a duration heuristic, so a mixed playlist has no single
  /// honest answer here.
  bool get _showsPosterRows {
    final playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return false;
    if (playlist.isContinueWatching) return true;
    if (playlist.isXtreamCodes) {
      return _catalogState.selectedContentType == 'vod' || _catalogState.selectedContentType == 'series';
    }
    return false;
  }



  // Focus nodes for DPAD
















  Map<String, int> get _categoryCounts {
    // Counts come from one GROUP BY at present time — scanning the
    // facade here would page through the whole catalog.
    if (_catalogState.dbSnapshot != null) return _catalogState.dbGroupCounts;
    if (!identical(_catalogState.categoryCountsSource, _catalogState.allChannels) ||
        _catalogState.categoryCountsLength != _catalogState.allChannels.length) {
      final counts = <String, int>{};
      for (final channel in _catalogState.allChannels) {
        final group = channel.group;
        if (group != null && group.isNotEmpty) {
          counts[group] = (counts[group] ?? 0) + 1;
        }
      }
      _catalogState.categoryCountsSource = _catalogState.allChannels;
      _catalogState.categoryCountsLength = _catalogState.allChannels.length;
      _catalogState.categoryCountsCache = counts;
    }
    return _catalogState.categoryCountsCache;
  }

  /// Whether the current list draws EPG rows (now/next inside each row).
  /// Poster lists never do; otherwise sampled from the first few channels —
  /// Xtream capability is homogeneous (URL parse), but XMLTV matching is
  /// per-channel, and a single unmatched channel at position 0 must not veto
  /// the whole list. Rows without data fall back gracefully; the grid needs
  /// one tile height for everything either way.
  bool get _epgRowsActive {
    if (_showsPosterRows) return false;
    final channels = _catalogState.filteredChannels;
    if (channels.isEmpty) return false;
    final sample = channels.length < 10 ? channels.length : 10;
    for (var i = 0; i < sample; i++) {
      if (IptvEpgService.isEpgCapable(channels[i])) return true;
    }
    return false;
  }

  // TV preview stage (the two-pane layout's left rail). Notifiers, not
  // setState: a DPAD move over the channel list must repaint the rail alone,
  // never rebuild the whole grid. [_previewShown] is the focused channel;
  // [_previewShowing] flips when the embedded player actually has frames;
  // [_previewEpoch] bumps after returning from real playback so the stage
  // remounts fresh (HeroTrailerBackdrop latches itself off for the rest of a
  // page visit once real content playback launches — a new instance is the
  // supported way to re-arm it).





  // The URL the preview stage actually plays. For M3U/Xtream channels this is
  // just the channel URL; for Stremio-addon channels it is the current rung of
  // the candidate ladder (resolved async on focus, advanced by
  // [_onPreviewPlaybackFailed] until one plays or the list runs out). Null =
  // nothing to play, the stage shows only its static floor.





  // Keyed by channel INSTANCE rather than list position (focus survives
  // category/search filtering, which reuses the same objects) — and rather
  // than URL: playlists routinely list one stream URL under several names,
  // and a URL key would hand those rows a single shared FocusNode, lighting
  // them all up together and scrambling DPAD traversal around the pair.
  // Instances are stable for a playlist's whole life (progressive Stremio
  // batches append to one list; filters select from it), and the map is
  // rebuilt with the instances on every _loadPlaylist.




  void _onRowDetached(IptvChannel channel) {
    _focusState.detachedRows.add(channel);
  }

  FocusNode _focusNodeFor(IptvChannel channel) {
    // Being asked for the node means the row is being (re)built right now.
    _focusState.detachedRows.remove(channel);
    return _focusState.cardFocusNodes.putIfAbsent(
      channel,
      () => FocusNode(debugLabel: 'iptv-card-${channel.name}-${channel.url}'),
    );
  }

  /// Whether [channel]'s row is currently built (its node attached). Nodes
  /// with no map entry count as detached.
  bool _rowAttached(IptvChannel channel) =>
      _focusState.cardFocusNodes.containsKey(channel) && !_focusState.detachedRows.contains(channel);

















  @override
  void initState() {
    super.initState();
    if (widget.isTelevision) {
      // Lifecycle observer completes the parked preview re-arm when the app
      // returns from the native player (see _playChannel); the sidebar
      // listener stops the preview while the menu overlay is open.
      WidgetsBinding.instance.addObserver(this);
      MainPageBridge.addTvSidebarFocusListener(_previewHandoff.onTvSidebarFocusChanged);
    }
    // Virtual Stremio playlists come and go with the installed addon set.
    StremioService.instance.addAddonsChangedListener(_settingsLoading.onStremioAddonsChanged);
    IptvChannelOrderSignal.revision.addListener(_filtersSection.onChannelOrderChanged);
    IptvCatalogRefreshService.instance.revision.addListener(
      _catalogRefresh.onCatalogRefreshed,
    );
    // Chained, not fire-and-forget: the startup launch needs the playlist list
    // to exist before it can pick the target's provider.
    // Guarded on the error too, not just mounted: _loadSettings now SWALLOWS
    // its failures (it renders them instead), so this callback runs on a path
    // that used to skip it entirely. _maybeRunStartupLaunch consumes the
    // one-shot startup payload, and burning it against an empty playlist set
    // would cancel a boot-to-channel request that Retry could still honour.
    _settingsLoading.loadSettings().then((_) {
      if (mounted && _settingsState.settingsError == null) {
        unawaited(_startupLaunch.maybeRunStartupLaunch());
      }
    });
    _favorites.loadFavorites();
    // Stage cockpit: recording availability + the rail's Scheduled badge.
    // Off the critical path; only ever ENABLES affordances.
    unawaited(_recordingSupport.initRecordingSupport());
    if (!kIsWeb && Platform.isIOS) {
      unawaited(
        DevicePreferences.instance().then((prefs) {
          if (!mounted) return;
          if (!(prefs.getBool(IptvSettingsState.iosNoticeDismissedPref) ?? false)) {
            setState(() => _settingsState.showIosRecordingNotice = true);
          }
        }),
      );
    }
    // Observe, don't sample: schedule mutations from ANY in-process surface
    // (player sheet, manual timer, desktop scheduler firing) update the rail
    // badge, and desktop capture starts/ends flip the stage's Record↔Stop —
    // including a SCHEDULED capture starting while focus parks on its channel.
    LiveRecordingService.schedulesRevision.addListener(_recordingSupport.onSchedulesChanged);
    DesktopRecordingService.instance.revision.addListener(
      _recordingSupport.onDesktopRecordingChanged,
    );
  }





























  @override
  void didUpdateWidget(IptvResultsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Search filter when query changes. Debounced: the field live-filters on
    // every keystroke, and re-scanning a 10k-channel playlist per keypress is
    // what made typing janky. Clearing applies immediately so backing out of
    // a search feels instant.
    if (widget.searchQuery != _selectionState.lastSearchQuery) {
      _selectionState.lastSearchQuery = widget.searchQuery;
      _selectionState.searchDebounce?.cancel();
      if (widget.searchQuery.isEmpty) {
        _filtersSection.applyFilters();
      } else {
        _selectionState.searchDebounce = Timer(const Duration(milliseconds: 220), () {
          if (mounted) _filtersSection.applyFilters();
        });
      }
    }
  }



  @override
  void dispose() {
    IptvCatalogRefreshService.instance.revision.removeListener(
      _catalogRefresh.onCatalogRefreshed,
    );
    _recordingState.sourceCountsDebounce?.cancel();
    _recordingState.androidRecStateDebounce?.cancel();
    LiveRecordingService.schedulesRevision.removeListener(_recordingSupport.onSchedulesChanged);
    DesktopRecordingService.instance.revision.removeListener(
      _recordingSupport.onDesktopRecordingChanged,
    );
    if (widget.isTelevision) {
      WidgetsBinding.instance.removeObserver(this);
      MainPageBridge.removeTvSidebarFocusListener(_previewHandoff.onTvSidebarFocusChanged);
    }
    StremioService.instance.removeAddonsChangedListener(
      _settingsLoading.onStremioAddonsChanged,
    );
    IptvChannelOrderSignal.revision.removeListener(_filtersSection.onChannelOrderChanged);
    _selectionState.searchDebounce?.cancel();
    _selectionState.contentTypeDebounce?.cancel();
    _statusState.loadTicker?.cancel();
    _statusState.maintenanceChipTimer?.cancel();
    _statusState.chipShowTimer?.cancel();
    _statusState.chipHideTimer?.cancel();
    _focusState.scrollController.dispose();
    _focusState.playlistFilterFocusNode.dispose();
    _focusState.categoryFilterFocusNode.dispose();
    _focusState.contentTypeFocusNode.dispose();
    _focusState.spotlightCategoryOptionsFocusNode.dispose();
    _focusState.spotlightPrimaryFocusNode.dispose();
    _focusState.spotlightRailScope.dispose();
    _focusState.spotlightHeroScope.dispose();
    _previewState.previewShown.dispose();
    _previewState.spotlightProgrammeShown.dispose();
    _previewState.previewShowing.dispose();
    _previewState.previewEpoch.dispose();
    _previewState.previewStreamUrl.dispose();
    for (final node in _focusState.cardFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }









  /// Local files bypass the catalog-backed load path, but their category-list
  /// order intentionally lives in the same profile-scoped database. Opening it
  /// here makes cold loads and the first load after a profile switch reliable.
  /// The database is optional for playback: if its cache cannot be opened, the
  /// provider order is returned and the local playlist still renders.
  @visibleForTesting
  static Future<List<String>> applyStoredLocalCategoryOrder(
    String playlistId,
    Iterable<String> categories,
  ) => IptvCategoryOrder.applyStoredLocalCategoryOrder(playlistId, categories);





















































  @visibleForTesting
  static String formatLoadBytes(int bytes) => IptvLoadStatusPolicy.formatLoadBytes(bytes);

  @visibleForTesting
  static String formatLoadElapsed(Duration d) => IptvLoadStatusPolicy.formatLoadElapsed(d);

  /// "12.4 / 50.0 MB" when the transfer is observable, "42.1 MB" when only the
  /// landed size is known, null when there is no honest number to show — a
  /// buffered fetch that has not landed yet must not imply progress it cannot
  /// measure.
  @visibleForTesting
  static String? loadBytesLabel(int? bytes, int? totalBytes) => IptvLoadStatusPolicy.loadBytesLabel(bytes, totalBytes);



  /// Whether a stage owning [incoming] may take the chip from [current].
  /// Pure, so the priority rule is testable without pumping the page.
  @visibleForTesting
  static bool chipClaimAllowed(int current, int incoming) => IptvLoadStatusPolicy.chipClaimAllowed(current, incoming);

  /// Priority ranks, exposed for the same reason.
  @visibleForTesting
  static int get chipRankNone => IptvLoadStatusPolicy.chipRankNone;
  @visibleForTesting
  static int get chipRankGuide => IptvLoadStatusPolicy.chipRankGuide;
  @visibleForTesting
  static int get chipRankMaintenance => IptvLoadStatusPolicy.chipRankMaintenance;
  @visibleForTesting
  static int get chipRankRefresh => IptvLoadStatusPolicy.chipRankRefresh;































  /// Pure decision behind [_landingCategory], split out for tests.
  @visibleForTesting
  static String? landingCategoryFor({
    required String? orderKey,
    required List<String> categories,
    required bool manuallyChosen,
    required bool searching,
  }) => IptvLandingPolicy.landingCategoryFor(orderKey: orderKey, categories: categories, manuallyChosen: manuallyChosen, searching: searching);

































  // ==========================================================================
  // Startup channel — boot straight into a live channel
  //
  // Runs against the MOUNTED page rather than as a headless launcher: the
  // player's launch payload includes `iptvBrowseProvider`, a closure into this
  // state, and without it a launched channel plays but cannot zap.
  // ==========================================================================













































  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _previewHandoff.flushPreviewRearm();
      // Android schedules fire NATIVELY (alarm → service) — no in-process
      // revision bump can see that. Coming back to the foreground is the
      // one reliable moment to reconcile the rail's Scheduled badge and the
      // stage's Record↔Stop state.
      unawaited(_recordingSupport.refreshScheduledCount());
      unawaited(_androidRecording.refreshAndroidRecordingState());
    }
  }












































  /// Focus the first filter (for DPAD navigation from search input)
  @override
  void focusFirstFilter() {
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _focusSpotlightSources();
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  @override
  void focusSearchResults() {
    if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic) {
      _focusSpotlightSearchResults();
    } else {
      focusFirstFilter();
    }
  }



  /// Refresh playlists from storage (call after settings change)
  Future<void> refreshPlaylists() async {
    await _settingsLoading.loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsState.settingsLoaded) {
      final settingsError = _settingsState.settingsError;
      if (settingsError == null) {
        return _withBrowseSearch(
          const Center(child: CircularProgressIndicator()),
        );
      }
      return _withBrowseSearch(
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Could not open IPTV',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  settingsError,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () {
                    setState(() => _settingsState.settingsError = null);
                    unawaited(_settingsLoading.loadSettings(forceReload: true));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Spotlight owns the full canvas because its search lives inside the
    // source rail. Legacy layouts mount search above their body, so their
    // breakpoints must be evaluated by the inner LayoutBuilder after that
    // header has taken its height.
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final outerSize = Size(
          outerConstraints.maxWidth,
          outerConstraints.maxHeight,
        );
        final spotlightRequested = _spotlightRequestedForDevice;
        final spotlightMode = spotlightRequested
            ? resolveIptvSpotlightLayout(outerSize)
            : IptvSpotlightLayoutMode.classic;
        if (spotlightMode != IptvSpotlightLayoutMode.classic) {
          return _buildLoadedLayout(
            outerConstraints,
            spotlightRequested: spotlightRequested,
            spotlightMode: spotlightMode,
          );
        }
        return _withBrowseSearch(
          LayoutBuilder(
            builder: (context, bodyConstraints) => _buildLoadedLayout(
              bodyConstraints,
              spotlightRequested: spotlightRequested,
              spotlightMode: IptvSpotlightLayoutMode.classic,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadedLayout(
    BoxConstraints constraints, {
    required bool spotlightRequested,
    required IptvSpotlightLayoutMode spotlightMode,
  }) {
    final availableSize = Size(constraints.maxWidth, constraints.maxHeight);
    final touchTablet = shouldUseTouchTabletTwoPane(
      isTelevision: widget.isTelevision,
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
      availableSize: availableSize,
    );
    final twoPaneEligible = widget.isTelevision || IptvSettingsState.isDesktop || touchTablet;
    final spotlightActive = spotlightMode != IptvSpotlightLayoutMode.classic;
    // Spotlight deliberately falls back to the useful single-pane page below
    // its minimum height. Do not route that saved preference into the old
    // two-pane cockpit with Spotlight colours.
    final spotlightFallback = spotlightRequested && !spotlightActive;
    final regularTwoPane =
        !spotlightFallback &&
        twoPaneEligible &&
        constraints.maxWidth >= 760 &&
        constraints.maxHeight >= 380;
    final twoPane = spotlightActive || regularTwoPane;
    final touchTwoPane = regularTwoPane && touchTablet && !spotlightActive;

    if (twoPane != _selectionState.tvTwoPaneActive ||
        touchTwoPane != _selectionState.touchTabletTwoPaneActive ||
        spotlightMode != _selectionState.spotlightLayoutMode) {
      // Never write state synchronously from the layout phase: playback and
      // schedule callbacks consult these flags. One post-frame of lag can only
      // occur while the window is actively changing size.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final wasTouchTablet = _selectionState.touchTabletTwoPaneActive;
        _selectionState.tvTwoPaneActive = twoPane;
        _selectionState.touchTabletTwoPaneActive = touchTwoPane;
        _selectionState.spotlightLayoutMode = spotlightMode;
        if (!twoPane && wasTouchTablet && _selectionState.scheduleChannel != null && mounted) {
          setState(() => _selectionState.scheduleChannel = null);
        }
      });
    }

    final Widget body = spotlightActive
        ? _buildSpotlight(constraints, spotlightMode)
        : !regularTwoPane
        ? _buildClassic()
        : _buildTvTwoPane(constraints, touchSelector: touchTablet);

    // The background-refresh chip floats over whichever layout is active.
    // Stack stays paint-neutral for the native preview underlay.
    final Widget page = _settingsState.showIosRecordingNotice
        ? Column(
            children: [
              _buildIosRecordingNotice(),
              Expanded(child: body),
            ],
          )
        : body;
    return Stack(
      fit: StackFit.passthrough,
      children: [page, _buildCatalogChip()],
    );
  }

  /// The iOS-only "no recording here" banner: dismiss is remembered forever.
  Widget _buildIosRecordingNotice() {
    final app = AppThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 2, 8),
      decoration: BoxDecoration(
        color: app.iptv.surfaceTint,
        borderRadius: app.shape.br(10),
        border: Border.all(color: app.iptv.hairline),
      ),
      child: Row(
        children: [
          Icon(
            Icons.fiber_manual_record_rounded,
            size: 14,
            color: app.core.tx.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "Recording isn't available on iOS — Apple doesn't let "
              'apps capture streams in the background.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: app.iptv.inkDim,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Dismiss',
            icon: Icon(
              Icons.close_rounded,
              size: 16,
              color: app.core.tx.withValues(alpha: 0.45),
            ),
            onPressed: _dismissIosRecordingNotice,
          ),
        ],
      ),
    );
  }

  void _dismissIosRecordingNotice() {
    setState(() => _settingsState.showIosRecordingNotice = false);
    unawaited(
      DevicePreferences.instance().then(
        (prefs) => prefs.setBool(IptvSettingsState.iosNoticeDismissedPref, true),
      ),
    );
  }

  /// Bottom-right status chip for background catalog refreshes. Pure
  /// display: no focusables, no hit-testing — DPAD and touch pass straight
  /// through. Snap show/hide, no tween (TV GPU rule).
  Widget _buildCatalogChip() {
    final app = AppThemeScope.of(context);
    if (_statusState.chipState == CatalogChipState.hidden) {
      return const SizedBox.shrink();
    }
    final Widget leading = switch (_statusState.chipState) {
      CatalogChipState.updating => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: app.seeAll.accent2,
        ),
      ),
      CatalogChipState.success => const Icon(
        Icons.check_circle_rounded,
        size: 15,
        color: Color(0xFF4ADE80),
      ),
      CatalogChipState.failure => const Icon(
        Icons.cloud_off_rounded,
        size: 15,
        color: Color(0xFFFBBF24),
      ),
      CatalogChipState.hidden => const SizedBox.shrink(),
    };
    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: app.iptv.chipSurface,
            borderRadius: app.shape.br(22),
            border: Border.all(color: app.core.tx.withValues(alpha: 0.10)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              leading,
              const SizedBox(width: 8),
              Text(
                _statusState.chipMessage,
                style: TextStyle(
                  fontSize: 12.5,
                  color: app.core.tx.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Spotlight Guide ───────────────────────────────────────────────────────

  Widget _buildSpotlight(
    BoxConstraints constraints,
    IptvSpotlightLayoutMode mode,
  ) {
    final selected = _settingsState.selectedPlaylist;
    return SpotlightShell(
      mode: mode,
      searchSlot: _buildSpotlightSearch(mode),
      sourcesWrapper: (child) => FocusScope(
        node: _focusState.spotlightRailScope,
        onFocusChange: (focused) {
          // Dialogs opened from the drawer temporarily own focus. Keep the
          // search available for their return instead of hiding its field.
          if (!focused && ModalRoute.of(context)?.isCurrent != false) {
            _setSpotlightSourcesExpanded(false);
          }
        },
        onKeyEvent: (_, event) {
          if (!widget.isTelevision &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (event is KeyDownEvent) _closeSpotlightSources();
            return KeyEventResult.handled;
          }

          // MainPage's automatic sidebar fallback deliberately excludes
          // nested scopes. This persistent rail must exit explicitly on TV.
          if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
              event.logicalKey == LogicalKeyboardKey.arrowLeft &&
              widget.isTelevision &&
              MainPageBridge.focusTvSidebar != null) {
            if (event is KeyDownEvent) _exitSpotlightSourcesToApp();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
      railSlot: _buildSpotlightRail(
        collapsed:
            mode == IptvSpotlightLayoutMode.wide && !_selectionState.spotlightSourcesExpanded,
      ),
      categorySlot: _spotlightControlNavigation(
        SpotlightCategoryControl(
          dense: true,
          categoryLabel: _filtersSection.effectiveCategory ?? 'All channels',
          channelCount: _catalogState.filteredChannels.length,
          loading: _catalogState.isLoading,
          onPressed: _showSpotlightCategoryPicker,
          focusNode: _focusState.categoryFilterFocusNode,
          optionsFocusNode: _focusState.spotlightCategoryOptionsFocusNode,
          onOpenOptions: _categoryActions.canShowCategoryOptions && _filtersSection.effectiveCategory != null
              ? () => unawaited(_categoryActions.promptCategoryOptions(_catalogState.selectedCategory!))
              : null,
        ),
      ),
      contentTypeSlot: selected?.isXtreamCodes ?? false
          ? _spotlightControlNavigation(
              SpotlightContentTypeControl(
                dense: true,
                value: _catalogState.selectedContentType,
                onChanged: _filtersSection.onContentTypeChanged,
                firstItemFocusNode: _focusState.contentTypeFocusNode,
              ),
            )
          : null,
      heroSlot: FocusScope(
        node: _focusState.spotlightHeroScope,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final direction = switch (event.logicalKey) {
            LogicalKeyboardKey.arrowUp => TraversalDirection.up,
            LogicalKeyboardKey.arrowDown => TraversalDirection.down,
            LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
            LogicalKeyboardKey.arrowRight => TraversalDirection.right,
            _ => null,
          };
          if (direction == null) return KeyEventResult.ignored;
          // Traverse all action rows before leaving the hero. Its scope
          // confines spatial traversal to these buttons, including Wrap rows.
          final primary = FocusManager.instance.primaryFocus;
          if (primary != null && primary.focusInDirection(direction)) {
            return KeyEventResult.handled;
          }
          switch (direction) {
            case TraversalDirection.down:
              _focusState.categoryFilterFocusNode.requestFocus();
            case TraversalDirection.up:
              _focusSpotlightSearchOrExit();
            case TraversalDirection.left:
              _focusSpotlightSources();
            case TraversalDirection.right:
              break;
          }
          return KeyEventResult.handled;
        },
        child: _buildSpotlightHero(mode),
      ),
      contentSlot: _buildSpotlightContent(mode),
      onOpenSources: _showSpotlightSources,
      sourcesExpanded: _selectionState.spotlightSourcesExpanded,
      onToggleSources: () {
        if (_selectionState.spotlightSourcesExpanded) {
          _closeSpotlightSources();
        } else {
          _focusSpotlightSources();
        }
      },
      onCloseSources: _closeSpotlightSources,
      onExitSourcesLeft: _exitSpotlightSourcesToApp,
      onOpenSearch: _openSpotlightSearch,
      compactSourceLabel: selected?.name ?? 'Sources',
      compactSourceCount: _spotlightSelectedSourceCount,
      compactSourceFocusNode: _focusState.playlistFilterFocusNode,
      onSourceDown: _focusSpotlightHero,
      railWidth: 244,
      padding: EdgeInsets.all(mode == IptvSpotlightLayoutMode.wide ? 10 : 8),
    );
  }

  void _setSpotlightSourcesExpanded(bool expanded) {
    if (!mounted || _selectionState.spotlightSourcesExpanded == expanded) return;
    setState(() => _selectionState.spotlightSourcesExpanded = expanded);
  }

  void _closeSpotlightSources() {
    _setSpotlightSourcesExpanded(false);
    _focusSpotlightContentEntry();
  }

  void _exitSpotlightSourcesToApp() {
    final focusSidebar = MainPageBridge.focusTvSidebar;
    if (!widget.isTelevision || focusSidebar == null) return;
    _setSpotlightSourcesExpanded(false);
    focusSidebar();
  }

  void _focusSpotlightSources() {
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _setSpotlightSourcesExpanded(true);
      final remembered = _focusState.spotlightRailScope.focusedChild;
      // A search field hidden by the collapsed drawer cannot receive focus.
      // Enter on the first source instead of leaving focus on an empty scope.
      if (remembered != null &&
          remembered is! FocusScopeNode &&
          remembered.canRequestFocus) {
        _focusState.spotlightRailScope.requestFocus();
      } else {
        _focusState.playlistFilterFocusNode.requestFocus();
      }
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  void _focusSpotlightHero() {
    if (_focusState.spotlightPrimaryFocusNode.context != null) {
      _focusState.spotlightPrimaryFocusNode.requestFocus();
    } else {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  Widget _spotlightControlNavigation(Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp) {
        if (_focusState.spotlightPrimaryFocusNode.context != null) {
          _focusState.spotlightPrimaryFocusNode.requestFocus();
        } else {
          _focusSpotlightSearchOrExit();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        if (_selectionState.scheduleChannel == null &&
            !_focusState.spotlightTimelineController.restoreFocus()) {
          _navigation.focusFirstChannel();
        }
        return _selectionState.scheduleChannel == null
            ? KeyEventResult.handled
            : KeyEventResult.ignored;
      }
      if (key == LogicalKeyboardKey.arrowLeft &&
          (_focusState.contentTypeFocusNode.hasFocus ||
              (!(_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
                  _focusState.categoryFilterFocusNode.hasFocus))) {
        _focusSpotlightSources();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );

  Widget _buildSpotlightSearch(IptvSpotlightLayoutMode mode) {
    final search = widget.searchHeader;
    if (search == null) return const SizedBox.shrink();
    if (search is! BrowseSearchHeader) return search;
    final t = IptvStyleTokens.spotlight;
    return BrowseSearchHeader(
      key: search.key,
      controller: search.controller,
      focusNode: search.focusNode,
      hintText: mode == IptvSpotlightLayoutMode.wide
          ? 'Search'
          : search.hintText,
      onChanged: search.onChanged,
      onSubmitted: (value) {
        search.onSubmitted?.call(value);
        // TV's parent coordinates keyboard dismissal before requesting focus.
        // Desktop and standalone headers can enter results immediately.
        if (!widget.isTelevision || search.onSubmitted == null) {
          _focusSpotlightSearchResults();
        }
      },
      onClear: search.onClear,
      onDownArrow: _focusSpotlightSearchResults,
      ink: t.fg,
      fillColor: t.fg.withValues(alpha: 0.055),
      focusedBorderColor: t.accent,
      accent: t.accent,
      keyboardGround: t.panel,
      keyboardInk: t.fg,
      keyboardInkOnAccent: t.focusInk,
      padding: mode == IptvSpotlightLayoutMode.wide
          ? const EdgeInsets.fromLTRB(8, 8, 8, 8)
          : EdgeInsets.zero,
    );
  }

  Widget _buildSpotlightRail({
    bool collapsed = false,
    bool autofocusFirstItem = false,
    ValueChanged<IptvPlaylist>? onSelectPlaylist,
    VoidCallback? onOpenRecordings,
    VoidCallback? onNewList,
    VoidCallback? onAddPlaylist,
    VoidCallback? onAddAddon,
    VoidCallback? onManageSources,
  }) {
    return SpotlightRail(
      collapsed: collapsed,
      onEntryFocus: autofocusFirstItem
          ? null
          : () {
              if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
                _setSpotlightSourcesExpanded(true);
              }
            },
      playlists: _settingsState.playlists,
      selectedPlaylist: _settingsState.selectedPlaylist,
      sourceCounts: _recordingState.sourceCounts,
      customListCounts: {
        for (final list in _favorites.customLists)
          'iptv-list-${list.id}': list.channelCount,
      },
      favoritesCount: _membershipState.favoriteUrls.length,
      continueWatchingCount: _recordingState.continueWatchingCount,
      recordingsCount: _recordingState.scheduledCount,
      showRecordings: _recordingState.pageCanRecord,
      recordingActive: _recordingSupport.anyRecordingLive,
      onSelectPlaylist:
          onSelectPlaylist ??
          (playlist) {
            _setSpotlightSourcesExpanded(false);
            _filtersSection.onPlaylistChanged(playlist, focusContent: true);
          },
      onOpenRecordings:
          onOpenRecordings ??
          (_recordingState.pageCanRecord ? _recordingSupport.openScheduledRecordings : null),
      onNewList: onNewList ?? () => unawaited(_favorites.promptCreateList()),
      onAddPlaylist: onAddPlaylist ?? _navigation.navigateToSettings,
      onAddAddon: onAddAddon ?? _navigateToAddons,
      onManageSources: onManageSources ?? _navigation.navigateToManageSources,
      firstItemFocusNode: autofocusFirstItem ? null : _focusState.playlistFilterFocusNode,
      autofocusFirstItem: autofocusFirstItem,
      onUpFromFirstItem: autofocusFirstItem
          ? null
          : _focusSpotlightSearchOrExit,
      onExitRight: autofocusFirstItem ? null : _closeSpotlightSources,
    );
  }

  void _openSpotlightSearch() {
    final search = widget.searchHeader;
    if (search is! BrowseSearchHeader) return;
    if (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide) {
      _setSpotlightSourcesExpanded(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          (_selectionState.spotlightLayoutMode == IptvSpotlightLayoutMode.wide &&
              !_selectionState.spotlightSourcesExpanded)) {
        return;
      }
      if (search.focusNode.canRequestFocus) search.focusNode.requestFocus();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _focusSpotlightSearchOrExit() {
    if (widget.searchHeader is BrowseSearchHeader) {
      _openSpotlightSearch();
    } else {
      widget.onUpArrowFromFilters?.call();
    }
  }

  void _focusSpotlightSearchResults() {
    _selectionState.searchDebounce?.cancel();
    _filtersSection.applyFilters();
    final query = widget.searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.searchQuery != query) return;
      // Keep an empty search editable. A matching query enters its first row.
      if (_catalogState.filteredChannels.isEmpty) {
        _openSpotlightSearch();
        return;
      }
      _setSpotlightSourcesExpanded(false);
      _navigation.focusFirstChannel();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _focusSpotlightContentEntry() {
    if (_catalogState.filteredChannels.isNotEmpty) {
      if (!_focusState.spotlightTimelineController.restoreFocus()) _navigation.focusFirstChannel();
      return;
    }
    if ((_settingsState.selectedPlaylist?.isXtreamCodes ?? false) &&
        _focusState.contentTypeFocusNode.canRequestFocus) {
      _focusState.contentTypeFocusNode.requestFocus();
      return;
    }
    if (_focusState.categoryFilterFocusNode.canRequestFocus) {
      _focusState.categoryFilterFocusNode.requestFocus();
    }
  }

  int? get _spotlightSelectedSourceCount {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return null;
    if (!_catalogState.isLoading) return _catalogState.allChannels.length;
    if (selected.isFavorites) return _membershipState.favoriteUrls.length;
    if (selected.isContinueWatching) return _recordingState.continueWatchingCount;
    if (selected.isCustomList) {
      for (final list in _favorites.customLists) {
        if (selected.customListId == list.id) return list.channelCount;
      }
    }
    return _recordingState.sourceCounts[selected.id];
  }

  Widget _buildSpotlightHero(IptvSpotlightLayoutMode mode) {
    return _stageHoverGuard(
      ValueListenableBuilder<int>(
        valueListenable: _previewState.previewEpoch,
        builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
          valueListenable: _previewState.previewShown,
          builder: (context, channel, _) =>
              ValueListenableBuilder<EpgProgramme?>(
                valueListenable: _previewState.spotlightProgrammeShown,
                builder: (context, programme, _) => SpotlightProgrammeHero(
                  now: widget.debugSpotlightNow,
                  channel: channel,
                  selectedProgramme: programme,
                  // TV uses short/held OK on the guide row for these actions.
                  actionsBuilder: widget.isTelevision
                      ? null
                      : (context, activeProgramme, dense) =>
                            _buildSpotlightHeroActions(
                              channel,
                              programme: activeProgramme,
                              compact:
                                  mode == IptvSpotlightLayoutMode.compact ||
                                  dense,
                            ),
                  // Keep the established preview subtree byte-for-byte.
                  // Spotlight only lays it out beside programme information.
                  previewSlot: Semantics(
                    button: channel != null,
                    label: channel == null
                        ? 'Channel preview'
                        : 'Watch ${channel.name}',
                    child: GestureDetector(
                      key: const ValueKey('spotlight-preview-play'),
                      behavior: HitTestBehavior.opaque,
                      onTap: channel == null
                          ? null
                          : () => unawaited(_playback.playChannel(channel)),
                      child: _buildPreviewStage(channel, epoch),
                    ),
                  ),
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildSpotlightHeroActions(
    IptvChannel? channel, {
    required EpgProgramme? programme,
    required bool compact,
  }) {
    if (channel == null) return const SizedBox.shrink();
    final t = IptvStyleTokens.spotlight;
    final primary = _spotlightPrimaryAction(channel, programme);
    final rawRecord = _spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    final canSave = channel.contentType != 'series';
    final hasMore =
        record != null || canSave || IptvEpgService.isEpgCapable(channel);

    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _spotlightActivation(
            primary.action,
            FilledButton.icon(
              focusNode: _focusState.spotlightPrimaryFocusNode,
              onPressed: primary.action,
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: t.focusInk,
                backgroundColor: t.focusFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(side: _spotlightFocusBorder),
              icon: Icon(primary.icon, size: 19),
              label: Text(primary.label),
            ),
          ),
          if (hasMore) ...[
            const SizedBox(width: 5),
            _spotlightIconAction(
              tooltip: 'More channel actions',
              icon: Icons.more_horiz_rounded,
              onPressed: () =>
                  _showSpotlightChannelActions(channel, programme: programme),
            ),
          ],
        ],
      );
    }

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    final compactPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 8,
    );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _spotlightActivation(
          primary.action,
          FilledButton.icon(
            focusNode: _focusState.spotlightPrimaryFocusNode,
            style: FilledButton.styleFrom(
              backgroundColor: t.focusFill,
              foregroundColor: t.focusInk,
              padding: compactPadding,
              visualDensity: VisualDensity.compact,
              shape: buttonShape,
            ).copyWith(side: _spotlightFocusBorder),
            onPressed: primary.action,
            icon: Icon(primary.icon, size: 18),
            label: Text(primary.label),
          ),
        ),
        if (record != null)
          _spotlightActivation(
            record.action,
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: record.label == 'Stop' ? t.rec : t.fg,
                side: BorderSide(
                  color: record.label == 'Stop' ? t.rec : t.hairline2,
                ),
                padding: compactPadding,
                visualDensity: VisualDensity.compact,
                shape: buttonShape,
              ),
              onPressed: record.action,
              icon: Icon(record.icon, size: 16),
              label: Text(record.label),
            ),
          ),
        if (canSave)
          _spotlightIconAction(
            tooltip: isFavorited ? 'Remove from Favorites' : 'Add to Favorites',
            icon: isFavorited
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            selected: isFavorited,
            onPressed: () => unawaited(_favorites.toggleFavorite(channel, !isFavorited)),
          ),
        if ((canSave && _favorites.customLists.isNotEmpty) ||
            IptvEpgService.isEpgCapable(channel))
          _spotlightIconAction(
            tooltip: 'More channel actions',
            icon: Icons.more_horiz_rounded,
            onPressed: () =>
                _showSpotlightChannelActions(channel, programme: programme),
          ),
      ],
    );
  }

  ({String label, IconData icon, VoidCallback action}) _spotlightPrimaryAction(
    IptvChannel channel,
    EpgProgramme? programme,
  ) {
    if (channel.contentType == 'series') {
      return (
        label: 'Open',
        icon: Icons.open_in_new_rounded,
        action: () => unawaited(_playback.playChannel(channel)),
      );
    }
    if (programme != null) {
      final now = DateTime.now();
      if (programme.airsAt(now)) {
        return (
          label: 'Watch',
          icon: Icons.play_arrow_rounded,
          action: () => unawaited(_playback.playChannel(channel)),
        );
      }
      if (IptvEpgService.isCatchupAvailable(channel, programme)) {
        return (
          label: 'Replay',
          icon: Icons.replay_rounded,
          action: () => unawaited(_catchup.playCatchup(channel, programme)),
        );
      }
      if (programme.start.isAfter(now)) {
        final recordProgramme = _scheduleActions.recordProgrammeActionFor(channel);
        if (recordProgramme != null) {
          return (
            label: 'Record',
            icon: Icons.fiber_manual_record_rounded,
            action: () => recordProgramme(programme),
          );
        }
      }
      return (
        label: 'Guide',
        icon: Icons.calendar_month_rounded,
        action: () => _scheduleActions.openSchedulePane(channel),
      );
    }
    return (
      label: 'Watch',
      icon: Icons.play_arrow_rounded,
      action: () => unawaited(_playback.playChannel(channel)),
    );
  }

  ({String label, IconData icon, VoidCallback action})? _spotlightRecordAction(
    IptvChannel channel,
  ) {
    final desktopCapture = _desktopRecording.desktopCaptureFor(channel);
    if (desktopCapture != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () => unawaited(_desktopRecording.stageStopDesktopRecording(desktopCapture)),
      );
    }
    final androidTask = !kIsWeb && Platform.isAndroid
        ? _androidRecording.androidEngineTaskFor(channel)
        : null;
    if (androidTask != null) {
      return (
        label: 'Stop',
        icon: Icons.stop_rounded,
        action: () =>
            unawaited(_androidRecording.stageStopAndroidRecording(channel, androidTask)),
      );
    }
    if (_recordingState.pageCanRecord && _recordingSupport.channelEngineRecordable(channel)) {
      return (
        label: 'Record',
        icon: Icons.fiber_manual_record_rounded,
        action: () => unawaited(_recordNow.stageRecordNow(channel)),
      );
    }
    return null;
  }

  Future<void> _showSpotlightChannelActions(
    IptvChannel channel, {
    EpgProgramme? programme,
  }) async {
    final t = IptvStyleTokens.spotlight;
    final rawRecord = _spotlightRecordAction(channel);
    final record =
        programme == null ||
            programme.airsAt(DateTime.now()) ||
            rawRecord?.label == 'Stop'
        ? rawRecord
        : null;
    final canSave = channel.contentType != 'series';
    final isFavorited = _membershipState.favoriteUrls.contains(channel.url);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) action();
          });
        }

        Widget actionTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
          bool autofocus = false,
        }) {
          final ink = color ?? t.fg;
          return ListTile(
            autofocus: autofocus,
            leading: Icon(icon, color: ink),
            title: Text(label, style: TextStyle(color: ink)),
            onTap: () => closeThen(onPressed),
          );
        }

        var first = true;
        Widget nextTile({
          required IconData icon,
          required String label,
          required VoidCallback onPressed,
          Color? color,
        }) {
          final tile = actionTile(
            icon: icon,
            label: label,
            onPressed: onPressed,
            color: color,
            autofocus: first,
          );
          first = false;
          return tile;
        }

        return TvHeldKeyGuard(
          child: SimpleDialog(
            backgroundColor: t.panel,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: t.hairline2),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: t.fg, fontWeight: FontWeight.w800),
                  ),
                ),
                CloseButton(onPressed: () => Navigator.of(dialogContext).pop()),
              ],
            ),
            children: [
              if (record != null)
                nextTile(
                  icon: record.icon,
                  label: record.label,
                  color: record.label == 'Stop' ? t.rec : null,
                  onPressed: record.action,
                ),
              if (canSave)
                nextTile(
                  icon: isFavorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: isFavorited
                      ? 'Remove from Favorites'
                      : 'Add to Favorites',
                  color: isFavorited ? t.accent : null,
                  onPressed: () =>
                      unawaited(_favorites.toggleFavorite(channel, !isFavorited)),
                ),
              if (canSave && _favorites.customLists.isNotEmpty)
                nextTile(
                  icon: Icons.bookmark_add_outlined,
                  label: 'Save to list',
                  onPressed: () => unawaited(_favorites.openListPicker(channel)),
                ),
              if (IptvEpgService.isEpgCapable(channel))
                nextTile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Full guide',
                  onPressed: () => _scheduleActions.openSchedulePane(channel),
                ),
            ],
          ),
        );
      },
    );
  }

  WidgetStateProperty<BorderSide?> get _spotlightFocusBorder =>
      WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.focused)
              ? IptvStyleTokens.spotlight.accent
              : Colors.transparent,
          width: 3,
        ),
      );

  Widget _spotlightActivation(VoidCallback action, Widget child) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (!isActivateOrSpaceKey(event.logicalKey)) {
        return KeyEventResult.ignored;
      }
      if (event is KeyDownEvent) action();
      return KeyEventResult.handled;
    },
    child: child,
  );

  Widget _spotlightIconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    bool selected = false,
  }) {
    final t = IptvStyleTokens.spotlight;
    return _spotlightActivation(
      onPressed,
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        style:
            IconButton.styleFrom(
              foregroundColor: selected ? t.accent : t.fgMid,
              backgroundColor: selected ? t.selectedTint : t.focusTint,
              side: BorderSide(color: selected ? t.accent : t.hairline2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ).copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusFill
                    : selected
                    ? t.selectedTint
                    : t.focusTint,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? t.focusInk
                    : selected
                    ? t.accent
                    : t.fgMid,
              ),
            ),
        icon: Icon(icon, size: 18),
      ),
    );
  }

  Widget _buildSpotlightContent(IptvSpotlightLayoutMode mode) {
    final scheduleChannel = _selectionState.scheduleChannel;
    final browser = _buildSpotlightBrowser(mode);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            child: browser,
          ),
        ),
        if (scheduleChannel != null)
          ValueListenableBuilder<int>(
            valueListenable: IptvEpgService.instance.contextVersion,
            builder: (context, epgVersion, _) => IptvSchedulePane(
              // A guide published after the pane opened must replace the
              // once-loaded empty schedule with a fresh one.
              key: ValueKey(
                'spotlight-schedule-${scheduleChannel.url}-$epgVersion',
              ),
              channel: scheduleChannel,
              onClose: _scheduleActions.closeSchedulePane,
              isTelevision: widget.isTelevision,
              onPlayProgramme: (programme) =>
                  _catchup.playCatchup(scheduleChannel, programme),
              onRecordProgramme: _scheduleActions.recordProgrammeActionFor(scheduleChannel),
            ),
          ),
      ],
    );
  }

  Widget _buildSpotlightBrowser(IptvSpotlightLayoutMode mode) {
    if (!_spotlightUsesTimeline) {
      return _buildContent(tvPane: true, cockpit: false);
    }

    // Preserve the existing load/error/empty surfaces. The timeline only
    // replaces the populated live-channel renderer.
    if (_settingsState.playlists.isEmpty ||
        _settingsState.selectedPlaylist == null ||
        _catalogState.isLoading ||
        (_catalogState.errorMessage != null && _catalogState.allChannels.isEmpty) ||
        _catalogState.filteredChannels.isEmpty) {
      return _buildContent(tvPane: true, cockpit: false);
    }

    final selected = _settingsState.selectedPlaylist!;
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<int>(
        valueListenable: IptvEpgService.instance.contextVersion,
        builder: (context, epgVersion, _) => SpotlightLiveTimeline(
          key: _focusState.spotlightTimelineKey,
          now: widget.debugSpotlightNow,
          channels: _catalogState.filteredChannels,
          sourceId: selected.id,
          loadGeneration: Object.hash(_catalogState.loadTicket, _catalogState.spotlightViewGeneration),
          scheduleLoader: (channel) =>
              IptvEpgService.instance.schedule(channel.url),
          controller: _focusState.spotlightTimelineController,
          epgContextVersion: epgVersion,
          onSelectionChanged: _onSpotlightSelection,
          onExitUp: () => _focusState.categoryFilterFocusNode.requestFocus(),
          onExitLeft: _focusSpotlightSources,
          onChannelActions: (entry) => _showSpotlightChannelActions(
            entry.channel,
            programme: _previewState.spotlightProgrammeShown.value,
          ),
          onChannelActivate: (entry) => unawaited(_playback.playChannel(entry.channel)),
          onProgrammeActivate: _activateSpotlightProgramme,
          // Keep short programmes readable on a television: the preceding
          // half-hour ruler interval plus the following hour.
          windowDuration: const Duration(minutes: 90),
          height: constraints.maxHeight,
          identityWidth: mode == IptvSpotlightLayoutMode.wide ? 300 : 260,
          dense: true,
          rowHeight: 46,
          rulerHeight: 32,
        ),
      ),
    );
  }

  bool get _spotlightUsesTimeline {
    final selected = _settingsState.selectedPlaylist;
    if (selected == null) return false;
    // Saved shelves share the guide's row navigation, including its playable
    // no-guide and on-demand rows. Schedule lookup stays channel-based so
    // mixed Xtream providers use their own credentials without switching the
    // page's global XMLTV context for each row.
    if (selected.isFavorites || selected.isCustomList) return true;
    if (selected.isVirtual) return false;
    return !selected.isXtreamCodes || _catalogState.selectedContentType == 'live';
  }

  void _onSpotlightSelection(SpotlightTimelineSelection selection) {
    final channel = selection.entry.channel;
    _onChannelFocused(channel, fromPointer: selection.fromPointer);
    if (identical(_previewState.previewShown.value, channel)) {
      _previewState.spotlightProgrammeShown.value = selection.programme;
    }
  }

  void _activateSpotlightProgramme(
    SpotlightTimelineEntry entry,
    EpgProgramme programme,
  ) {
    final now = DateTime.now();
    if (programme.airsAt(now)) {
      unawaited(_playback.playChannel(entry.channel));
      return;
    }
    if (IptvEpgService.isCatchupAvailable(entry.channel, programme)) {
      unawaited(_catchup.playCatchup(entry.channel, programme));
      return;
    }
    if (programme.start.isAfter(now)) {
      final record = _scheduleActions.recordProgrammeActionFor(entry.channel);
      if (record != null) {
        record(programme);
        return;
      }
    }
    // A programme without a direct replay/record action still opens the full
    // schedule, where the user can inspect the surrounding listings.
    _scheduleActions.openSchedulePane(entry.channel);
  }

  Future<void> _showSpotlightSources() async {
    final size = MediaQuery.sizeOf(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (dialogContext) {
        void closeThen(VoidCallback action) {
          Navigator.of(dialogContext).pop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) action();
          });
        }

        return TvHeldKeyGuard(
          child: Dialog(
            backgroundColor: IptvStyleTokens.spotlight.panel,
            insetPadding: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: IptvStyleTokens.spotlight.hairline2),
            ),
            child: SizedBox(
              width: math.min(390, size.width - 32),
              height: math.min(620, size.height - 32),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Expanded(child: Text('Sources')),
                        CloseButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _buildSpotlightRail(
                        autofocusFirstItem: true,
                        onSelectPlaylist: (playlist) => closeThen(
                          () =>
                              _filtersSection.onPlaylistChanged(playlist, focusContent: true),
                        ),
                        onOpenRecordings: _recordingState.pageCanRecord
                            ? () => closeThen(_recordingSupport.openScheduledRecordings)
                            : null,
                        onNewList: () =>
                            closeThen(() => unawaited(_favorites.promptCreateList())),
                        onAddPlaylist: () => closeThen(_navigation.navigateToSettings),
                        onAddAddon: () => closeThen(_navigateToAddons),
                        onManageSources: () =>
                            closeThen(_navigation.navigateToManageSources),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }



  Future<void> _showSpotlightCategoryPicker() async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.68),
      builder: (_) => SpotlightCategoryPickerDialog(
        categories: List<String>.of(_catalogState.categories, growable: false),
        selectedCategory: _filtersSection.effectiveCategory,
        categoryCounts: Map<String, int>.of(_categoryCounts),
        allChannelCount: _catalogState.allChannels.length,
        showOptionsHint: _categoryActions.canShowCategoryOptions && _catalogState.categories.isNotEmpty,
        allCategoryValue: IptvSelectionState.kSpotlightAllCategory,
      ),
    );
    if (!mounted || picked == null) return;
    _filtersSection.onCategoryChanged(picked == IptvSelectionState.kSpotlightAllCategory ? null : picked);
  }

  /// The single-pane layout: boxed filter bar over a full-width channel list.
  /// Phones keep it (no embedded preview there), and TV/desktop fall back to
  /// it when the canvas can't fit two panes.
  Widget _buildClassic() {
    return Column(
      children: [
        // Filters bar
        IptvFiltersBar(
          playlists: _settingsState.playlists,
          selectedPlaylist: _settingsState.selectedPlaylist,
          categories: _catalogState.categories,
          selectedCategory: _filtersSection.effectiveCategory,
          categoryCounts: _categoryCounts,
          channelCount: _catalogState.filteredChannels.length,
          isLoading: _catalogState.isLoading,
          isLoadingMore: _catalogState.isLoadingMore,
          onPlaylistChanged: _filtersSection.onPlaylistChanged,
          onCategoryChanged: _filtersSection.onCategoryChanged,
          onAddPlaylist: _navigation.navigateToSettings,
          playlistFocusNode: _focusState.playlistFilterFocusNode,
          categoryFocusNode: _focusState.categoryFilterFocusNode,
          showContentTypeFilter: _settingsState.selectedPlaylist?.isXtreamCodes ?? false,
          selectedContentType: _catalogState.selectedContentType,
          onContentTypeChanged: _filtersSection.onContentTypeChanged,
          contentTypeFocusNode: _focusState.contentTypeFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _navigation.focusFirstChannel,
          onOpenRecordings: _recordingState.pageCanRecord ? _recordingSupport.openScheduledRecordings : null,
          recordingLive: _recordingSupport.anyRecordingLive,
          onCategoryOptions: _categoryActions.canShowCategoryOptions
              ? _categoryActions.promptCategoryOptions
              : null,
        ),

        // Content
        Expanded(child: _buildContent()),
      ],
    );
  }

  // ── TV two-pane ──────────────────────────────────────────────────────────

  Widget _buildTvTwoPane(BoxConstraints c, {required bool touchSelector}) {
    // Every source (Favorites, Continue watching, and each playlist) lives in
    // the header's Sources dropdown now — no left rail eating horizontal space.
    // TV uses a wider focus stage; desktop keeps the compact preview rail so a
    // resizable window never gives up too much guide space.
    final paneW = c.maxWidth;
    final scheduleChannel = _selectionState.scheduleChannel;

    // An open schedule covers the guide column in place — the preview
    // keeps playing, and BACK restores the list exactly as it was. Offstage
    // (not a swap) keeps the grid, its scroll offset and its focus nodes
    // alive, so closing can hand focus straight back to the originating row;
    // ExcludeFocus keeps DPAD from wandering into the hidden rows meanwhile.
    Widget guideStack({required bool cockpit}) => Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: scheduleChannel != null,
          child: ExcludeFocus(
            excluding: scheduleChannel != null,
            // The LayoutBuilder is inside the Stack (bounded), so the styled
            // branches can gate their display inserts on the real guide
            // height. The command branch below it is the shipped tree,
            // untouched.
            child: LayoutBuilder(
              builder: (context, gc) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 24, 4),
                    child: _buildQuietFilters(),
                  ),
                  // First Edition's editorial hero — display-only (no focus
                  // nodes), inside the Offstage subtree so the schedule pane
                  // covers it. Gate = every vertical consumer at worst case:
                  // filter line ~50 + hero 128 + progressive-status line ~24
                  // + grid top pad 8 + 4 tall EPG rows (4x118) + 3 gaps
                  // (3x4) = 694 → 700 with margin, so >=4 full rows always
                  // survive the insert.
                  if (cockpit &&
                      _settingsState.iptvStyle == IptvStyle.edition &&
                      gc.maxHeight >= 700)
                    IptvEditionHero(
                      channel: _previewState.previewShown,
                      tokens: IptvStyleTokens.edition,
                      suspended: scheduleChannel != null,
                    ),
                  // Master Control's 6-hour strip — same display-only rules
                  // as the hero. Same budget with its own 96px height:
                  // 50 + 96 + 24 + 8 + 472 + 12 = 662 → 670 with margin.
                  if (cockpit &&
                      _settingsState.iptvStyle == IptvStyle.console &&
                      gc.maxHeight >= 670)
                    IptvConsoleTimeline(
                      channel: _previewState.previewShown,
                      tokens: IptvStyleTokens.console,
                      suspended: scheduleChannel != null,
                    ),
                  Expanded(
                    child: _buildContent(
                      tvPane: true,
                      touchSelector: touchSelector,
                      cockpit: cockpit,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (scheduleChannel != null)
          IptvSchedulePane(
            channel: scheduleChannel,
            onClose: _scheduleActions.closeSchedulePane,
            isTelevision: widget.isTelevision,
            onPlayProgramme: (programme) =>
                _catchup.playCatchup(scheduleChannel, programme),
            // The full-day guide records too — same gates and confirm flow
            // as the stage's compact list (it was the one schedule surface
            // that never got the callback).
            onRecordProgramme: _scheduleActions.recordProgrammeActionFor(scheduleChannel),
          ),
      ],
    );

    if (!touchSelector) {
      // Command Center (TV + desktop pointer): rail → guide → stage cockpit.
      // Geometry does the DPAD work — the rail's focusables sit left of the
      // grid, the stage's actions sit right of it, and LEFT from the rail
      // bubbles to the shell's global action (the app sidebar) untouched.
      final railW = paneW >= 1150 ? 196.0 : 172.0;
      final cockpitStageW = (paneW * (paneW >= 1200 ? 0.34 : 0.36)).clamp(
        300.0,
        480.0,
      );
      final cockpitTokens = IptvStyleTokens.of(_settingsState.iptvStyle);
      final cockpitRow = Row(
        key: const ValueKey('iptv-cockpit'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: railW,
            child: IptvCommandRail(
              tokens: cockpitTokens,
              playlists: _settingsState.playlists,
              selectedPlaylist: _settingsState.selectedPlaylist,
              customLists: _membershipState.lists,
              sourceCounts: _recordingState.sourceCounts,
              favoritesCount: _membershipState.favoriteUrls.length,
              scheduledCount: _recordingState.scheduledCount,
              // focusContent: OK is a decision, so it lands DPAD on the
              // channels it just loaded. (Merely walking RIGHT does not
              // select — it traverses into the guide, which still shows the
              // selected source.)
              onSelectPlaylist: (p) =>
                  _filtersSection.onPlaylistChanged(p, focusContent: true),
              onOpenScheduled: _recordingSupport.openScheduledRecordings,
              onManageSources: _navigation.navigateToManageSources,
              // Engine off / unsupported: don't advertise a scheduler that
              // would refuse to work (settings hides its row in this state).
              showScheduled: _recordingState.pageCanRecord,
            ),
          ),
          Expanded(
            // Styled looks paint the guide column's background HERE, not as
            // one sheet under the whole cockpit: the stage's RepaintBoundary
            // is its own compositing layer, so the preview's BlendMode.clear
            // hole cannot erase paint living in an ancestor layer — a page-
            // wide ColoredBox turns the live underlay video into an opaque
            // block (frozen frame + audio-only on TV). The rail and status
            // bar paint their own; the stage's panel color already lives
            // INSIDE the boundary where the hole clears it.
            child: cockpitTokens == null
                ? guideStack(cockpit: true)
                : ColoredBox(
                    color: cockpitTokens.bg,
                    child: guideStack(cockpit: true),
                  ),
          ),
          SizedBox(width: cockpitStageW, child: _buildCockpitStage()),
        ],
      );
      // NO ColoredBox around the cockpit row — see the guide-column note
      // above (the underlay hole must composite against transparency all the
      // way down). Master Control adds its status strip above the cockpit —
      // the Row stays bounded inside the Expanded.
      if (cockpitTokens == null) return cockpitRow;
      if (_settingsState.iptvStyle == IptvStyle.console) {
        return Column(
          children: [
            IptvConsoleStatusBar(
              tokens: cockpitTokens,
              sourceName: _settingsState.selectedPlaylist?.name ?? 'IPTV',
              channelCount: _catalogState.filteredChannels.length,
              recCount: (!kIsWeb && Platform.isAndroid)
                  ? _recordingState.androidRecordingsByUrl.length
                  : DesktopRecordingService.instance.isSupported
                  ? DesktopRecordingService.instance.captures.length
                  : 0,
              schedCount: _recordingState.scheduledCount,
              statusText: _statusState.chipState == CatalogChipState.hidden
                  ? null
                  : _statusState.chipMessage,
              // The Android url→task map refreshes on selected events only;
              // the bar's tick reconciles it so REC can't sit stale while
              // focus is parked (no-op off Android / when recording is off).
              onTick: () => unawaited(_androidRecording.refreshAndroidRecordingState()),
            ),
            Expanded(child: cockpitRow),
          ],
        );
      }
      return cockpitRow;
    }

    // Touch tablet keeps the shipped preview-left arrangement unchanged.
    final stageW = (paneW * 0.40).clamp(320.0, 470.0);
    return Row(
      key: const ValueKey('iptv-tablet-two-pane'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: stageW,
          child: _buildPreviewRail(touchSelector: touchSelector),
        ),
        Expanded(child: guideStack(cockpit: false)),
      ],
    );
  }

  /// The Command Center stage: live preview on top, identity + now/next,
  /// then the action row and the focused channel's compact day schedule
  /// (IptvStagePanel). One RepaintBoundary so the preview's frames never
  /// re-rasterize the panel and vice versa.
  Widget _buildCockpitStage() {
    final app = AppThemeScope.of(context);
    return _stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 14, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              return RepaintBoundary(
                child: ClipRRect(
                  borderRadius: app.shape.br(10),
                  child: ColoredBox(
                    color:
                        IptvStyleTokens.of(_settingsState.iptvStyle)?.panel ??
                        app.iptv.stageBg,
                    child: ch == null
                        ? const SizedBox.expand()
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // UNDERLAY RULE (device-verified 2026-08-05):
                              // the preview subtree is handed over UNWRAPPED,
                              // byte-identical to the shipped Command Center
                              // path. Wrapping it (a CustomPaint, a Column, a
                              // foregroundDecoration Container) froze the
                              // underlay video on Android TV — frozen frame +
                              // audio-only. Styled chrome therefore lives as
                              // SIBLINGS: the caption below is a plain child
                              // of this ALREADY-EXISTING Column, and the
                              // brackets/frame paint inside the preview's own
                              // Stack next to the status chip.
                              _buildPreviewStage(ch, epoch),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  0,
                                ),
                                child: _cockpitIdentity(ch),
                              ),
                              Expanded(
                                // Rebuilds when an XMLTV guide finishes loading
                                // (contextVersion), so a channel that probed
                                // "no EPG" a moment ago gets its schedule.
                                child: ValueListenableBuilder<int>(
                                  valueListenable:
                                      IptvEpgService.instance.contextVersion,
                                  builder: (context, epgVersion, _) {
                                    final desktopCapture = _desktopRecording.desktopCaptureFor(
                                      ch,
                                    );
                                    final androidTask =
                                        (!kIsWeb && Platform.isAndroid)
                                        ? _androidRecording.androidEngineTaskFor(ch)
                                        : null;
                                    return IptvStagePanel(
                                      key: ValueKey('stage-${ch.url}'),
                                      tokens: IptvStyleTokens.of(_settingsState.iptvStyle),
                                      channel: ch,
                                      isTelevision: widget.isTelevision,
                                      isFavorited: _membershipState.favoriteUrls.contains(
                                        ch.url,
                                      ),
                                      canRecord: _recordingState.pageCanRecord,
                                      isRecordingThis:
                                          desktopCapture != null ||
                                          androidTask != null,
                                      epgContextVersion: epgVersion,
                                      onWatch: () =>
                                          unawaited(_playback.playChannel(ch)),
                                      onExitLeft: _returnFocusFromStage,
                                      onRecordNow: desktopCapture != null
                                          ? () => unawaited(
                                              _desktopRecording.stageStopDesktopRecording(
                                                desktopCapture,
                                              ),
                                            )
                                          : androidTask != null
                                          ? () => unawaited(
                                              _androidRecording.stageStopAndroidRecording(
                                                ch,
                                                androidTask,
                                              ),
                                            )
                                          : _recordingSupport.channelEngineRecordable(ch)
                                          ? () => unawaited(_recordNow.stageRecordNow(ch))
                                          : null,
                                      // _toggleFavorite takes the DESIRED state
                                      // (the row passes !isFavorited too) —
                                      // passing the current one would write a
                                      // no-op.
                                      onToggleFavorite:
                                          ch.contentType == 'series'
                                          ? null
                                          : () => unawaited(
                                              _favorites.toggleFavorite(
                                                ch,
                                                !_membershipState.favoriteUrls.contains(ch.url),
                                              ),
                                            ),
                                      // Only when a guide can exist — otherwise
                                      // the pane could only say "No guide data".
                                      onOpenFullSchedule:
                                          IptvEpgService.isEpgCapable(ch)
                                          ? () => _scheduleActions.openSchedulePane(ch)
                                          : null,
                                      // Stricter than Record-now: scheduling has
                                      // no player probe at alarm time, so REC
                                      // rows only appear on affirmatively-TS/
                                      // Xtream channels — never a tag that gets
                                      // refused on press.
                                      onScheduleProgramme:
                                          LiveRecordingService.isSchedulableUrl(
                                            ch.url,
                                          )
                                          ? _scheduleActions.scheduleProgrammeFromStage
                                          : null,
                                      onPlayProgramme: (c, p) =>
                                          unawaited(_catchup.playCatchup(c, p)),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Compact identity header for the cockpit: logo chip, CH number + name,
  /// group/resolution sub-line, then the shared now/next EPG card.
  Widget _cockpitIdentity(IptvChannel channel) {
    final app = AppThemeScope.of(context);
    final t = IptvStyleTokens.of(_settingsState.iptvStyle);
    final isConsole = _settingsState.iptvStyle == IptvStyle.console;
    // Styled looks never paint the brand color.
    final brand = t == null ? brandAccentFor(channel.name) : Colors.transparent;
    final resMatch = railResExp.firstMatch(channel.name);
    final resolution = resMatch?.group(1)?.toLowerCase();
    final displayName = resMatch == null
        ? channel.name
        : channel.name
              .replaceRange(resMatch.start, resMatch.end, '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
    final group = channel.group?.trim();
    final subParts = <String>[
      if (group != null && group.isNotEmpty) group,
      if (resolution != null) resolution,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: t == null
                  ? BoxDecoration(
                      borderRadius: app.shape.br(8),
                      border: Border.all(color: app.iptv.hairline),
                      color: Color.alphaBlend(
                        brand.withValues(alpha: 0.18),
                        const Color(0xFF171B19),
                      ),
                    )
                  : BoxDecoration(
                      shape: isConsole ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isConsole ? app.shape.br(6) : null,
                      border: Border.all(color: t.hairline2),
                      color: t.fg.withValues(alpha: 0.03),
                    ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: (channel.logoUrl != null && channel.logoUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: channel.logoUrl!,
                        cacheManager: DebrifyImageCache.iptvLogos,
                        fit: BoxFit.contain,
                        memCacheHeight: 96,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.live_tv_rounded,
                          size: 16,
                          color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                        ),
                      )
                    : Icon(
                        Icons.live_tv_rounded,
                        size: 16,
                        color: t?.fgDim ?? brand.withValues(alpha: 0.85),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.channelNumber == null
                        ? displayName
                        : 'CH ${channel.channelNumber}  $displayName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t == null
                        ? TextStyle(
                            color: app.core.tx,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          )
                        : TextStyle(
                            color: t.fg,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.1,
                            fontFamily: t.nameFamily.isEmpty
                                ? null
                                : t.nameFamily,
                          ),
                  ),
                  if (subParts.isNotEmpty)
                    Text(
                      subParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t == null
                          ? TextStyle(
                              color: app.core.tx.withValues(alpha: 0.5),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            )
                          : TextStyle(
                              color: t.fgDim,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              fontFamily: t.monoFamily.isEmpty
                                  ? null
                                  : t.monoFamily,
                            ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        IptvRailEpgCard(
          channel: channel,
          stageOverlay: true,
          dense: true,
          tokens: t,
        ),
      ],
    );
  }

  /// The Discover-style quiet filter line: bare dot-separated text segments
  /// (source • [Live/Movies] • category • count) instead of boxed pills.
  Widget _buildQuietFilters() {
    final app = AppThemeScope.of(context);
    return SeeAllFilterBar(
      isTelevision: widget.isTelevision,
      quiet: true,
      buildChips: () => [
        // The Sources dropdown — EVERY source in one place: Favorites,
        // Continue watching, and each playlist. Replaces the old left rail.
        // Holds _playlistFilterFocusNode so every wire into "the first filter"
        // (down-from-search-field, revalidate focus repair, focusFirstFilter)
        // keeps working.
        StremioDropdown<String>(
          value: _settingsState.selectedPlaylist?.id ?? '',
          quiet: true,
          quietAccent: true,
          isTelevision: widget.isTelevision,
          focusNode: _focusState.playlistFilterFocusNode,
          onUpArrowPressed: widget.onUpArrowFromFilters,
          onDownArrowPressed: _navigation.focusFirstChannel,
          options: _sourceDropdownOptions(),
          onSelected: (id) {
            if (id == IptvSelectionState.kNewListSentinel) {
              _favorites.promptCreateList();
              return;
            }
            if (id == IptvSelectionState.kAddPlaylistSentinel) {
              _navigation.navigateToSettings();
              return;
            }
            if (id == IptvSelectionState.kAddAddonSentinel) {
              _navigateToAddons();
              return;
            }
            for (final p in _settingsState.playlists) {
              if (p.id == id) {
                _filtersSection.onPlaylistChanged(p);
                return;
              }
            }
          },
        ),
        if (_settingsState.selectedPlaylist?.isXtreamCodes ?? false)
          StremioDropdown<String>(
            label: 'type',
            value: _catalogState.selectedContentType,
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _focusState.contentTypeFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _navigation.focusFirstChannel,
            options: const [
              StremioDropdownOption('live', 'Live TV'),
              StremioDropdownOption('vod', 'Movies'),
              StremioDropdownOption('series', 'Series'),
            ],
            onSelected: _filtersSection.onContentTypeChanged,
          ),
        if (_catalogState.categories.isNotEmpty)
          StremioDropdown<String>(
            label: 'category',
            value: _filtersSection.effectiveCategory ?? '',
            quiet: true,
            isTelevision: widget.isTelevision,
            focusNode: _focusState.categoryFilterFocusNode,
            onUpArrowPressed: widget.onUpArrowFromFilters,
            onDownArrowPressed: _navigation.focusFirstChannel,
            options: [
              StremioDropdownOption('', 'All · ${_catalogState.allChannels.length}'),
              for (final cat in _catalogState.categories)
                StremioDropdownOption(
                  cat,
                  '$cat · ${_categoryCounts[cat] ?? 0}',
                  // "All" is deliberately not holdable — there is no such
                  // category to hide.
                  holdable: _categoryActions.canShowCategoryOptions,
                ),
            ],
            holdHint: widget.isTelevision
                ? 'HOLD OK FOR OPTIONS'
                : 'HOLD FOR OPTIONS',
            onOptionHold: _categoryActions.promptCategoryOptions,
            onSelected: (v) => _filtersSection.onCategoryChanged(v.isEmpty ? null : v),
          ),
        // Non-focusable count — DPAD skips straight over it.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Text(
            _catalogState.isLoading
                ? 'Loading…'
                : '${_catalogState.filteredChannels.length} channel'
                      '${_catalogState.filteredChannels.length == 1 ? '' : 's'}'
                      // The list is still streaming in — never present a
                      // partial count as final.
                      '${_catalogState.isLoadingMore ? ' • loading more…' : ''}',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.40),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }





  /// The Sources dropdown, grouped: the two derived shelves, then the user's
  /// own lists, their playlists, and any live-TV catalogs their Stremio addons
  /// expose — each ending with the action that adds another one of its kind.
  ///
  /// The grouping mirrors the order [_loadSettings] already builds, so this
  /// only draws the lines where the list already changes character.
  List<StremioDropdownOption<String>> _sourceDropdownOptions() {
    final quickAccess = [
      for (final p in _settingsState.playlists)
        if (p.isFavorites || p.isContinueWatching) p,
    ];
    final lists = [
      for (final p in _settingsState.playlists)
        if (p.isCustomList) p,
    ];
    final addons = [
      for (final p in _settingsState.playlists)
        if (p.isStremioAddon) p,
    ];
    final playlists = [
      for (final p in _settingsState.playlists)
        if (!p.isVirtual) p,
    ];

    return [
      if (quickAccess.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_quick__', 'Quick access'),
        for (final p in quickAccess) StremioDropdownOption(p.id, p.name),
      ],
      // Always shown, empty or not — it is where "New list" lives, and a user
      // with no lists yet is exactly who needs to find it.
      const StremioDropdownOption.header('__hdr_lists__', 'Your lists'),
      for (final p in lists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(IptvSelectionState.kNewListSentinel, '＋ New list'),
      const StremioDropdownOption.header('__hdr_playlists__', 'Your playlists'),
      for (final p in playlists) StremioDropdownOption(p.id, p.name),
      const StremioDropdownOption(IptvSelectionState.kAddPlaylistSentinel, '＋ Add playlist'),
      // Only for people who actually run addons — an empty section would push
      // Stremio at everyone else.
      if (addons.isNotEmpty) ...[
        const StremioDropdownOption.header('__hdr_addons__', 'Stremio Addons'),
        for (final p in addons) StremioDropdownOption(p.id, p.name),
        const StremioDropdownOption(IptvSelectionState.kAddAddonSentinel, '＋ Add addon'),
      ],
    ];
  }

  /// Open the Addons hub. Tab-switch rather than a pushed route: the hub is a
  /// tab body with no app bar of its own, so pushing it would strand the user
  /// with no way back.
  void _navigateToAddons() {
    MainPageBridge.switchTab?.call(MainTab.addons);
  }

  /// Stage LEFT-exit: land on the exact row the stage was opened from — the
  /// row that owns the preview — so the return trip never retunes the stream.
  /// Geometric traversal would pick the nearest row instead, refocusing a
  /// DIFFERENT channel and reloading the preview twice on the way back.
  void _returnFocusFromStage() {
    // Full-schedule pane open: the grid is ExcludeFocus'd, so a row focus
    // request would silently strand DPAD. The pane owns navigation (its own
    // LEFT/BACK close it); the stage's LEFT just stays put.
    if (_selectionState.scheduleChannel != null) return;
    final channel = _previewState.previewShown.value;
    if (channel != null &&
        _selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic &&
        _focusState.spotlightTimelineController.restoreFocus()) {
      return;
    }
    if (channel != null && _rowAttached(channel)) {
      _focusNodeFor(channel).requestFocus();
      return;
    }
    _navigation.focusFirstChannel();
  }



  /// Lets a preview stage claim the pointer, so nothing repoints it while the
  /// cursor is inside on its way to Watch or Record. A row the pointer RESTS on
  /// is exempt (see [_onChannelFocused]) — the cursor cannot be on a row and in
  /// the stage at once, so that exemption also means a flag left stuck true by
  /// a missed onExit can never strand the hover preview.
  Widget _stageHoverGuard(Widget child) {
    if (widget.isTelevision) return child;
    return MouseRegion(
      onEnter: (_) => _previewState.pointerInStage = true,
      onExit: (_) => _previewState.pointerInStage = false,
      child: child,
    );
  }

  /// Called by a channel row gaining DPAD focus, or by a pointer resting on it
  /// ([fromPointer]) — retunes the preview stage.
  void _onChannelFocused(IptvChannel channel, {bool fromPointer = false}) {
    // Focus-driven retargets (a reload refocusing the first channel, a restore
    // after a route pops) must not swap the panel out from under a cursor
    // already inside it. Only once something IS shown: the very first
    // population has to land even if the pointer happens to be parked there.
    if (!fromPointer && _previewState.pointerInStage && _previewState.previewShown.value != null) return;
    // The in-app player fallback never pauses the app, so a parked re-arm
    // wouldn't flush via the lifecycle observer — the focus restore after its
    // route pops (or the user's next move) lands here instead.
    _previewHandoff.flushPreviewRearm();
    final shown = _previewState.previewShown.value;
    if (identical(shown, channel)) return;
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = channel;
    if (_settingsState.channelPreviewEnabled) {
      _retunePreview(channel);
    } else {
      _stopPreviewPlayback();
    }
    // Keep the stage's Record↔Stop honest for whichever channel is focused
    // now (debounced — zapping through rows costs nothing).
    _androidRecording.armAndroidRecStateRefresh();
  }

  /// Point the stage at the focused channel's stream. M3U/Xtream channels
  /// carry their URL; Stremio channels resolve theirs first (the 900ms dwell
  /// hides most of that latency) and start the candidate ladder.
  void _retunePreview(IptvChannel channel) {
    _previewState.previewResolveTicket++;
    final ticket = _previewState.previewResolveTicket;
    _previewState.previewCandidates = null;
    // Series carry a sentinel URL, not a stream — the stage rests on its
    // floor (logo slab), like a channel with nothing playable.
    if (channel.contentType == 'series') {
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) {
      _previewState.previewStreamUrl.value = channel.url;
      return;
    }
    // Unmounting the backdrop skips its teardown notification — reset the
    // "has frames" chip state ourselves or it would keep reading LIVE.
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!mounted || ticket != _previewState.previewResolveTicket) return;
      // No playable streams — the stage stays on its floor, exactly like a
      // dead M3U channel.
      if (found.isEmpty) return;
      final urls = [for (final c in found) c.url];
      _previewState.previewCandidates = urls;
      _previewState.previewStreamUrl.value = urls.first;
    });
  }

  /// The stage's current stream genuinely failed (refused to open, errored, or
  /// stalled past the first-frame timeout). Stremio channels step down their
  /// candidate ladder; anything else keeps the old behavior (silent floor).
  /// [ticket] is the ladder generation the failing backdrop was built for —
  /// the notification is post-frame, so by the time it lands the focus may
  /// already be on another channel whose ladder must not be touched.
  void _onPreviewPlaybackFailed(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final candidates = _previewState.previewCandidates;
    final current = _previewState.previewStreamUrl.value;
    if (candidates == null || current == null) return;
    final next = candidates.indexOf(current) + 1;
    if (next <= 0) return; // stale failure for a URL we've already moved off
    if (next >= candidates.length) {
      // Every candidate is dead: drop back to the floor and forget the cached
      // list so a later attempt re-resolves fresh links.
      final shown = _previewState.previewShown.value;
      if (shown != null) StremioIptvService.instance.invalidate(shown.url);
      _previewState.previewStreamUrl.value = null;
      _previewState.previewShowing.value = false;
      return;
    }
    _previewState.previewStreamUrl.value = candidates[next];
  }

  /// First frames arrived — remember which candidate actually plays so the
  /// next preview/play of this channel starts there. Same staleness guard as
  /// the failure path: frames from a previous channel's engine must not
  /// crown the new channel's candidate.
  void _markPreviewWinner(int ticket) {
    if (ticket != _previewState.previewResolveTicket) return;
    final shown = _previewState.previewShown.value;
    final current = _previewState.previewStreamUrl.value;
    if (shown == null || current == null || _previewState.previewCandidates == null) return;
    if (StremioIptvService.isStremioChannelUrl(shown.url)) {
      StremioIptvService.instance.markWinner(shown.url, current);
    }
  }

  /// Release the embedded stream and abandon any in-flight Stremio resolve,
  /// while leaving the selected channel's artwork, metadata and actions in
  /// the stage. This is the persistent-setting path.
  void _stopPreviewPlayback() {
    _previewState.previewResolveTicket++;
    _previewState.previewCandidates = null;
    _previewState.previewStreamUrl.value = null;
    _previewState.previewShowing.value = false;
  }

  /// Empty the stage entirely (playlist switch, sidebar open) and abandon any
  /// in-flight resolve.
  void _clearPreview() {
    _stopPreviewPlayback();
    _previewState.spotlightProgrammeShown.value = null;
    _previewState.previewShown.value = null;
  }

  Widget _buildPreviewRail({required bool touchSelector}) {
    final app = AppThemeScope.of(context);
    return _stageHoverGuard(
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
        child: ValueListenableBuilder<int>(
          valueListenable: _previewState.previewEpoch,
          builder: (context, epoch, _) => ValueListenableBuilder<IptvChannel?>(
            valueListenable: _previewState.previewShown,
            builder: (context, ch, _) {
              if (widget.isTelevision) {
                return _buildTvFocusStage(ch, epoch);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildPreviewStage(ch, epoch),
                  const SizedBox(height: 16),
                  Expanded(child: IptvRailInfo(channel: ch)),
                  if (touchSelector) ...[
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('iptv-tablet-watch-fullscreen'),
                        onPressed: ch == null
                            ? null
                            : () => unawaited(_playback.playChannel(ch)),
                        style: FilledButton.styleFrom(
                          backgroundColor: app.seeAll.accent,
                          foregroundColor: app.inkOn(app.seeAll.accent),
                          disabledBackgroundColor: app.seeAll.panel2.withValues(
                            alpha: 0.72,
                          ),
                          disabledForegroundColor: app.core.tx.withValues(
                            alpha: 0.30,
                          ),
                          overlayColor: app.seeAll.accent2.withValues(
                            alpha: 0.18,
                          ),
                          shadowColor: app.seeAll.accent.withValues(
                            alpha: 0.34,
                          ),
                          elevation: 0,
                          side: BorderSide(
                            color: app.seeAll.accent2.withValues(alpha: 0.46),
                          ),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: app.shape.br(13),
                          ),
                        ),
                        icon: Icon(
                          ch?.contentType == 'series'
                              ? Icons.video_library_rounded
                              : Icons.fullscreen_rounded,
                          size: 21,
                        ),
                        label: Text(
                          ch?.contentType == 'series'
                              ? 'Open series'
                              : 'Watch fullscreen',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        _settingsState.channelPreviewEnabled
                            ? 'Scroll channels through the arrow to preview'
                            : 'Preview is off · choose Watch fullscreen',
                        style: TextStyle(
                          color: app.seeAll.accent2.withValues(alpha: 0.66),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _settingsState.channelPreviewEnabled
                            ? 'Hover a channel to preview  ·  Click to watch'
                            : 'Preview is off  ·  Click to watch',
                        style: TextStyle(
                          color: app.iptv.inkFaint,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Television's preview-first composition: a true 16:9 video surface in the
  /// upper section, with identity, EPG and key hints on a separate lower
  /// surface. Keeping chrome outside the video avoids cover-cropping a normal
  /// broadcast into a tall stage.
  Widget _buildTvFocusStage(IptvChannel? ch, int epoch) {
    final app = AppThemeScope.of(context);
    return ClipRRect(
      borderRadius: app.shape.br(8),
      child: ColoredBox(
        color: app.iptv.stageBg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPreviewStage(ch, epoch),
            Expanded(
              child: ch == null
                  ? const SizedBox.shrink()
                  : IptvFocusStageInfo(
                      channel: ch,
                      hasLists: _favorites.customLists.isNotEmpty,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewStage(IptvChannel? ch, int epoch) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Painted FIRST so the video covers it: the underlay engine's
            // punched hole wipes these pixels once frames arrive, and the
            // Texture engine simply draws over them. No Opacity/fade wrappers
            // here — anything layer-based over the punched hole would break
            // the punch-through (house underlay invariant). The floor's tuning
            // animation stops itself once frames show, so nothing keeps
            // repainting under a playing video.
            ValueListenableBuilder<bool>(
              valueListenable: _previewState.previewShowing,
              builder: (context, showing, _) => IptvStageFloor(
                channel: ch,
                tuning: _settingsState.channelPreviewEnabled && ch != null && !showing,
              ),
            ),
            // Startup launch owns the screen: the stage's 900ms dwell would
            // otherwise open a SECOND live stream under the launching player.
            if (ch != null && _settingsState.channelPreviewEnabled && !_playerState.startupLaunchActive)
              ValueListenableBuilder<String?>(
                valueListenable: _previewState.previewStreamUrl,
                builder: (context, streamUrl, _) {
                  // Null while a Stremio channel resolves (or when every
                  // candidate died) — only the floor shows.
                  if (streamUrl == null) return const SizedBox.shrink();
                  // Ladder generation these callbacks belong to — they fire
                  // post-frame, possibly after focus moved to another channel.
                  final ticket = _previewState.previewResolveTicket;
                  return HeroTrailerBackdrop(
                    key: ValueKey('iptv-preview-$epoch'),
                    imageUrl: null,
                    videoUrl: streamUrl,
                    enabled: true,
                    live: true,
                    // The channel's declared UA/Referer — panels that guard
                    // playback with them guard the preview identically.
                    httpHeaders: ch.playbackHeaders,
                    imageBlurSigma: 0,
                    videoBlurSigma: 0,
                    // The dwell: arrowing down the guide never opens a stream
                    // until focus rests. Live streams also open slower than
                    // trailer clips, so a slightly longer debounce than Home's.
                    startDelay: const Duration(milliseconds: 900),
                    ambientVolume: 100,
                    onPlayingChanged: (p) {
                      if (ticket == _previewState.previewResolveTicket) {
                        _previewState.previewShowing.value = p;
                      }
                      if (p) _markPreviewWinner(ticket);
                    },
                    onPlaybackFailed: () => _onPreviewPlaybackFailed(ticket),
                    // Stremio ladder needs stalls to count as failures, or a
                    // silent-dead candidate would block the walk to the next.
                    firstFrameTimeout:
                        StremioIptvService.isStremioChannelUrl(ch.url)
                        ? const Duration(seconds: 12)
                        : null,
                  );
                },
              ),
            // Status chip — top-left, direct paint over the stage.
            Positioned(
              left: 10,
              top: 10,
              child: ValueListenableBuilder<bool>(
                valueListenable: _previewState.previewShowing,
                builder: (context, showing, _) => IptvStageChip(
                  channel: ch,
                  showing: showing,
                  previewEnabled: _settingsState.channelPreviewEnabled,
                ),
              ),
            ),
            // NO styled chrome over the video — final, device-verified rule.
            // Wrapping the preview froze the underlay; even full-rect
            // SIBLING overlays (Positioned.fill brackets/frame painted above
            // the hole, the status-chip pattern) made it flicker on real TV
            // hardware. The styles decorate the panel AROUND this stack only;
            // the shipped chip/identity are the sole overlays. Do not add
            // paint over the preview rect without an on-device test.
          ],
        ),
      ),
    );
  }

  Widget _buildContent({
    bool tvPane = false,
    bool touchSelector = false,
    bool cockpit = false,
  }) {
    // Empty state when no playlists
    if (_settingsState.playlists.isEmpty) {
      return IptvEmptyState(
        hasPlaylists: false,
        onAddPlaylist: _navigation.navigateToSettings,
      );
    }

    // Empty state when no playlist selected
    if (_settingsState.selectedPlaylist == null) {
      return const IptvEmptyState(hasPlaylists: true);
    }

    // Loading
    if (_catalogState.isLoading) {
      return _loadStatus.buildLoadingState(context);
    }

    // Error
    if (_catalogState.errorMessage != null && _catalogState.allChannels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load playlist',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _catalogState.errorMessage!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _settingsLoading.retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // No channels matched. While a progressive load is still streaming in,
    // a definitive "No channels found" would be a lie — matches may simply
    // not have arrived yet, so say that instead.
    if (_catalogState.filteredChannels.isEmpty) {
      if (_catalogState.isLoadingMore) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(height: 16),
              Text(
                widget.searchQuery.isNotEmpty
                    ? 'No matches yet — channels are still loading'
                    : _catalogState.selectedCategory != null
                    ? 'Nothing in this category yet — still loading'
                    : 'Loading channels…',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '${_catalogState.allChannels.length} channel'
                '${_catalogState.allChannels.length == 1 ? '' : 's'} loaded so far',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      final isFavoritesView = _settingsState.selectedPlaylist?.isFavorites ?? false;
      final isListView = _settingsState.selectedPlaylist?.isCustomList ?? false;
      final isContinueView = _settingsState.selectedPlaylist?.isContinueWatching ?? false;
      final unfiltered =
          widget.searchQuery.isEmpty && _catalogState.selectedCategory == null;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              !unfiltered
                  ? Icons.live_tv_outlined
                  : isContinueView
                  ? Icons.history_rounded
                  : isFavoritesView
                  ? Icons.star_border
                  : isListView
                  ? Icons.playlist_add_rounded
                  : Icons.live_tv_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              !unfiltered
                  ? 'No channels found'
                  : isContinueView
                  ? 'Nothing in progress'
                  : isFavoritesView
                  ? 'No favorites yet'
                  : isListView
                  ? 'Nothing in ${_settingsState.selectedPlaylist?.name ?? 'this list'} yet'
                  : 'No channels found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              widget.searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : _catalogState.selectedCategory != null
                  ? 'Try a different category'
                  : isContinueView
                  ? 'Movies you start but do not finish show up here'
                  : isFavoritesView || isListView
                  ? (widget.isTelevision
                        ? 'Hold OK on any channel to add it here'
                        : 'Long-press any channel to add it here')
                  : 'This playlist appears to be empty',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Results — a compact, guide-style list. Multi-column on wide screens so
    // the horizontal space isn't wasted; a single column on phones and in the
    // TV two-pane's guide column (which is roughly phone-width anyway).
    final w = MediaQuery.of(context).size.width;
    final narrowRows = !widget.isTelevision && w < 600;
    final hPadding = tvPane ? 10.0 : (w >= 900 ? 28.0 : 12.0);
    final maxCrossAxisExtent = tvPane ? 720.0 : 440.0;
    const crossAxisSpacing = 12.0;
    final padRight = tvPane ? 24.0 : hPadding;

    // Resolved ONCE per build, not per row: the getter probes channels with
    // IptvEpgService.isEpgCapable, which parses a URL per probe (one for a
    // capable list, up to ten when the leading channels aren't) — reading it
    // from the item builder repeated that for every row the grid materialized.
    // It is constant for the whole list anyway, and the grid gives every tile
    // ONE height, so hoisting also makes the delegate and the rows agree by
    // construction instead of by coincidence.
    final epgRows = _epgRowsActive;
    final rowExtent = _showsPosterRows
        ? kIptvPosterRowExtent
        : epgRows
        ? (cockpit ? kIptvEpgRowTallExtent : kIptvEpgRowExtent)
        : cockpit
        ? kIptvRowTallExtent
        : narrowRows
        ? kIptvNarrowRowExtent
        : kIptvRowExtent;

    final Widget channelBrowser = touchSelector
        ? _buildTabletCenteredSelector(
            _catalogState.filteredChannels,
            rowExtent: rowExtent,
            epgRows: epgRows,
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              // The delegate's own column math, replicated so rows can know
              // whether they sit on the grid's right edge (those get the
              // RIGHT-opens-schedule key; the rest keep plain traversal).
              final crossExtent = (constraints.maxWidth - hPadding - padRight)
                  .clamp(1.0, double.infinity);
              final columns =
                  (crossExtent / (maxCrossAxisExtent + crossAxisSpacing))
                      .ceil()
                      .clamp(1, 100);
              // Captured together so itemCount and the list the delegate indexes
              // can never disagree: a RangeError in itemBuilder is exactly what a
              // count-from-one-variable / rows-from-another split produces the
              // day someone assigns _filteredChannels outside setState.
              final channelList = _catalogState.filteredChannels;
              final itemCount = channelList.length;
              // Published for the startup-channel launch, which must scroll to
              // a row that has never been built (so it has no focus node and
              // no ensureVisible of its own). These are LayoutBuilder locals —
              // unreachable from outside without stashing them.
              _selectionState.gridColumns = columns;
              _selectionState.gridRowExtent = rowExtent;

              // NOT wrapped in TvFocusScrollWrapper: this subtree has no ancestor
              // Scrollable, so the wrapper's ensureVisible walk was a silent no-op
              // — and each row already runs its own ensureVisible on focus, so the
              // wrapper only ever risked a second, competing scroll animation.
              return FocusTraversalGroup(
                child: GridView.builder(
                  controller: _focusState.scrollController,
                  padding: EdgeInsets.fromLTRB(hPadding, 8, padRight, 24),
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: maxCrossAxisExtent,
                    mainAxisExtent: rowExtent,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: crossAxisSpacing,
                  ),
                  itemCount: itemCount,
                  itemBuilder: (context, index) {
                    final channel = channelList[index];
                    // Right edge = last column, or the final item of a partial
                    // last row (nothing exists to its right either way).
                    final rightEdge =
                        index % columns == columns - 1 ||
                        index == itemCount - 1;
                    return IptvChannelRow(
                      // ObjectKey, not ValueKey(url): duplicate URLs are legal
                      // in a playlist and must keep independent row state.
                      key: ObjectKey(channel),
                      channel: channel,
                      isTelevision: widget.isTelevision,
                      onTap: () => _playback.playChannel(channel),
                      onLongPress: (_settingsState.selectedPlaylist?.isContinueWatching ?? false)
                          ? () => _playbackActions.showContinueWatchingActions(channel)
                          : null,
                      focusNode: _focusNodeFor(channel),
                      isFavorited: _membershipState.favoriteUrls.contains(channel.url),
                      inAnyList: _membershipState.membership[channel.url]?.isNotEmpty ?? false,
                      onFavoriteToggle: channel.contentType == 'series'
                          ? null
                          : (isFavorited) =>
                                _favorites.toggleFavorite(channel, isFavorited),
                      onOpenListPicker: channel.contentType == 'series'
                          ? null
                          : () => _favorites.openListPicker(channel),
                      hasCustomLists: _favorites.customLists.isNotEmpty,
                      onFocused: tvPane
                          ? () => _onChannelFocused(channel)
                          : null,
                      onPointerRest: tvPane
                          ? () => _onChannelFocused(channel, fromPointer: true)
                          : null,
                      onDetached: () => _onRowDetached(channel),
                      onSchedule: _scheduleActions.scheduleActionFor(
                        channel,
                        inPlace: widget.isTelevision && tvPane,
                      ),
                      // Cockpit: RIGHT walks into the stage's actions by
                      // geometry instead; the full schedule pane stays
                      // reachable from the stage's Guide button.
                      scheduleOnRightKey: rightEdge && !cockpit,
                      progress: _membershipState.progressByUrl[channel.url],
                      poster: _showsPosterRows,
                      epg: epgRows,
                      twoLineName: cockpit && !_showsPosterRows,
                      // Styled looks exist only in the cockpit, and only for
                      // live/EPG rows — VOD/series posters keep the shipped
                      // layout in every style (plan: posters are untouched).
                      style: cockpit && !_showsPosterRows
                          ? _settingsState.iptvStyle
                          : IptvStyle.command,
                      tileWidth:
                          (crossExtent - (columns - 1) * crossAxisSpacing) /
                          columns,
                    );
                  },
                ),
              );
            },
          );
    // Streamed load still running: a quiet, non-focusable line keeps the
    // visible (possibly filtered) rows honest about being a partial list.
    final subtle = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget buildProgressiveStatus() => Padding(
      padding: EdgeInsets.fromLTRB(hPadding + 4, 6, hPadding, 0),
      child: Row(
        children: [
          SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: subtle.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.searchQuery.isNotEmpty
                  ? 'Still loading (${_catalogState.allChannels.length} so far) — '
                        'search results may be incomplete'
                  : 'Still loading channels — '
                        '${_catalogState.allChannels.length} so far',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: subtle,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (touchSelector) {
      // Keep this parent chain stable when the final progressive result hides
      // the status line. Moving the selector from inside a Column to the root
      // would dispose it even with a stable key and reset its scroll state.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _catalogState.isLoadingMore ? buildProgressiveStatus() : const SizedBox.shrink(),
          Expanded(
            key: const ValueKey('iptv-tablet-selector-slot'),
            child: channelBrowser,
          ),
        ],
      );
    }

    if (!_catalogState.isLoadingMore) return channelBrowser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildProgressiveStatus(),
        Expanded(child: channelBrowser),
      ],
    );
  }

  Widget _buildTabletCenteredSelector(
    List<IptvChannel> channels, {
    required double rowExtent,
    required bool epgRows,
  }) {
    final selection = _reconcileTabletSelection(channels);
    return IptvCenteredSelector(
      key: const ValueKey('iptv-tablet-centered-selector'),
      itemCount: channels.length,
      itemExtent: rowExtent,
      initialIndex: selection.index,
      selectionToken: selection.identity,
      onSelected: (index) {
        if (!mounted || index < 0 || index >= channels.length) return;
        _selectTabletChannel(index, channels[index]);
      },
      itemBuilder: (context, index, selected, centerItem) {
        final channel = channels[index];
        final openSchedule = _scheduleActions.scheduleActionFor(channel, inPlace: true);
        return IptvChannelRow(
          key: ObjectKey(channel),
          channel: channel,
          isPreviewSelected: selected,
          onTap: centerItem,
          onLongPress: (_settingsState.selectedPlaylist?.isContinueWatching ?? false)
              ? () => _playbackActions.showContinueWatchingActions(channel)
              : null,
          isFavorited: _membershipState.favoriteUrls.contains(channel.url),
          inAnyList: _membershipState.membership[channel.url]?.isNotEmpty ?? false,
          onFavoriteToggle: channel.contentType == 'series'
              ? null
              : (isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
          onOpenListPicker: channel.contentType == 'series'
              ? null
              : () => _favorites.openListPicker(channel),
          hasCustomLists: _favorites.customLists.isNotEmpty,
          onSchedule: openSchedule == null
              ? null
              : () {
                  centerItem();
                  _selectTabletChannel(index, channel);
                  openSchedule();
                },
          progress: _membershipState.progressByUrl[channel.url],
          poster: _showsPosterRows,
          epg: epgRows,
        );
      },
    );
  }

  TabletChannelIdentity _tabletIdentityOf(IptvChannel channel) => (
    channelNumber: channel.channelNumber,
    name: channel.name,
    url: channel.url,
    group: channel.group,
    contentType: channel.contentType,
  );

  ({int index, TabletChannelIdentity identity}) _reconcileTabletSelection(
    List<IptvChannel> channels,
  ) {
    assert(channels.isNotEmpty);
    final wanted = _selectionState.tabletSelectedIdentity;
    if (wanted != null) {
      final previous = _selectionState.tabletSelectedIndex;
      if (previous >= 0 &&
          previous < channels.length &&
          _tabletIdentityOf(channels[previous]) == wanted) {
        return (index: previous, identity: wanted);
      }

      // Materialized lists (including progressive Stremio snapshots) can
      // cheaply find a row that moved after filtering. Never walk a paged DB
      // facade here: that could fault tens of thousands of rows during build.
      if (channels is! DbChannelList) {
        for (var index = 0; index < channels.length; index++) {
          if (_tabletIdentityOf(channels[index]) == wanted) {
            _selectionState.tabletSelectedIndex = index;
            return (index: index, identity: wanted);
          }
        }
      } else {
        final shown = _previewState.previewShown.value;
        final index = shown == null ? null : channels.indexOfInstance(shown);
        if (index != null && _tabletIdentityOf(channels[index]) == wanted) {
          _selectionState.tabletSelectedIndex = index;
          return (index: index, identity: wanted);
        }
      }
    }

    final identity = _tabletIdentityOf(channels.first);
    _selectionState.tabletSelectedIndex = 0;
    _selectionState.tabletSelectedIdentity = identity;
    return (index: 0, identity: identity);
  }

  void _selectTabletChannel(int index, IptvChannel channel) {
    _selectionState.tabletSelectedIndex = index;
    _selectionState.tabletSelectedIdentity = _tabletIdentityOf(channel);
    _onChannelFocused(channel);
  }
}





// ── TV preview rail widgets ─────────────────────────────────────────────────





















/// Real production tear-offs and borrowed identities for characterization.
@visibleForTesting
({
  Future<Map<String, dynamic>?> Function(Map<String, dynamic>) browse,
  Future<void> Function(IptvPlaylist) loadPlaylist,
  void Function(String?) chooseCategory,
  Future<void> Function(
    IptvPlaylist,
    String,
    String,
    int, {
    bool usePublishedSnapshot,
  }) refreshCatalog,
  Future<void> Function(
    IptvPlaylist,
    int,
    CatalogSnapshot, {
    String? warning,
    bool migrateFavorites,
  }) presentDbCatalog,
  FocusNode Function(IptvChannel) focusNodeFor,
  bool Function(IptvChannel) rowAttached,
  List<IptvChannel> allChannels,
  List<IptvChannel> filteredChannels,
  List<IptvPlaylist> playlists,
  IptvPlaylist? selectedPlaylist,
  String? selectedCategory,
  CatalogSnapshot? snapshot,
  Map<IptvChannel, FocusNode> focusNodes,
  Set<IptvChannel> detachedRows,
  ValueNotifier<IptvChannel?> previewShown,
  ValueNotifier<EpgProgramme?> programmeShown,
  int loadTicket,
  bool landingSeedArmed,
  bool categoryManuallyChosen,
}) iptvResultsViewTestAccess(IptvResultsViewState state) => (
  browse: state._playerBrowse.providePlayerIptvBrowse,
  loadPlaylist: state._catalogLoading.loadPlaylist,
  chooseCategory: state._filtersSection.onCategoryChanged,
  refreshCatalog: state._catalogRefresh.applyDbCatalogRefresh,
  presentDbCatalog: state._catalogPresentation.presentDbCatalog,
  focusNodeFor: state._focusNodeFor,
  rowAttached: state._rowAttached,
  allChannels: state._catalogState.allChannels,
  filteredChannels: state._catalogState.filteredChannels,
  playlists: state._settingsState.playlists,
  selectedPlaylist: state._settingsState.selectedPlaylist,
  selectedCategory: state._catalogState.selectedCategory,
  snapshot: state._catalogState.dbSnapshot,
  focusNodes: state._focusState.cardFocusNodes,
  detachedRows: state._focusState.detachedRows,
  previewShown: state._previewState.previewShown,
  programmeShown: state._previewState.spotlightProgrammeShown,
  loadTicket: state._catalogState.loadTicket,
  landingSeedArmed: state._catalogState.landingSeedArmed,
  categoryManuallyChosen: state._catalogState.categoryManuallyChosen,
);
