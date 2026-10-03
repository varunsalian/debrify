import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_classic_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_cockpit_stage.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_content_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_loaded_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_quiet_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_content.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_focus.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_hero.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_selection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_two_pane_layout.dart';
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
import 'package:debrify/features/iptv/application/iptv_status_chip_types.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_landing_policy.dart';
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import '../../models/iptv_playlist.dart';
import '../browse/browse_results_focus.dart';
import '../../services/iptv_channel_order.dart';
import '../../services/iptv_media_store.dart' show IptvListMeta;
import '../../services/iptv_catalog_db.dart';
import '../../services/iptv_catalog_refresh_service.dart';
import '../../services/main_page_bridge.dart';
import '../../services/stremio_service.dart';
import '../../services/iptv_epg_service.dart';
import 'spotlight/iptv_spotlight_layout.dart';
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
  late final IptvRowProjection _rowProjection = IptvRowProjection((
    catalogState: _catalogState,
    focusState: _focusState,
    settingsState: _settingsState,
    isTelevision: () => widget.isTelevision,
  ));
  late final IptvLoadedLayout _loadedLayout = IptvLoadedLayout((
    selectionState: _selectionState,
    settingsState: _settingsState,
    statusState: _statusState,
    buildClassic: () => _classicLayout.buildClassic(),
    buildSpotlight: (BoxConstraints constraints, IptvSpotlightLayoutMode mode) => _spotlightLayout.buildSpotlight(constraints, mode),
    buildTvTwoPane: (BoxConstraints c, {required bool touchSelector}) => _twoPaneLayout.buildTvTwoPane(c, touchSelector: touchSelector),
    context: () => context,
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    searchHeader: () => widget.searchHeader,
    setState: setState,
  ));
  late final IptvSpotlightLayout _spotlightLayout = IptvSpotlightLayout((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    recordingState: _recordingState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    anyRecordingLive: () => _recordingSupport.anyRecordingLive,
    buildSpotlightContent: (IptvSpotlightLayoutMode mode) => _spotlightContent.buildSpotlightContent(mode),
    buildSpotlightHero: (IptvSpotlightLayoutMode mode) => _spotlightHero.buildSpotlightHero(mode),
    canShowCategoryOptions: () => _categoryActions.canShowCategoryOptions,
    categoryCounts: () => _rowProjection.categoryCounts,
    closeSpotlightSources: () => _spotlightFocus.closeSpotlightSources(),
    context: () => context,
    customLists: () => _favorites.customLists,
    effectiveCategory: () => _filtersSection.effectiveCategory,
    exitSpotlightSourcesToApp: () => _spotlightFocus.exitSpotlightSourcesToApp(),
    focusSpotlightHero: () => _spotlightFocus.focusSpotlightHero(),
    focusSpotlightSearchOrExit: () => _spotlightFocus.focusSpotlightSearchOrExit(),
    focusSpotlightSearchResults: () => _spotlightFocus.focusSpotlightSearchResults(),
    focusSpotlightSources: () => _spotlightFocus.focusSpotlightSources(),
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    navigateToAddons: () => _quietFilters.navigateToAddons(),
    navigateToManageSources: () => _navigation.navigateToManageSources(),
    navigateToSettings: ({bool openAddSource = true}) => _navigation.navigateToSettings(openAddSource: openAddSource),
    onCategoryChanged: (String? category) => _filtersSection.onCategoryChanged(category),
    onContentTypeChanged: (String contentType) => _filtersSection.onContentTypeChanged(contentType),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    openScheduledRecordings: () => _recordingSupport.openScheduledRecordings(),
    openSpotlightSearch: () => _spotlightFocus.openSpotlightSearch(),
    promptCategoryOptions: (String category) => _categoryActions.promptCategoryOptions(category),
    promptCreateList: () => _favorites.promptCreateList(),
    searchHeader: () => widget.searchHeader,
    setSpotlightSourcesExpanded: (bool expanded) => _spotlightFocus.setSpotlightSourcesExpanded(expanded),
    spotlightControlNavigation: (Widget child) => _spotlightFocus.spotlightControlNavigation(child),
    spotlightSelectedSourceCount: () => _spotlightFocus.spotlightSelectedSourceCount,
  ));
  late final IptvSpotlightFocus _spotlightFocus = IptvSpotlightFocus((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    recordingState: _recordingState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    applyFilters: () => _filtersSection.applyFilters(),
    customLists: () => _favorites.customLists,
    focusFirstChannel: () => _navigation.focusFirstChannel(),
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    onUpArrowFromFilters: () => widget.onUpArrowFromFilters,
    searchHeader: () => widget.searchHeader,
    searchQuery: () => widget.searchQuery,
    setState: setState,
  ));
  late final IptvSpotlightHero _spotlightHero = IptvSpotlightHero((
    focusState: _focusState,
    membershipState: _membershipState,
    previewState: _previewState,
    recordingState: _recordingState,
    androidEngineTaskFor: (IptvChannel channel) => _androidRecording.androidEngineTaskFor(channel),
    buildPreviewStage: (IptvChannel? ch, int epoch) => _previewLayout.buildPreviewStage(ch, epoch),
    channelEngineRecordable: (IptvChannel channel) => _recordingSupport.channelEngineRecordable(channel),
    customLists: () => _favorites.customLists,
    debugSpotlightNow: () => widget.debugSpotlightNow,
    desktopCaptureFor: (IptvChannel channel) => _desktopRecording.desktopCaptureFor(channel),
    isTelevision: () => widget.isTelevision,
    openSchedulePane: (IptvChannel channel) => _scheduleActions.openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) => _catchup.playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    recordProgrammeActionFor: (IptvChannel channel) => _scheduleActions.recordProgrammeActionFor(channel),
    showSpotlightChannelActions: (IptvChannel channel, {EpgProgramme? programme}) => _spotlightActions.showSpotlightChannelActions(channel, programme: programme),
    spotlightActivation: (VoidCallback action, Widget child) => _spotlightActions.spotlightActivation(action, child),
    spotlightFocusBorder: () => _spotlightActions.spotlightFocusBorder,
    spotlightIconAction: ({required String tooltip, required IconData icon, required VoidCallback onPressed, bool selected = false}) => _spotlightActions.spotlightIconAction(tooltip: tooltip, icon: icon, onPressed: onPressed, selected: selected),
    stageHoverGuard: (Widget child) => _previewTuning.stageHoverGuard(child),
    stageRecordNow: (IptvChannel channel) => _recordNow.stageRecordNow(channel),
    stageStopAndroidRecording: (IptvChannel channel, String taskId) => _androidRecording.stageStopAndroidRecording(channel, taskId),
    stageStopDesktopRecording: (DesktopRecordingCapture capture) => _desktopRecording.stageStopDesktopRecording(capture),
    toggleFavorite: (IptvChannel channel, bool isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
  ));
  late final IptvSpotlightActions _spotlightActions = IptvSpotlightActions((
    membershipState: _membershipState,
    context: () => context,
    customLists: () => _favorites.customLists,
    mounted: () => mounted,
    openListPicker: (IptvChannel channel) => _favorites.openListPicker(channel),
    openSchedulePane: (IptvChannel channel) => _scheduleActions.openSchedulePane(channel),
    spotlightRecordAction: (IptvChannel channel) => _spotlightHero.spotlightRecordAction(channel),
    toggleFavorite: (IptvChannel channel, bool isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
  ));
  late final IptvSpotlightContent _spotlightContent = IptvSpotlightContent((
    catalogState: _catalogState,
    focusState: _focusState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    buildContent: ({bool tvPane = false, bool touchSelector = false, bool cockpit = false}) => _contentLayout.buildContent(tvPane: tvPane, touchSelector: touchSelector, cockpit: cockpit),
    closeSchedulePane: () => _scheduleActions.closeSchedulePane(),
    debugSpotlightNow: () => widget.debugSpotlightNow,
    focusSpotlightSources: () => _spotlightFocus.focusSpotlightSources(),
    isTelevision: () => widget.isTelevision,
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) => _previewTuning.onChannelFocused(channel, fromPointer: fromPointer),
    openSchedulePane: (IptvChannel channel) => _scheduleActions.openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) => _catchup.playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    recordProgrammeActionFor: (IptvChannel channel) => _scheduleActions.recordProgrammeActionFor(channel),
    showSpotlightChannelActions: (IptvChannel channel, {EpgProgramme? programme}) => _spotlightActions.showSpotlightChannelActions(channel, programme: programme),
  ));
  late final IptvClassicLayout _classicLayout = IptvClassicLayout((
    catalogState: _catalogState,
    focusState: _focusState,
    recordingState: _recordingState,
    settingsState: _settingsState,
    anyRecordingLive: () => _recordingSupport.anyRecordingLive,
    buildContent: ({bool tvPane = false, bool touchSelector = false, bool cockpit = false}) => _contentLayout.buildContent(tvPane: tvPane, touchSelector: touchSelector, cockpit: cockpit),
    canShowCategoryOptions: () => _categoryActions.canShowCategoryOptions,
    categoryCounts: () => _rowProjection.categoryCounts,
    effectiveCategory: () => _filtersSection.effectiveCategory,
    focusFirstChannel: () => _navigation.focusFirstChannel(),
    navigateToSettings: ({bool openAddSource = true}) => _navigation.navigateToSettings(openAddSource: openAddSource),
    onCategoryChanged: (String? category) => _filtersSection.onCategoryChanged(category),
    onContentTypeChanged: (String contentType) => _filtersSection.onContentTypeChanged(contentType),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    onUpArrowFromFilters: () => widget.onUpArrowFromFilters,
    openScheduledRecordings: () => _recordingSupport.openScheduledRecordings(),
    promptCategoryOptions: (String category) => _categoryActions.promptCategoryOptions(category),
  ));
  late final IptvTwoPaneLayout _twoPaneLayout = IptvTwoPaneLayout((
    catalogState: _catalogState,
    membershipState: _membershipState,
    previewState: _previewState,
    recordingState: _recordingState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    statusState: _statusState,
    buildCockpitStage: () => _cockpitStage.buildCockpitStage(),
    buildContent: ({bool tvPane = false, bool touchSelector = false, bool cockpit = false}) => _contentLayout.buildContent(tvPane: tvPane, touchSelector: touchSelector, cockpit: cockpit),
    buildPreviewRail: ({required bool touchSelector}) => _previewLayout.buildPreviewRail(touchSelector: touchSelector),
    buildQuietFilters: () => _quietFilters.buildQuietFilters(),
    closeSchedulePane: () => _scheduleActions.closeSchedulePane(),
    isTelevision: () => widget.isTelevision,
    navigateToManageSources: () => _navigation.navigateToManageSources(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    openScheduledRecordings: () => _recordingSupport.openScheduledRecordings(),
    playCatchup: (IptvChannel channel, EpgProgramme programme) => _catchup.playCatchup(channel, programme),
    recordProgrammeActionFor: (IptvChannel channel) => _scheduleActions.recordProgrammeActionFor(channel),
    refreshAndroidRecordingState: () => _androidRecording.refreshAndroidRecordingState(),
  ));
  late final IptvCockpitStage _cockpitStage = IptvCockpitStage((
    membershipState: _membershipState,
    previewState: _previewState,
    recordingState: _recordingState,
    settingsState: _settingsState,
    androidEngineTaskFor: (IptvChannel channel) => _androidRecording.androidEngineTaskFor(channel),
    buildPreviewStage: (IptvChannel? ch, int epoch) => _previewLayout.buildPreviewStage(ch, epoch),
    channelEngineRecordable: (IptvChannel channel) => _recordingSupport.channelEngineRecordable(channel),
    context: () => context,
    desktopCaptureFor: (IptvChannel channel) => _desktopRecording.desktopCaptureFor(channel),
    isTelevision: () => widget.isTelevision,
    openSchedulePane: (IptvChannel channel) => _scheduleActions.openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) => _catchup.playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    returnFocusFromStage: () => _previewTuning.returnFocusFromStage(),
    scheduleProgrammeFromStage: (IptvChannel channel, EpgProgramme programme) => _scheduleActions.scheduleProgrammeFromStage(channel, programme),
    stageHoverGuard: (Widget child) => _previewTuning.stageHoverGuard(child),
    stageRecordNow: (IptvChannel channel) => _recordNow.stageRecordNow(channel),
    stageStopAndroidRecording: (IptvChannel channel, String taskId) => _androidRecording.stageStopAndroidRecording(channel, taskId),
    stageStopDesktopRecording: (DesktopRecordingCapture capture) => _desktopRecording.stageStopDesktopRecording(capture),
    toggleFavorite: (IptvChannel channel, bool isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
  ));
  late final IptvQuietFilters _quietFilters = IptvQuietFilters((
    catalogState: _catalogState,
    focusState: _focusState,
    settingsState: _settingsState,
    canShowCategoryOptions: () => _categoryActions.canShowCategoryOptions,
    categoryCounts: () => _rowProjection.categoryCounts,
    context: () => context,
    effectiveCategory: () => _filtersSection.effectiveCategory,
    focusFirstChannel: () => _navigation.focusFirstChannel(),
    isTelevision: () => widget.isTelevision,
    navigateToSettings: ({bool openAddSource = true}) => _navigation.navigateToSettings(openAddSource: openAddSource),
    onCategoryChanged: (String? category) => _filtersSection.onCategoryChanged(category),
    onContentTypeChanged: (String contentType) => _filtersSection.onContentTypeChanged(contentType),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) => _filtersSection.onPlaylistChanged(playlist, focusContent: focusContent),
    onUpArrowFromFilters: () => widget.onUpArrowFromFilters,
    promptCategoryOptions: (String category) => _categoryActions.promptCategoryOptions(category),
    promptCreateList: () => _favorites.promptCreateList(),
  ));
  late final IptvPreviewTuning _previewTuning = IptvPreviewTuning((
    focusState: _focusState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    armAndroidRecStateRefresh: () => _androidRecording.armAndroidRecStateRefresh(),
    flushPreviewRearm: () => _previewHandoff.flushPreviewRearm(),
    focusFirstChannel: () => _navigation.focusFirstChannel(),
    focusNodeFor: (IptvChannel channel) => _rowProjection.focusNodeFor(channel),
    isTelevision: () => widget.isTelevision,
    mounted: () => mounted,
    rowAttached: (IptvChannel channel) => _rowProjection.rowAttached(channel),
  ));
  late final IptvPreviewLayout _previewLayout = IptvPreviewLayout((
    playerState: _playerState,
    previewState: _previewState,
    settingsState: _settingsState,
    context: () => context,
    customLists: () => _favorites.customLists,
    isTelevision: () => widget.isTelevision,
    markPreviewWinner: (int ticket) => _previewTuning.markPreviewWinner(ticket),
    onPreviewPlaybackFailed: (int ticket) => _previewTuning.onPreviewPlaybackFailed(ticket),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    stageHoverGuard: (Widget child) => _previewTuning.stageHoverGuard(child),
  ));
  late final IptvContentLayout _contentLayout = IptvContentLayout((
    catalogState: _catalogState,
    focusState: _focusState,
    membershipState: _membershipState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    buildLoadingState: (BuildContext context) => _loadStatus.buildLoadingState(context),
    buildTabletCenteredSelector: (List<IptvChannel> channels, {required double rowExtent, required bool epgRows}) => _tabletSelection.buildTabletCenteredSelector(channels, rowExtent: rowExtent, epgRows: epgRows),
    context: () => context,
    customLists: () => _favorites.customLists,
    epgRowsActive: () => _rowProjection.epgRowsActive,
    focusNodeFor: (IptvChannel channel) => _rowProjection.focusNodeFor(channel),
    isTelevision: () => widget.isTelevision,
    navigateToSettings: ({bool openAddSource = true}) => _navigation.navigateToSettings(openAddSource: openAddSource),
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) => _previewTuning.onChannelFocused(channel, fromPointer: fromPointer),
    onRowDetached: (IptvChannel channel) => _rowProjection.onRowDetached(channel),
    openListPicker: (IptvChannel channel) => _favorites.openListPicker(channel),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) => _playback.playChannel(channel, shouldCancel: shouldCancel),
    retryLoad: () => _settingsLoading.retryLoad(),
    scheduleActionFor: (IptvChannel channel, {bool inPlace = false}) => _scheduleActions.scheduleActionFor(channel, inPlace: inPlace),
    searchQuery: () => widget.searchQuery,
    showContinueWatchingActions: (IptvChannel channel) => _playbackActions.showContinueWatchingActions(channel),
    showsPosterRows: () => _rowProjection.showsPosterRows,
    toggleFavorite: (IptvChannel channel, bool isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
  ));
  late final IptvTabletSelection _tabletSelection = IptvTabletSelection((
    membershipState: _membershipState,
    previewState: _previewState,
    selectionState: _selectionState,
    settingsState: _settingsState,
    customLists: () => _favorites.customLists,
    mounted: () => mounted,
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) => _previewTuning.onChannelFocused(channel, fromPointer: fromPointer),
    openListPicker: (IptvChannel channel) => _favorites.openListPicker(channel),
    scheduleActionFor: (IptvChannel channel, {bool inPlace = false}) => _scheduleActions.scheduleActionFor(channel, inPlace: inPlace),
    showContinueWatchingActions: (IptvChannel channel) => _playbackActions.showContinueWatchingActions(channel),
    showsPosterRows: () => _rowProjection.showsPosterRows,
    toggleFavorite: (IptvChannel channel, bool isFavorited) => _favorites.toggleFavorite(channel, isFavorited),
  ));

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
    selectTabletChannel: (int index, IptvChannel channel) => _tabletSelection.selectTabletChannel(index, channel),
    setState: setState,
    spotlightRequestedForDevice: () => _rowProjection.spotlightRequestedForDevice,
    spotlightUsesTimeline: () => _spotlightContent.spotlightUsesTimeline,
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
    clearPreview: () => _previewTuning.clearPreview(),
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
    clearPreview: () => _previewTuning.clearPreview(),
    mounted: () => mounted,
    refreshAfterPlayback: () => _playbackRefresh.refreshAfterPlayback(),
    setSpotlightSourcesExpanded: (bool expanded) => _spotlightFocus.setSpotlightSourcesExpanded(expanded),
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
    focusNodeFor: (IptvChannel channel) => _rowProjection.focusNodeFor(channel),
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
    clearPreview: () => _previewTuning.clearPreview(),
    focusNodeFor: (IptvChannel channel) => _rowProjection.focusNodeFor(channel),
    focusSpotlightContentEntry: () => _spotlightFocus.focusSpotlightContentEntry(),
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
    categoryCounts: () => _rowProjection.categoryCounts,
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
    retunePreview: (IptvChannel channel) => _previewTuning.retunePreview(channel),
    setState: setState,
    stopPreviewPlayback: () => _previewTuning.stopPreviewPlayback(),
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
    clearPreview: () => _previewTuning.clearPreview(),
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
    rowAttached: (IptvChannel channel) => _rowProjection.rowAttached(channel),
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























  static const double tabletTwoPaneMinWidth = IptvLayoutPolicy.tabletTwoPaneMinWidth;
  static const double tabletTwoPaneMinHeight = IptvLayoutPolicy.tabletTwoPaneMinHeight;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) => IptvLayoutPolicy.shouldUseTouchTabletTwoPane(isTelevision: isTelevision, isWeb: isWeb, platform: platform, availableSize: availableSize);



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






















  // Focus nodes for DPAD




















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
      _spotlightFocus.focusSpotlightSources();
    } else {
      _focusState.playlistFilterFocusNode.requestFocus();
    }
  }

  @override
  void focusSearchResults() {
    if (_selectionState.spotlightLayoutMode != IptvSpotlightLayoutMode.classic) {
      _spotlightFocus.focusSpotlightSearchResults();
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
        return _loadedLayout.withBrowseSearch(
          const Center(child: CircularProgressIndicator()),
        );
      }
      return _loadedLayout.withBrowseSearch(
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
        final spotlightRequested = _rowProjection.spotlightRequestedForDevice;
        final spotlightMode = spotlightRequested
            ? resolveIptvSpotlightLayout(outerSize)
            : IptvSpotlightLayoutMode.classic;
        if (spotlightMode != IptvSpotlightLayoutMode.classic) {
          return _loadedLayout.buildLoadedLayout(
            outerConstraints,
            spotlightRequested: spotlightRequested,
            spotlightMode: spotlightMode,
          );
        }
        return _loadedLayout.withBrowseSearch(
          LayoutBuilder(
            builder: (context, bodyConstraints) => _loadedLayout.buildLoadedLayout(
              bodyConstraints,
              spotlightRequested: spotlightRequested,
              spotlightMode: IptvSpotlightLayoutMode.classic,
            ),
          ),
        );
      },
    );
  }









  // ── Spotlight Guide ───────────────────────────────────────────────────────































































  // ── TV two-pane ──────────────────────────────────────────────────────────


















































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
  focusNodeFor: state._rowProjection.focusNodeFor,
  rowAttached: state._rowProjection.rowAttached,
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
