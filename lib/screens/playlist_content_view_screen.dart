import 'package:debrify/features/playlist_content/application/playlist_content_file_trees.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_launches.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_content_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_debrid_launches.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_desktop_episode.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_dormant.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_card.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_list.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_metadata.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_file_list.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_initialization.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_mobile_episode.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_view.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_play_entries.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_playlist_order.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_posters.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_progress.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_root_layout.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_layout.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_sections.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_metadata.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_view_modes.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_watched.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
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
  PlaylistContentSections _createSections() {
    final sections = PlaylistContentSections();
    sections.initializationSlot = PlaylistContentInitialization((
      loadSavedViewMode: () => sections.viewModes.loadSavedViewMode(),
      loadContent: () => sections.contentLoading.loadContent(),
      catalogState: _catalog,
      parseSeriesPlaylist: () => sections.seriesMetadata.parseSeriesPlaylist(),
      playlistItem: () => widget.playlistItem,
      seriesState: _series,
      setState: setState,
      navigationState: _navigation,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      mounted: () => mounted,
      episodeState: _episode,
    ));
    sections.navigationSlot = PlaylistContentNavigation((
      searchState: _search,
      toggleSearch: () => sections.search.toggleSearch(),
      navigationState: _navigation,
      setState: setState,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      context: () => context,
    ));
    sections.viewModesSlot = PlaylistContentViewModes((
      playlistItem: () => widget.playlistItem,
      mounted: () => mounted,
      setState: setState,
      navigationState: _navigation,
      catalogState: _catalog,
      searchState: _search,
      seriesState: _series,
    ));
    sections.dormantSlot = PlaylistContentDormant((
      playlistItem: () => widget.playlistItem,
      setState: setState,
      seriesState: _series,
    ));
    sections.contentLoadingSlot = PlaylistContentContentLoading((
      setState: setState,
      catalogState: _catalog,
      playlistItem: () => widget.playlistItem,
      loadPikPakContent: () => sections.cloudLoading.loadPikPakContent(),
      loadWebDavContent: () => sections.cloudLoading.loadWebDavContent(),
      loadPremiumizeContent: () =>
          sections.cloudLoading.loadPremiumizeContent(),
      mounted: () => mounted,
    ));
    sections.cloudLoadingSlot = PlaylistContentCloudLoading((
      playlistItem: () => widget.playlistItem,
      catalogState: _catalog,
    ));
    sections.playlistOrderSlot = PlaylistContentPlaylistOrder((
      navigationState: _navigation,
      playlistItem: () => widget.playlistItem,
    ));
    sections.playEntriesSlot = PlaylistContentPlayEntries((
      catalogState: _catalog,
      context: () => context,
      applySortedPlaylistOrder: (List<RDFileNode> videoFiles) =>
          sections.playlistOrder.applySortedPlaylistOrder(videoFiles),
      playlistItem: () => widget.playlistItem,
      playRealDebridPlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.debridLaunches.playRealDebridPlaylist(
            videoFiles,
            startIndex,
          ),
      playTorboxPlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.debridLaunches.playTorboxPlaylist(videoFiles, startIndex),
      playPikPakPlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.cloudLaunches.playPikPakPlaylist(videoFiles, startIndex),
      playWebDavPlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.cloudLaunches.playWebDavPlaylist(videoFiles, startIndex),
      playPremiumizePlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.cloudLaunches.playPremiumizePlaylist(videoFiles, startIndex),
      playAllDebridPlaylist: (List<RDFileNode> videoFiles, int startIndex) =>
          sections.debridLaunches.playAllDebridPlaylist(videoFiles, startIndex),
      mounted: () => mounted,
      reloadProgress: () => sections.progress.reloadProgress(),
      navigationState: _navigation,
    ));
    sections.searchSlot = PlaylistContentSearch((
      setState: setState,
      searchState: _search,
      focusState: _focus,
      catalogState: _catalog,
    ));
    sections.progressSlot = PlaylistContentProgress((
      seriesState: _series,
      catalogState: _catalog,
      applySortedPlaylistOrder: (List<RDFileNode> videoFiles) =>
          sections.playlistOrder.applySortedPlaylistOrder(videoFiles),
      mounted: () => mounted,
      playlistItem: () => widget.playlistItem,
      setState: setState,
    ));
    sections.seriesMetadataSlot = PlaylistContentSeriesMetadata((
      seriesState: _series,
      playlistItem: () => widget.playlistItem,
      catalogState: _catalog,
      determineInitialSeason: () => sections.progress.determineInitialSeason(),
      setState: setState,
      saveDetectedSeriesPosterToPlaylist: () =>
          sections.posters.saveDetectedSeriesPosterToPlaylist(),
      mounted: () => mounted,
      context: () => context,
      updatePlaylistPoster: (Map<String, dynamic> showInfo) =>
          sections.posters.updatePlaylistPoster(showInfo),
    ));
    sections.postersSlot = PlaylistContentPosters((
      seriesState: _series,
      playlistItem: () => widget.playlistItem,
    ));
    sections.episodeListSlot = PlaylistContentEpisodeList((
      scrollState: _scroll,
      determineInitialEpisodeIndex: (SeriesSeason season) =>
          sections.progress.determineInitialEpisodeIndex(season),
      mounted: () => mounted,
      buildEpisodeCard: (SeriesEpisode episode) =>
          sections.episodeCard.buildEpisodeCard(episode),
      context: () => context,
    ));
    sections.episodeCardSlot = PlaylistContentEpisodeCard((
      context: () => context,
      seriesState: _series,
      episodeState: _episode,
      toggleWatchedState: (SeriesEpisode episode) =>
          sections.watched.toggleWatchedState(episode),
      playEpisode: (SeriesEpisode episode) =>
          sections.playEntries.playEpisode(episode),
      buildMobileEpisodeCard:
          (
            SeriesEpisode episode,
            double progress,
            bool isFinished,
            bool hasMetadata,
            EpisodeInfo? episodeInfo,
          ) => sections.mobileEpisode.buildMobileEpisodeCard(
            episode,
            progress,
            isFinished,
            hasMetadata,
            episodeInfo,
          ),
      buildDesktopEpisodeCard:
          (
            SeriesEpisode episode,
            double progress,
            bool isFinished,
            bool hasMetadata,
            EpisodeInfo? episodeInfo,
          ) => sections.desktopEpisode.buildDesktopEpisodeCard(
            episode,
            progress,
            isFinished,
            hasMetadata,
            episodeInfo,
          ),
    ));
    sections.mobileEpisodeSlot = PlaylistContentMobileEpisode((
      context: () => context,
      buildThumbnailPlaceholder: (SeriesEpisode episode) =>
          sections.episodeMetadata.buildThumbnailPlaceholder(episode),
      buildEpisodeMetadataRow:
          (
            SeriesEpisode episode,
            EpisodeInfo? episodeInfo,
            double progress,
            bool isFinished,
          ) => sections.episodeMetadata.buildEpisodeMetadataRow(
            episode,
            episodeInfo,
            progress,
            isFinished,
          ),
      toggleWatchedState: (SeriesEpisode episode) =>
          sections.watched.toggleWatchedState(episode),
    ));
    sections.desktopEpisodeSlot = PlaylistContentDesktopEpisode((
      context: () => context,
      buildThumbnailPlaceholder: (SeriesEpisode episode) =>
          sections.episodeMetadata.buildThumbnailPlaceholder(episode),
      buildEpisodeMetadataRow:
          (
            SeriesEpisode episode,
            EpisodeInfo? episodeInfo,
            double progress,
            bool isFinished,
          ) => sections.episodeMetadata.buildEpisodeMetadataRow(
            episode,
            episodeInfo,
            progress,
            isFinished,
          ),
      toggleWatchedState: (SeriesEpisode episode) =>
          sections.watched.toggleWatchedState(episode),
    ));
    sections.episodeMetadataSlot = PlaylistContentEpisodeMetadata((
      context: () => context,
    ));
    sections.watchedSlot = PlaylistContentWatched((
      seriesState: _series,
      playlistItem: () => widget.playlistItem,
      reloadProgress: () => sections.progress.reloadProgress(),
      mounted: () => mounted,
      context: () => context,
    ));
    sections.debridLaunchesSlot = PlaylistContentDebridLaunches((
      playlistItem: () => widget.playlistItem,
      seriesState: _series,
      mounted: () => mounted,
      onPlaybackStarted: () => widget.onPlaybackStarted,
      context: () => context,
      convertToPlaylistViewMode: (FolderViewMode mode) =>
          sections.viewModes.convertToPlaylistViewMode(mode),
      navigationState: _navigation,
      catalogState: _catalog,
      loadAllDebridContent: () =>
          sections.contentLoading.loadAllDebridContent(),
    ));
    sections.cloudLaunchesSlot = PlaylistContentCloudLaunches((
      seriesState: _series,
      playlistItem: () => widget.playlistItem,
      mounted: () => mounted,
      onPlaybackStarted: () => widget.onPlaybackStarted,
      context: () => context,
      convertToPlaylistViewMode: (FolderViewMode mode) =>
          sections.viewModes.convertToPlaylistViewMode(mode),
      navigationState: _navigation,
    ));
    sections.searchLayoutSlot = PlaylistContentSearchLayout((
      context: () => context,
      searchState: _search,
      focusState: _focus,
      performSearch: sections.search.performSearch,
      setState: setState,
      getProgressForFile: (RDFileNode file) =>
          sections.progress.getProgressForFile(file),
      playFile: (RDFileNode file) => sections.playEntries.playFile(file),
    ));
    sections.rootLayoutSlot = PlaylistContentRootLayout((
      focusState: _focus,
      navigateUp: sections.navigation.navigateUp,
      navigationState: _navigation,
      searchState: _search,
      toggleSearch: sections.search.toggleSearch,
      loadContent: sections.contentLoading.loadContent,
      catalogState: _catalog,
      applyViewMode: sections.viewModes.applyViewMode,
      buildSearchBar: () => sections.searchLayout.buildSearchBar(),
      buildSearchResults: () => sections.searchLayout.buildSearchResults(),
      buildContent: () => sections.fileList.buildContent(),
    ));
    sections.fileListSlot = PlaylistContentFileList((
      catalogState: _catalog,
      loadContent: sections.contentLoading.loadContent,
      navigationState: _navigation,
      buildOTTView: () => sections.ottView.buildOTTView(),
      context: () => context,
      getProgressForFile: (RDFileNode file) =>
          sections.progress.getProgressForFile(file),
      navigateIntoFolder: (RDFileNode folder) =>
          sections.navigation.navigateIntoFolder(folder),
      playFile: (RDFileNode file) => sections.playEntries.playFile(file),
    ));
    sections.ottViewSlot = PlaylistContentOttView((
      seriesState: _series,
      catalogState: _catalog,
      parseSeriesPlaylist: () => sections.seriesMetadata.parseSeriesPlaylist(),
      ottState: _ott,
      mounted: () => mounted,
      navigationState: _navigation,
      setState: setState,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      context: () => context,
      buildEpisodeList: (SeriesSeason season) =>
          sections.episodeList.buildEpisodeList(season),
      scrollState: _scroll,
      showFixMetadataDialog: sections.seriesMetadata.showFixMetadataDialog,
    ));
    return sections;
  }

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
