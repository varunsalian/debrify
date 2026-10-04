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
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';

typedef PlaylistContentCompositionDeps = ({
  Map<String, dynamic> Function() playlistItem,
  VoidCallback? Function() onPlaybackStarted,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PlaylistContentCatalogState catalogState,
  PlaylistContentNavigationState navigationState,
  PlaylistContentFocusState focusState,
  PlaylistContentSeriesState seriesState,
  PlaylistContentScrollState scrollState,
  PlaylistContentOttState ottState,
  PlaylistContentSearchState searchState,
  PlaylistContentEpisodeState episodeState,
});

class PlaylistContentComposition {
  PlaylistContentComposition(this._deps);
  final PlaylistContentCompositionDeps _deps;

  PlaylistContentSections createSections() {
    final sections = PlaylistContentSections();
    sections.initializationSlot = PlaylistContentInitialization((
      loadSavedViewMode: () => sections.viewModes.loadSavedViewMode(),
      loadContent: () => sections.contentLoading.loadContent(),
      catalogState: _deps.catalogState,
      parseSeriesPlaylist: () => sections.seriesMetadata.parseSeriesPlaylist(),
      playlistItem: _deps.playlistItem,
      seriesState: _deps.seriesState,
      setState: _deps.setState,
      navigationState: _deps.navigationState,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      mounted: _deps.mounted,
      episodeState: _deps.episodeState,
    ));
    sections.navigationSlot = PlaylistContentNavigation((
      searchState: _deps.searchState,
      toggleSearch: () => sections.search.toggleSearch(),
      navigationState: _deps.navigationState,
      setState: _deps.setState,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      context: _deps.context,
    ));
    sections.viewModesSlot = PlaylistContentViewModes((
      playlistItem: _deps.playlistItem,
      mounted: _deps.mounted,
      setState: _deps.setState,
      navigationState: _deps.navigationState,
      catalogState: _deps.catalogState,
      searchState: _deps.searchState,
      seriesState: _deps.seriesState,
    ));
    sections.dormantSlot = PlaylistContentDormant((
      playlistItem: _deps.playlistItem,
      setState: _deps.setState,
      seriesState: _deps.seriesState,
    ));
    sections.contentLoadingSlot = PlaylistContentContentLoading((
      setState: _deps.setState,
      catalogState: _deps.catalogState,
      playlistItem: _deps.playlistItem,
      loadPikPakContent: () => sections.cloudLoading.loadPikPakContent(),
      loadWebDavContent: () => sections.cloudLoading.loadWebDavContent(),
      loadPremiumizeContent: () =>
          sections.cloudLoading.loadPremiumizeContent(),
      mounted: _deps.mounted,
    ));
    sections.cloudLoadingSlot = PlaylistContentCloudLoading((
      playlistItem: _deps.playlistItem,
      catalogState: _deps.catalogState,
    ));
    sections.playlistOrderSlot = PlaylistContentPlaylistOrder((
      navigationState: _deps.navigationState,
      playlistItem: _deps.playlistItem,
    ));
    sections.playEntriesSlot = PlaylistContentPlayEntries((
      catalogState: _deps.catalogState,
      context: _deps.context,
      applySortedPlaylistOrder: (List<RDFileNode> videoFiles) =>
          sections.playlistOrder.applySortedPlaylistOrder(videoFiles),
      playlistItem: _deps.playlistItem,
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
      mounted: _deps.mounted,
      reloadProgress: () => sections.progress.reloadProgress(),
      navigationState: _deps.navigationState,
    ));
    sections.searchSlot = PlaylistContentSearch((
      setState: _deps.setState,
      searchState: _deps.searchState,
      focusState: _deps.focusState,
      catalogState: _deps.catalogState,
    ));
    sections.progressSlot = PlaylistContentProgress((
      seriesState: _deps.seriesState,
      catalogState: _deps.catalogState,
      applySortedPlaylistOrder: (List<RDFileNode> videoFiles) =>
          sections.playlistOrder.applySortedPlaylistOrder(videoFiles),
      mounted: _deps.mounted,
      playlistItem: _deps.playlistItem,
      setState: _deps.setState,
    ));
    sections.seriesMetadataSlot = PlaylistContentSeriesMetadata((
      seriesState: _deps.seriesState,
      playlistItem: _deps.playlistItem,
      catalogState: _deps.catalogState,
      determineInitialSeason: () => sections.progress.determineInitialSeason(),
      setState: _deps.setState,
      saveDetectedSeriesPosterToPlaylist: () =>
          sections.posters.saveDetectedSeriesPosterToPlaylist(),
      mounted: _deps.mounted,
      context: _deps.context,
      updatePlaylistPoster: (Map<String, dynamic> showInfo) =>
          sections.posters.updatePlaylistPoster(showInfo),
    ));
    sections.postersSlot = PlaylistContentPosters((
      seriesState: _deps.seriesState,
      playlistItem: _deps.playlistItem,
    ));
    sections.episodeListSlot = PlaylistContentEpisodeList((
      scrollState: _deps.scrollState,
      determineInitialEpisodeIndex: (SeriesSeason season) =>
          sections.progress.determineInitialEpisodeIndex(season),
      mounted: _deps.mounted,
      buildEpisodeCard: (SeriesEpisode episode) =>
          sections.episodeCard.buildEpisodeCard(episode),
      context: _deps.context,
    ));
    sections.episodeCardSlot = PlaylistContentEpisodeCard((
      context: _deps.context,
      seriesState: _deps.seriesState,
      episodeState: _deps.episodeState,
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
      context: _deps.context,
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
      context: _deps.context,
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
      context: _deps.context,
    ));
    sections.watchedSlot = PlaylistContentWatched((
      seriesState: _deps.seriesState,
      playlistItem: _deps.playlistItem,
      reloadProgress: () => sections.progress.reloadProgress(),
      mounted: _deps.mounted,
      context: _deps.context,
    ));
    sections.debridLaunchesSlot = PlaylistContentDebridLaunches((
      playlistItem: _deps.playlistItem,
      seriesState: _deps.seriesState,
      mounted: _deps.mounted,
      onPlaybackStarted: _deps.onPlaybackStarted,
      context: _deps.context,
      convertToPlaylistViewMode: (FolderViewMode mode) =>
          sections.viewModes.convertToPlaylistViewMode(mode),
      navigationState: _deps.navigationState,
      catalogState: _deps.catalogState,
      loadAllDebridContent: () =>
          sections.contentLoading.loadAllDebridContent(),
    ));
    sections.cloudLaunchesSlot = PlaylistContentCloudLaunches((
      seriesState: _deps.seriesState,
      playlistItem: _deps.playlistItem,
      mounted: _deps.mounted,
      onPlaybackStarted: _deps.onPlaybackStarted,
      context: _deps.context,
      convertToPlaylistViewMode: (FolderViewMode mode) =>
          sections.viewModes.convertToPlaylistViewMode(mode),
      navigationState: _deps.navigationState,
    ));
    sections.searchLayoutSlot = PlaylistContentSearchLayout((
      context: _deps.context,
      searchState: _deps.searchState,
      focusState: _deps.focusState,
      performSearch: sections.search.performSearch,
      setState: _deps.setState,
      getProgressForFile: (RDFileNode file) =>
          sections.progress.getProgressForFile(file),
      playFile: (RDFileNode file) => sections.playEntries.playFile(file),
    ));
    sections.rootLayoutSlot = PlaylistContentRootLayout((
      focusState: _deps.focusState,
      navigateUp: sections.navigation.navigateUp,
      navigationState: _deps.navigationState,
      searchState: _deps.searchState,
      toggleSearch: sections.search.toggleSearch,
      loadContent: sections.contentLoading.loadContent,
      catalogState: _deps.catalogState,
      applyViewMode: sections.viewModes.applyViewMode,
      buildSearchBar: () => sections.searchLayout.buildSearchBar(),
      buildSearchResults: () => sections.searchLayout.buildSearchResults(),
      buildContent: () => sections.fileList.buildContent(),
    ));
    sections.fileListSlot = PlaylistContentFileList((
      catalogState: _deps.catalogState,
      loadContent: sections.contentLoading.loadContent,
      navigationState: _deps.navigationState,
      buildOTTView: () => sections.ottView.buildOTTView(),
      context: _deps.context,
      getProgressForFile: (RDFileNode file) =>
          sections.progress.getProgressForFile(file),
      navigateIntoFolder: (RDFileNode folder) =>
          sections.navigation.navigateIntoFolder(folder),
      playFile: (RDFileNode file) => sections.playEntries.playFile(file),
    ));
    sections.ottViewSlot = PlaylistContentOttView((
      seriesState: _deps.seriesState,
      catalogState: _deps.catalogState,
      parseSeriesPlaylist: () => sections.seriesMetadata.parseSeriesPlaylist(),
      ottState: _deps.ottState,
      mounted: _deps.mounted,
      navigationState: _deps.navigationState,
      setState: _deps.setState,
      applyViewMode: (FolderViewMode mode) =>
          sections.viewModes.applyViewMode(mode),
      context: _deps.context,
      buildEpisodeList: (SeriesSeason season) =>
          sections.episodeList.buildEpisodeList(season),
      scrollState: _deps.scrollState,
      showFixMetadataDialog: sections.seriesMetadata.showFixMetadataDialog,
    ));
    return sections;
  }
}
