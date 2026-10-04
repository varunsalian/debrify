import 'dart:async';
import 'package:debrify/features/playlist_content/application/playlist_content_file_trees.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_formatting.dart';
import 'package:debrify/features/playlist_content/application/playlist_content_sort_policy.dart';
import 'package:debrify/features/playlist_content/models/playlist_content_search_result.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_catalog_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_cloud_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_content_loading.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_episode_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_focus_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_initialization.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_navigation_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_ott_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_playlist_order.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_scroll_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_search_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_sections.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_series_state.dart';
import 'package:debrify/features/playlist_content/presentation/legacy_playlist_content/playlist_content_view_modes.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/screens/video_player/models/playlist_entry.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/episode_info_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/services/storage/playlist_poster_storage.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/tvmaze_mapping_storage.dart';
import 'package:debrify/services/storage/webdav_server_storage.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/services/webdav_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/utils/tv_keys.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:debrify/widgets/tvmaze_search_dialog.dart';
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
      parseSeriesPlaylist: () => _parseSeriesPlaylist(),
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
      toggleSearch: () => _toggleSearch(),
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

  /// Load progress data for all files
  Future<void> _loadProgressData() async {
    try {
      Map<String, Map<String, dynamic>> episodeProgress = {};

      // 1. Try IMDB ID lookup first (most reliable — avoids title mismatches)
      final imdbId = widget.playlistItem['imdbId'] as String?;
      if (imdbId != null && imdbId.isNotEmpty) {
        episodeProgress =
            await MergedEpisodeProgressStorage.getEpisodeProgressByImdbId(
              imdbId,
            );
      }

      // 2. Fallback: try seriesTitle field
      if (episodeProgress.isEmpty) {
        final seriesTitle = widget.playlistItem['seriesTitle'] as String?;
        if (seriesTitle != null && seriesTitle.isNotEmpty) {
          episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
            seriesTitle: seriesTitle,
          );
        }
      }

      // 3. Fallback: try raw title
      if (episodeProgress.isEmpty) {
        final title = widget.playlistItem['title'] as String?;
        if (title != null) {
          episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
            seriesTitle: title,
          );
        }
      }

      setState(() {
        _series.fileProgressCache = episodeProgress;
      });
    } catch (e) {
      print('❌ Error loading progress data: $e');
      _series.fileProgressCache = {};
    }
  }

  /// Play a file with full playlist support
  Future<void> _playFile(RDFileNode file) async {
    if (file.isFolder || _catalog.rootContent == null) return;

    try {
      // Show loading dialog
      final app = AppThemeScope.of(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          // A MODAL ground, which is why it is cloud.dialogSurface and not
          // playlist.card — legacy spells both #1E293B.
          backgroundColor: app.cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _catalog.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _sections.playlistOrder.applySortedPlaylistOrder(videoFiles);

      // Find the selected file index
      int startIndex = 0;
      for (int i = 0; i < videoFiles.length; i++) {
        if (videoFiles[i].name == file.name &&
            videoFiles[i].path == file.path) {
          startIndex = i;
          break;
        }
      }

      final provider =
          ((widget.playlistItem['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

      if (provider == 'realdebrid') {
        await _playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _playPikPakPlaylist(videoFiles, startIndex);
      } else if (provider == 'webdav') {
        await _playWebDavPlaylist(videoFiles, startIndex);
      } else if (provider == 'premiumize') {
        await _playPremiumizePlaylist(videoFiles, startIndex);
      } else if (provider == 'alldebrid') {
        await _playAllDebridPlaylist(videoFiles, startIndex);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress after returning from video player
      if (mounted) {
        await _reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing file: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (mounted) {
        await _reloadProgress();
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play file: $e')));
      }
    }
  }

  // ============ Search Methods ============
  /// Toggle search mode on/off
  void _toggleSearch() {
    setState(() {
      _search.isSearchActive = !_search.isSearchActive;
      if (!_search.isSearchActive) {
        _search.searchController.clear();
        _search.searchResults.clear();
      } else {
        // Focus the search field when activating
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files
  void _performSearch(String query) {
    if (_catalog.rootContent == null || query.isEmpty) {
      setState(() => _search.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <PlaylistContentSearchResult>[];

    // Recursive function to search with path tracking
    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        // Only search video files
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(
            PlaylistContentSearchResult(node: node, path: path.join(' / ')),
          );
        }
      } else {
        // Recurse into folder
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    // Start search from root's children (skip root name itself)
    for (final child in _catalog.rootContent!.children) {
      searchNode(child, []);
    }

    setState(() => _search.searchResults = results);
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
              onChanged: _performSearch,
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
    final progressData = _getProgressForFile(node);
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
        onTap: () => _playFile(node),
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
              onPressed: _toggleSearch,
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
      final progressData = _getProgressForFile(node);
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
              _playFile(node);
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
              _playFile(node);
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

  /// Get progress data for a specific file
  Map<String, dynamic>? _getProgressForFile(RDFileNode file) {
    // ALWAYS try to parse season/episode from filename first (regardless of view mode)
    // This ensures progress is consistent across Raw and Series Arrange modes
    final seriesInfo = SeriesParser.parseFilename(file.name);
    if (seriesInfo.season != null && seriesInfo.episode != null) {
      final key = '${seriesInfo.season}_${seriesInfo.episode}';
      final progressData = _series.fileProgressCache[key];
      if (progressData != null) {
        return progressData;
      }
    }

    // Fallback: For files without parseable season/episode, use sequential indexing
    // This is for non-series content like movies or special features
    if (_catalog.rootContent != null) {
      final allFiles = _catalog.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      // IMPORTANT: Apply sorting if in sortedAZ mode to match the index used when saving progress
      // When playing in Sort A-Z mode, progress is saved using indices from the sorted list,
      // so we must apply the same sorting here to look up the correct progress key
      _sections.playlistOrder.applySortedPlaylistOrder(videoFiles);

      final fileIndex = videoFiles.indexWhere(
        (node) => node.name == file.name && node.path == file.path,
      );

      if (fileIndex >= 0) {
        final key = '0_${fileIndex + 1}'; // season 0, 1-based episode index
        return _series.fileProgressCache[key];
      }
    }

    // Final fallback: try using filename as key
    return _series.fileProgressCache[file.name];
  }

  /// Build OTT-style view for Series Arrange mode
  Widget _buildOTTView() {
    // Parse series playlist if not already done
    if (_series.seriesPlaylist == null && _catalog.rootContent != null) {
      _parseSeriesPlaylist();
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

  /// Determine initial season based on most recently watched episode
  /// Returns the season number to start with (defaults to 1 if no progress)
  int _determineInitialSeason() {
    if (_series.fileProgressCache.isEmpty) return 1;

    // Find most recently watched episode
    String? mostRecentKey;
    int? mostRecentTimestamp;

    for (var entry in _series.fileProgressCache.entries) {
      final updatedAt = entry.value['updatedAt'];
      if (updatedAt != null) {
        try {
          // Handle both int (milliseconds) and String formats
          int timestamp;
          if (updatedAt is int) {
            // Assume it's already in milliseconds (most common format)
            timestamp = updatedAt;
          } else if (updatedAt is String) {
            // Try parsing as numeric timestamp first, then as ISO date string
            final parsed = int.tryParse(updatedAt);
            if (parsed != null) {
              // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
              // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
              // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
              if (parsed < 10000000000) {
                // Likely seconds, convert to milliseconds
                timestamp = parsed * 1000;
              } else {
                // Already milliseconds
                timestamp = parsed;
              }
            } else {
              // Parse as ISO date string
              timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
            }
          } else {
            continue;
          }

          if (mostRecentTimestamp == null || timestamp > mostRecentTimestamp) {
            mostRecentTimestamp = timestamp;
            mostRecentKey = entry.key;
          }
        } catch (e) {
          print(
            '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
          );
        }
      }
    }

    if (mostRecentKey != null) {
      // Extract season from key format "{season}_{episode}"
      final parts = mostRecentKey.split('_');
      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        if (seasonNum != null) {
          print(
            '🎯 Found most recent season: $seasonNum from key: $mostRecentKey',
          );
          return seasonNum;
        }
      }
    }

    print('📺 No recent progress found, defaulting to Season 1');
    return 1; // Default to season 1
  }

  /// Determine initial episode index to scroll to within the selected season
  /// Returns the episode index (0-based) or null if no specific episode to scroll to
  int? _determineInitialEpisodeIndex(SeriesSeason season) {
    if (_series.fileProgressCache.isEmpty) return null;

    // Find most recently watched episode in this season
    int? mostRecentTimestamp;
    int? mostRecentEpisodeNum;

    for (var entry in _series.fileProgressCache.entries) {
      final key = entry.key;
      final parts = key.split('_');

      if (parts.length >= 2) {
        final seasonNum = int.tryParse(parts[0]);
        final episodeNum = int.tryParse(parts[1]);

        // Only consider episodes from the current season
        if (seasonNum == season.seasonNumber && episodeNum != null) {
          final updatedAt = entry.value['updatedAt'];
          if (updatedAt != null) {
            try {
              // Handle both int (milliseconds) and String formats
              int timestamp;
              if (updatedAt is int) {
                // Assume it's already in milliseconds (most common format)
                timestamp = updatedAt;
              } else if (updatedAt is String) {
                // Try parsing as numeric timestamp first, then as ISO date string
                final parsed = int.tryParse(updatedAt);
                if (parsed != null) {
                  // Detect if it's likely seconds (10 digits) vs milliseconds (13 digits)
                  // Unix timestamp in seconds: ~10 digits (e.g., 1735134769)
                  // Unix timestamp in milliseconds: ~13 digits (e.g., 1735134769000)
                  if (parsed < 10000000000) {
                    // Likely seconds, convert to milliseconds
                    timestamp = parsed * 1000;
                  } else {
                    // Already milliseconds
                    timestamp = parsed;
                  }
                } else {
                  // Parse as ISO date string
                  timestamp = DateTime.parse(updatedAt).millisecondsSinceEpoch;
                }
              } else {
                continue;
              }

              if (mostRecentTimestamp == null ||
                  timestamp > mostRecentTimestamp) {
                mostRecentTimestamp = timestamp;
                mostRecentEpisodeNum = episodeNum;
              }
            } catch (e) {
              print(
                '⚠️ Failed to parse updatedAt timestamp: $updatedAt (${e.toString()})',
              );
            }
          }
        }
      }
    }

    if (mostRecentEpisodeNum != null) {
      // Find the episode index in the season's episode list
      for (int i = 0; i < season.episodes.length; i++) {
        final episode = season.episodes[i];
        if (episode.seriesInfo.episode == mostRecentEpisodeNum) {
          print(
            '🎯 Found most recent episode in season: Episode $mostRecentEpisodeNum at index $i',
          );
          return i;
        }
      }
    }

    return null; // No specific episode to scroll to
  }

  /// Reload progress data from storage
  /// Called when returning from video player to refresh progress indicators
  Future<void> _reloadProgress() async {
    if (!mounted) return;

    try {
      // Get the series/collection title from the playlist item
      // IMPORTANT: Use same logic as _parseSeriesPlaylist() for consistency
      final String? seriesTitle =
          _series.seriesPlaylist?.seriesTitle ??
          widget.playlistItem['title'] as String?;

      if (seriesTitle != null && seriesTitle.isNotEmpty) {
        print('🔄 Reloading progress after video playback for: $seriesTitle');
        final episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
          seriesTitle: seriesTitle,
        );

        if (!mounted) return; // Check again after async operation

        print(
          '📊 Reloaded ${episodeProgress.length} episodes with updated progress',
        );
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');

        setState(() {
          _series.fileProgressCache = episodeProgress;
        });
      }
    } catch (e) {
      print('❌ Error reloading progress data: $e');
      // Don't rethrow - this is a non-critical background operation
    }
  }

  /// Parse series playlist from current view nodes
  Future<void> _saveImdbIdToPlaylist({bool force = false}) async {
    final imdbId = _series.seriesPlaylist?.imdbId;
    if (imdbId == null || !imdbId.startsWith('tt')) return;
    if (!force && (widget.playlistItem?['imdbId'] as String?) != null) return;

    final rdTorrentId = widget.playlistItem?['rdTorrentId'] as String?;
    final torboxTorrentId = widget.playlistItem?['torboxTorrentId']?.toString();
    final pikpakCollectionId = widget.playlistItem?['pikpakFileId'] as String?;
    final isPremiumize =
        (widget.playlistItem?['provider'] as String?)?.toLowerCase() ==
        'premiumize';
    final String? premiumizeHash = isPremiumize
        ? (widget.playlistItem?['torrent_hash'] as String?)
        : null;
    final String? premiumizeItemId = isPremiumize
        ? (widget.playlistItem?['premiumizeItemId']?.toString())
        : null;
    final bool isAllDebrid =
        (widget.playlistItem?['provider'] as String?)?.toLowerCase() ==
        'alldebrid';
    final String? allDebridHash = isAllDebrid
        ? (widget.playlistItem?['torrent_hash'] as String?)
        : null;

    await PlaylistMetadataStorage.updatePlaylistItemImdbId(
      imdbId,
      rdTorrentId: rdTorrentId,
      torboxTorrentId: torboxTorrentId,
      pikpakCollectionId: pikpakCollectionId,
      premiumizeHash: premiumizeHash,
      premiumizeItemId: premiumizeItemId,
      allDebridHash: allDebridHash,
      force: force,
    );
  }

  Future<void> _parseSeriesPlaylist() async {
    if (_catalog.rootContent == null) return;

    try {
      // Get ALL video files recursively from the entire content tree
      final allFiles = _catalog.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        return;
      }

      // Create PlaylistEntry objects from video files
      final entries = videoFiles
          .map(
            (f) => PlaylistEntry(
              url: '', // Not needed for parsing
              title: f.name,
              relativePath:
                  f.relativePath ??
                  f.path, // Use relativePath if available, fallback to path
            ),
          )
          .toList();

      // Get series/collection title from playlist item
      // Try 'seriesTitle' first (if previously extracted), fallback to 'title' (raw torrent name)
      final String? collectionTitle =
          widget.playlistItem['seriesTitle'] as String? ??
          widget.playlistItem['title'] as String?;

      _series.seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle: collectionTitle,
      );

      // Reload progress with the clean extracted series/collection title!
      // This works for both series and movie collections
      final String? titleForProgress =
          _series.seriesPlaylist!.seriesTitle ??
          widget.playlistItem['title'] as String?;

      if (titleForProgress != null && titleForProgress.isNotEmpty) {
        print('🔄 Reloading progress with clean title: $titleForProgress');
        print('📌 isSeries: ${_series.seriesPlaylist!.isSeries}');
        final episodeProgress = await EpisodeProgressStorage.getEpisodeProgress(
          seriesTitle: titleForProgress,
        );
        print('📊 Loaded ${episodeProgress.length} episodes with progress');
        print('🔑 Progress keys: ${episodeProgress.keys.toList()}');
        _series.fileProgressCache = episodeProgress;

        // Determine initial season based on most recent viewing history
        if (_series.seriesPlaylist!.isSeries &&
            _series.fileProgressCache.isNotEmpty) {
          final initialSeason = _determineInitialSeason();
          print('🎬 Setting initial season to: $initialSeason');
          _series.selectedSeasonNumber = initialSeason;
        }
      }

      // Check if we have a saved TVMaze mapping (indicates cached data)
      // Only show loading indicator if data needs to be fetched
      bool showLoading = true;
      if (widget.playlistItem != null) {
        final mapping = await TvMazeMappingStorage.getTVMazeSeriesMapping(
          widget.playlistItem!,
        );
        if (mapping != null) {
          showLoading = false; // Data should be cached, skip loading indicator
        }
      }

      if (showLoading) {
        setState(() {
          _series.isLoadingSeriesMetadata = true;
        });
      }

      // Fetch TVMaze metadata asynchronously
      if (_series.seriesPlaylist!.isSeries) {
        _series.seriesPlaylist!
            .fetchEpisodeInfo(
              playlistItem: widget.playlistItem,
              imdbId: widget.playlistItem?['imdbId'] as String?,
            )
            .then((_) async {
              await _saveImdbIdToPlaylist();
              await _saveDetectedSeriesPosterToPlaylist();
              if (mounted) {
                setState(() {
                  _series.isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
              print('Failed to fetch episode metadata: $e');
              if (mounted) {
                setState(() {
                  _series.isLoadingSeriesMetadata = false;
                });
              }
            });
      }
    } catch (e) {
      print('Failed to parse series playlist: $e');
      setState(() {
        _series.isLoadingSeriesMetadata = false;
      });
    }
  }

  /// Show the Fix Metadata dialog to manually select a TV show
  Future<void> _showFixMetadataDialog() async {
    // Show the search dialog
    final selectedShow = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TVMazeSearchDialog(
        initialQuery: _series.seriesPlaylist?.seriesTitle ?? '',
      ),
    );

    if (selectedShow != null && mounted) {
      // 1. Get OLD mapping (before it's overwritten)
      final oldMapping = await TvMazeMappingStorage.getTVMazeSeriesMapping(
        widget.playlistItem,
      );
      final oldShowId = oldMapping?['tvmazeShowId'] as int?;

      // 2. Clear old show ID cache if it exists
      if (oldShowId != null && oldShowId != selectedShow['id']) {
        debugPrint('🧹 Clearing old show ID cache: $oldShowId');
        await TVMazeService.clearShowCache(oldShowId);
        await EpisodeInfoService.clearShowCache(oldShowId);
      }

      // 3. Clear series name cache (existing logic)
      await EpisodeInfoService.clearSeriesCache(
        _series.seriesPlaylist?.seriesTitle ?? '',
      );
      await TVMazeService.clearSeriesCache(
        _series.seriesPlaylist?.seriesTitle ?? '',
      );

      // 4. Save new mapping
      await TvMazeMappingStorage.saveTVMazeSeriesMapping(
        playlistItem: widget.playlistItem,
        tvmazeShowId: selectedShow['id'] as int,
        showName: selectedShow['name'] as String,
      );

      // Update playlist item poster/cover image
      await _updatePlaylistPoster(selectedShow);

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Metadata fixed! Using "${selectedShow['name']}" from TVMaze',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Reload episode info with the new show ID
      if (_series.seriesPlaylist != null &&
          _series.seriesPlaylist!.isSeries &&
          mounted) {
        // Clear stale tvmazeShowId so fetchEpisodeInfo reads the new mapping.
        // The name goes with it: fetchEpisodeInfo rewrites it on success, but
        // a failed lookup must not leave the OLD show's name captioning the
        // player dock.
        _series.seriesPlaylist!.tvmazeShowId = null;
        _series.seriesPlaylist!.tvmazeShowName = null;
        _series.seriesPlaylist!.showPosterUrl = null;

        setState(() {
          _series.isLoadingSeriesMetadata = true;
        });

        _series.seriesPlaylist!
            .fetchEpisodeInfo(
              playlistItem: widget.playlistItem,
              imdbId: widget.playlistItem?['imdbId'] as String?,
            )
            .then((_) async {
              await _saveImdbIdToPlaylist(force: true);
              await _saveDetectedSeriesPosterToPlaylist();
              if (mounted) {
                setState(() {
                  _series.isLoadingSeriesMetadata = false;
                });
              }
            })
            .catchError((e) {
              print('Failed to refresh episode metadata: $e');
              if (mounted) {
                setState(() {
                  _series.isLoadingSeriesMetadata = false;
                });
              }
            });
      }
    }
  }

  Future<void> _saveDetectedSeriesPosterToPlaylist() async {
    final posterUrl = _series.seriesPlaylist?.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) return;

    try {
      await PlaylistPosterStorage.savePlaylistPosterOverride(
        playlistItem: widget.playlistItem,
        posterUrl: posterUrl,
      );

      final itemKey = PlaylistStorage.computePlaylistDedupeKey(
        widget.playlistItem,
      );
      final items = await PlaylistStorage.getPlaylistItemsRaw();
      final itemIndex = items.indexWhere(
        (item) => PlaylistStorage.computePlaylistDedupeKey(item) == itemKey,
      );

      if (itemIndex >= 0) {
        items[itemIndex]['posterUrl'] = posterUrl;
        await PlaylistStorage.savePlaylistItemsRaw(items);
      }
    } catch (e) {
      debugPrint('Error saving detected series poster: $e');
    }
  }

  /// Update the playlist item's poster/cover image with the TVMaze show poster
  Future<void> _updatePlaylistPoster(Map<String, dynamic> showInfo) async {
    try {
      // Extract poster URL from TVMaze show data
      // TVMaze provides 'image' with 'medium' and 'original' URLs
      final image = showInfo['image'];
      String? posterUrl;

      if (image != null && image is Map<String, dynamic>) {
        // Prefer original over medium for better quality
        posterUrl = image['original'] as String? ?? image['medium'] as String?;
      }

      if (posterUrl == null || posterUrl.isEmpty) {
        print('No poster URL found in TVMaze show data');
        return;
      }

      print('🎬 Updating playlist poster with: $posterUrl');

      // CRITICAL: Save poster override to persistent storage
      // This ensures the poster persists across app restarts
      await PlaylistPosterStorage.savePlaylistPosterOverride(
        playlistItem: widget.playlistItem,
        posterUrl: posterUrl,
      );

      // Also update the in-memory playlist item for immediate UI update
      final provider =
          (widget.playlistItem['provider'] as String?) ?? 'realdebrid';
      bool updated = false;

      if (provider.toLowerCase() == 'realdebrid') {
        final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
        if (rdTorrentId != null) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            rdTorrentId: rdTorrentId,
          );
        }
      } else if (provider.toLowerCase() == 'torbox') {
        final torboxTorrentId = widget.playlistItem['torboxTorrentId'];
        if (torboxTorrentId != null) {
          // Torbox uses integer IDs, but updatePlaylistItemPoster expects String
          // We need to update the playlist manually
          final items = await PlaylistStorage.getPlaylistItemsRaw();
          final itemIndex = items.indexWhere(
            (item) => item['torboxTorrentId'] == torboxTorrentId,
          );

          if (itemIndex >= 0) {
            items[itemIndex]['posterUrl'] = posterUrl;
            await PlaylistStorage.savePlaylistItemsRaw(items);
            updated = true;
          }
        }
      } else if (provider.toLowerCase() == 'pikpak') {
        final pikpakCollectionId =
            widget.playlistItem['pikpakFileId'] as String?;
        if (pikpakCollectionId != null) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            pikpakCollectionId: pikpakCollectionId,
          );
        }
      } else if (provider.toLowerCase() == 'premiumize') {
        final premiumizeHash = widget.playlistItem['torrent_hash'] as String?;
        final premiumizeItemId = widget.playlistItem['premiumizeItemId']
            ?.toString();
        if (premiumizeHash != null && premiumizeHash.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            premiumizeHash: premiumizeHash,
          );
        } else if (premiumizeItemId != null && premiumizeItemId.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            premiumizeItemId: premiumizeItemId,
          );
        }
      } else if (provider.toLowerCase() == 'alldebrid') {
        final allDebridHash = widget.playlistItem['torrent_hash'] as String?;
        if (allDebridHash != null && allDebridHash.isNotEmpty) {
          updated = await PlaylistArtworkStorage.updatePlaylistItemPoster(
            posterUrl,
            allDebridHash: allDebridHash,
          );
        }
      }

      if (updated) {
        print(
          '✅ Successfully updated playlist poster in memory and persistent storage',
        );
      } else {
        print(
          '⚠️ Updated persistent storage but in-memory update failed - poster will still persist on restart',
        );
      }
    } catch (e) {
      print('❌ Error updating playlist poster: $e');
    }
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
              onTap: _showFixMetadataDialog,
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
      _scroll.targetEpisodeIndex = _determineInitialEpisodeIndex(season);

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
                _toggleWatchedState(episode);
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
              _playEpisode(episode);
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
                      : () => _playEpisode(episode),
                  onLongPress: _episode.isAndroidTv
                      ? null
                      : () => _toggleWatchedState(episode),
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
            onTap: () => _toggleWatchedState(episode),
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
            onTap: () => _toggleWatchedState(episode),
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

  /// Toggle the watched state of an episode
  Future<void> _toggleWatchedState(SeriesEpisode episode) async {
    if (_series.seriesPlaylist == null) return;

    // Cloud-playlist rows are intentionally local-only: they have file/folder
    // identity but no reliable tracker title identity. Tracker-aware catalog
    // and detail actions fan out through WatchedActionCoordinator instead.

    // Get the series title for storage
    final String? seriesTitle =
        _series.seriesPlaylist!.seriesTitle ??
        widget.playlistItem['title'] as String?;

    if (seriesTitle == null || seriesTitle.isEmpty) {
      print('❌ Cannot toggle watched state: No series title available');
      return;
    }

    // Get episode details
    final season = episode.seriesInfo.season ?? 1;
    final episodeNum = episode.seriesInfo.episode ?? 1;
    final imdbId =
        _series.seriesPlaylist?.imdbId ??
        widget.playlistItem['imdbId'] as String?;

    try {
      // Check current watched state
      final isCurrentlyFinished =
          await EpisodeProgressStorage.isEpisodeFinished(
            seriesTitle: seriesTitle,
            season: season,
            episode: episodeNum,
            imdbId: imdbId,
          );

      if (isCurrentlyFinished) {
        // Episode is marked as watched, unmark it
        print('🔄 Unmarking as watched: $seriesTitle S${season}E$episodeNum');
        await EpisodeCompletionStorage.unmarkEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
          imdbId: imdbId,
        );
      } else {
        // Episode is not watched, mark it as finished
        print('✅ Marking as watched: $seriesTitle S${season}E$episodeNum');
        await EpisodeCompletionStorage.markEpisodeAsFinished(
          seriesTitle: seriesTitle,
          season: season,
          episode: episodeNum,
          imdbId: imdbId,
        );
      }

      // Reload the progress to update the UI
      await _reloadProgress();

      // Show a snackbar to confirm the action
      // Note: isCurrentlyFinished is the OLD state before toggle, so we invert the message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCurrentlyFinished
                  ? 'Episode marked as unwatched'
                  : 'Episode marked as watched',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: isCurrentlyFinished
                ? const Color(0xFF6366F1)
                : const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('❌ Error toggling watched state: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating watched state: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Play episode from OTT view with full playlist support
  Future<void> _playEpisode(SeriesEpisode episode) async {
    if (_catalog.rootContent == null || !mounted) return;

    try {
      // Show loading dialog
      final app = AppThemeScope.of(context);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          // A MODAL ground, which is why it is cloud.dialogSurface and not
          // playlist.card — legacy spells both #1E293B.
          backgroundColor: app.cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get all video files from the entire tree
      final allFiles = _catalog.rootContent!.getAllFiles();
      final videoFiles = allFiles
          .where((node) => FileUtils.isVideoFile(node.name))
          .toList();

      if (videoFiles.isEmpty) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      // Apply Sort A-Z sorting if in sortedAZ mode
      // Use EXACT same sorting logic as UI view mode (_applySortedView)
      _sections.playlistOrder.applySortedPlaylistOrder(videoFiles);

      // Find the selected episode index
      // The approach differs based on view mode:
      // - sortedAZ: Sorting changes indices, so we MUST find by filename
      // - raw/series/collection: originalIndex is still accurate (faster and more reliable)
      int startIndex = 0;
      if (_navigation.currentViewMode == FolderViewMode.sortedAZ) {
        // After sorting, indices change - must find by filename
        for (int i = 0; i < videoFiles.length; i++) {
          if (videoFiles[i].name == episode.filename) {
            startIndex = i;
            break;
          }
        }
      } else {
        // Raw/Series/Collection modes: originalIndex is still correct
        if (episode.originalIndex >= 0 &&
            episode.originalIndex < videoFiles.length) {
          startIndex = episode.originalIndex;
        } else {
          // Fallback: try to match by filename
          for (int i = 0; i < videoFiles.length; i++) {
            if (videoFiles[i].name == episode.filename) {
              startIndex = i;
              break;
            }
          }
        }
      }

      final provider =
          ((widget.playlistItem['provider'] as String?) ?? 'realdebrid')
              .toLowerCase();

      if (provider == 'realdebrid') {
        await _playRealDebridPlaylist(videoFiles, startIndex);
      } else if (provider == 'torbox') {
        await _playTorboxPlaylist(videoFiles, startIndex);
      } else if (provider == 'pikpak') {
        await _playPikPakPlaylist(videoFiles, startIndex);
      } else if (provider == 'webdav') {
        await _playWebDavPlaylist(videoFiles, startIndex);
      } else if (provider == 'premiumize') {
        await _playPremiumizePlaylist(videoFiles, startIndex);
      } else if (provider == 'alldebrid') {
        await _playAllDebridPlaylist(videoFiles, startIndex);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress after returning from video player
      if (mounted) {
        await _reloadProgress();
      }
    } catch (e) {
      print('❌ Error playing episode: $e');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }

      // Reload progress even if an error occurred
      // (user might have watched part of video before error)
      if (mounted) {
        await _reloadProgress();
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  /// Play Real-Debrid playlist
  Future<void> _playRealDebridPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final String? apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Real-Debrid API key in Settings');
    }

    final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
    if (rdTorrentId == null) {
      throw Exception('No Real-Debrid torrent ID found');
    }

    final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
    final links = (info['links'] as List<dynamic>?) ?? [];

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final linkIndex = file.linkIndex ?? i;

      if (linkIndex >= links.length) continue;

      if (i == startIndex) {
        // Unrestrict the first file
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            links[linkIndex],
          );
          final url = unrestrictResult['download']?.toString() ?? '';
          entries.add(
            PlaylistEntry(
              url: url,
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              restrictedLink: links[linkIndex],
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              sizeBytes: file.bytes,
              provider: 'realdebrid',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath ?? file.path,
            restrictedLink: links[linkIndex],
            rdTorrentId: rdTorrentId,
            rdLinkIndex: linkIndex,
            sizeBytes: file.bytes,
            provider: 'realdebrid',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        rdTorrentId: rdTorrentId,
        disableAutoResume: true,
        viewMode: _sections.viewModes.convertToPlaylistViewMode(
          _navigation.currentViewMode,
        ),
        // Pass catalog metadata for optimized TVMaze lookup
        contentImdbId: widget.playlistItem['imdbId'] as String?,
        contentType: widget.playlistItem['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play AllDebrid playlist. Each node's linkIndex maps to its locked link in
  /// [PlaylistContentCatalogState.allDebridFiles] (populated by [PlaylistContentContentLoading.loadAllDebridContent]); the start file is
  /// unlocked, the rest carry their locked link for lazy unlock by the player.
  Future<void> _playAllDebridPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your AllDebrid API key in Settings');
    }
    final torrentHash = widget.playlistItem['torrent_hash'] as String?;

    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final linkIndex = file.linkIndex;
      if (linkIndex < 0 || linkIndex >= _catalog.allDebridFiles.length) {
        continue;
      }
      final lockedLink = _catalog.allDebridFiles[linkIndex].link;

      String url = '';
      if (i == startIndex) {
        try {
          url = await AllDebridService.unlockLink(apiKey, lockedLink);
        } catch (_) {}
      }
      entries.add(
        PlaylistEntry(
          url: url,
          title: file.name,
          relativePath: file.relativePath ?? file.path,
          provider: 'alldebrid',
          allDebridLink: lockedLink,
          torrentHash: torrentHash,
          sizeBytes: file.bytes,
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        disableAutoResume: true,
        viewMode: _sections.viewModes.convertToPlaylistViewMode(
          _navigation.currentViewMode,
        ),
        contentImdbId: widget.playlistItem['imdbId'] as String?,
        contentType: widget.playlistItem['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play Torbox playlist
  Future<void> _playTorboxPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final String? apiKey = await TorboxStorage.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Torbox API key in Settings');
    }

    final torboxTorrentId = widget.playlistItem['torboxTorrentId'] as int?;
    if (torboxTorrentId == null) {
      throw Exception('No Torbox torrent ID found');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          if (file.fileId != null) {
            final url = await TorboxService.requestFileDownloadLink(
              apiKey: apiKey,
              torrentId: torboxTorrentId,
              fileId: file.fileId!,
            );
            entries.add(
              PlaylistEntry(
                url: url,
                title: file.name,
                relativePath: cleanTorboxPath(file.path),
                torboxTorrentId: torboxTorrentId,
                torboxFileId: file.fileId,
                sizeBytes: file.bytes,
                provider: 'torbox',
              ),
            );
          }
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: cleanTorboxPath(file.path),
              torboxTorrentId: torboxTorrentId,
              torboxFileId: file.fileId,
              sizeBytes: file.bytes,
              provider: 'torbox',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: cleanTorboxPath(file.path),
            torboxTorrentId: torboxTorrentId,
            torboxFileId: file.fileId,
            sizeBytes: file.bytes,
            provider: 'torbox',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        torboxTorrentId: torboxTorrentId.toString(),
        disableAutoResume: true,
        viewMode: _sections.viewModes.convertToPlaylistViewMode(
          _navigation.currentViewMode,
        ),
        // Pass catalog metadata for optimized TVMaze lookup
        contentImdbId: widget.playlistItem['imdbId'] as String?,
        contentType: widget.playlistItem['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play PikPak playlist
  Future<void> _playPikPakPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final pikpak = PikPakApiService.instance;

    if (!await pikpak.isAuthenticated()) {
      throw Exception('Please login to PikPak in Settings');
    }

    // Build playlist entries
    final List<PlaylistEntry> entries = [];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];

      // Extract PikPak file ID from the path field
      // Format: "pikpak://fileId|fileName"
      String? fileId;
      final path = file.path;
      if (path != null && path.startsWith('pikpak://')) {
        final parts = path.substring(9).split('|');
        if (parts.isNotEmpty) {
          fileId = parts[0];
        }
      }

      if (fileId == null) continue;

      if (i == startIndex) {
        // Get streaming URL for first file
        try {
          final fileData = await pikpak.getFileDetails(fileId);
          final streamingUrl = pikpak.getStreamingUrl(fileData);
          entries.add(
            PlaylistEntry(
              url: streamingUrl ?? '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        } catch (_) {
          entries.add(
            PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath,
              pikpakFileId: fileId,
              sizeBytes: file.bytes,
              provider: 'pikpak',
            ),
          );
        }
      } else {
        entries.add(
          PlaylistEntry(
            url: '',
            title: file.name,
            relativePath: file.relativePath,
            pikpakFileId: fileId,
            sizeBytes: file.bytes,
            provider: 'pikpak',
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;

    // Hide auto-launch overlay before launching player
    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        pikpakCollectionId: widget.playlistItem['pikpakFileId'] as String?,
        disableAutoResume: true,
        viewMode: _sections.viewModes.convertToPlaylistViewMode(
          _navigation.currentViewMode,
        ),
        // Pass catalog metadata for optimized TVMaze lookup
        contentImdbId: widget.playlistItem['imdbId'] as String?,
        contentType: widget.playlistItem['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play Premiumize playlist
  Future<void> _playPremiumizePlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final infohash = (widget.playlistItem['torrent_hash'] as String?)?.trim();
    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('Please set your Premiumize API key in Settings');
    }

    // Cloud-browser collection: nodes carry cloud item ids in `path`. Resolve
    // only the starting item's link up front; the rest resolve lazily.
    if (infohash == null || infohash.isEmpty) {
      if (videoFiles.isEmpty) throw Exception('No playable files found');
      if (startIndex < 0 || startIndex >= videoFiles.length) startIndex = 0;
      final startId = videoFiles[startIndex].path;
      final startFile = startId != null
          ? await PremiumizeService.resolveItemById(apiKey, startId)
          : null;
      if (startFile == null || startFile.link.isEmpty) {
        throw Exception('Could not get Premiumize streaming URL');
      }
      final List<PlaylistEntry> cloudEntries = [];
      for (int i = 0; i < videoFiles.length; i++) {
        final file = videoFiles[i];
        final id = file.path;
        if (id == null) continue;
        cloudEntries.add(
          PlaylistEntry(
            url: i == startIndex ? startFile.link : '',
            title: file.name,
            relativePath: file.relativePath,
            provider: 'premiumize',
            premiumizeItemId: id,
            sizeBytes: file.bytes,
          ),
        );
      }
      if (cloudEntries.isEmpty) throw Exception('No playable files found');
      final String seriesTitleCloud =
          _series.seriesPlaylist?.seriesTitle ??
          widget.playlistItem['title'] as String? ??
          'Series';
      if (!mounted) return;
      widget.onPlaybackStarted?.call();
      MainPageBridge.notifyPlayerLaunching();
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: cloudEntries[startIndex].url,
          title: seriesTitleCloud,
          subtitle: '${cloudEntries.length} episodes',
          playlist: cloudEntries,
          startIndex: startIndex,
          disableAutoResume: true,
          viewMode: _sections.viewModes.convertToPlaylistViewMode(
            _navigation.currentViewMode,
          ),
          contentImdbId: widget.playlistItem['imdbId'] as String?,
          contentType: widget.playlistItem['contentType'] as String?,
          suppressTraktAutoSync: true,
        ),
      );
      return;
    }

    // Re-resolve fresh direct links and index them by path for matching.
    final resolved = await PremiumizeService.resolveFilesByHash(
      apiKey,
      infohash,
    );
    final linkByPath = <String, String>{
      for (final f in resolved) f.path: f.link,
    };

    final List<PlaylistEntry> entries = [];
    for (final file in videoFiles) {
      final path = file.path;
      if (path == null) continue;
      entries.add(
        PlaylistEntry(
          url: linkByPath[path] ?? '',
          title: file.name,
          relativePath: file.relativePath,
          provider: 'premiumize',
          premiumizeHash: infohash,
          premiumizePath: path,
          torrentHash: infohash,
          sizeBytes: file.bytes,
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }
    if (startIndex < 0 || startIndex >= entries.length) startIndex = 0;

    final String initialVideoUrl = entries[startIndex].url;
    final String seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;

    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialVideoUrl,
        title: seriesTitle,
        subtitle: '${entries.length} episodes',
        playlist: entries,
        startIndex: startIndex,
        disableAutoResume: true,
        viewMode: _sections.viewModes.convertToPlaylistViewMode(
          _navigation.currentViewMode,
        ),
        contentImdbId: widget.playlistItem['imdbId'] as String?,
        contentType: widget.playlistItem['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  /// Play WebDAV playlist
  Future<void> _playWebDavPlaylist(
    List<RDFileNode> videoFiles,
    int startIndex,
  ) async {
    final config = await _resolveWebDavConfig();
    if (config == null) {
      throw Exception('WebDAV server is no longer configured');
    }

    final entries = <PlaylistEntry>[];
    for (final file in videoFiles) {
      final path = file.path;
      if (path == null || path.isEmpty) continue;
      entries.add(
        PlaylistEntry(
          url: WebDavService.directUrl(config, path),
          title: file.name,
          relativePath: file.relativePath ?? path,
          sizeBytes: file.bytes,
          provider: 'webdav',
        ),
      );
    }

    if (entries.isEmpty) {
      throw Exception('No playable files found');
    }
    if (startIndex < 0 || startIndex >= entries.length) {
      startIndex = 0;
    }

    final seriesTitle =
        _series.seriesPlaylist?.seriesTitle ??
        widget.playlistItem['title'] as String? ??
        'Series';

    if (!mounted) return;

    widget.onPlaybackStarted?.call();
    MainPageBridge.notifyPlayerLaunching();

    final args = VideoPlayerLaunchArgs(
      videoUrl: entries[startIndex].url,
      title: seriesTitle,
      subtitle: '${entries.length} episodes',
      playlist: entries,
      startIndex: startIndex,
      disableAutoResume: true,
      viewMode: _sections.viewModes.convertToPlaylistViewMode(
        _navigation.currentViewMode,
      ),
      httpHeaders: WebDavService.authHeaders(config),
      disableExternalPlayer: hasWebDavCredentials(config),
      webDavServerId: (widget.playlistItem['webdavServerId'] ?? config.id)
          .toString(),
      webDavBaseUrl: (widget.playlistItem['webdavBaseUrl'] ?? config.baseUrl)
          .toString(),
      webDavPath:
          (widget.playlistItem['webdavFolderPath'] ??
                  widget.playlistItem['webdavPath'] ??
                  '')
              .toString(),
      contentImdbId: widget.playlistItem['imdbId'] as String?,
      contentType: widget.playlistItem['contentType'] as String?,
      suppressTraktAutoSync: true,
    );

    await VideoPlayerLauncher.push(context, args);
  }

  Future<WebDavConfig?> _resolveWebDavConfig() async {
    final serverId = (widget.playlistItem['webdavServerId'] ?? '').toString();
    final baseUrl = (widget.playlistItem['webdavBaseUrl'] ?? '').toString();
    final servers = await WebdavServerStorage.getWebDavServers(
      forSettings: false,
    );
    for (final server in servers) {
      if (serverId.isNotEmpty && server.id == serverId) return server;
    }
    for (final server in servers) {
      if (baseUrl.isNotEmpty && server.baseUrl == baseUrl) return server;
    }
    if (serverId.isEmpty && baseUrl.isEmpty && servers.length == 1) {
      return servers.first;
    }
    return null;
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
    'playFile': s._playFile,
    'toggleSearch': s._toggleSearch,
    'performSearch': s._performSearch,
    'getProgressForFile': s._getProgressForFile,
    'determineInitialSeason': s._determineInitialSeason,
    'determineInitialEpisodeIndex': s._determineInitialEpisodeIndex,
    'reloadProgress': s._reloadProgress,
    'saveImdbIdToPlaylist': s._saveImdbIdToPlaylist,
    'parseSeriesPlaylist': s._parseSeriesPlaylist,
    'showFixMetadataDialog': s._showFixMetadataDialog,
    'saveDetectedSeriesPosterToPlaylist': s._saveDetectedSeriesPosterToPlaylist,
    'updatePlaylistPoster': s._updatePlaylistPoster,
    'scrollToEpisode': s._scrollToEpisode,
    'formatAirDate': formatAirDate,
    'toggleWatchedState': s._toggleWatchedState,
    'playEpisode': s._playEpisode,
    'playRealDebridPlaylist': s._playRealDebridPlaylist,
    'playAllDebridPlaylist': s._playAllDebridPlaylist,
    'playTorboxPlaylist': s._playTorboxPlaylist,
    'playPikPakPlaylist': s._playPikPakPlaylist,
    'playPremiumizePlaylist': s._playPremiumizePlaylist,
    'playWebDavPlaylist': s._playWebDavPlaylist,
    'resolveWebDavConfig': s._resolveWebDavConfig,
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
