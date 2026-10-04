import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_file_trees.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/models/playlist_content_search_result.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_launches.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_content_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_debrid_launches.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_dormant.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_initialization.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_play_entries.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_playlist_order.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_posters.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_progress.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search.dart';
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
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/widgets/view_mode_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// Build the search bar widget
  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _search.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _search.searchController,
              focusNode: _focus.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _focus.searchFocusNode.unfocus(),
              onDownArrow: () => _focus.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _focus.searchClearFocusNode.requestFocus()
                  : null,
              // The shared TV shell/keyboard chrome follows settings.accent,
              // as Downloads established. The panel's ground and ink are the
              // keyboard's own roles rather than this surface's, so they come
              // from `youtube.keyboardPanel` / `core.tx`; the keycap label is
              // scored against the accent actually being painted.
              accent: app.settings.accent,
              keyboardGround: app.youtube.keyboardPanel,
              keyboardInk: app.core.tx,
              keyboardInkOnAccent: app.inkOn(app.settings.accent),
              decoration: InputDecoration(
                hintText: 'Search all files...',
                // Colors.grey left literal: no token carries it.
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.playlist.fieldFill,
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _sections.search.performSearch,
              onSubmitted: (_) {
                // Unfocus TextField when user presses search/enter on TV keyboard
                _focus.searchFocusNode.unfocus();
              },
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    setState(() {
                      _search.searchController.clear();
                      _search.searchResults.clear();
                    });
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _focus.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.playlist.fieldFill,
                        borderRadius: app.shape.br(8),
                        border: isFocused
                            ? Border.all(color: app.core.tx, width: 2)
                            : null,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          setState(() {
                            _search.searchController.clear();
                            _search.searchResults.clear();
                          });
                          _focus.searchFocusNode.requestFocus();
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build the search results list
  Widget _buildSearchResults() {
    if (_search.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search all files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_search.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _search.searchResults.length,
      itemBuilder: (context, index) {
        final result = _search.searchResults[index];
        return _buildSearchResultCard(result);
      },
    );
  }

  /// Build a card for a search result
  Widget _buildSearchResultCard(PlaylistContentSearchResult result) {
    final app = AppThemeScope.of(context);
    final node = result.node;

    // Get progress for this file
    double progress = 0.0;
    bool isFinished = false;
    final progressData = _sections.progress.getProgressForFile(node);
    if (progressData != null) {
      final positionMs = progressData['positionMs'] as int? ?? 0;
      final durationMs = progressData['durationMs'] as int? ?? 0;
      if (durationMs > 0) {
        progress = positionMs / durationMs;
        isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: app.playlist.card,
      child: InkWell(
        onTap: () => _sections.playEntries.playFile(node),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Icon
                  const Icon(
                    Icons.play_circle_outline,
                    color: Colors.blue,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  // File info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Show path if not empty
                        if (result.path.isNotEmpty)
                          Text(
                            result.path,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (node.bytes != null)
                          Text(
                            Formatters.formatFileSize(node.bytes!),
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Progress badge
                  if (progress > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        // Colors.green (#4CAF50) left literal: it is NOT
                        // playlist.statusWatched (#059669), so no token holds
                        // it. The in-progress half is progressPlayed.
                        color: isFinished
                            ? Colors.green
                            : app.playlist.progressPlayed,
                        borderRadius: app.shape.br(4),
                      ),
                      child: Text(
                        isFinished ? 'DONE' : '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          color: app.core.tx,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Progress bar at bottom
            if (progress > 0 && !isFinished)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    app.playlist.progressPlayed,
                  ),
                  minHeight: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Back navigation is handled via MainPageBridge.handleBackNavigation
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          focusNode: _focus.backButtonFocusNode,
          icon: const Icon(Icons.arrow_back),
          onPressed: _sections.navigation.navigateUp,
        ),
        actions: [
          // Search button (only for Raw and Sort A-Z modes)
          if (_navigation.currentViewMode != FolderViewMode.seriesArrange)
            IconButton(
              focusNode: _focus.searchButtonFocusNode,
              icon: Icon(_search.isSearchActive ? Icons.close : Icons.search),
              onPressed: _sections.search.toggleSearch,
              tooltip: _search.isSearchActive ? 'Close search' : 'Search files',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _sections.contentLoading.loadContent,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // View mode dropdown
          if (!_catalog.isLoading && _catalog.errorMessage == null)
            ViewModeDropdown(
              currentMode: _navigation.currentViewMode,
              onModeChanged: _sections.viewModes.applyViewMode,
              focusNode: _focus.viewModeDropdownFocusNode,
            ),

          // Search bar (only for Raw and Sort A-Z modes when active)
          if (_search.isSearchActive &&
              _navigation.currentViewMode != FolderViewMode.seriesArrange)
            _buildSearchBar(),

          // Content area
          Expanded(
            child: _search.isSearchActive
                ? _buildSearchResults()
                : _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_catalog.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_catalog.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _catalog.errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _sections.contentLoading.loadContent,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_navigation.currentViewNodes == null ||
        _navigation.currentViewNodes!.isEmpty) {
      return const Center(child: Text('No files found'));
    }

    // For Series Arrange mode, show OTT-style view
    if (_navigation.currentViewMode == FolderViewMode.seriesArrange) {
      return _buildOTTView();
    }

    // For Raw and Sort modes, show file browser
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _navigation.currentViewNodes!.length,
      itemBuilder: (context, index) {
        final node = _navigation.currentViewNodes![index];
        return _buildFileCard(node);
      },
    );
  }

  Widget _buildFileCard(RDFileNode node) {
    final app = AppThemeScope.of(context);
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);

    // Get progress for this file (if it's a video)
    double progress = 0.0;
    bool isFinished = false;
    if (isVideo) {
      // Try to get progress from cache
      // For series, use season/episode key; for others use filename
      final progressData = _sections.progress.getProgressForFile(node);
      if (progressData != null) {
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Consider finished if 90%+ watched or less than 2 minutes remaining
          isFinished = progress >= 0.9 || (durationMs - positionMs) < 120000;
        }
      }
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            if (isFolder) {
              _sections.navigation.navigateIntoFolder(node);
            } else if (isVideo) {
              _sections.playEntries.playFile(node);
            }
            return null;
          },
        ),
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: app.playlist.card,
        child: InkWell(
          onTap: () {
            if (isFolder) {
              _sections.navigation.navigateIntoFolder(node);
            } else if (isVideo) {
              _sections.playEntries.playFile(node);
            }
          },
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Icon
                    Icon(
                      isFolder
                          ? Icons.folder
                          : isVideo
                          ? Icons.play_circle_outline
                          : Icons.insert_drive_file,
                      color: isFolder ? Colors.amber : Colors.blue,
                      size: 32,
                    ),
                    const SizedBox(width: 12),

                    // File info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            node.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFolder
                                ? '${node.fileCount} files • ${Formatters.formatFileSize(node.totalBytes)}'
                                : Formatters.formatFileSize(node.bytes ?? 0),
                            style: TextStyle(
                              color: app.playlist.ink2,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Arrow for folders or progress indicator for videos
                    if (isFolder)
                      Icon(
                        Icons.chevron_right,
                        // Colors.white54 at its exact alpha, off the page ink.
                        color: app.core.tx.withValues(alpha: 0x8A / 255),
                      )
                    else if (isVideo && progress > 0.0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isFinished
                              ? app.playlist.statusWatched
                              : app.playlist.progressPlayed,
                          borderRadius: app.shape.br(4),
                        ),
                        child: Text(
                          isFinished ? 'DONE' : '${(progress * 100).round()}%',
                          style: TextStyle(
                            // Legacy keeps its shipped WHITE explicitly. It
                            // cannot be left to inkOn: white scores 3.77 on
                            // legacy's #059669 and 3.12 on Colors.blue, both
                            // under the 4.0 threshold, so inkOn returns
                            // core.ground and the badge would flip to
                            // near-black — a visible change to today's app.
                            //
                            // Every other theme scores, because white on a
                            // DERIVED success green is ~1.9:1 and unreadable.
                            color: app.isLegacy
                                ? app.core.tx
                                : app.inkOn(
                                    isFinished
                                        ? app.playlist.statusWatched
                                        : app.playlist.progressPlayed,
                                  ),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Progress bar overlay for videos
              if (isVideo && progress > 0.0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isFinished
                              ? app.playlist.statusWatched
                              : app.playlist.progressPlayed,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build OTT-style view for Series Arrange mode
  Widget _buildOTTView() {
    // Parse series playlist if not already done
    if (_series.seriesPlaylist == null && _catalog.rootContent != null) {
      _sections.seriesMetadata.parseSeriesPlaylist();
    }

    if (_series.seriesPlaylist == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_series.seriesPlaylist!.isSeries) {
      // Auto-switch to Sort (A-Z) view after a brief delay
      // Cancel any pending timer to prevent duplicates
      _ott.ottViewAutoSwitchTimer?.cancel();
      _ott.ottViewAutoSwitchTimer = Timer(const Duration(seconds: 2), () {
        if (mounted &&
            _navigation.currentViewMode == FolderViewMode.seriesArrange) {
          setState(() {
            _navigation.currentViewMode = FolderViewMode.sortedAZ;
            _sections.viewModes.applyViewMode(FolderViewMode.sortedAZ);
          });
        }
      });

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 48,
                color: AppThemeScope.of(context).playlist.ink2,
              ),
              const SizedBox(height: 16),
              const Text(
                'No series detected in this content',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Switching to Sort (A-Z) view...',
                // Colors.white60 at its exact alpha, off the page ink.
                style: TextStyle(
                  color: AppThemeScope.of(
                    context,
                  ).core.tx.withValues(alpha: 0x99 / 255),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final season = _series.seriesPlaylist!.getSeason(
      _series.selectedSeasonNumber,
    );
    if (season == null) {
      // Default to first available season
      if (_series.seriesPlaylist!.seasons.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _series.selectedSeasonNumber =
                _series.seriesPlaylist!.seasons.first.seasonNumber;
          });
        });
      }
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Season selector
        _buildSeasonSelector(),

        // Loading indicator for metadata
        if (_series.isLoadingSeriesMetadata) const LinearProgressIndicator(),

        // Episode list
        Expanded(child: _buildEpisodeList(season)),
      ],
    );
  }

  /// Build season selector dropdown
  Widget _buildSeasonSelector() {
    if (_series.seriesPlaylist == null) return const SizedBox.shrink();
    final app = AppThemeScope.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          DropdownButton<int>(
            value: _series.selectedSeasonNumber,
            dropdownColor: app.cloud.dialogSurface,
            underline: const SizedBox.shrink(),
            items: _series.seriesPlaylist!.seasons.map((season) {
              return DropdownMenuItem(
                value: season.seasonNumber,
                child: Text(
                  season.seasonNumber == 0
                      ? 'Specials'
                      : 'Season ${season.seasonNumber}',
                  style: const TextStyle(fontSize: 14),
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value != null) {
                // Cancel any pending scroll retry timer before season change
                _scroll.scrollRetryTimer?.cancel();

                setState(() {
                  _series.selectedSeasonNumber = value;
                  // Reset target episode index when season changes manually
                  // so it recalculates for the new season
                  _scroll.targetEpisodeIndex = null;
                  // Reset scroll scheduled flag to allow auto-scroll in new season
                  _scroll.isScrollScheduled = false;
                });
              }
            },
          ),
          const Spacer(),
          // Fix Metadata button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _sections.seriesMetadata.showFixMetadataDialog,
              borderRadius: app.shape.br(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: app.playlist.warning.withValues(alpha: 0.2),
                  borderRadius: app.shape.br(8),
                  border: Border.all(
                    color: app.playlist.warning.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.build, color: app.playlist.warning, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Fix Metadata',
                      style: TextStyle(
                        color: app.playlist.warning,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build episode list
  Widget _buildEpisodeList(SeriesSeason season) {
    // Determine which episode to scroll to (if any)
    // Use _isScrollScheduled flag to prevent duplicate scroll scheduling during rebuilds
    if (_scroll.targetEpisodeIndex == null && !_scroll.isScrollScheduled) {
      _scroll.targetEpisodeIndex = _sections.progress
          .determineInitialEpisodeIndex(season);

      // Schedule auto-scroll after the list is built
      // IMPORTANT: Always schedule the callback - hasClients will be checked inside
      if (_scroll.targetEpisodeIndex != null) {
        _scroll.isScrollScheduled =
            true; // Mark as scheduled to prevent duplicates
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _scrollToEpisode(_scroll.targetEpisodeIndex!);
          }
          _scroll.isScrollScheduled = false; // Reset after scroll attempt
        });
      }
    }

    return ListView.builder(
      controller: _scroll.episodeListScrollController,
      padding: const EdgeInsets.all(16),
      itemCount: season.episodes.length,
      itemBuilder: (context, index) {
        final episode = season.episodes[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildEpisodeCard(episode),
        );
      },
    );
  }

  /// Scroll to a specific episode index with animation
  void _scrollToEpisode(int episodeIndex, {int retryCount = 0}) {
    // Cancel any existing retry timer to prevent memory leaks
    _scroll.scrollRetryTimer?.cancel();

    if (!_scroll.episodeListScrollController.hasClients) {
      // Retry up to 3 times with increasing delay
      if (retryCount < 3) {
        print(
          '⏳ ScrollController not ready yet, scheduling retry ${retryCount + 1}/3',
        );
        _scroll.scrollRetryTimer = Timer(
          Duration(milliseconds: 100 * (retryCount + 1)),
          () {
            if (mounted) {
              _scrollToEpisode(episodeIndex, retryCount: retryCount + 1);
            }
          },
        );
      } else {
        print(
          '❌ Failed to scroll after 3 retries - ScrollController never attached',
        );
      }
      return;
    }

    // Calculate approximate position
    // Each episode card is roughly 108px (desktop) or 100px (mobile) + 16px padding
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final estimatedItemHeight = isMobile
        ? 116.0
        : 124.0; // card height + padding
    final targetOffset = episodeIndex * estimatedItemHeight;

    // Ensure we don't scroll beyond the max extent
    final maxScrollExtent =
        _scroll.episodeListScrollController.position.maxScrollExtent;
    final finalOffset = targetOffset > maxScrollExtent
        ? maxScrollExtent
        : targetOffset;

    print(
      '📜 Auto-scrolling to episode index: $episodeIndex (offset: $finalOffset, max: $maxScrollExtent)',
    );

    // Scroll to the target episode with animation
    _scroll.episodeListScrollController.animateTo(
      finalOffset,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
    );
  }

  /// Build episode card with responsive layout (vertical on mobile, horizontal on desktop)
  Widget _buildEpisodeCard(SeriesEpisode episode) {
    final app = AppThemeScope.of(context);
    // Get progress for this episode
    double progress = 0.0;
    bool isFinished = false;
    if (episode.seriesInfo.season != null &&
        episode.seriesInfo.episode != null) {
      final key = '${episode.seriesInfo.season}_${episode.seriesInfo.episode}';
      print(
        '🔍 Looking for progress with key: $key for ${episode.displayTitle}',
      );
      print(
        '💾 Available keys in cache: ${_series.fileProgressCache.keys.toList()}',
      );
      final progressData = _series.fileProgressCache[key];
      if (progressData != null) {
        print('✅ Found progress data: $progressData');
        final positionMs = progressData['positionMs'] as int? ?? 0;
        final durationMs = progressData['durationMs'] as int? ?? 0;
        if (durationMs > 0) {
          progress = positionMs / durationMs;
          // Check if finished based on progress OR if it's marked as finished explicitly
          // Dummy data has durationMs = 1 to indicate manually marked as watched
          isFinished =
              progress >= 0.9 ||
              (durationMs - positionMs) < 120000 ||
              (positionMs == 0 && durationMs == 1);
          print(
            '📈 Progress: ${(progress * 100).round()}%, Finished: $isFinished',
          );
        }
      } else {
        print('❌ No progress data found for key: $key');
      }
    }

    final episodeInfo = episode.episodeInfo;
    final hasMetadata = episodeInfo != null;

    // Detect screen width for responsive layout
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Focus(
      onFocusChange: (focused) {
        if (!focused) {
          // Clean up long press state when losing focus
          _episode.episodeLongPressTimer?.cancel();
          _episode.episodeLongPressTriggered = false;
          _episode.episodeKeyDownReceived = false;
        }
      },
      onKeyEvent: (node, event) {
        // Handle Select/Enter button press for D-pad long press detection
        if (isActivateKey(event.logicalKey)) {
          if (event is KeyDownEvent) {
            _episode.episodeKeyDownReceived = true;
            _episode.episodeLongPressTriggered = false;

            // Start timer for long press (800ms) - marks as watched
            _episode.episodeLongPressTimer?.cancel();
            _episode.episodeLongPressTimer = Timer(
              const Duration(milliseconds: 800),
              () {
                _episode.episodeLongPressTriggered = true;
                _episode.lastEpisodeLongPressTime = DateTime.now();
                _sections.watched.toggleWatchedState(episode);
              },
            );

            return KeyEventResult.handled;
          } else if (event is KeyRepeatEvent) {
            // Ignore key repeat events - don't restart the timer
            return KeyEventResult.handled;
          } else if (event is KeyUpEvent) {
            _episode.episodeLongPressTimer?.cancel();

            // Only process KeyUp if we received KeyDown while focused
            if (!_episode.episodeKeyDownReceived) {
              return KeyEventResult.handled;
            }

            // Check if we recently triggered a long press
            final timeSinceLongPress = _episode.lastEpisodeLongPressTime != null
                ? DateTime.now()
                      .difference(_episode.lastEpisodeLongPressTime!)
                      .inMilliseconds
                : 999999;

            // Short press - play episode
            if (!_episode.episodeLongPressTriggered &&
                timeSinceLongPress > 300) {
              _sections.playEntries.playEpisode(episode);
            }
            _episode.episodeLongPressTriggered = false;
            _episode.episodeKeyDownReceived = false;

            return KeyEventResult.handled;
          }
        }

        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = Focus.of(context).hasFocus;
          return Stack(
            children: [
              Card(
                // The focused state is the idle veil LIFTED, so it is spelled
                // off rowFill rather than as an unrelated white.
                color: isFocused
                    ? app.playlist.rowFill.withValues(alpha: 0.08)
                    : app.playlist.rowFill,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: app.shape.br(12),
                  side: BorderSide(
                    color: isFocused
                        ? app.playlist.focusRing
                        : app.fade(app.core.tx, 0.06),
                    width: isFocused ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  onTap: _episode.isAndroidTv
                      ? null
                      : () => _sections.playEntries.playEpisode(episode),
                  onLongPress: _episode.isAndroidTv
                      ? null
                      : () => _sections.watched.toggleWatchedState(episode),
                  child: isMobile
                      ? _buildMobileEpisodeCard(
                          episode,
                          progress,
                          isFinished,
                          hasMetadata,
                          episodeInfo,
                        )
                      : _buildDesktopEpisodeCard(
                          episode,
                          progress,
                          isFinished,
                          hasMetadata,
                          episodeInfo,
                        ),
                ),
              ),
              // Long press hint for Android TV (bottom-right when focused)
              if (_episode.isAndroidTv && isFocused)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      // Black glass stays black on every theme.
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: app.shape.br(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isFinished ? Icons.remove_done : Icons.done_all,
                          size: 14,
                          color: app.onGlass.withValues(alpha: 0.9),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFinished
                              ? 'Hold to unmark'
                              : 'Hold to mark watched',
                          style: TextStyle(
                            color: app.onGlass.withValues(alpha: 0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Build mobile layout — compact horizontal row with thumbnail left, info right (Trakt-style)
  Widget _buildMobileEpisodeCard(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  ) {
    final app = AppThemeScope.of(context);
    final epNum = episode.seriesInfo.episode;
    final titlePrefix = epNum != null
        ? 'E${epNum.toString().padLeft(2, '0')} - '
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Compact thumbnail
          ClipRRect(
            borderRadius: app.shape.brImg(8),
            child: SizedBox(
              width: 120,
              height: 68,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasMetadata && episodeInfo!.poster != null)
                    Image.network(
                      episodeInfo.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildThumbnailPlaceholder(episode);
                      },
                    )
                  else
                    _buildThumbnailPlaceholder(episode),

                  if (isFinished)
                    // Black scrim over artwork — stays black on every theme.
                    Container(color: Colors.black.withValues(alpha: 0.6)),

                  // Thin progress bar at bottom
                  if (progress > 0.0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              // The finished half is statusWatched; the
                              // in-progress indigo is left literal — it is
                              // NOT playlist.progressPlayed (Material blue),
                              // and playlist.accent's role is the surface's
                              // action colour, not a progress bar.
                              gradient: LinearGradient(
                                colors: [
                                  isFinished
                                      ? app.playlist.statusWatched
                                      : const Color(0xFF6366F1),
                                  isFinished
                                      ? app.playlist.statusWatched.withValues(
                                          alpha: 0.7,
                                        )
                                      : const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Middle: Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$titlePrefix${episode.displayTitle}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _buildEpisodeMetadataRow(
                  episode,
                  episodeInfo,
                  progress,
                  isFinished,
                ),
                if (hasMetadata && episodeInfo!.plot != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    episodeInfo.plot!,
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Watched button
          GestureDetector(
            onTap: () => _sections.watched.toggleWatchedState(episode),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // #4CAF50 left literal: playlist.statusWatched is #059669,
                // so no token carries this green.
                color: isFinished
                    ? const Color(0xFF4CAF50)
                    : app.playlist.controlFill,
                border: Border.all(
                  color: isFinished
                      ? const Color(0xFF4CAF50)
                      : app.fade(app.core.tx, 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isFinished ? Icons.check : Icons.circle_outlined,
                color: app.core.tx,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build desktop horizontal layout (thumbnail left, info right) — Trakt-style
  Widget _buildDesktopEpisodeCard(
    SeriesEpisode episode,
    double progress,
    bool isFinished,
    bool hasMetadata,
    EpisodeInfo? episodeInfo,
  ) {
    final app = AppThemeScope.of(context);
    final epNum = episode.seriesInfo.episode;
    final titlePrefix = epNum != null
        ? 'E${epNum.toString().padLeft(2, '0')} - '
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Compact thumbnail
          ClipRRect(
            borderRadius: app.shape.brImg(8),
            child: SizedBox(
              width: 155,
              height: 88,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasMetadata && episodeInfo!.poster != null)
                    Image.network(
                      episodeInfo.poster!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildThumbnailPlaceholder(episode);
                      },
                    )
                  else
                    _buildThumbnailPlaceholder(episode),

                  // Dim overlay for watched episodes
                  if (isFinished)
                    // Black scrim over artwork — stays black on every theme.
                    Container(color: Colors.black.withValues(alpha: 0.6)),

                  // Thin progress bar at bottom of thumbnail
                  if (progress > 0.0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress.clamp(0.0, 1.0),
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              // The finished half is statusWatched; the
                              // in-progress indigo is left literal — it is
                              // NOT playlist.progressPlayed (Material blue),
                              // and playlist.accent's role is the surface's
                              // action colour, not a progress bar.
                              gradient: LinearGradient(
                                colors: [
                                  isFinished
                                      ? app.playlist.statusWatched
                                      : const Color(0xFF6366F1),
                                  isFinished
                                      ? app.playlist.statusWatched.withValues(
                                          alpha: 0.7,
                                        )
                                      : const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 14),

          // Middle: Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Episode title with E## prefix
                Text(
                  '$titlePrefix${episode.displayTitle}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 4),

                // Metadata row — S01E01 badge, air date, runtime, rating, watch status
                _buildEpisodeMetadataRow(
                  episode,
                  episodeInfo,
                  progress,
                  isFinished,
                ),

                // Description
                if (hasMetadata && episodeInfo!.plot != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    episodeInfo.plot!,
                    style: TextStyle(
                      color: app.core.tx.withValues(alpha: 0.45),
                      fontSize: 11,
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Mark as watched button
          GestureDetector(
            onTap: () => _sections.watched.toggleWatchedState(episode),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // #4CAF50 left literal: playlist.statusWatched is #059669,
                // so no token carries this green.
                color: isFinished
                    ? const Color(0xFF4CAF50)
                    : app.playlist.controlFill,
                border: Border.all(
                  color: isFinished
                      ? const Color(0xFF4CAF50)
                      : app.fade(app.core.tx, 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                isFinished ? Icons.check : Icons.circle_outlined,
                color: app.core.tx,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build compact metadata row (Trakt-style) for episode cards
  Widget _buildEpisodeMetadataRow(
    SeriesEpisode episode,
    EpisodeInfo? episodeInfo,
    double progress,
    bool isFinished,
  ) {
    final app = AppThemeScope.of(context);
    final seString = episode.seasonEpisodeString;

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Green S01E01 badge. #34D399 left literal: no token carries it.
        if (seString.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF34D399).withValues(alpha: 0.15),
              borderRadius: app.shape.br(4),
            ),
            child: Text(
              seString,
              style: const TextStyle(
                color: Color(0xFF34D399),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (episodeInfo?.airDate != null)
          Text(
            formatAirDate(episodeInfo!.airDate!),
            style: TextStyle(color: app.playlist.ink3, fontSize: 11),
          ),
        if (episodeInfo?.runtime != null)
          Text(
            '${episodeInfo!.runtime} min',
            style: TextStyle(color: app.playlist.ink3, fontSize: 11),
          ),
        if (episodeInfo?.rating != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Left literal on purpose: value-equal to the DPAD cursor but a
              // RATING, whose real destination (core.rating, #F5C518) is a
              // different colour and therefore a separate sweep decision.
              const Icon(
                Icons.star_rounded,
                size: 13,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 2),
              Text(
                episodeInfo!.rating!.toStringAsFixed(1),
                style: TextStyle(
                  color: app.core.tx.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        if (progress > 0.0)
          Text(
            isFinished ? 'Watched' : '${(progress * 100).round()}%',
            style: TextStyle(
              color: app.core.tx.withValues(alpha: 0.45),
              fontSize: 11,
            ),
          ),
      ],
    );
  }

  /// Build thumbnail placeholder
  Widget _buildThumbnailPlaceholder(SeriesEpisode episode) {
    final app = AppThemeScope.of(context);
    // `Colors.white38` at its exact alpha, spelled off the page ink.
    final ink38 = app.core.tx.withValues(alpha: 0x62 / 255);
    return Container(
      // Colors.grey.shade900 left literal: no token carries it.
      color: Colors.grey.shade900,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library, color: ink38, size: 48),
            const SizedBox(height: 8),
            Text(
              episode.seasonEpisodeString,
              style: TextStyle(color: ink38, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
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
    'scrollToEpisode': s._scrollToEpisode,
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
