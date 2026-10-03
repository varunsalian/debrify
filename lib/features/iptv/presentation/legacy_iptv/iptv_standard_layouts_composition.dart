import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catchup.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_categories.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_classic_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_cockpit_stage.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_content_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_desktop_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_load_status.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_loaded_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_navigation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_quiet_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_record_now.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_root_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_selection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_two_pane_layout.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';

typedef IptvStandardLayoutsCompositionExternalSections = ({
  IptvAndroidRecording Function() androidRecording,
  IptvCatchup Function() catchup,
  IptvCategories Function() categoryActions,
  IptvDesktopRecording Function() desktopRecording,
  IptvFavorites Function() favorites,
  IptvFiltersSection Function() filtersSection,
  IptvLoadStatus Function() loadStatus,
  IptvNavigation Function() navigation,
  IptvPlayback Function() playback,
  IptvPlaybackActions Function() playbackActions,
  IptvPreviewLayout Function() previewLayout,
  IptvPreviewTuning Function() previewTuning,
  IptvRecordNow Function() recordNow,
  IptvRecordingSupport Function() recordingSupport,
  IptvRowProjection Function() rowProjection,
  IptvScheduleActions Function() scheduleActions,
  IptvSettingsLoading Function() settingsLoading,
  IptvSpotlightLayout Function() spotlightLayout,
  IptvTabletSelection Function() tabletSelection,
});

/// Constructs the standard layouts sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvStandardLayoutsComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvStandardLayoutsCompositionExternalSections _external;

  IptvStandardLayoutsComposition(this._view, this._states, this._external);

  late final IptvRootLayout rootLayout = IptvRootLayout((
    setState: _view.setState,
    settingsState: _states.settingsState,
    withBrowseSearch: (child) => loadedLayout.withBrowseSearch(child),
    buildLoadedLayout:
        (constraints, {required spotlightRequested, required spotlightMode}) =>
            loadedLayout.buildLoadedLayout(
              constraints,
              spotlightRequested: spotlightRequested,
              spotlightMode: spotlightMode,
            ),
    loadSettings: ({bool forceReload = false}) =>
        _external.settingsLoading().loadSettings(forceReload: forceReload),
    spotlightRequestedForDevice: () =>
        _external.rowProjection().spotlightRequestedForDevice,
  ));

  late final IptvLoadedLayout loadedLayout = IptvLoadedLayout((
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    statusState: _states.statusState,
    buildClassic: () => classicLayout.buildClassic(),
    buildSpotlight:
        (BoxConstraints constraints, IptvSpotlightLayoutMode mode) =>
            _external.spotlightLayout().buildSpotlight(constraints, mode),
    buildTvTwoPane: (BoxConstraints c, {required bool touchSelector}) =>
        twoPaneLayout.buildTvTwoPane(c, touchSelector: touchSelector),
    context: () => _view.context(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    searchHeader: () => _view.searchHeader(),
    setState: _view.setState,
  ));

  late final IptvClassicLayout classicLayout = IptvClassicLayout((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    anyRecordingLive: () => _external.recordingSupport().anyRecordingLive,
    buildContent:
        ({
          bool tvPane = false,
          bool touchSelector = false,
          bool cockpit = false,
        }) => contentLayout.buildContent(
          tvPane: tvPane,
          touchSelector: touchSelector,
          cockpit: cockpit,
        ),
    canShowCategoryOptions: () =>
        _external.categoryActions().canShowCategoryOptions,
    categoryCounts: () => _external.rowProjection().categoryCounts,
    effectiveCategory: () => _external.filtersSection().effectiveCategory,
    focusFirstChannel: () => _external.navigation().focusFirstChannel(),
    navigateToSettings: ({bool openAddSource = true}) =>
        _external.navigation().navigateToSettings(openAddSource: openAddSource),
    onCategoryChanged: (String? category) =>
        _external.filtersSection().onCategoryChanged(category),
    onContentTypeChanged: (String contentType) =>
        _external.filtersSection().onContentTypeChanged(contentType),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    onUpArrowFromFilters: () => _view.onUpArrowFromFilters(),
    openScheduledRecordings: () =>
        _external.recordingSupport().openScheduledRecordings(),
    promptCategoryOptions: (String category) =>
        _external.categoryActions().promptCategoryOptions(category),
  ));

  late final IptvTwoPaneLayout twoPaneLayout = IptvTwoPaneLayout((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    recordingState: _states.recordingState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    statusState: _states.statusState,
    buildCockpitStage: () => cockpitStage.buildCockpitStage(),
    buildContent:
        ({
          bool tvPane = false,
          bool touchSelector = false,
          bool cockpit = false,
        }) => contentLayout.buildContent(
          tvPane: tvPane,
          touchSelector: touchSelector,
          cockpit: cockpit,
        ),
    buildPreviewRail: ({required bool touchSelector}) => _external
        .previewLayout()
        .buildPreviewRail(touchSelector: touchSelector),
    buildQuietFilters: () => quietFilters.buildQuietFilters(),
    closeSchedulePane: () => _external.scheduleActions().closeSchedulePane(),
    isTelevision: () => _view.isTelevision(),
    navigateToManageSources: () =>
        _external.navigation().navigateToManageSources(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    openScheduledRecordings: () =>
        _external.recordingSupport().openScheduledRecordings(),
    playCatchup: (IptvChannel channel, EpgProgramme programme) =>
        _external.catchup().playCatchup(channel, programme),
    recordProgrammeActionFor: (IptvChannel channel) =>
        _external.scheduleActions().recordProgrammeActionFor(channel),
    refreshAndroidRecordingState: () =>
        _external.androidRecording().refreshAndroidRecordingState(),
  ));

  late final IptvCockpitStage cockpitStage = IptvCockpitStage((
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    androidEngineTaskFor: (IptvChannel channel) =>
        _external.androidRecording().androidEngineTaskFor(channel),
    buildPreviewStage: (IptvChannel? ch, int epoch) =>
        _external.previewLayout().buildPreviewStage(ch, epoch),
    channelEngineRecordable: (IptvChannel channel) =>
        _external.recordingSupport().channelEngineRecordable(channel),
    context: () => _view.context(),
    desktopCaptureFor: (IptvChannel channel) =>
        _external.desktopRecording().desktopCaptureFor(channel),
    isTelevision: () => _view.isTelevision(),
    openSchedulePane: (IptvChannel channel) =>
        _external.scheduleActions().openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) =>
        _external.catchup().playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        _external.playback().playChannel(channel, shouldCancel: shouldCancel),
    returnFocusFromStage: () =>
        _external.previewTuning().returnFocusFromStage(),
    scheduleProgrammeFromStage: (IptvChannel channel, EpgProgramme programme) =>
        _external.scheduleActions().scheduleProgrammeFromStage(
          channel,
          programme,
        ),
    stageHoverGuard: (Widget child) =>
        _external.previewTuning().stageHoverGuard(child),
    stageRecordNow: (IptvChannel channel) =>
        _external.recordNow().stageRecordNow(channel),
    stageStopAndroidRecording: (IptvChannel channel, String taskId) =>
        _external.androidRecording().stageStopAndroidRecording(channel, taskId),
    stageStopDesktopRecording: (DesktopRecordingCapture capture) =>
        _external.desktopRecording().stageStopDesktopRecording(capture),
    toggleFavorite: (IptvChannel channel, bool isFavorited) =>
        _external.favorites().toggleFavorite(channel, isFavorited),
  ));

  late final IptvQuietFilters quietFilters = IptvQuietFilters((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    settingsState: _states.settingsState,
    canShowCategoryOptions: () =>
        _external.categoryActions().canShowCategoryOptions,
    categoryCounts: () => _external.rowProjection().categoryCounts,
    context: () => _view.context(),
    effectiveCategory: () => _external.filtersSection().effectiveCategory,
    focusFirstChannel: () => _external.navigation().focusFirstChannel(),
    isTelevision: () => _view.isTelevision(),
    navigateToSettings: ({bool openAddSource = true}) =>
        _external.navigation().navigateToSettings(openAddSource: openAddSource),
    onCategoryChanged: (String? category) =>
        _external.filtersSection().onCategoryChanged(category),
    onContentTypeChanged: (String contentType) =>
        _external.filtersSection().onContentTypeChanged(contentType),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    onUpArrowFromFilters: () => _view.onUpArrowFromFilters(),
    promptCategoryOptions: (String category) =>
        _external.categoryActions().promptCategoryOptions(category),
    promptCreateList: () => _external.favorites().promptCreateList(),
  ));

  late final IptvContentLayout contentLayout = IptvContentLayout((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    buildLoadingState: (BuildContext context) =>
        _external.loadStatus().buildLoadingState(context),
    buildTabletCenteredSelector:
        (
          List<IptvChannel> channels, {
          required double rowExtent,
          required bool epgRows,
        }) => _external.tabletSelection().buildTabletCenteredSelector(
          channels,
          rowExtent: rowExtent,
          epgRows: epgRows,
        ),
    context: () => _view.context(),
    customLists: () => _external.favorites().customLists,
    epgRowsActive: () => _external.rowProjection().epgRowsActive,
    focusNodeFor: (IptvChannel channel) =>
        _external.rowProjection().focusNodeFor(channel),
    isTelevision: () => _view.isTelevision(),
    navigateToSettings: ({bool openAddSource = true}) =>
        _external.navigation().navigateToSettings(openAddSource: openAddSource),
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) =>
        _external.previewTuning().onChannelFocused(
          channel,
          fromPointer: fromPointer,
        ),
    onRowDetached: (IptvChannel channel) =>
        _external.rowProjection().onRowDetached(channel),
    openListPicker: (IptvChannel channel) =>
        _external.favorites().openListPicker(channel),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        _external.playback().playChannel(channel, shouldCancel: shouldCancel),
    retryLoad: () => _external.settingsLoading().retryLoad(),
    scheduleActionFor: (IptvChannel channel, {bool inPlace = false}) =>
        _external.scheduleActions().scheduleActionFor(
          channel,
          inPlace: inPlace,
        ),
    searchQuery: () => _view.searchQuery(),
    showContinueWatchingActions: (IptvChannel channel) =>
        _external.playbackActions().showContinueWatchingActions(channel),
    showsPosterRows: () => _external.rowProjection().showsPosterRows,
    toggleFavorite: (IptvChannel channel, bool isFavorited) =>
        _external.favorites().toggleFavorite(channel, isFavorited),
  ));
}
