import 'package:debrify/features/pikpak_files/models/folder_view_mode.dart';
import 'package:debrify/features/pikpak_files/models/pikpak_playlist_item.dart';
import 'package:debrify/features/pikpak_files/models/pikpak_search_result.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_sort_policy.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_playlist_titles.dart';
import 'package:debrify/features/pikpak_files/application/pikpak_link_policy.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_catalog_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_navigation_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_view_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_focus_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_selection_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_search_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_link_state.dart';
import 'package:debrify/features/pikpak_files/presentation/legacy_pikpak/pikpak_composition.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import '../../screens/video_player_screen.dart';
import '../../services/analytics_service.dart';
import '../../services/pikpak_api_service.dart';
import '../../services/download_service.dart';
import '../../services/video_player_launcher.dart';
import '../../services/main_page_bridge.dart';
import '../../services/series_source_service.dart';
import '../../utils/file_utils.dart';
import '../../utils/formatters.dart';
import '../../utils/series_parser.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/tv_keys.dart';
import '../../widgets/cloud/cloud_file_row.dart';
import '../../widgets/cloud/cloud_row_skeleton.dart';
import '../../widgets/cloud/cloud_theme.dart';
import '../../widgets/file_selection_dialog.dart';
import '../../widgets/tv_text_field.dart';

class PikPakFilesScreen extends StatefulWidget {
  final String? initialFolderId;
  final String? initialFolderName;
  final bool selectSourceMode;
  final Future<void> Function(SeriesSource)? onSourceSelected;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  const PikPakFilesScreen({
    super.key,
    this.initialFolderId,
    this.initialFolderName,
    this.isPushedRoute = false,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  @override
  State<PikPakFilesScreen> createState() => _PikPakFilesScreenState();
}

class _PikPakFilesScreenState extends State<PikPakFilesScreen> {
  final _catalog = PikpakCatalogState();
  final _nav = PikpakNavigationState();
  final _view = PikpakViewState();
  final _focus = PikpakFocusState();
  final _selection = PikpakSelectionState();
  final _search = PikpakSearchState();
  final _link = PikpakLinkState();
  PikpakSections? _sectionCache;
  PikpakSections get _sections => _sectionCache ??= createPikpakSections(
    (
      setState: setState,
      mounted: () => mounted,
      context: () => context,
      initialFolderId: () => widget.initialFolderId,
      initialFolderName: () => widget.initialFolderName,
      isPushedRoute: () => widget.isPushedRoute,
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ),
    (
      catalogState: _catalog,
      navigationState: _nav,
      viewState: _view,
      focusState: _focus,
      selectionState: _selection,
      searchState: _search,
      linkState: _link,
    ),
  );

  // TV content focus handler (stored for proper unregistration)

  // Add link state

  // Pagination state

  // Folder navigation state

  // View mode state (per-folder persistence during session)

  // Virtual folder navigation for Series Arrange mode

  // e.g., "Season 1"
  // Files in virtual Season

  // Cache for recursive file listings (avoid repeated API calls)

  // Focus nodes for TV/DPAD navigation

  // Flag to focus first item after data loads (set by TV content focus handler)

  // Multi-select state

  // Search state (for folder browsing mode)

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('pikpak_files');
    _focus.scrollController.addListener(_sections.catalogLoading.onScroll);
    _sections.catalogLoading.loadSettings();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
      // Set up timeout - only when DEEP-LINKED into a specific folder
      // (initialFolderId). Browsing from the Cloud hub has no target, so the
      // root is the resting state — no spurious auto-close.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            widget.initialFolderId != null &&
            _nav.currentFolderId == null) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open folder. Please try again.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      });
    } else {
      MainPageBridge.registerTabBackHandler(
        'pikpak',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 6 = PikPak)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        6,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void dispose() {
    // Unregister back navigation handler
    if (widget.isPushedRoute) {
      MainPageBridge.popRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
    } else {
      MainPageBridge.unregisterTabBackHandler('pikpak');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          6,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.scrollController.dispose();
    _link.linkController.dispose();
    _focus.refreshButtonFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _focus.retryButtonFocusNode.dispose();
    _focus.settingsButtonFocusNode.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.addLinkButtonFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _search.searchController.dispose();
    _search.searchFocusNode.dispose();
    _search.searchButtonFocusNode.dispose();
    _search.searchClearFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _playFile(Map<String, dynamic> fileData) async {
    try {
      // Check if it's a folder
      final kind = fileData['kind'];
      if (kind == 'drive#folder') {
        _sections.feedback.showSnackBar(
          'Cannot play folders. Please select a video file.',
          isError: true,
        );
        return;
      }

      // Check if it's a video
      final mimeType = fileData['mime_type'] ?? '';
      if (!mimeType.startsWith('video/')) {
        _sections.feedback.showSnackBar(
          'Only video files can be played',
          isError: true,
        );
        return;
      }

      // CRITICAL FIX: Fetch fresh file details with download URLs
      // listFiles() returns empty web_content_link/medias, so we need to call
      // getFileDetails() with usage=FETCH to get populated download URLs
      final fileId = fileData['id'];

      // Show loading indicator
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            const Center(child: CircularProgressIndicator()),
      );

      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } finally {
        // Close loading indicator
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }

      // Extract streaming URL from fresh data
      final streamingUrl = PikPakApiService.instance.getStreamingUrl(
        freshFileData,
      );

      if (streamingUrl == null || streamingUrl.isEmpty) {
        _sections.feedback.showSnackBar(
          'No streaming URL available for this file',
          isError: true,
        );
        return;
      }

      // Links ready - play the video
      if (!mounted) return;

      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: streamingUrl,
          title: freshFileData['name'] ?? 'Video',
        ),
      );
    } catch (e) {
      print('Error playing file: $e');
      _sections.feedback.showSnackBar(
        'Failed to play video: $e',
        isError: true,
      );
    }
  }

  /// Download a single file
  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final fileId = file['id'] as String?;
    final fileName = file['name'] ?? 'download';

    if (fileId == null) {
      _sections.feedback.showSnackBar('Invalid file ID', isError: true);
      return;
    }

    // Check if it's a folder
    final kind = file['kind'];
    if (kind == 'drive#folder') {
      _sections.feedback.showSnackBar(
        'Cannot download folders directly. Use Download button on folder.',
        isError: true,
      );
      return;
    }

    try {
      // Show loading indicator
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Preparing download...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );

      // Get fresh file details with download URLs
      Map<String, dynamic> freshFileData;
      try {
        freshFileData = await PikPakApiService.instance.getFileDetails(fileId);
      } catch (e) {
        // Close loading indicator
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        _sections.feedback.showSnackBar(
          'Failed to get download URL: $e',
          isError: true,
        );
        return;
      }

      // Extract download URL (use web_content_link for all files)
      final downloadUrl = freshFileData['web_content_link'] as String?;

      // Close loading indicator
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        _sections.feedback.showSnackBar(
          'No download URL available for this file',
          isError: true,
        );
        return;
      }

      // Prepare metadata for download service
      final meta = jsonEncode({
        'pikpakDownload': true,
        'pikpakFileId': fileId,
        'pikpakFileName': fileName,
      });

      // Enqueue download
      await DownloadService.instance.enqueueDownload(
        credentialKey: 'pikpak_email',
        url: downloadUrl,
        fileName: fileName,
        meta: meta,
        context: mounted ? context : null,
      );

      _sections.feedback.showSnackBar(
        'Download queued: $fileName',
        isError: false,
      );
    } catch (e) {
      print('Error downloading file: $e');
      // Close loading indicator if still open
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showSnackBar('Failed to download: $e', isError: true);
    }
  }

  /// Download all files in a folder with file selection dialog
  /// Works for both root folders and subfolders
  /// When downloading a subfolder, only shows that subfolder's contents (not parent structure)
  Future<void> _downloadFolder(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _sections.feedback.showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning folder for files...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files WITH path tracking
      // This ensures the dialog shows folder structure starting from this folder
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true, // Enable path tracking for folder structure
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter out folders, keep only files
      final filesOnly = allFiles.where((file) {
        final kind = file['kind'] ?? '';
        return kind != 'drive#folder';
      }).toList();

      if (filesOnly.isEmpty) {
        _sections.feedback.showSnackBar(
          'This folder doesn\'t contain any files',
          isError: true,
        );
        return;
      }

      // Show file selection dialog
      await showDialog(
        context: context,
        builder: (context) => FileSelectionDialog(
          files: filesOnly,
          torrentName: folderName,
          onDownload: (selectedFiles) {
            _downloadSelectedPikPakFiles(selectedFiles, folderName);
          },
        ),
      );
    } catch (e) {
      print('Error downloading folder: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showSnackBar(
        'Failed to scan folder: $e',
        isError: true,
      );
    }
  }

  /// Download selected PikPak files from the file selection dialog
  /// Handles error reporting and uses folder name for download organization
  Future<void> _downloadSelectedPikPakFiles(
    List<Map<String, dynamic>> selectedFiles,
    String folderName,
  ) async {
    if (selectedFiles.isEmpty) {
      _sections.feedback.showSnackBar('No files selected', isError: true);
      return;
    }

    int successCount = 0;
    int failCount = 0;

    // Show progress indicator
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Queuing ${selectedFiles.length} file${selectedFiles.length == 1 ? '' : 's'}...',
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      for (final file in selectedFiles) {
        try {
          final fileId = file['id'] as String?;
          // Use _fullPath if available (from path tracking), otherwise use original name
          final fileName =
              (file['_fullPath'] as String?) ?? file['name'] ?? 'download';

          if (fileId == null) {
            failCount++;
            continue;
          }

          // Get fresh file details with download URLs
          final freshFileData = await PikPakApiService.instance.getFileDetails(
            fileId,
          );
          final downloadUrl = freshFileData['web_content_link'] as String?;

          if (downloadUrl == null || downloadUrl.isEmpty) {
            failCount++;
            continue;
          }

          // Prepare metadata for download service
          final meta = jsonEncode({
            'pikpakDownload': true,
            'pikpakFileId': fileId,
            'pikpakFileName': fileName,
          });

          // Enqueue download with folder name for organization
          await DownloadService.instance.enqueueDownload(
            credentialKey: 'pikpak_email',
            url: downloadUrl,
            fileName: fileName,
            meta: meta,
            torrentName: folderName, // Use folder name for organization
            context: mounted ? context : null,
          );

          successCount++;
        } catch (e) {
          print('Error queuing file for download: $e');
          failCount++;
        }
      }
    } finally {
      // Close progress dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) return;

    // Show result
    if (successCount > 0 && failCount == 0) {
      _sections.feedback.showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'} for download',
        isError: false,
      );
    } else if (successCount > 0 && failCount > 0) {
      _sections.feedback.showSnackBar(
        'Queued $successCount file${successCount == 1 ? '' : 's'}, $failCount failed',
        isError: true,
      );
    } else {
      _sections.feedback.showSnackBar(
        'Failed to queue any files for download',
        isError: true,
      );
    }
  }

  // --- Multi-select helpers ---

  // ========== VIEW MODE TRANSFORMATION METHODS ==========

  /// Build the view mode dropdown (shown below AppBar when inside folders)
  Widget _buildViewModeDropdown() {
    final theme = Theme.of(context);
    final mode = _sections.viewModes.getCurrentViewMode();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Focus(
        skipTraversal: true,
        onKeyEvent: (node, event) {
          // Navigate to back button on up arrow
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _focus.backButtonFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: DropdownButtonFormField<FolderViewMode>(
          focusNode: _focus.viewModeDropdownFocusNode,
          autofocus: true,
          isExpanded: true,
          value: mode,
          decoration: InputDecoration(
            labelText: 'View Mode',
            prefixIcon: Icon(
              mode == FolderViewMode.raw
                  ? Icons.view_list
                  : mode == FolderViewMode.sortedAZ
                  ? Icons.sort_by_alpha
                  : Icons.video_library,
              color: theme.colorScheme.primary,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.3,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
          items: const [
            DropdownMenuItem(value: FolderViewMode.raw, child: Text('Raw')),
            DropdownMenuItem(
              value: FolderViewMode.sortedAZ,
              child: Text('Sort (A-Z)'),
            ),
          ],
          onChanged: (value) {
            if (value != null) _sections.viewModes.setViewMode(value);
          },
        ),
      ),
    );
  }

  // ============ Search Methods ============

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
              focusNode: _search.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _search.searchFocusNode.unfocus(),
              onDownArrow: () => _search.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _search.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search files...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _sections.searchActions.performSearch,
              onSubmitted: (_) => _search.searchFocusNode.unfocus(),
            ),
          ),
          // Clear button - separate focusable widget for D-pad navigation
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _search.searchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;

                  // Select/Enter: clear search
                  if (isActivateKey(key)) {
                    setState(() {
                      _search.searchController.clear();
                      _search.searchResults.clear();
                    });
                    _search.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  // Arrow Left: go back to TextField
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _search.searchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }

                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return Container(
                      decoration: BoxDecoration(
                        color: app.fade(app.core.tx, 0.06),
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
                          _search.searchFocusNode.requestFocus();
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

  /// Build search results list
  Widget _buildSearchResults() {
    if (_search.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search files',
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
  Widget _buildSearchResultCard(PikPakSearchResult result) {
    final file = result.file;
    final name = file['name'] as String? ?? 'Unknown';
    final size = file['size'] as String? ?? '0';

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: CloudRowKind.video,
        title: name,
        meta: result.path.isEmpty
            ? Formatters.formatFileSize(int.tryParse(size) ?? 0)
            : result.path,
        onTap: () => _sections.sourceBinding.selectBoundSource(file),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _playFile(file),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.play_circle_outline,
                  color: Colors.blue,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (result.path.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          result.path,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      Text(
                        Formatters.formatFileSize(int.tryParse(size) ?? 0),
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Pushed from the Cloud hub to browse (no folder target) — the root has no
  /// folder-up Back, so the AppBar offers a Back-to-hub instead.
  bool get _isBrowsePush =>
      widget.isPushedRoute && widget.initialFolderId == null;

  @override
  Widget build(BuildContext context) {
    // When DEEP-LINKED into a specific folder (pushed WITH a target) and still
    // at root, show the loading state. Browsing from the Cloud hub has no target
    // (and non-restricted accounts stay at a null root folder), so don't gate the
    // real content behind a spinner.
    if (widget.isPushedRoute &&
        widget.initialFolderId != null &&
        _nav.currentFolderId == null) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening folder...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading folder contents...'),
            ],
          ),
        ),
      );
    }

    if (!_catalog.pikpakEnabled) {
      return _buildNotEnabled();
    }

    if (_catalog.initialLoad && _catalog.isLoading) {
      return const CloudScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_catalog.errorMessage.isNotEmpty) {
      return _buildError();
    }

    // Check if we should show the view mode dropdown
    // Only show when navigated at least one level deep (inside a folder)
    final showViewModeDropdown =
        _nav.navigationStack.isNotEmpty || _view.isInVirtualFolder;
    final currentMode = _sections.viewModes.getCurrentViewMode();
    final showSearch =
        showViewModeDropdown &&
        currentMode != FolderViewMode.seriesArrange &&
        !_view.isInVirtualFolder;

    final bool isCompactActions = MediaQuery.sizeOf(context).width < 500;
    final double actionIconSize = isCompactActions ? 20 : 24;
    final EdgeInsets actionIconPadding = isCompactActions
        ? const EdgeInsets.all(6)
        : const EdgeInsets.all(8);
    final BoxConstraints actionIconConstraints = isCompactActions
        ? const BoxConstraints(minWidth: 36, minHeight: 36)
        : const BoxConstraints(minWidth: 48, minHeight: 48);

    // Back navigation is handled via MainPageBridge.handleBackNavigation
    return CloudScaffold(
      appBar: AppBar(
        leading:
            (_nav.currentFolderId != null && !_nav.isAtRestrictedRoot) ||
                _view.isInVirtualFolder
            ? Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                      MainPageBridge.focusTvSidebar != null) {
                    MainPageBridge.focusTvSidebar!();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: IconButton(
                  focusNode: _focus.backButtonFocusNode,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () =>
                      _sections.backNavigation.handleBackNavigation(),
                  tooltip: 'Back',
                ),
              )
            // At the browse root (opened from the Cloud hub with no folder
            // target) there's no folder-up back — offer a Back-to-hub instead.
            : (_isBrowsePush
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _view.isInVirtualFolder
                  ? _view.virtualFolderName ?? 'Virtual Folder'
                  : widget.selectSourceMode
                  ? 'Select PikPak Source'
                  : _nav.currentFolderName,
            ),
            if (_nav.restrictedFolderId != null && !_view.isInVirtualFolder)
              const Text(
                'Restricted Access',
                style: TextStyle(fontSize: 12, color: Colors.amber),
              ),
          ],
        ),
        actions: [
          // Keep the button mounted while a navigation fetch runs (_files is
          // cleared then) so the AppBar doesn't flicker and TV focus parked
          // on it isn't dropped.
          if ((_catalog.files.isNotEmpty || _catalog.isLoading) &&
              !_view.isInVirtualFolder &&
              !widget.selectSourceMode)
            IconButton(
              icon: Icon(
                _selection.isSelectionMode
                    ? Icons.close
                    : Icons.checklist_outlined,
              ),
              onPressed: _sections.selectionActions.toggleSelectionMode,
              tooltip: _selection.isSelectionMode
                  ? 'Exit selection'
                  : 'Select items',
              color: _selection.isSelectionMode
                  ? Theme.of(context).colorScheme.error
                  : null,
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (showSearch)
            IconButton(
              focusNode: _search.searchButtonFocusNode,
              icon: Icon(_search.isSearchActive ? Icons.close : Icons.search),
              onPressed: _sections.searchActions.toggleSearch,
              tooltip: _search.isSearchActive ? 'Close search' : 'Search files',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          if (!widget.selectSourceMode)
            IconButton(
              focusNode: _focus.addLinkButtonFocusNode,
              icon: const Icon(Icons.add_link),
              onPressed: _catalog.isLoading ? null : _showAddLinkDialog,
              tooltip: 'Add Link',
              iconSize: actionIconSize,
              padding: actionIconPadding,
              constraints: actionIconConstraints,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            focusNode: _focus.refreshButtonFocusNode,
            icon: const Icon(Icons.refresh),
            onPressed: _catalog.isLoading
                ? null
                : _sections.feedback.refreshFiles,
            tooltip: 'Refresh',
            iconSize: actionIconSize,
            padding: actionIconPadding,
            constraints: actionIconConstraints,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_selection.isSelectionMode) _buildSelectionBar(),
          // View mode dropdown (only shown when inside folders)
          if (showViewModeDropdown && !_view.isInVirtualFolder)
            _buildViewModeDropdown(),
          if (_search.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: _search.isSearchActive
                ? _buildSearchResults()
                : FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: RefreshIndicator(
                      onRefresh: _sections.feedback.refreshFiles,
                      // Folder navigation clears _files, so a fetch with
                      // nothing to show gets the shimmer skeleton;
                      // pull-to-refresh keeps its items and skips it.
                      child: _catalog.isLoading && _catalog.files.isEmpty
                          ? const CloudRowSkeletonList()
                          : _catalog.files.isEmpty
                          ? _buildEmpty()
                          : _buildFileList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotEnabled() {
    final app = AppThemeScope.of(context);
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 24),
                Text(
                  'PikPak Not Configured',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  'Configure your PikPak account in Settings to view and manage files.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.settingsButtonFocusNode,
                  autofocus: true,
                  onPressed: () {
                    // TODO: Navigate to settings
                    _sections.feedback.showSnackBar(
                      'Open Settings > PikPak to configure',
                      isError: false,
                    );
                  },
                  icon: const Icon(Icons.settings),
                  label: const Text('Go to Settings'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final app = AppThemeScope.of(context);
    return CloudScaffold(
      appBar: AppBar(title: const Text('PikPak Files')),
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Failed to Load Files',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(
                  _catalog.errorMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  focusNode: _focus.retryButtonFocusNode,
                  autofocus: true,
                  onPressed: _sections.feedback.refreshFiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom().copyWith(
                    side: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return BorderSide(color: app.core.tx, width: 3);
                      }
                      return null;
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final isInFolder = _nav.currentFolderId != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 24),
            Text(
              isInFolder ? 'Folder is Empty' : 'No Files Yet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Text(
              isInFolder
                  ? 'This folder doesn\'t contain any files or subfolders.'
                  : 'Add torrents from the search screen to see them here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectionBar() {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    final count = _selection.selectedFileIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: app.shape.br(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: _sections.selectionActions.toggleSelectAll,
            child: Text(
              _sections.selectionActions.isAllSelected
                  ? 'Deselect All'
                  : 'Select All',
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            focusNode: _focus.deleteButtonFocusNode,
            onPressed: count > 0
                ? _sections.deleteActions.handleDeleteSelected
                : null,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
            style:
                FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.error,
                  disabledBackgroundColor: theme.colorScheme.error.withValues(
                    alpha: 0.3,
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.focused)) {
                      return BorderSide(color: app.core.tx, width: 3);
                    }
                    return null;
                  }),
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileList() {
    // Add 1 to item count for loading indicator when loading more
    final itemCount =
        _catalog.files.length +
        (_catalog.isLoadingMore || _catalog.hasMore ? 1 : 0);

    return ListView.builder(
      controller: _focus.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Show loading indicator at the end
        if (index >= _catalog.files.length) {
          return _buildLoadingIndicator();
        }
        final file = _catalog.files[index];
        return KeyedSubtree(
          key: ValueKey(file['id'] ?? index),
          child: _buildFileCard(file, index),
        );
      },
    );
  }

  Widget _buildLoadingIndicator() {
    if (_catalog.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // Show a subtle hint that more can be loaded
    if (_catalog.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'Scroll for more',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildFileCard(Map<String, dynamic> file, int index) {
    final name = file['name']?.toString() ?? 'Unknown';
    final size = file['size'];
    final mimeType = file['mime_type'] ?? '';
    final kind = file['kind'] ?? '';
    final phase = file['phase'] ?? '';
    final createdTime = file['created_time'] ?? '';
    final fileId = file['id'] as String?;

    final isFolder = kind == 'drive#folder';
    final isVirtualFolder = kind == 'virtual#season'; // Virtual Season folder
    final isVideo =
        mimeType.startsWith('video/') || FileUtils.isVideoFile(name);
    final isComplete = phase == 'PHASE_TYPE_COMPLETE';

    final date = _formatDate(createdTime);
    final metaParts = <String>[
      if (size != null)
        Formatters.formatFileSize(int.tryParse(size.toString()) ?? 0),
      if (date.isNotEmpty) date,
    ];

    if (widget.selectSourceMode) {
      final selectable =
          !isVirtualFolder && (isFolder || (isVideo && isComplete));
      return CloudFileRow(
        kind: isVirtualFolder
            ? CloudRowKind.season
            : isFolder
            ? CloudRowKind.folder
            : isVideo
            ? CloudRowKind.video
            : CloudRowKind.file,
        title: name,
        meta: metaParts.isEmpty ? null : metaParts.join(' · '),
        extra: (!isComplete && !isVirtualFolder)
            ? Text(
                'Still downloading',
                style: TextStyle(color: Colors.orange.shade700, fontSize: 12.5),
              )
            : null,
        onTap: selectable
            ? () => _sections.sourceBinding.selectBoundSource(file)
            : null,
        actions: isFolder
            ? [
                CloudRowAction(
                  icon: Icons.folder_open_rounded,
                  label: 'Browse folder',
                  onSelected: () => _sections.folderNavigation
                      .navigateIntoFolder(file['id'], name),
                ),
              ]
            : const [],
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old pills + ⋮ menu offered.
    // Virtual Season folders keep their special shape: Open only (via tap),
    // no menu, not selectable.
    final actions = <CloudRowAction>[
      if (!isVirtualFolder) ...[
        if (isFolder || (isVideo && isComplete))
          CloudRowAction(
            icon: Icons.play_arrow_rounded,
            label: 'Play',
            showInStrip: true,
            onSelected: () {
              if (isFolder) {
                _playFolder(file);
              } else {
                _playFile(file);
              }
            },
          ),
        CloudRowAction(
          icon: Icons.download,
          label: 'Download',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _downloadFolder(file);
            } else {
              _downloadFile(file);
            }
          },
        ),
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () => _handleAddToPlaylist(file),
        ),
        CloudRowAction(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onSelected: () => _sections.deleteActions.showDeleteDialog(file),
        ),
      ],
    ];

    return CloudFileRow(
      kind: isVirtualFolder
          ? CloudRowKind.season
          : isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: name,
      meta: metaParts.isEmpty ? null : metaParts.join(' · '),
      // Virtual season rows are client-synthesized and carry no 'phase', so
      // without the !isVirtualFolder gate they'd show a perpetual spinner.
      extra: (!isComplete && !isVirtualFolder && !_selection.isSelectionMode)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  'Downloading...',
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            )
          : null,
      onTap: isVirtualFolder
          ? () => _sections.folderNavigation.navigateIntoVirtualFolder(file)
          : isFolder
          ? () =>
                _sections.folderNavigation.navigateIntoFolder(file['id'], name)
          : (isVideo && isComplete)
          ? () => _playFile(file)
          : null,
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: fileId != null && _selection.selectedFileIds.contains(fileId),
      selectable: fileId != null && !isVirtualFolder,
      onToggleSelected: fileId != null
          ? () => _sections.selectionActions.toggleFileSelection(fileId)
          : null,
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        if (difference.inHours == 0) {
          return '${difference.inMinutes}m ago';
        }
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${date.month}/${date.day}/${date.year}';
      }
    } catch (e) {
      return '';
    }
  }

  /// Play all videos in a folder (recursively scans subfolders)
  Future<void> _playFolder(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _sections.feedback.showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning folder for videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files (includePaths for auxiliary folder detection)
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_catalog.showVideosOnly) {
        // Already filtered for videos above
      }

      if (_catalog.ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _sections.feedback.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }

      // Same logic the retired TorrentSearchScreen used
      await _playPikPakVideos(videoFiles, folderName);
    } catch (e) {
      print('Error playing folder: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showSnackBar(
        'Failed to scan folder: $e',
        isError: true,
      );
    }
  }

  /// Play PikPak videos (single or playlist) - mirrors the retired TorrentSearchScreen
  Future<void> _playPikPakVideos(
    List<Map<String, dynamic>> videoFiles,
    String collectionName,
  ) async {
    if (videoFiles.isEmpty) return;

    final pikpak = PikPakApiService.instance;

    // Single video - play with playlist entry for consistent resume key
    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final fullData = await pikpak.getFileDetails(file['id']);
        final url = pikpak.getStreamingUrl(fullData);
        if (url != null && mounted) {
          final sizeBytes = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
          final title = file['name'] ?? collectionName;
          await VideoPlayerLauncher.push(
            context,
            VideoPlayerLaunchArgs(
              videoUrl: url,
              title: title,
              subtitle: Formatters.formatFileSize(sizeBytes),
              playlist: [
                PlaylistEntry(
                  url: url,
                  title: title,
                  relativePath: file['_fullPath'] as String?,
                  provider: 'pikpak',
                  pikpakFileId: file['id'],
                  sizeBytes: sizeBytes,
                ),
              ],
              startIndex: 0,
            ),
          );
        }
      } catch (e) {
        _sections.feedback.showSnackBar(
          'Failed to play: ${e.toString()}',
          isError: true,
        );
      }
      return;
    }

    // Multiple videos - build playlist
    final entries = <PikPakPlaylistItem>[];
    for (int i = 0; i < videoFiles.length; i++) {
      final file = videoFiles[i];
      final displayName = pikpakDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      entries.add(
        PikPakPlaylistItem(
          file: file,
          originalIndex: i,
          seriesInfo: info,
          displayName: displayName,
        ),
      );
    }

    // Detect if it's a series collection
    final filenames = entries.map((e) => e.displayName).toList();
    final bool isSeriesCollection =
        entries.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    // Sort entries
    final sortedEntries = [...entries];
    if (isSeriesCollection) {
      sortedEntries.sort((a, b) {
        final aInfo = a.seriesInfo;
        final bInfo = b.seriesInfo;
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;
        final episodeCompare = (aInfo.episode ?? 0).compareTo(
          bInfo.episode ?? 0,
        );
        if (episodeCompare != 0) return episodeCompare;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    } else {
      sortedEntries.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    }

    // Find first episode to start from
    final seriesInfos = sortedEntries.map((e) => e.seriesInfo).toList();
    int startIndex = isSeriesCollection
        ? findFirstEpisodeIndex(seriesInfos)
        : 0;
    if (startIndex < 0 || startIndex >= sortedEntries.length) {
      startIndex = 0;
    }

    // Resolve only the first video URL (lazy loading for rest)
    String initialUrl = '';
    try {
      final firstFile = sortedEntries[startIndex].file;
      final fullData = await pikpak.getFileDetails(firstFile['id']);
      initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
    } catch (e) {
      _sections.feedback.showSnackBar(
        'Failed to prepare stream: ${e.toString()}',
        isError: true,
      );
      return;
    }

    if (initialUrl.isEmpty) {
      _sections.feedback.showSnackBar(
        'Could not get streaming URL',
        isError: true,
      );
      return;
    }

    // Build playlist entries
    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      final seriesInfo = entry.seriesInfo;
      final episodeLabel = formatPikPakPlaylistTitle(
        info: seriesInfo,
        fallback: entry.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = combineSeriesAndEpisodeTitle(
        seriesTitle: seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: entry.displayName,
      );
      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: entry.file['_fullPath'] as String?,
          provider: 'pikpak',
          pikpakFileId: entry.file['id'],
          sizeBytes: int.tryParse(entry.file['size']?.toString() ?? '0'),
        ),
      );
    }

    // Calculate subtitle
    final totalBytes = sortedEntries.fold<int>(
      0,
      (sum, e) => sum + (int.tryParse(e.file['size']?.toString() ?? '0') ?? 0),
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    if (!mounted) return;
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: collectionName,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
      ),
    );
  }

  /// Handle adding a file or folder to playlist
  Future<void> _handleAddToPlaylist(Map<String, dynamic> file) async {
    final kind = file['kind'] ?? '';
    final isFolder = kind == 'drive#folder';

    if (isFolder) {
      await _addFolderToPlaylist(file);
    } else {
      await _addSingleFileToPlaylist(file);
    }
  }

  /// Add a single video file to playlist
  Future<void> _addSingleFileToPlaylist(Map<String, dynamic> file) async {
    final mimeType = file['mime_type'] ?? '';
    final isVideo = mimeType.startsWith('video/');

    if (!isVideo) {
      _sections.feedback.showSnackBar(
        'Only video files can be added to playlist',
        isError: true,
      );
      return;
    }

    final added = await PlaylistStorage.addPlaylistItemRaw({
      'provider': 'pikpak',
      'title': FileUtils.cleanPlaylistTitle(file['name'] ?? 'Video'),
      'kind': 'single',
      'pikpakFileId': file['id'],
      // Store full metadata for instant playback
      'pikpakFile': {
        'id': file['id'],
        'name': file['name'],
        'size': file['size'],
        'mime_type': file['mime_type'],
      },
      'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
    });

    _sections.feedback.showSnackBar(
      added ? 'Added to playlist' : 'Already in playlist',
      isError: !added,
    );
  }

  /// Add all videos in a folder to playlist (recursively scans subfolders)
  Future<void> _addFolderToPlaylist(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _sections.feedback.showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Scanning folder for videos...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      // Recursively scan folder for all files (includePaths for auxiliary folder detection)
      final allFiles = await PikPakApiService.instance.listFilesRecursive(
        folderId: folderId,
        includePaths: true,
      );

      // Close loading dialog
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (!mounted) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_catalog.ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _sections.feedback.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }

      // Add to playlist
      if (videoFiles.length == 1) {
        // Single video file - store full metadata for instant playback
        final file = videoFiles.first;
        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(file['name'] ?? folderName),
          'kind': 'single',
          'pikpakFileId': file['id'],
          'pikpakFile': {
            'id': file['id'],
            'name': file['name'],
            'size': file['size'],
            'mime_type': file['mime_type'],
          },
          'sizeBytes': int.tryParse(file['size']?.toString() ?? '0'),
        });
        _sections.feedback.showSnackBar(
          added ? 'Added to playlist' : 'Already in playlist',
          isError: !added,
        );
      } else {
        // Multiple videos - save as collection with full metadata for instant playback
        // Store both pikpakFiles (new format) and pikpakFileIds (for dedupe compatibility)
        final fileIds = videoFiles.map((f) => f['id'] as String).toList();
        final filesMetadata = videoFiles
            .map(
              (f) => {
                'id': f['id'],
                'name': f['name'],
                'size': f['size'],
                'mime_type': f['mime_type'],
              },
            )
            .toList();

        final added = await PlaylistStorage.addPlaylistItemRaw({
          'provider': 'pikpak',
          'title': FileUtils.cleanPlaylistTitle(folderName),
          'kind': 'collection',
          'pikpakFileId': folderId, // Store the folder ID for folder structure
          'pikpakFiles':
              filesMetadata, // NEW: Full metadata for instant playback
          'pikpakFileIds':
              fileIds, // KEEP: For backward compatibility and deduplication
          'count': videoFiles.length,
        });
        _sections.feedback.showSnackBar(
          added
              ? 'Added ${videoFiles.length} videos to playlist'
              : 'Already in playlist',
          isError: !added,
        );
      }
    } catch (e) {
      print('Error adding folder to playlist: $e');
      if (mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();
      }
      _sections.feedback.showSnackBar(
        'Failed to scan folder: $e',
        isError: true,
      );
    }
  }

  // ============================================================================
  // Add Link Dialog
  // ============================================================================

  Future<void> _showAddLinkDialog() async {
    // Auto-paste link from clipboard if available
    await _autoPasteLink();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Add Link',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter a link to download:',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  node.nextFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _link.linkController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'magnet:?xt=... or https://...',
                  hintStyle: TextStyle(color: Colors.grey[600]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF475569)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF475569)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFFFAA00)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                maxLines: 3,
                minLines: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Supported: Magnet links, HTTP/HTTPS URLs',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    _link.linkController.clear();
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Color(0xFF475569)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _link.isAddingLink ? null : _addLink,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: const Color(0xFFFFAA00),
                  ),
                  child: _link.isAddingLink
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Add',
                          style: TextStyle(color: Colors.black),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _autoPasteLink() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData?.text != null) {
        final text = clipboardData!.text!.trim();
        // Check if it looks like a supported link
        if (text.startsWith('http://') ||
            text.startsWith('https://') ||
            text.startsWith('magnet:')) {
          _link.linkController.text = text;
        }
      }
    } catch (e) {
      debugPrint('Failed to read clipboard: $e');
    }
  }

  Future<void> _addLink() async {
    final link = _link.linkController.text.trim();
    if (link.isEmpty) {
      _sections.feedback.showSnackBar('Please enter a link', isError: true);
      return;
    }

    if (!isValidPikPakLink(link)) {
      _sections.feedback.showSnackBar(
        'Please enter a valid URL or magnet link',
        isError: true,
      );
      return;
    }

    Navigator.of(context).pop(); // Close the dialog

    setState(() {
      _link.isAddingLink = true;
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFFFFAA00)),
            const SizedBox(height: 16),
            const Text('Adding to PikPak...'),
            const SizedBox(height: 8),
            Text(
              link.length > 50 ? '${link.substring(0, 50)}...' : link,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    try {
      final pikpak = PikPakApiService.instance;

      // Use current folder if browsing, otherwise use restricted folder or root
      final parentFolderId = _nav.currentFolderId ?? _nav.restrictedFolderId;

      final result = await pikpak.addOfflineDownload(
        link,
        parentFolderId: parentFolderId,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      // Extract file name from response
      String? fileName;
      if (result['file'] != null) {
        fileName = result['file']['name'];
      } else if (result['task'] != null) {
        fileName = result['task']['name'];
      }

      _sections.feedback.showSnackBar(
        'Added to PikPak${fileName != null ? ': $fileName' : ''}',
        isError: false,
      );

      // Clear the controller and refresh
      _link.linkController.clear();
      _sections.feedback.refreshFiles();
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // Close loading dialog

      _sections.feedback.showSnackBar(
        'Failed to add: ${e.toString()}',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _link.isAddingLink = false;
        });
      }
    }
  }
}

/// Original-code characterization seam: fresh state and real action tear-offs.
@visibleForTesting
Map<String, Object?> pikpakFilesTestAccess(State<PikPakFilesScreen> state) {
  final s = state as _PikPakFilesScreenState;
  return {
    'scrollController': s._focus.scrollController,
    'files': s._catalog.files,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'isLoading': s._catalog.isLoading,
    'initialLoad': s._catalog.initialLoad,
    'errorMessage': s._catalog.errorMessage,
    'pikpakEnabled': s._catalog.pikpakEnabled,
    'showVideosOnly': s._catalog.showVideosOnly,
    'ignoreSmallVideos': s._catalog.ignoreSmallVideos,
    'linkController': s._link.linkController,
    'isAddingLink': s._link.isAddingLink,
    'nextPageToken': s._catalog.nextPageToken,
    'hasMore': s._catalog.hasMore,
    'isLoadingMore': s._catalog.isLoadingMore,
    'currentFolderId': s._nav.currentFolderId,
    'currentFolderName': s._nav.currentFolderName,
    'navigationStack': s._nav.navigationStack,
    'restrictedFolderId': s._nav.restrictedFolderId,
    'restrictedFolderName': s._nav.restrictedFolderName,
    'isAtRestrictedRoot': s._nav.isAtRestrictedRoot,
    'folderViewModes': s._view.folderViewModes,
    'isInVirtualFolder': s._view.isInVirtualFolder,
    'virtualFolderName': s._view.virtualFolderName,
    'virtualFolderFiles': s._view.virtualFolderFiles,
    'recursiveFileCache': s._view.recursiveFileCache,
    'refreshButtonFocusNode': s._focus.refreshButtonFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'retryButtonFocusNode': s._focus.retryButtonFocusNode,
    'settingsButtonFocusNode': s._focus.settingsButtonFocusNode,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'addLinkButtonFocusNode': s._focus.addLinkButtonFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedFileIds': s._selection.selectedFileIds,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'isSearchActive': s._search.isSearchActive,
    'searchController': s._search.searchController,
    'searchFocusNode': s._search.searchFocusNode,
    'searchButtonFocusNode': s._search.searchButtonFocusNode,
    'searchClearFocusNode': s._search.searchClearFocusNode,
    'searchResults': s._search.searchResults,
    'selectableFileCount': s._sections.selectionActions.selectableFileCount,
    'isAllSelected': s._sections.selectionActions.isAllSelected,
    'selectBoundSource': s._sections.sourceBinding.selectBoundSource,
    'onScroll': s._sections.catalogLoading.onScroll,
    'resetListScroll': s._sections.catalogLoading.resetListScroll,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'loadSettings': s._sections.catalogLoading.loadSettings,
    'handleRestrictedFolderDeleted':
        s._sections.catalogLoading.handleRestrictedFolderDeleted,
    'loadFiles': s._sections.catalogLoading.loadFiles,
    'loadMoreFiles': s._sections.catalogLoading.loadMoreFiles,
    'filterFiles': s._sections.folderNavigation.filterFiles,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'navigateUpWithVirtual': s._sections.folderNavigation.navigateUpWithVirtual,
    'navigateIntoVirtualFolder':
        s._sections.folderNavigation.navigateIntoVirtualFolder,
    'playFile': s._playFile,
    'downloadFile': s._downloadFile,
    'downloadFolder': s._downloadFolder,
    'downloadSelectedPikPakFiles': s._downloadSelectedPikPakFiles,
    'refreshFiles': s._sections.feedback.refreshFiles,
    'showDeleteDialog': s._sections.deleteActions.showDeleteDialog,
    'deleteFile': s._sections.deleteActions.deleteFile,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleFileSelection': s._sections.selectionActions.toggleFileSelection,
    'toggleSelectAll': s._sections.selectionActions.toggleSelectAll,
    'handleDeleteSelected': s._sections.deleteActions.handleDeleteSelected,
    'executeDeleteSelected': s._sections.deleteActions.executeDeleteSelected,
    'showSnackBar': s._sections.feedback.showSnackBar,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
    'setViewMode': s._sections.viewModes.setViewMode,
    'showFallbackToSorted': s._sections.viewModes.showFallbackToSorted,
    'applyViewMode': s._sections.viewModes.applyViewMode,
    'applySortedView': applySortedView,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySeriesArrangeView': s._sections.viewModes.applySeriesArrangeView,
    'toggleSearch': s._sections.searchActions.toggleSearch,
    'performSearch': s._sections.searchActions.performSearch,
    'isBrowsePush': s._isBrowsePush,
    'formatDate': s._formatDate,
    'playFolder': s._playFolder,
    'playPikPakVideos': s._playPikPakVideos,
    'handleAddToPlaylist': s._handleAddToPlaylist,
    'addSingleFileToPlaylist': s._addSingleFileToPlaylist,
    'addFolderToPlaylist': s._addFolderToPlaylist,
    'pikpakDisplayName': pikpakDisplayName,
    'formatPikPakPlaylistTitle': formatPikPakPlaylistTitle,
    'combineSeriesAndEpisodeTitle': combineSeriesAndEpisodeTitle,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'showAddLinkDialog': s._showAddLinkDialog,
    'autoPasteLink': s._autoPasteLink,
    'isValidPikPakLink': isValidPikPakLink,
    'addLink': s._addLink,
    'rawMode': FolderViewMode.raw,
    'sortedMode': FolderViewMode.sortedAZ,
    'seriesMode': FolderViewMode.seriesArrange,
  };
}
