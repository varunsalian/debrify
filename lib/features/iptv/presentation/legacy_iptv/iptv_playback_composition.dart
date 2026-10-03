import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_android_recording.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_loading.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catchup.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_composition_bindings.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_favorites.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_filters.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_actions.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_playback_refresh.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_browse.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_payload.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_handoff.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_tuning.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_row_projection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_content.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_spotlight_focus.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_startup_launch.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_startup_resolution.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_tablet_selection.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_virtual_results.dart';
import 'package:debrify/models/iptv_playlist.dart';

typedef IptvPlaybackCompositionExternalSections = ({
  IptvAndroidRecording Function() androidRecording,
  IptvCatalogLoading Function() catalogLoading,
  IptvFavorites Function() favorites,
  IptvFiltersSection Function() filtersSection,
  IptvPlayerBrowse Function() playerBrowse,
  IptvPlayerPayload Function() playerPayload,
  IptvPreviewTuning Function() previewTuning,
  IptvRowProjection Function() rowProjection,
  IptvSpotlightContent Function() spotlightContent,
  IptvSpotlightFocus Function() spotlightFocus,
  IptvTabletSelection Function() tabletSelection,
  IptvVirtualResults Function() virtualResults,
});

/// Constructs the playback sections for one view lifetime.
/// State owners are borrowed; cross-group getters are resolved only by actions.
class IptvPlaybackComposition {
  final IptvViewBindings _view;
  final IptvCompositionStates _states;
  final IptvPlaybackCompositionExternalSections _external;

  IptvPlaybackComposition(this._view, this._states, this._external);

  late final IptvPlayback playback = IptvPlayback((
    catalogState: _states.catalogState,
    playerState: _states.playerState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    adoptStartupCategoryValue: (String? group) =>
        startupResolution.adoptStartupCategoryValue(group),
    context: () => _view.context(),
    effectiveCategory: () => _external.filtersSection().effectiveCategory,
    flushPreviewRearm: () => previewHandoff.flushPreviewRearm(),
    fullCategoryList: () => _external.playerPayload().fullCategoryList(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    normalizedName: (String value) =>
        IptvStartupResolution.normalizedName(value),
    openSeriesDetail: (IptvChannel channel) =>
        playbackActions.openSeriesDetail(channel),
    originPlaylistIdFor: (IptvChannel channel) =>
        _external.favorites().originPlaylistIdFor(channel),
    playerChannelWithOrigin: (IptvChannel channel, IptvPlaylist source) =>
        _external.playerPayload().playerChannelWithOrigin(channel, source),
    playerListsPayload: () => _external.playerPayload().playerListsPayload(),
    playerSourcePayload: () => _external.playerPayload().playerSourcePayload(),
    providePlayerIptvBrowse: (Map<String, dynamic> request) =>
        _external.playerBrowse().providePlayerIptvBrowse(request),
    refreshAfterPlayback: () => playbackRefresh.refreshAfterPlayback(),
  ));

  late final IptvStartupLaunch startupLaunch = IptvStartupLaunch((
    catalogState: _states.catalogState,
    focusState: _states.focusState,
    playerState: _states.playerState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    settingsState: _states.settingsState,
    context: () => _view.context(),
    debugOnSpotlightStartupFocus: () => _view.debugOnSpotlightStartupFocus(),
    mounted: () => _view.mounted(),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        playback.playChannel(channel, shouldCancel: shouldCancel),
    resolveStartupRow:
        (Map<String, dynamic> payload, bool Function() cancelled) =>
            startupResolution.resolveStartupRow(payload, cancelled),
    selectTabletChannel: (int index, IptvChannel channel) =>
        _external.tabletSelection().selectTabletChannel(index, channel),
    setState: _view.setState,
    spotlightRequestedForDevice: () =>
        _external.rowProjection().spotlightRequestedForDevice,
    spotlightUsesTimeline: () =>
        _external.spotlightContent().spotlightUsesTimeline,
  ));

  late final IptvStartupResolution startupResolution = IptvStartupResolution((
    catalogState: _states.catalogState,
    settingsState: _states.settingsState,
    applyFilters: () => _external.filtersSection().applyFilters(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    residentDbRow:
        (
          ({int position, IptvChannel channel}) entry,
          String url,
          String name,
          int? storedNumber,
        ) => playback.residentDbRow(entry, url, name, storedNumber),
    setState: _view.setState,
    startupPlaylistFor: (Map<String, dynamic> payload) =>
        startupLaunch.startupPlaylistFor(payload),
  ));

  late final IptvCatchup catchup = IptvCatchup((
    catalogState: _states.catalogState,
    playerState: _states.playerState,
    previewState: _states.previewState,
    selectionState: _states.selectionState,
    context: () => _view.context(),
    flushPreviewRearm: () => previewHandoff.flushPreviewRearm(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    originPlaylistIdFor: (IptvChannel channel) =>
        _external.favorites().originPlaylistIdFor(channel),
    refreshAfterPlayback: () => playbackRefresh.refreshAfterPlayback(),
  ));

  late final IptvPlaybackActions playbackActions = IptvPlaybackActions((
    settingsState: _states.settingsState,
    clearPreview: () => _external.previewTuning().clearPreview(),
    context: () => _view.context(),
    isTelevision: () => _view.isTelevision(),
    mounted: () => _view.mounted(),
    originPlaylistIdFor: (IptvChannel channel) =>
        _external.favorites().originPlaylistIdFor(channel),
    playChannel: (IptvChannel channel, {bool Function()? shouldCancel}) =>
        playback.playChannel(channel, shouldCancel: shouldCancel),
    refreshAfterPlayback: () => playbackRefresh.refreshAfterPlayback(),
  ));

  late final IptvPlaybackRefresh playbackRefresh = IptvPlaybackRefresh((
    catalogState: _states.catalogState,
    membershipState: _states.membershipState,
    recordingState: _states.recordingState,
    settingsState: _states.settingsState,
    armAndroidRecStateRefresh: () =>
        _external.androidRecording().armAndroidRecStateRefresh(),
    customLists: () => _external.favorites().customLists,
    loadFavorites: () => _external.favorites().loadFavorites(),
    loadPlaylist: (IptvPlaylist playlist, {bool userRequested = false}) =>
        _external.catalogLoading().loadPlaylist(
          playlist,
          userRequested: userRequested,
        ),
    loadProgress: (int ticket, List<IptvChannel> channels) =>
        _external.virtualResults().loadProgress(ticket, channels),
    mounted: () => _view.mounted(),
    onPlaylistChanged: (IptvPlaylist? playlist, {bool focusContent = false}) =>
        _external.filtersSection().onPlaylistChanged(
          playlist,
          focusContent: focusContent,
        ),
    setState: _view.setState,
  ));

  late final IptvPreviewHandoff previewHandoff = IptvPreviewHandoff((
    playerState: _states.playerState,
    previewState: _states.previewState,
    clearPreview: () => _external.previewTuning().clearPreview(),
    mounted: () => _view.mounted(),
    refreshAfterPlayback: () => playbackRefresh.refreshAfterPlayback(),
    setSpotlightSourcesExpanded: (bool expanded) =>
        _external.spotlightFocus().setSpotlightSourcesExpanded(expanded),
  ));
}
