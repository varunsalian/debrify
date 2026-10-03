import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catchup.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_categories.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_content_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_desktop_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_navigation.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_layout.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_quiet_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_record_now.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_recording_support.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_schedule_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_content.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_focus.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_hero.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_layout.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/desktop_recording_service.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/spotlight/iptv_spotlight_layout.dart';
import 'package:flutter/material.dart';

typedef IptvSpotlightCompositionExternalSections = ({
  IptvAndroidRecording Function() androidRecording,
  IptvCatchup Function() catchup,
  IptvCategories Function() categoryActions,
  IptvContentLayout Function() contentLayout,
  IptvDesktopRecording Function() desktopRecording,
  IptvFavorites Function() favorites,
  IptvFiltersSection Function() filtersSection,
  IptvNavigation Function() navigation,
  IptvPlayback Function() playback,
  IptvPreviewLayout Function() previewLayout,
  IptvPreviewTuning Function() previewTuning,
  IptvQuietFilters Function() quietFilters,
  IptvRecordNow Function() recordNow,
  IptvRecordingSupport Function() recordingSupport,
  IptvRowProjection Function() rowProjection,
  IptvScheduleActions Function() scheduleActions,
});

/// Constructs the spotlight sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvSpotlightComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvSpotlightCompositionExternalSections _external;

  IptvSpotlightComposition(this._view, this._states, this._external);

  late final IptvSpotlightLayout spotlightLayout = IptvSpotlightLayout((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    recordingState: _states.recordingState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    anyRecordingLive: () => _external.recordingSupport().anyRecordingLive,
    buildSpotlightContent: (IptvSpotlightLayoutMode mode) =>
        spotlightContent.buildSpotlightContent(mode),
    buildSpotlightHero: (IptvSpotlightLayoutMode mode) =>
        spotlightHero.buildSpotlightHero(mode),
    canShowCategoryOptions: () =>
        _external.categoryActions().canShowCategoryOptions,
    categoryCounts: () => _external.rowProjection().categoryCounts,
    closeSpotlightSources: () => spotlightFocus.closeSpotlightSources(),
    context: () => _view.context(),
    customLists: () => _external.favorites().customLists,
    effectiveCategory: () => _external.filtersSection().effectiveCategory,
    exitSpotlightSourcesToApp: () => spotlightFocus.exitSpotlightSourcesToApp(),
    focusSpotlightHero: () => spotlightFocus.focusSpotlightHero(),
    focusSpotlightSearchOrExit: () =>
        spotlightFocus.focusSpotlightSearchOrExit(),
    focusSpotlightSearchResults: () =>
        spotlightFocus.focusSpotlightSearchResults(),
    focusSpotlightSources: () => spotlightFocus.focusSpotlightSources(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    navigateToAddons: () => _external.quietFilters().navigateToAddons(),
    navigateToManageSources: () =>
        _external.navigation().navigateToManageSources(),
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
    openScheduledRecordings: () =>
        _external.recordingSupport().openScheduledRecordings(),
    openSpotlightSearch: () => spotlightFocus.openSpotlightSearch(),
    promptCategoryOptions: (String category) =>
        _external.categoryActions().promptCategoryOptions(category),
    promptCreateList: () => _external.favorites().promptCreateList(),
    searchHeader: () => _view.searchHeader(),
    setSpotlightSourcesExpanded: (bool expanded) =>
        spotlightFocus.setSpotlightSourcesExpanded(expanded),
    spotlightControlNavigation: (Widget child) =>
        spotlightFocus.spotlightControlNavigation(child),
    spotlightSelectedSourceCount: () =>
        spotlightFocus.spotlightSelectedSourceCount,
  ));

  late final IptvSpotlightFocus spotlightFocus = IptvSpotlightFocus((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    recordingState: _states.recordingState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    applyFilters: () => _external.filtersSection().applyFilters(),
    customLists: () => _external.favorites().customLists,
    focusFirstChannel: () => _external.navigation().focusFirstChannel(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    onUpArrowFromFilters: () => _view.onUpArrowFromFilters(),
    searchHeader: () => _view.searchHeader(),
    searchQuery: () => _view.searchQuery(),
    setState: _view.setState,
  ));

  late final IptvSpotlightHero spotlightHero = IptvSpotlightHero((
    focusState: _states.focusState,
    membershipState: _states.membershipState,
    previewState: _states.previewState,
    recordingState: _states.recordingState,
    androidEngineTaskFor: (IptvChannel channel) =>
        _external.androidRecording().androidEngineTaskFor(channel),
    buildPreviewStage: (IptvChannel? ch, int epoch) =>
        _external.previewLayout().buildPreviewStage(ch, epoch),
    channelEngineRecordable: (IptvChannel channel) =>
        _external.recordingSupport().channelEngineRecordable(channel),
    customLists: () => _external.favorites().customLists,
    debugSpotlightNow: () => _view.debugSpotlightNow(),
    desktopCaptureFor: (IptvChannel channel) =>
        _external.desktopRecording().desktopCaptureFor(channel),
    isTelevision: () => _view.isTelevision(),
    openSchedulePane: (IptvChannel channel) =>
        _external.scheduleActions().openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) =>
        _external.catchup().playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        _external.playback().playChannel(channel, shouldCancel: shouldCancel),
    recordProgrammeActionFor: (IptvChannel channel) =>
        _external.scheduleActions().recordProgrammeActionFor(channel),
    showSpotlightChannelActions:
        (IptvChannel channel, {EpgProgramme? programme}) => spotlightActions
            .showSpotlightChannelActions(channel, programme: programme),
    spotlightActivation: (VoidCallback action, Widget child) =>
        spotlightActions.spotlightActivation(action, child),
    spotlightFocusBorder: () => spotlightActions.spotlightFocusBorder,
    spotlightIconAction:
        ({
          required String tooltip,
          required IconData icon,
          required VoidCallback onPressed,
          bool selected = false,
        }) => spotlightActions.spotlightIconAction(
          tooltip: tooltip,
          icon: icon,
          onPressed: onPressed,
          selected: selected,
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

  late final IptvSpotlightActions spotlightActions = IptvSpotlightActions((
    membershipState: _states.membershipState,
    context: () => _view.context(),
    customLists: () => _external.favorites().customLists,
    mounted: () => _view.mounted(),
    openListPicker: (IptvChannel channel) =>
        _external.favorites().openListPicker(channel),
    openSchedulePane: (IptvChannel channel) =>
        _external.scheduleActions().openSchedulePane(channel),
    spotlightRecordAction: (IptvChannel channel) =>
        spotlightHero.spotlightRecordAction(channel),
    toggleFavorite: (IptvChannel channel, bool isFavorited) =>
        _external.favorites().toggleFavorite(channel, isFavorited),
  ));

  late final IptvSpotlightContent spotlightContent = IptvSpotlightContent((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    buildContent:
        ({
          bool tvPane = false,
          bool touchSelector = false,
          bool cockpit = false,
        }) => _external.contentLayout().buildContent(
          tvPane: tvPane,
          touchSelector: touchSelector,
          cockpit: cockpit,
        ),
    closeSchedulePane: () => _external.scheduleActions().closeSchedulePane(),
    debugSpotlightNow: () => _view.debugSpotlightNow(),
    focusSpotlightSources: () => spotlightFocus.focusSpotlightSources(),
    isTelevision: () => _view.isTelevision(),
    onChannelFocused: (IptvChannel channel, {bool fromPointer = false}) =>
        _external.previewTuning().onChannelFocused(
          channel,
          fromPointer: fromPointer,
        ),
    openSchedulePane: (IptvChannel channel) =>
        _external.scheduleActions().openSchedulePane(channel),
    playCatchup: (IptvChannel channel, EpgProgramme programme) =>
        _external.catchup().playCatchup(channel, programme),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        _external.playback().playChannel(channel, shouldCancel: shouldCancel),
    recordProgrammeActionFor: (IptvChannel channel) =>
        _external.scheduleActions().recordProgrammeActionFor(channel),
    showSpotlightChannelActions:
        (IptvChannel channel, {EpgProgramme? programme}) => spotlightActions
            .showSpotlightChannelActions(channel, programme: programme),
  ));
}
