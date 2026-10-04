import 'package:debrify/features/playlist_content/application/playlist_content_file_trees.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_composition.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_sections.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

/// Screen for viewing contents of a playlist item
/// Supports Raw, Sort, and Series Arrange view modes
/// Handles folder navigation and progress tracking
class PlaylistContentViewScreen extends StatefulWidget {
  final Map<String, dynamic> playlistItem;
  final VoidCallback? onPlaybackStarted;

  const PlaylistContentViewScreen({
    super.key,
    required this.playlistItem,
    this.onPlaybackStarted,
  });

  @override
  State<PlaylistContentViewScreen> createState() =>
      _PlaylistContentViewScreenState();
}

class _PlaylistContentViewScreenState extends State<PlaylistContentViewScreen> {
  final _catalog = PlaylistContentCatalogState();
  final _navigation = PlaylistContentNavigationState();
  final _focus = PlaylistContentFocusState();
  final _series = PlaylistContentSeriesState();
  final _scroll = PlaylistContentScrollState();
  final _ott = PlaylistContentOttState();
  final _search = PlaylistContentSearchState();
  final _episode = PlaylistContentEpisodeState();
  PlaylistContentSections? _sectionCache;
  PlaylistContentSections get _sections => _sectionCache ??= _createSections();
  PlaylistContentSections _createSections() => PlaylistContentComposition((
    playlistItem: () => widget.playlistItem,
    onPlaybackStarted: () => widget.onPlaybackStarted,
    context: () => context,
    mounted: () => mounted,
    setState: setState,
    catalogState: _catalog,
    navigationState: _navigation,
    focusState: _focus,
    seriesState: _series,
    scrollState: _scroll,
    ottState: _ott,
    searchState: _search,
    episodeState: _episode,
  )).createSections();

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('playlist_content');
    _sections.initialization.checkIfAndroidTv();
    _sections.initialization.initializeScreen();

    // Register back navigation handler for folder navigation (pushed route)
    MainPageBridge.pushRouteBackHandler(
      _sections.navigation.handleBackNavigation,
    );
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    MainPageBridge.popRouteBackHandler(
      _sections.navigation.handleBackNavigation,
    );

    _scroll.scrollRetryTimer
        ?.cancel(); // Cancel any pending scroll retry to prevent memory leaks
    _ott.ottViewAutoSwitchTimer
        ?.cancel(); // Cancel OTT view auto-switch timer to prevent memory leaks
    _episode.episodeLongPressTimer
        ?.cancel(); // Cancel any pending long press timer
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _scroll.episodeListScrollController.dispose();
    _search.searchController.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
}

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> playlistContentTestAccess(
  State<PlaylistContentViewScreen> state,
) {
  final s = state as _PlaylistContentViewScreenState;
  return {
    'isLoading': s._catalog.isLoading,
    'errorMessage': s._catalog.errorMessage,
    'folderPath': s._navigation.folderPath,
    'rootContent': s._catalog.rootContent,
    'currentViewNodes': s._navigation.currentViewNodes,
    'allDebridFiles': s._catalog.allDebridFiles,
    'currentViewMode': s._navigation.currentViewMode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'fileProgressCache': s._series.fileProgressCache,
    'seriesPlaylist': s._series.seriesPlaylist,
    'selectedSeasonNumber': s._series.selectedSeasonNumber,
    'isLoadingSeriesMetadata': s._series.isLoadingSeriesMetadata,
    'episodeListScrollController': s._scroll.episodeListScrollController,
    'targetEpisodeIndex': s._scroll.targetEpisodeIndex,
    'scrollRetryTimer': s._scroll.scrollRetryTimer,
    'isScrollScheduled': s._scroll.isScrollScheduled,
    'ottViewAutoSwitchTimer': s._ott.ottViewAutoSwitchTimer,
    'isSearchActive': s._search.isSearchActive,
    'searchController': s._search.searchController,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'searchResults': s._search.searchResults,
    'episodeLongPressTimer': s._episode.episodeLongPressTimer,
    'episodeLongPressTriggered': s._episode.episodeLongPressTriggered,
    'lastEpisodeLongPressTime': s._episode.lastEpisodeLongPressTime,
    'episodeKeyDownReceived': s._episode.episodeKeyDownReceived,
    'isAndroidTv': s._episode.isAndroidTv,
    'initializeScreen': s._sections.initialization.initializeScreen,
    'checkIfAndroidTv': s._sections.initialization.checkIfAndroidTv,
    'handleBackNavigation': s._sections.navigation.handleBackNavigation,
    'loadSavedViewMode': s._sections.viewModes.loadSavedViewMode,
    'viewModeFromString': s._sections.viewModes.viewModeFromString,
    'viewModeToString': s._sections.viewModes.viewModeToString,
    'convertToPlaylistViewMode':
        s._sections.viewModes.convertToPlaylistViewMode,
    'loadContent': s._sections.contentLoading.loadContent,
    'loadRealDebridContent': s._sections.contentLoading.loadRealDebridContent,
    'loadAllDebridContent': s._sections.contentLoading.loadAllDebridContent,
    'loadTorboxContent': s._sections.contentLoading.loadTorboxContent,
    'loadPikPakContent': s._sections.cloudLoading.loadPikPakContent,
    'loadPremiumizeContent': s._sections.cloudLoading.loadPremiumizeContent,
    'loadWebDavContent': s._sections.cloudLoading.loadWebDavContent,
    'relativeWebDavPath': relativeWebDavPath,
    'fileNameFromPath': fileNameFromPath,
    'asStringDynamicMap': asStringDynamicMap,
    'asInt': asInt,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySortedPlaylistOrder':
        s._sections.playlistOrder.applySortedPlaylistOrder,
    'applySeriesArrangeView': s._sections.viewModes.applySeriesArrangeView,
    'navigateIntoFolder': s._sections.navigation.navigateIntoFolder,
    'navigateUp': s._sections.navigation.navigateUp,
    'playFile': s._sections.playEntries.playFile,
    'toggleSearch': s._sections.search.toggleSearch,
    'performSearch': s._sections.search.performSearch,
    'getProgressForFile': s._sections.progress.getProgressForFile,
    'determineInitialSeason': s._sections.progress.determineInitialSeason,
    'determineInitialEpisodeIndex':
        s._sections.progress.determineInitialEpisodeIndex,
    'reloadProgress': s._sections.progress.reloadProgress,
    'saveImdbIdToPlaylist': s._sections.seriesMetadata.saveImdbIdToPlaylist,
    'parseSeriesPlaylist': s._sections.seriesMetadata.parseSeriesPlaylist,
    'showFixMetadataDialog': s._sections.seriesMetadata.showFixMetadataDialog,
    'saveDetectedSeriesPosterToPlaylist':
        s._sections.posters.saveDetectedSeriesPosterToPlaylist,
    'updatePlaylistPoster': s._sections.posters.updatePlaylistPoster,
    'scrollToEpisode': s._sections.episodeList.scrollToEpisode,
    'formatAirDate': formatAirDate,
    'toggleWatchedState': s._sections.watched.toggleWatchedState,
    'playEpisode': s._sections.playEntries.playEpisode,
    'playRealDebridPlaylist': s._sections.debridLaunches.playRealDebridPlaylist,
    'playAllDebridPlaylist': s._sections.debridLaunches.playAllDebridPlaylist,
    'playTorboxPlaylist': s._sections.debridLaunches.playTorboxPlaylist,
    'playPikPakPlaylist': s._sections.cloudLaunches.playPikPakPlaylist,
    'playPremiumizePlaylist': s._sections.cloudLaunches.playPremiumizePlaylist,
    'playWebDavPlaylist': s._sections.cloudLaunches.playWebDavPlaylist,
    'resolveWebDavConfig': s._sections.cloudLaunches.resolveWebDavConfig,
    'hasWebDavCredentials': hasWebDavCredentials,
    'cleanTorboxPath': cleanTorboxPath,
    'buildPikPakFolderTree': s._sections.cloudLoading.buildPikPakFolderTree,
    'buildPikPakFileTree': buildPikPakFileTree,
    'buildPremiumizeCloudFileTree': buildPremiumizeCloudFileTree,
    'buildPremiumizeFileTree': buildPremiumizeFileTree,
    'buildWebDavFileTree': buildWebDavFileTree,
    'setAndroidTv': (bool value) {
      s._episode.isAndroidTv = value;
      (state.context as Element).markNeedsBuild();
    },
  };
}
