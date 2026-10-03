import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_navigation_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_add_input_state.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_download_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playlist_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_link_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_delete_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_back_navigation.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_loading.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_zip_download.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_file_downloads.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_link_playlist_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_delete_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_bulk_delete.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_create_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_initial_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_stream_request.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_sheet.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_enqueue.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_zip_download.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_download_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_list_layouts.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_series_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_card.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playlist_links.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_downloads.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_search_result.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_magnet_policy.dart';
import 'package:debrify/features/torbox_downloads/application/torbox_folder_policy.dart';

import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../models/torbox_web_download.dart';
import '../../models/rd_file_node.dart';
import '../../services/analytics_service.dart';
import '../../services/series_source_service.dart';
import '../../services/torbox_service.dart';
import '../../services/main_page_bridge.dart';
import '../../theme/app_theme_scope.dart';
import '../../utils/formatters.dart';
import '../../utils/file_utils.dart';
import '../../utils/torbox_folder_tree_builder.dart';
import '../../widgets/cloud/cloud_file_row.dart';
import '../../widgets/cloud/cloud_row_skeleton.dart';
import '../../widgets/cloud/cloud_segmented_tabs.dart';
import '../../widgets/cloud/cloud_theme.dart';
import '../../widgets/tv_text_field.dart';
import '../../utils/platform_util.dart';
import '../../utils/tv_keys.dart';

class TorboxDownloadsScreen extends StatefulWidget {
  const TorboxDownloadsScreen({
    super.key,
    this.initialTorrentToOpen,
    this.isPushedRoute = false,
    this.initialSearchQuery,
    this.selectSourceMode = false,
    this.onSourceSelected,
  });

  final TorboxTorrent? initialTorrentToOpen;

  /// When true, this screen was pushed as a route (not displayed in a tab).
  /// Back navigation will pop the route instead of switching tabs.
  final bool isPushedRoute;

  /// Pre-populate torrent search with this query on init.
  final String? initialSearchQuery;

  /// When true, torrent cards show "Select" instead of Open/Play/3-dot.
  final bool selectSourceMode;

  /// Called when user selects a torrent in select-source mode.
  final void Function(SeriesSource)? onSourceSelected;

  @override
  State<TorboxDownloadsScreen> createState() => _TorboxDownloadsScreenState();
}

class _TorboxDownloadsScreenState extends State<TorboxDownloadsScreen> {
  final _catalog = TorboxCatalogState();
  final _web = TorboxWebState();
  final _nav = TorboxNavigationState();
  final _view = TorboxViewState();
  final _focus = TorboxFocusState();
  final _folderSearch = TorboxFolderSearchState();
  final _torrentSearch = TorboxTorrentSearchState();
  final _selection = TorboxSelectionState();
  final _addInput = TorboxAddInputState();
  late final _sections = _createSections();

  TorboxSections _createSections() {
    final sections = TorboxSections();
    sections.focusActions = TorboxFocusActions((
      focusState: _focus,
      mounted: () => mounted,
      viewState: _view,
      catalogState: _catalog,
      webState: _web,
    ));
    sections.torrentDownloadAction = TorboxTorrentDownloadAction((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      navigationState: _nav,
      mounted: () => mounted,
      context: () => context,
      downloadSelectedTorboxFiles:
          (List<Map<String, dynamic>> selectedFiles, String folderName) =>
              sections.fileActions.downloadSelectedTorboxFiles(
                selectedFiles,
                folderName,
              ),
    ));
    sections.torrentPlaylistActions = TorboxTorrentPlaylistActions((
      mounted: () => mounted,
      context: () => context,
      torrentSearchState: _torrentSearch,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
    ));
    sections.torrentLinkActions = TorboxTorrentLinkActions((
      showComingSoon: (String action) =>
          sections.magnetActions.showComingSoon(action),
      catalogState: _catalog,
      mounted: () => mounted,
      context: () => context,
    ));
    sections.torrentOptions = TorboxTorrentOptions((
      handleAddToPlaylist: (TorboxTorrent torrent) =>
          sections.torrentPlaylistActions.handleAddToPlaylist(torrent),
      handleAddToDebrifyTv: (TorboxTorrent torrent) =>
          sections.torrentPlaylistActions.handleAddToDebrifyTv(torrent),
      copyTorrentZipLink: (TorboxTorrent torrent) =>
          sections.torrentLinkActions.copyTorrentZipLink(torrent),
      copyTorrentLink: (TorboxTorrent torrent) =>
          sections.torrentLinkActions.copyTorrentLink(torrent),
      confirmDeleteTorrent: (TorboxTorrent torrent) =>
          sections.torrentDeleteActions.confirmDeleteTorrent(torrent),
      context: () => context,
    ));
    sections.torrentPlayback = TorboxTorrentPlayback((
      catalogState: _catalog,
      showComingSoon: (String action) =>
          sections.magnetActions.showComingSoon(action),
      mounted: () => mounted,
      context: () => context,
      requestTorboxStreamUrl:
          ({
            required String apiKey,
            required TorboxTorrent torrent,
            required TorboxFile file,
          }) => sections.streamRequest.requestTorboxStreamUrl(
            apiKey: apiKey,
            torrent: torrent,
            file: file,
          ),
    ));
    sections.torrentDeleteActions = TorboxTorrentDeleteActions((
      catalogState: _catalog,
      showComingSoon: (String action) =>
          sections.magnetActions.showComingSoon(action),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      selectionState: _selection,
    ));
    sections.backNavigation = TorboxBackNavigation((
      context: () => context,
      selectionState: _selection,
      exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
      torrentSearchState: _torrentSearch,
      toggleTorrentSearch: () => _toggleTorrentSearch(),
      folderSearchState: _folderSearch,
      toggleSearch: () => _toggleSearch(),
      isAtRoot: () => _isAtRoot,
      navigationState: _nav,
      navigateUp: () => _navigateUp(),
      selectSourceMode: () => widget.selectSourceMode,
      isPushedRoute: () => widget.isPushedRoute,
      initialTorrentToOpen: () => widget.initialTorrentToOpen,
    ));
    sections.catalogLoading = TorboxCatalogLoading((
      focusState: _focus,
      catalogState: _catalog,
      webState: _web,
      mounted: () => mounted,
      setState: setState,
      submitTorrentSearch: () => _submitTorrentSearch(),
      initialSearchQuery: () => widget.initialSearchQuery,
      torrentSearchState: _torrentSearch,
      focusFirstItemOrFallback: () =>
          sections.focusActions.focusFirstItemOrFallback(),
      maybeTriggerInitialAction: () =>
          sections.initialAction.maybeTriggerInitialAction(),
    ));
    sections.webPlayback = TorboxWebPlayback((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      mounted: () => mounted,
      context: () => context,
    ));
    sections.webOptions = TorboxWebOptions((
      context: () => context,
      buildDownloadOptionCard:
          ({
            required IconData icon,
            required String title,
            required String description,
            required Color color,
            required VoidCallback onTap,
          }) => sections.downloadOptions.buildDownloadOptionCard(
            icon: icon,
            title: title,
            description: description,
            color: color,
            onTap: onTap,
          ),
      downloadWebDownloadFiles: (TorboxWebDownload webDownload) =>
          sections.webFileDownloads.downloadWebDownloadFiles(webDownload),
      enqueueWebDownloadZipDownload:
          ({
            required TorboxWebDownload webDownload,
            required BuildContext sheetContext,
          }) => sections.webZipDownload.enqueueWebDownloadZipDownload(
            webDownload: webDownload,
            sheetContext: sheetContext,
          ),
    ));
    sections.webZipDownload = TorboxWebZipDownload((
      catalogState: _catalog,
      mounted: () => mounted,
      context: () => context,
    ));
    sections.webFileDownloads = TorboxWebFileDownloads((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      mounted: () => mounted,
      context: () => context,
    ));
    sections.webLinkPlaylistActions = TorboxWebLinkPlaylistActions((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      mounted: () => mounted,
    ));
    sections.webDeleteAction = TorboxWebDeleteAction((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      context: () => context,
      mounted: () => mounted,
      setState: setState,
      webState: _web,
    ));
    sections.selectionActions = TorboxSelectionActions((
      catalogState: _catalog,
      selectionState: _selection,
      webState: _web,
      setState: setState,
      context: () => context,
      mounted: () => mounted,
      showDeleteSelectedProgressDialog: (Set<int> ids, bool isTorrents) =>
          sections.bulkDelete.showDeleteSelectedProgressDialog(ids, isTorrents),
    ));
    sections.bulkDelete = TorboxBulkDelete((
      context: () => context,
      catalogState: _catalog,
      mounted: () => mounted,
      setState: setState,
      webState: _web,
      selectionState: _selection,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
    ));
    sections.webCreateActions = TorboxWebCreateActions((
      catalogState: _catalog,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      addInputState: _addInput,
      context: () => context,
      mounted: () => mounted,
      fetchWebDownloads: ({bool reset = false}) =>
          sections.catalogLoading.fetchWebDownloads(reset: reset),
    ));
    sections.initialAction = TorboxInitialAction((
      catalogState: _catalog,
      mounted: () => mounted,
      navigateIntoTorrent: (TorboxTorrent torrent) =>
          _navigateIntoTorrent(torrent),
    ));
    sections.streamRequest = TorboxStreamRequest();
    sections.fileSelectionSheet = TorboxFileSelectionSheet((
      showComingSoon: (String action) =>
          sections.magnetActions.showComingSoon(action),
      context: () => context,
      buildTorboxRawList:
          ({
            required List<TorboxFileEntry> entries,
            required Set<int> selectedIndices,
            required ValueChanged<int> onToggle,
            Future<void> Function(TorboxFileEntry entry)? onCopy,
          }) => sections.fileListLayouts.buildTorboxRawList(
            entries: entries,
            selectedIndices: selectedIndices,
            onToggle: onToggle,
            onCopy: onCopy,
          ),
      copyTorboxFileLink: (TorboxTorrent torrent, TorboxFile file) =>
          sections.torrentLinkActions.copyTorboxFileLink(torrent, file),
      buildTorboxSeriesView:
          ({
            required List<TorboxFileEntry> entries,
            required Set<int> selectedIndices,
            required int? currentSeason,
            required ValueChanged<int?> onSeasonChange,
            required ValueChanged<int> onToggleFile,
            required void Function(int season, List<int> indices)
            onToggleSeason,
            Future<void> Function(TorboxFileEntry entry)? onCopy,
          }) => sections.seriesLayout.buildTorboxSeriesView(
            entries: entries,
            selectedIndices: selectedIndices,
            currentSeason: currentSeason,
            onSeasonChange: onSeasonChange,
            onToggleFile: onToggleFile,
            onToggleSeason: onToggleSeason,
            onCopy: onCopy,
          ),
      buildTorboxMovieView:
          ({
            required List<TorboxFileEntry> entries,
            required Set<int> selectedIndices,
            required ValueChanged<int> onToggle,
            Future<void> Function(TorboxFileEntry entry)? onCopy,
          }) => sections.fileListLayouts.buildTorboxMovieView(
            entries: entries,
            selectedIndices: selectedIndices,
            onToggle: onToggle,
            onCopy: onCopy,
          ),
      buildTorboxGenericList:
          ({
            required List<TorboxFileEntry> entries,
            required Set<int> selectedIndices,
            required ValueChanged<int> onToggle,
            Future<void> Function(TorboxFileEntry entry)? onCopy,
          }) => sections.fileListLayouts.buildTorboxGenericList(
            entries: entries,
            selectedIndices: selectedIndices,
            onToggle: onToggle,
            onCopy: onCopy,
          ),
      enqueueTorboxDownloads:
          ({
            required TorboxTorrent torrent,
            required List<TorboxFileEntry> entriesToDownload,
            required BuildContext sheetContext,
          }) => sections.torrentEnqueue.enqueueTorboxDownloads(
            torrent: torrent,
            entriesToDownload: entriesToDownload,
            sheetContext: sheetContext,
          ),
    ));
    sections.torrentEnqueue = TorboxTorrentEnqueue((
      catalogState: _catalog,
      mounted: () => mounted,
      context: () => context,
    ));
    sections.torrentZipDownload = TorboxTorrentZipDownload((
      catalogState: _catalog,
      mounted: () => mounted,
      context: () => context,
    ));
    sections.downloadOptions = TorboxDownloadOptions((
      context: () => context,
      downloadAllTorrentFiles: (TorboxTorrent torrent) =>
          sections.torrentDownloadAction.downloadAllTorrentFiles(torrent),
      enqueueTorboxZipDownload:
          ({
            required TorboxTorrent torrent,
            required BuildContext sheetContext,
          }) => sections.torrentZipDownload.enqueueTorboxZipDownload(
            torrent: torrent,
            sheetContext: sheetContext,
          ),
    ));
    sections.fileListLayouts = TorboxFileListLayouts((
      context: () => context,
      buildTorboxFileCard:
          ({
            required TorboxFileEntry entry,
            required bool isSelected,
            required VoidCallback onToggle,
            required int animationIndex,
            required Color surface,
            String? badge,
            String? subtitle,
            Future<void> Function()? onCopy,
          }) => sections.fileSelectionCard.buildTorboxFileCard(
            entry: entry,
            isSelected: isSelected,
            onToggle: onToggle,
            animationIndex: animationIndex,
            surface: surface,
            badge: badge,
            subtitle: subtitle,
            onCopy: onCopy,
          ),
    ));
    sections.seriesLayout = TorboxSeriesLayout((
      context: () => context,
      buildSectionHeader: (String title) =>
          sections.fileListLayouts.buildSectionHeader(title),
      buildTorboxFileCard:
          ({
            required TorboxFileEntry entry,
            required bool isSelected,
            required VoidCallback onToggle,
            required int animationIndex,
            required Color surface,
            String? badge,
            String? subtitle,
            Future<void> Function()? onCopy,
          }) => sections.fileSelectionCard.buildTorboxFileCard(
            entry: entry,
            isSelected: isSelected,
            onToggle: onToggle,
            animationIndex: animationIndex,
            surface: surface,
            badge: badge,
            subtitle: subtitle,
            onCopy: onCopy,
          ),
    ));
    sections.fileSelectionCard = TorboxFileSelectionCard();
    sections.magnetActions = TorboxMagnetActions((
      mounted: () => mounted,
      context: () => context,
      catalogState: _catalog,
      addInputState: _addInput,
      refresh: () => sections.catalogLoading.refresh(),
    ));
    sections.fileActions = TorboxFileActions((
      navigationState: _nav,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      playTorboxFiles: (List<TorboxFile> files, String collectionName) =>
          sections.filePlayback.playTorboxFiles(files, collectionName),
      catalogState: _catalog,
      requestTorboxStreamUrl:
          ({
            required String apiKey,
            required TorboxTorrent torrent,
            required TorboxFile file,
          }) => sections.streamRequest.requestTorboxStreamUrl(
            apiKey: apiKey,
            torrent: torrent,
            file: file,
          ),
      mounted: () => mounted,
      context: () => context,
      downloadSingleFile: (TorboxFile file) =>
          sections.fileDownloads.downloadSingleFile(file),
    ));
    sections.filePlaylistLinks = TorboxFilePlaylistLinks((
      navigationState: _nav,
      currentFiles: () => sections.fileActions.currentFiles,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      copyTorboxFileLink: (TorboxTorrent torrent, TorboxFile file) =>
          sections.torrentLinkActions.copyTorboxFileLink(torrent, file),
      catalogState: _catalog,
      mounted: () => mounted,
    ));
    sections.fileDownloads = TorboxFileDownloads((
      catalogState: _catalog,
      navigationState: _nav,
      mounted: () => mounted,
      context: () => context,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
    ));
    sections.filePlayback = TorboxFilePlayback((
      catalogState: _catalog,
      navigationState: _nav,
      showSnackBar: (String message, {bool isError = true}) =>
          sections.notifications.showSnackBar(message, isError: isError),
      requestTorboxStreamUrl:
          ({
            required String apiKey,
            required TorboxTorrent torrent,
            required TorboxFile file,
          }) => sections.streamRequest.requestTorboxStreamUrl(
            apiKey: apiKey,
            torrent: torrent,
            file: file,
          ),
      mounted: () => mounted,
      context: () => context,
    ));
    sections.notifications = TorboxNotifications((
      mounted: () => mounted,
      context: () => context,
    ));
    return sections;
  }

  // TV content focus handler (stored for proper unregistration)

  // Web Downloads state

  // Folder navigation state
  // null means we're at root (torrent list)
  // null means we're not viewing a web download
  // Path within current torrent/web download's folder tree
  // Current folder node being viewed

  // View mode state

  // Focus nodes for TV/DPAD navigation

  // Flag to focus first item after data loads (set by TV content focus handler)

  // Search state (for folder browsing mode)

  // Torrent-level search state (for root torrent list)

  // Whether TorBox is hidden from bottom-nav. In selectSourceMode we use this to
  // decide whether to restrict searches to queries matching the show title.

  // Multi-select state

  @override
  void initState() {
    super.initState();
    AnalyticsService.screenView('torbox_downloads');

    // Initialize first item focus node with DPAD up handler
    _focus.firstItemFocusNode = FocusNode(
      debugLabel: 'torbox-first-item',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_torrentSearch.isTorrentSearchActive) {
            _focus.torrentSearchFocusNode.requestFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );

    // Initialize torrent search focus node with DPAD navigation
    _focus.torrentSearchFocusNode = FocusNode(
      debugLabel: 'torbox-torrent-search',
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          _focus.torrentSearchToggleFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          _focus.firstItemFocusNode.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );

    _focus.scrollController.addListener(_sections.catalogLoading.onScroll);
    _focus.webDownloadScrollController.addListener(
      _sections.catalogLoading.onWebDownloadScroll,
    );
    _catalog.pendingInitialTorrent = widget.initialTorrentToOpen;

    if (widget.selectSourceMode &&
        widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.isNotEmpty) {
      _torrentSearch.isTorrentSearchActive = true;
      _torrentSearch.torrentSearchController.text = widget.initialSearchQuery!;
      TorboxStorage.getTorboxHiddenFromNav().then((v) {
        if (mounted) setState(() => _torrentSearch.hiddenFromNav = v);
      });
    }

    _sections.catalogLoading.loadApiKeyAndTorrents();

    // Register back navigation handler for folder navigation
    if (widget.isPushedRoute) {
      MainPageBridge.pushRouteBackHandler(
        _sections.backNavigation.handleBackNavigation,
      );
      // Set up timeout - only when DEEP-LINKED into a specific torrent
      // (initialTorrentToOpen). Browsing from the Cloud hub has no target, so
      // the root list is the resting state — no spurious auto-close.
      Future.delayed(const Duration(seconds: 10), () {
        if (mounted &&
            widget.isPushedRoute &&
            !widget.selectSourceMode &&
            widget.initialTorrentToOpen != null &&
            _isAtRoot) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to open torrent. Please try again.'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      });
    } else {
      MainPageBridge.registerTabBackHandler(
        'torbox',
        _sections.backNavigation.handleBackNavigation,
      );
      // Register TV sidebar focus handler (tab index 5 = Torbox)
      _focus.tvContentFocusHandler = () {
        // Set flag to focus after data loads
        _focus.shouldFocusOnLoad = true;
        // Try to focus now in case data is already loaded
        _sections.focusActions.focusFirstItemOrFallback();
      };
      MainPageBridge.registerTvContentFocusHandler(
        5,
        _focus.tvContentFocusHandler!,
      );
    }
  }

  @override
  void didUpdateWidget(TorboxDownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTorrentToOpen != null) {
      _catalog.pendingInitialTorrent = widget.initialTorrentToOpen;
      _catalog.initialActionHandled = false;
      _sections.initialAction.maybeTriggerInitialAction();
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
      MainPageBridge.unregisterTabBackHandler('torbox');
      if (_focus.tvContentFocusHandler != null) {
        MainPageBridge.unregisterTvContentFocusHandler(
          5,
          _focus.tvContentFocusHandler!,
        );
      }
    }

    _focus.scrollController.dispose();
    _focus.webDownloadScrollController.dispose();
    _addInput.magnetController.dispose();
    _addInput.webLinkController.dispose();
    _addInput.webNameController.dispose();
    _addInput.webPasswordController.dispose();
    _focus.viewModeDropdownFocusNode.dispose();
    _focus.firstItemFocusNode.dispose();
    _focus.backButtonFocusNode.dispose();
    _folderSearch.searchController.dispose();
    _focus.searchFocusNode.dispose();
    _focus.searchButtonFocusNode.dispose();
    _focus.searchClearFocusNode.dispose();
    _torrentSearch.torrentSearchController.dispose();
    _focus.torrentSearchFocusNode.dispose();
    _focus.torrentSearchClearFocusNode.dispose();
    _focus.torrentSearchToggleFocusNode.dispose();
    _focus.deleteButtonFocusNode.dispose();
    super.dispose();
  }

  // ==================== WEB DOWNLOADS METHODS ====================

  // --- Multi-select helpers ---

  // ==================== FILE/FOLDER ACTION METHODS ====================

  // ==================== FOLDER NAVIGATION METHODS ====================

  /// Navigate into a torrent (show its folder structure)
  void _navigateIntoTorrent(TorboxTorrent torrent) {
    _sections.selectionActions.exitSelectionMode();
    // Focus first item after navigation
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();

    print('🔍 Navigating into torrent: id=${torrent.id}, name=${torrent.name}');
    print('   Files count: ${torrent.files.length}');
    print('   Sample files:');
    for (
      int i = 0;
      i < (torrent.files.length < 5 ? torrent.files.length : 5);
      i++
    ) {
      print(
        '     [$i] id=${torrent.files[i].id}, name=${torrent.files[i].name}',
      );
    }

    // Build folder tree for this torrent
    print('   Building folder tree...');
    final tree = TorboxFolderTreeBuilder.buildTree(torrent.files);
    print('   Tree built: root has ${tree.children.length} children');

    // Initialize view mode for this torrent if not already set
    _view.torrentViewModes.putIfAbsent(torrent.id, () => FolderViewMode.raw);

    // Apply view mode transformation to root nodes
    final mode = _view.torrentViewModes[torrent.id]!;
    List<RDFileNode> transformedNodes;
    switch (mode) {
      case FolderViewMode.raw:
        transformedNodes = tree.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedNodes = applySortedView(tree.children);
        break;
      case FolderViewMode.seriesArrange:
        transformedNodes = applySeriesArrangedView(tree.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _nav.navigationStack.add((
        torrent: _nav.currentTorrent,
        webDownload: _nav.currentWebDownload,
        path: List.from(_nav.currentPath),
        node: _nav.currentFolderNode,
      ));

      // Navigate to torrent root
      _nav.currentTorrent = torrent;
      _nav.currentWebDownload = null;
      _nav.currentPath = [];
      _nav.currentFolderNode = tree;
      _view.currentViewNodes = transformedNodes;
    });

    // Focus first item after navigation
    _sections.focusActions.focusFirstItemOrFallback();
  }

  /// Navigate into a web download (show its folder structure)
  void _navigateIntoWebDownload(TorboxWebDownload webDownload) {
    _sections.selectionActions.exitSelectionMode();
    // Focus first item after navigation
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();

    // Build folder tree for this web download
    final tree = TorboxFolderTreeBuilder.buildTree(webDownload.files);

    // Initialize view mode for this web download if not already set
    _view.webDownloadViewModes.putIfAbsent(
      webDownload.id,
      () => FolderViewMode.raw,
    );

    // Apply view mode transformation to root nodes
    final mode = _view.webDownloadViewModes[webDownload.id]!;
    List<RDFileNode> transformedNodes;
    switch (mode) {
      case FolderViewMode.raw:
        transformedNodes = tree.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedNodes = applySortedView(tree.children);
        break;
      case FolderViewMode.seriesArrange:
        transformedNodes = applySeriesArrangedView(tree.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _nav.navigationStack.add((
        torrent: _nav.currentTorrent,
        webDownload: _nav.currentWebDownload,
        path: List.from(_nav.currentPath),
        node: _nav.currentFolderNode,
      ));

      // Navigate to web download root
      _nav.currentTorrent = null;
      _nav.currentWebDownload = webDownload;
      _nav.currentPath = [];
      _nav.currentFolderNode = tree;
      _view.currentViewNodes = transformedNodes;
    });

    // Focus first item after navigation
    _sections.focusActions.focusFirstItemOrFallback();
  }

  /// Navigate into a subfolder within current torrent/web download
  void _navigateIntoFolder(RDFileNode folderNode) {
    if (!folderNode.isFolder) return;

    // Focus first item after navigation
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();

    // Apply view mode to folder children
    // NOTE: Series Arrange only makes sense at root level (it creates virtual Season folders)
    // When inside any folder, show files in sorted or raw view
    final mode = _getCurrentViewMode();
    List<RDFileNode> transformedChildren;

    switch (mode) {
      case FolderViewMode.raw:
        transformedChildren = folderNode.children;
        break;
      case FolderViewMode.sortedAZ:
        transformedChildren = applySortedView(folderNode.children);
        break;
      case FolderViewMode.seriesArrange:
        // Inside a folder with Series Arrange mode: show files sorted by name
        transformedChildren = applySortedView(folderNode.children);
        break;
    }

    setState(() {
      // Push current state to navigation stack
      _nav.navigationStack.add((
        torrent: _nav.currentTorrent,
        webDownload: _nav.currentWebDownload,
        path: List.from(_nav.currentPath),
        node: _nav.currentFolderNode,
      ));

      // Navigate into folder
      _nav.currentPath.add(folderNode.name);
      _nav.currentFolderNode = folderNode;
      _view.currentViewNodes = transformedChildren;
    });

    // Focus first item after navigation
    _sections.focusActions.focusFirstItemOrFallback();
  }

  /// Navigate up one level (back button)
  void _navigateUp() {
    if (_nav.navigationStack.isEmpty) return;

    // Refocus the first row once the previous listing shows — the focused
    // row is disposed by the swap and nothing else reclaims DPAD focus.
    _focus.shouldFocusOnLoad = true;
    _sections.catalogLoading.resetListScroll();
    final previous = _nav.navigationStack.removeLast();

    // Reapply view mode transformation after navigation
    List<RDFileNode>? transformedNodes;
    if (previous.node != null &&
        (previous.torrent != null || previous.webDownload != null)) {
      FolderViewMode mode;
      if (previous.torrent != null) {
        mode =
            _view.torrentViewModes[previous.torrent!.id] ?? FolderViewMode.raw;
      } else {
        mode =
            _view.webDownloadViewModes[previous.webDownload!.id] ??
            FolderViewMode.raw;
      }
      final rawNodes = previous.node!.children;

      // Apply view mode transformation
      // NOTE: Series Arrange only applies at root level
      if (mode == FolderViewMode.seriesArrange && previous.path.isNotEmpty) {
        // Still inside a folder after going up - use sorted view
        transformedNodes = applySortedView(rawNodes);
      } else {
        switch (mode) {
          case FolderViewMode.raw:
            transformedNodes = rawNodes;
            break;
          case FolderViewMode.sortedAZ:
            transformedNodes = applySortedView(rawNodes);
            break;
          case FolderViewMode.seriesArrange:
            transformedNodes = applySeriesArrangedView(rawNodes);
            break;
        }
      }
    }

    setState(() {
      _nav.currentTorrent = previous.torrent;
      _nav.currentWebDownload = previous.webDownload;
      _nav.currentPath = previous.path;
      _nav.currentFolderNode = previous.node;
      _view.currentViewNodes = transformedNodes;
    });
  }

  /// Check if we're at root level (torrent/web download list)
  bool get _isAtRoot =>
      _nav.currentTorrent == null && _nav.currentWebDownload == null;

  /// Get current folder/torrent/web download name for display
  String get _currentFolderName {
    if (_isAtRoot) return 'Torbox Files';
    if (_nav.currentPath.isEmpty) {
      return _nav.currentTorrent?.name ??
          _nav.currentWebDownload?.name ??
          'Download';
    }
    return _nav.currentPath.last;
  }

  /// Get current view mode for active torrent/web download
  FolderViewMode _getCurrentViewMode() {
    if (_nav.currentTorrent != null) {
      return _view.torrentViewModes[_nav.currentTorrent!.id] ??
          FolderViewMode.raw;
    }
    if (_nav.currentWebDownload != null) {
      return _view.webDownloadViewModes[_nav.currentWebDownload!.id] ??
          FolderViewMode.raw;
    }
    return FolderViewMode.raw;
  }

  /// Set view mode and refresh display
  void _setViewMode(FolderViewMode mode) {
    if ((_nav.currentTorrent == null && _nav.currentWebDownload == null) ||
        _nav.currentFolderNode == null) {
      return;
    }

    // Get raw nodes based on current path
    // Always rebuild tree from scratch to handle virtual folders
    final files =
        _nav.currentTorrent?.files ?? _nav.currentWebDownload?.files ?? [];
    final tree = TorboxFolderTreeBuilder.buildTree(files);
    List<RDFileNode> rawNodes;

    if (_nav.currentPath.isEmpty) {
      // At torrent/web download root
      rawNodes = tree.children;
    } else {
      // Navigate to current path to get raw nodes
      RDFileNode currentNode = tree;
      bool pathValid = true;

      for (final folderName in _nav.currentPath) {
        final childFolder = currentNode.children.cast<RDFileNode?>().firstWhere(
          (node) => node?.name == folderName && node?.isFolder == true,
          orElse: () => null,
        );
        if (childFolder != null) {
          currentNode = childFolder;
        } else {
          // Path not found in raw tree (likely inside virtual folder)
          // Fall back to root level
          pathValid = false;
          break;
        }
      }

      if (pathValid) {
        // Successfully navigated to the path
        rawNodes = currentNode.children;
      } else {
        // Path invalid (e.g., inside virtual Season folder) - reset to root
        rawNodes = tree.children;
        _nav.currentPath.clear();
        _nav.currentFolderNode = tree;
      }
    }

    // If user selected Series Arrange, detect if content is actually a series
    if (mode == FolderViewMode.seriesArrange) {
      final isSeries = detectSeriesPattern(rawNodes);

      if (!isSeries) {
        // Not a series - show snackbar and fallback to sorted view
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No series detected in this folder. Switching to Sort (A-Z) view.',
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
            behavior: SnackBarBehavior.floating,
          ),
        );

        // Switch to sorted view instead
        setState(() {
          if (_nav.currentTorrent != null) {
            _view.torrentViewModes[_nav.currentTorrent!.id] =
                FolderViewMode.sortedAZ;
          } else if (_nav.currentWebDownload != null) {
            _view.webDownloadViewModes[_nav.currentWebDownload!.id] =
                FolderViewMode.sortedAZ;
          }
          _view.currentViewNodes = applySortedView(rawNodes);
        });
        return;
      }
    }

    // Apply transformation based on mode
    setState(() {
      if (_nav.currentTorrent != null) {
        _view.torrentViewModes[_nav.currentTorrent!.id] = mode;
      } else if (_nav.currentWebDownload != null) {
        _view.webDownloadViewModes[_nav.currentWebDownload!.id] = mode;
      }

      switch (mode) {
        case FolderViewMode.raw:
          _view.currentViewNodes = rawNodes;
          break;
        case FolderViewMode.sortedAZ:
          _view.currentViewNodes = applySortedView(rawNodes);
          break;
        case FolderViewMode.seriesArrange:
          _view.currentViewNodes = applySeriesArrangedView(rawNodes);
          break;
      }
    });
  }

  Widget _buildViewModeDropdown() {
    final theme = Theme.of(context);
    final mode = _getCurrentViewMode();

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
            if (value != null) _setViewMode(value);
          },
        ),
      ),
    );
  }

  // ============ Torrent-Level Search Methods ============

  void _toggleTorrentSearch() {
    if (widget.selectSourceMode) return;
    setState(() {
      _torrentSearch.isTorrentSearchActive =
          !_torrentSearch.isTorrentSearchActive;
      if (!_torrentSearch.isTorrentSearchActive) {
        _torrentSearch.torrentSearchController.clear();
        _torrentSearch.torrentSearchQuery = '';
        _torrentSearch.allTorrentsForSearch.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.torrentSearchFocusNode.requestFocus();
        });
      }
    });
  }

  bool _queryMatchesInitialTitle(String query) {
    final title = widget.initialSearchQuery;
    if (title == null || title.isEmpty) return true;
    const stopwords = {'the', 'a', 'an'};
    final rawTokens = title
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final filtered = rawTokens
        .where((t) => !stopwords.contains(t) && t.length >= 2)
        .toList();
    final effectiveTokens = filtered.isEmpty ? rawTokens : filtered;
    if (effectiveTokens.isEmpty) return true;
    final normalizedQuery = query.toLowerCase();
    return effectiveTokens.any((t) => normalizedQuery.contains(t));
  }

  void _submitTorrentSearch() {
    final query = _torrentSearch.torrentSearchController.text.trim();
    if (query.isEmpty) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    if (widget.selectSourceMode &&
        _torrentSearch.hiddenFromNav &&
        !_queryMatchesInitialTitle(query)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Search must include part of "${widget.initialSearchQuery}"',
          ),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 3),
        ),
      );
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    _focus.torrentSearchSubmitFocus.arm(enabled: PlatformUtil.isTelevision);
    if (_torrentSearch.allTorrentsForSearch.isEmpty) {
      setState(() => _torrentSearch.torrentSearchQuery = query);
      if (!_torrentSearch.isLoadingTorrentSearch) {
        setState(() => _torrentSearch.isLoadingTorrentSearch = true);
        _fetchAllTorrentsForSearch();
      }
    } else {
      setState(() => _torrentSearch.torrentSearchQuery = query);
      _completeTorrentSearchSubmitFocus();
    }
  }

  void _completeTorrentSearchSubmitFocus() {
    if (_filteredTorrentSearchResults.isEmpty) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }
    _focus.torrentSearchSubmitFocus.complete(
      field: _focus.torrentSearchFocusNode,
      isMounted: () => mounted,
      requestFocus: _focus.firstItemFocusNode.requestFocus,
      targetHasFocus: () => _focus.firstItemFocusNode.hasFocus,
    );
  }

  Future<void> _fetchAllTorrentsForSearch() async {
    final key = _catalog.apiKey;
    if (key == null || key.isEmpty) {
      _focus.torrentSearchSubmitFocus.cancel();
      return;
    }

    try {
      final List<TorboxTorrent> allTorrents = [];
      int offset = 0;
      const limit = 1000;
      bool hasMore = true;

      while (hasMore) {
        final result = await TorboxService.getTorrents(
          key,
          offset: offset,
          limit: limit,
        );
        final List<TorboxTorrent> batch = (result['torrents'] as List)
            .cast<TorboxTorrent>();
        allTorrents.addAll(batch);
        hasMore = result['hasMore'] as bool? ?? false;
        offset += limit;
        if (offset > 5000) break; // Safety cap
      }

      if (mounted) {
        setState(() {
          _torrentSearch.allTorrentsForSearch = allTorrents;
          _torrentSearch.isLoadingTorrentSearch = false;
        });
        _completeTorrentSearchSubmitFocus();
      }
    } catch (e) {
      if (mounted) {
        _focus.torrentSearchSubmitFocus.cancel();
        setState(() => _torrentSearch.isLoadingTorrentSearch = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load torrents for search: ${e.toString()}',
            ),
          ),
        );
      }
    }
  }

  List<TorboxTorrent> get _filteredTorrentSearchResults {
    final source = _torrentSearch.allTorrentsForSearch.isNotEmpty
        ? _torrentSearch.allTorrentsForSearch
        : _catalog.torrents;
    if (_torrentSearch.torrentSearchQuery.isEmpty) return [];
    final query = _torrentSearch.torrentSearchQuery.toLowerCase();
    return source.where((t) => t.name.toLowerCase().contains(query)).toList();
  }

  // ============ File Search Methods ============

  /// Toggle search mode on/off
  void _toggleSearch() {
    setState(() {
      _folderSearch.isSearchActive = !_folderSearch.isSearchActive;
      if (!_folderSearch.isSearchActive) {
        _folderSearch.searchController.clear();
        _folderSearch.searchResults.clear();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _focus.searchFocusNode.requestFocus();
        });
      }
    });
  }

  /// Perform deep search across all files in current torrent
  void _performSearch(String query) {
    // Get root folder node from navigation stack
    if (_nav.navigationStack.isEmpty || query.isEmpty) {
      setState(() => _folderSearch.searchResults = []);
      return;
    }

    final rootEntry = _nav.navigationStack.first;
    final rootNode = rootEntry.node;
    if (rootNode == null) {
      setState(() => _folderSearch.searchResults = []);
      return;
    }

    final lowerQuery = query.toLowerCase();
    final results = <TorboxSearchResult>[];

    void searchNode(RDFileNode node, List<String> path) {
      if (!node.isFolder) {
        if (FileUtils.isVideoFile(node.name) &&
            node.name.toLowerCase().contains(lowerQuery)) {
          results.add(TorboxSearchResult(node: node, path: path.join(' / ')));
        }
      } else {
        for (final child in node.children) {
          searchNode(child, [...path, node.name]);
        }
      }
    }

    for (final child in rootNode.children) {
      searchNode(child, []);
    }

    setState(() => _folderSearch.searchResults = results);
  }

  /// Build the search bar widget
  Widget _buildSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _folderSearch.searchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _folderSearch.searchController,
              focusNode: _focus.searchFocusNode,
              textInputAction: TextInputAction.search,
              // D-pad exits for Android TV (formerly a Focus/onKeyEvent wrapper)
              onUpArrow: () => _focus.searchFocusNode.unfocus(),
              onDownArrow: () => _focus.searchFocusNode.unfocus(),
              onRightArrow: hasText
                  ? () => _focus.searchClearFocusNode.requestFocus()
                  : null,
              decoration: InputDecoration(
                hintText: 'Search all files...',
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
              onChanged: _performSearch,
              onSubmitted: (_) => _focus.searchFocusNode.unfocus(),
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
                      _folderSearch.searchController.clear();
                      _folderSearch.searchResults.clear();
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
                            _folderSearch.searchController.clear();
                            _folderSearch.searchResults.clear();
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

  /// Build search results list
  Widget _buildSearchResults() {
    if (_folderSearch.searchController.text.isEmpty) {
      return const Center(
        child: Text(
          'Type to search all files',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    if (_folderSearch.searchResults.isEmpty) {
      return const Center(
        child: Text('No files found', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _folderSearch.searchResults.length,
      itemBuilder: (context, index) {
        final result = _folderSearch.searchResults[index];
        return _buildSearchResultCard(result);
      },
    );
  }

  /// Build a card for a search result
  Widget _buildSearchResultCard(TorboxSearchResult result) {
    final node = result.node;

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
          onTap: () => _sections.fileActions.playVideoFile(node),
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
                        node.name,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Get items to display (torrents/web downloads or files/folders)
  List<dynamic> get _currentItems {
    if (_isAtRoot) {
      // At root: show torrents or web downloads based on selected view
      if (_catalog.selectedView == TorboxDownloadsView.webDownloads) {
        return _web.webDownloads;
      }
      return _catalog.torrents;
    } else {
      // Inside torrent/web download: show current folder's children (transformed by view mode)
      return _view.currentViewNodes ?? _nav.currentFolderNode?.children ?? [];
    }
  }

  @override
  Widget build(BuildContext context) {
    // Back navigation is handled via MainPageBridge.handleBackNavigation

    // When DEEP-LINKED into a specific torrent (pushed WITH a target) and still
    // at root, show the loading state. Browsing from the Cloud hub has no target,
    // so the list root is the real content — don't gate it behind a spinner.
    if (widget.isPushedRoute &&
        !widget.selectSourceMode &&
        widget.initialTorrentToOpen != null &&
        _isAtRoot) {
      return CloudScaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: 'Back',
          ),
          title: const Text('Opening torrent...'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading torrent files...'),
            ],
          ),
        ),
      );
    }

    final currentMode = _getCurrentViewMode();
    final showSearch =
        !_isAtRoot && currentMode != FolderViewMode.seriesArrange;

    return CloudScaffold(
      appBar: _isAtRoot
          ? (widget.selectSourceMode
                ? AppBar(
                    leading: IconButton(
                      focusNode: _focus.backButtonFocusNode,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                    ),
                    title: const Text('Select Source from TorBox'),
                  )
                : null)
          : AppBar(
              leading: IconButton(
                focusNode: _focus.backButtonFocusNode,
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    _sections.backNavigation.handleBackNavigation(),
                tooltip: 'Back',
              ),
              title: Text(_currentFolderName),
              actions: [
                if (showSearch)
                  Focus(
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
                      focusNode: _focus.searchButtonFocusNode,
                      icon: Icon(
                        _folderSearch.isSearchActive
                            ? Icons.close
                            : Icons.search,
                      ),
                      onPressed: _toggleSearch,
                      tooltip: _folderSearch.isSearchActive
                          ? 'Close search'
                          : 'Search files',
                    ),
                  ),
              ],
            ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          if (_isAtRoot && !widget.selectSourceMode) _buildToolbar(),
          if (_isAtRoot) _buildViewSelectorBar(),
          if (_isAtRoot && _torrentSearch.isTorrentSearchActive)
            _buildTorrentSearchBar(),
          if (_isAtRoot && _selection.isSelectionMode) _buildSelectionBar(),
          if (!_isAtRoot) _buildViewModeDropdown(),
          if (_folderSearch.isSearchActive && showSearch) _buildSearchBar(),
          Expanded(
            child: _torrentSearch.isTorrentSearchActive && _isAtRoot
                ? _buildTorrentSearchResults()
                : _folderSearch.isSearchActive
                ? _buildSearchResults()
                : RefreshIndicator(
                    onRefresh: _sections.catalogLoading.refresh,
                    child: _buildFilesFoldersList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesFoldersList() {
    // Check if we're showing web downloads view at root level
    final isWebDownloadsView =
        _isAtRoot && _catalog.selectedView == TorboxDownloadsView.webDownloads;

    if (isWebDownloadsView) {
      return _buildWebDownloadsList();
    }

    // Loading state
    if (_catalog.isLoading && _currentItems.isEmpty) {
      return const CloudRowSkeletonList();
    }

    // Error state
    if (_catalog.errorMessage.isNotEmpty &&
        _currentItems.isEmpty &&
        !_catalog.initialLoad) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _catalog.errorMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_catalog.apiKey == null || _catalog.apiKey!.isEmpty)
            FilledButton(
              onPressed: _sections.magnetActions.openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_currentItems.isEmpty && !_catalog.isLoading) {
      final isRoot = _isAtRoot;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isRoot ? Icons.inbox_outlined : Icons.folder_open,
                size: 64,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                isRoot ? 'No Torrents Yet' : 'Folder is Empty',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                isRoot
                    ? 'Add torrents via Torbox to see them here.'
                    : 'This folder doesn\'t contain any files or subfolders.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of items (torrents or files/folders)
    return ListView.builder(
      controller: _focus.scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _currentItems.length + (_catalog.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _currentItems.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final item = _currentItems[index];

        if (_isAtRoot) {
          // Show torrent as a folder
          return _buildTorrentFolderCard(item as TorboxTorrent, index);
        } else {
          // Show file or folder node
          return _buildFileOrFolderCard(item as RDFileNode, index);
        }
      },
    );
  }

  Widget _buildWebDownloadsList() {
    // Loading state
    if (_web.isLoadingWebDownloads && _web.webDownloads.isEmpty) {
      return const CloudRowSkeletonList();
    }

    // Error state
    if (_web.webDownloadErrorMessage.isNotEmpty && _web.webDownloads.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.link_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _web.webDownloadErrorMessage,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (_catalog.apiKey == null || _catalog.apiKey!.isEmpty)
            FilledButton(
              onPressed: _sections.magnetActions.openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    // Empty state
    if (_web.webDownloads.isEmpty && !_web.isLoadingWebDownloads) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 24),
              Text(
                'No Web Downloads Yet',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Add web downloads from YouTube, file hosts, and more.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // List of web downloads
    return ListView.builder(
      controller: _focus.webDownloadScrollController,
      padding: const EdgeInsets.all(16),
      itemCount:
          _web.webDownloads.length + (_web.isLoadingMoreWebDownloads ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _web.webDownloads.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        return _buildWebDownloadCard(_web.webDownloads[index], index);
      },
    );
  }

  Widget _buildWebDownloadCard(TorboxWebDownload webDownload, int index) {
    final videoCount = webDownload.files
        .where((file) => !file.zipped && torboxFileLooksLikeVideo(file))
        .length;

    if (widget.selectSourceMode) {
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: webDownload.name,
        meta:
            '${Formatters.formatFileSize(webDownload.size)} · ${webDownload.files.length} file${webDownload.files.length == 1 ? '' : 's'}',
        onTap: videoCount > 0
            ? () {
                widget.onSourceSelected?.call(
                  SeriesSource(
                    torrentHash: '',
                    torrentName: webDownload.name,
                    debridService: 'torbox',
                    debridTorrentId: webDownload.id.toString(),
                    cloudSourceKind: SeriesSource.cloudKindWebDownload,
                    boundAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                Navigator.of(context).pop();
              }
            : null,
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open.
    final actions = <CloudRowAction>[
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () =>
              _sections.webPlayback.handlePlayWebDownload(webDownload),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download to device',
        showInStrip: true,
        onSelected: () =>
            _sections.webOptions.showWebDownloadOptionsDialog(webDownload),
      ),
      CloudRowAction(
        icon: Icons.folder_open,
        label: 'Open',
        onSelected: () => _navigateIntoWebDownload(webDownload),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Download Link',
        onSelected: () =>
            _sections.webLinkPlaylistActions.copyWebDownloadLink(webDownload),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () =>
            _sections.webDeleteAction.confirmDeleteWebDownload(webDownload),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: webDownload.name,
      meta:
          '${Formatters.formatFileSize(webDownload.size)} · ${webDownload.files.length} file${webDownload.files.length == 1 ? '' : 's'}',
      onTap: () => _navigateIntoWebDownload(webDownload),
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedWebDownloadIds.contains(webDownload.id),
      onToggleSelected: () =>
          _sections.selectionActions.toggleWebDownloadSelection(webDownload.id),
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
    );
  }

  /// Build a card for a torrent (displayed as a folder at root level)
  Widget _buildTorrentFolderCard(TorboxTorrent torrent, int index) {
    final videoCount = torrent.files.where(torboxFileLooksLikeVideo).length;
    final meta =
        '${Formatters.formatFileSize(torrent.size)} · ${torrent.files.length} files';
    final upNode = (index == 0 && _torrentSearch.isTorrentSearchActive)
        ? _focus.torrentSearchFocusNode
        : null;

    if (widget.selectSourceMode) {
      // Select-source flow: the row IS the Select action — no strip, no menu.
      return CloudFileRow(
        kind: CloudRowKind.folder,
        title: torrent.name,
        meta: meta,
        onTap: () {
          final source = SeriesSource(
            torrentHash: torrent.hash,
            torrentName: torrent.name,
            debridService: 'torbox',
            debridTorrentId: torrent.id.toString(),
            boundAt: DateTime.now().millisecondsSinceEpoch,
          );
          widget.onSourceSelected?.call(source);
          Navigator.of(context).pop();
        },
        focusNode: index == 0 ? _focus.firstItemFocusNode : null,
        upFocusNode: upNode,
      );
    }

    // Same action set (labels, conditions) the old Open/Play pills + ⋮ menu
    // offered; the row's tap now carries Open.
    final actions = <CloudRowAction>[
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () =>
              _sections.torrentPlayback.handlePlayTorrent(torrent),
        ),
      CloudRowAction(
        icon: Icons.download,
        label: 'Download to device',
        showInStrip: true,
        onSelected: () =>
            _sections.downloadOptions.showDownloadOptionsDialog(torrent),
      ),
      CloudRowAction(
        icon: Icons.folder_open,
        label: 'Open',
        onSelected: () => _navigateIntoTorrent(torrent),
      ),
      CloudRowAction(
        icon: Icons.link,
        label: 'Copy Download Link (Zip)',
        onSelected: () =>
            _sections.torrentLinkActions.copyTorboxZipLink(torrent),
      ),
      if (videoCount > 0)
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () =>
              _sections.torrentPlaylistActions.handleAddToPlaylist(torrent),
        ),
      CloudRowAction(
        icon: Icons.live_tv_rounded,
        label: 'Add to Debrify TV',
        onSelected: () =>
            _sections.torrentPlaylistActions.handleAddToDebrifyTv(torrent),
      ),
      CloudRowAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        destructive: true,
        onSelected: () =>
            _sections.torrentDeleteActions.confirmDeleteTorrent(torrent),
      ),
    ];

    return CloudFileRow(
      kind: CloudRowKind.folder,
      title: torrent.name,
      meta: meta,
      badges: [
        if (torrent.cached)
          const CloudRowBadge('✓ Cached', CloudBadgeKind.ok)
        else if (!torrent.downloadFinished)
          CloudRowBadge(
            '${(torrent.progress * 100).clamp(0, 100).round()}%',
            CloudBadgeKind.warn,
          ),
      ],
      onTap: () => _navigateIntoTorrent(torrent),
      actions: actions,
      selectionMode: _selection.isSelectionMode,
      selected: _selection.selectedTorrentIds.contains(torrent.id),
      onToggleSelected: () =>
          _sections.selectionActions.toggleTorrentSelection(torrent.id),
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
      upFocusNode: upNode,
    );
  }

  /// Build a card for a file or folder node (inside a torrent)
  Widget _buildFileOrFolderCard(RDFileNode node, int index) {
    final isFolder = node.isFolder;
    final isVideo = !isFolder && FileUtils.isVideoFile(node.name);
    final folderHasVideos =
        isFolder && TorboxFolderTreeBuilder.hasVideoFiles(node);

    // Same action set (labels, conditions) the old pills + ⋮ menu offered —
    // note: no delete at node granularity, and Add to Playlist only for
    // torrents (not web downloads), exactly as before.
    final actions = <CloudRowAction>[
      if (folderHasVideos || isVideo)
        CloudRowAction(
          icon: Icons.play_arrow_rounded,
          label: 'Play',
          showInStrip: true,
          onSelected: () {
            if (isFolder) {
              _sections.fileActions.playFolderVideos(node);
            } else {
              _sections.fileActions.playVideoFile(node);
            }
          },
        ),
      CloudRowAction(
        icon: Icons.download_rounded,
        label: 'Download',
        showInStrip: true,
        onSelected: () => _sections.fileActions.downloadFileOrFolder(node),
      ),
      if (_nav.currentWebDownload == null && (isVideo || folderHasVideos))
        CloudRowAction(
          icon: Icons.playlist_add,
          label: 'Add to Playlist',
          onSelected: () =>
              _sections.filePlaylistLinks.addFileOrFolderToPlaylist(node),
        ),
      if (!isFolder)
        CloudRowAction(
          icon: Icons.link,
          label: 'Copy Link',
          onSelected: () => _sections.filePlaylistLinks.copyFileLink(node),
        ),
    ];

    return CloudFileRow(
      kind: isFolder
          ? CloudRowKind.folder
          : isVideo
          ? CloudRowKind.video
          : CloudRowKind.file,
      title: node.name,
      meta: isFolder
          ? '${node.fileCount} items · ${Formatters.formatFileSize(node.totalBytes)}'
          : Formatters.formatFileSize(node.bytes ?? 0),
      onTap: isFolder
          ? () => _navigateIntoFolder(node)
          : isVideo
          ? () => _sections.fileActions.playVideoFile(node)
          : null,
      actions: actions,
      focusNode: index == 0 ? _focus.firstItemFocusNode : null,
    );
  }

  /// Full-width view switcher on its own line under the toolbar (two labels
  /// don't fit the toolbar slot the old single-label dropdown used).
  Widget _buildViewSelectorBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: CloudSegmentedTabs<TorboxDownloadsView>(
        segments: const [
          CloudSegment(
            TorboxDownloadsView.torrents,
            'Torrents',
            Icons.folder_rounded,
          ),
          CloudSegment(
            TorboxDownloadsView.webDownloads,
            'Web Downloads',
            Icons.link_rounded,
          ),
        ],
        selected: _catalog.selectedView,
        onSelected: (value) {
          if (value == _catalog.selectedView) return;
          // The two root lists swap in the same element slot, so the incoming
          // one would inherit the outgoing list's scroll offset.
          _sections.catalogLoading.resetListScroll();
          setState(() {
            _catalog.selectedView = value;
            // Source-selection mode arrives with torrent title search active.
            // Suspend that search while Web Downloads is selected, then
            // restore it if the user switches back to Torrents.
            _torrentSearch.isTorrentSearchActive =
                value == TorboxDownloadsView.torrents &&
                _torrentSearch.torrentSearchController.text.trim().isNotEmpty;
            // Exit selection mode when switching views
            if (_selection.isSelectionMode) {
              _selection.isSelectionMode = false;
              _selection.selectedTorrentIds.clear();
              _selection.selectedWebDownloadIds.clear();
            }
          });
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final app = AppThemeScope.of(context);
    final theme = Theme.of(context);
    final count = _sections.selectionActions.activeSelectedIds.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
                ? _sections.selectionActions.handleDeleteSelected
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

  Widget _buildTorrentSearchBar() {
    final app = AppThemeScope.of(context);
    final hasText = _torrentSearch.torrentSearchController.text.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: TvTextField(
              controller: _torrentSearch.torrentSearchController,
              focusNode: _focus.torrentSearchFocusNode,
              autofocus: true,
              onChanged: (_) => _focus.torrentSearchSubmitFocus.cancel(),
              onSubmitted: (_) => _submitTorrentSearch(),
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search your torrents...',
                hintStyle: TextStyle(color: app.fade(app.core.tx, 0.3)),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: app.fade(app.core.tx, 0.4),
                  size: 20,
                ),
                filled: true,
                fillColor: app.fade(app.core.tx, 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.fade(app.core.tx, 0.08)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: app.shape.br(12),
                  borderSide: BorderSide(color: app.cloud.accent),
                ),
              ),
            ),
          ),
          if (hasText)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Focus(
                focusNode: _focus.torrentSearchClearFocusNode,
                onKeyEvent: (node, event) {
                  if (event is! KeyDownEvent) return KeyEventResult.ignored;
                  final key = event.logicalKey;
                  if (isActivateKey(key) || key == LogicalKeyboardKey.space) {
                    _focus.torrentSearchSubmitFocus.cancel();
                    _torrentSearch.torrentSearchController.clear();
                    setState(() => _torrentSearch.torrentSearchQuery = '');
                    _focus.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  if (key == LogicalKeyboardKey.arrowLeft) {
                    _focus.torrentSearchFocusNode.requestFocus();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Builder(
                  builder: (context) {
                    final isFocused = Focus.of(context).hasFocus;
                    return IconButton(
                      onPressed: () {
                        _focus.torrentSearchSubmitFocus.cancel();
                        _torrentSearch.torrentSearchController.clear();
                        setState(() => _torrentSearch.torrentSearchQuery = '');
                        _focus.torrentSearchFocusNode.requestFocus();
                      },
                      icon: Icon(
                        Icons.clear_rounded,
                        color: isFocused
                            ? app.core.tx
                            : app.fade(app.core.tx, 0.4),
                        size: 18,
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

  Widget _buildTorrentSearchResults() {
    final app = AppThemeScope.of(context);
    if (_torrentSearch.isLoadingTorrentSearch) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading all torrents...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_torrentSearch.torrentSearchQuery.isEmpty) {
      return Center(
        child: Text(
          'Type a keyword and press search',
          style: TextStyle(color: app.fade(app.core.tx, 0.4)),
        ),
      );
    }

    final results = _filteredTorrentSearchResults;

    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: app.fade(app.core.tx, 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No results for "${_torrentSearch.torrentSearchQuery}"',
              style: TextStyle(color: app.fade(app.core.tx, 0.5)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final torrent = results[index];
        return _buildTorrentFolderCard(torrent, index);
      },
    );
  }

  /// Opened from the Cloud hub to browse (pushed, no deep-link target, not
  /// select-source) — the list root otherwise has no Back affordance.
  bool get _isBrowsePush =>
      widget.isPushedRoute &&
      !widget.selectSourceMode &&
      widget.initialTorrentToOpen == null;

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    final app = AppThemeScope.of(context);
    final isTorrentsView =
        _catalog.selectedView == TorboxDownloadsView.torrents;
    final hasItems = isTorrentsView
        ? _catalog.torrents.isNotEmpty
        : _web.webDownloads.isNotEmpty;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 480;
        final double iconSize = isCompact ? 20 : 24;
        final EdgeInsets iconPadding = isCompact
            ? const EdgeInsets.all(6)
            : const EdgeInsets.all(8);
        final BoxConstraints iconConstraints = isCompact
            ? const BoxConstraints(minWidth: 36, minHeight: 36)
            : const BoxConstraints(minWidth: 44, minHeight: 44);
        return Container(
          margin: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 8 : 16,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: app.fade(app.core.tx, 0.05),
            borderRadius: app.shape.br(12),
            border: Border.all(color: app.fade(app.core.tx, 0.08)),
          ),
          child: Row(
            children: [
              if (_isBrowsePush) ...[
                Tooltip(
                  message: 'Back',
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.arrow_back),
                    color: theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                SizedBox(width: isCompact ? 4 : 8),
              ],
              const Spacer(),
              if (hasItems) ...[
                Tooltip(
                  message: _selection.isSelectionMode
                      ? 'Exit selection'
                      : 'Select items',
                  child: IconButton(
                    onPressed: _sections.selectionActions.toggleSelectionMode,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _selection.isSelectionMode
                          ? Icons.close
                          : Icons.checklist_outlined,
                    ),
                    color: _selection.isSelectionMode
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (isTorrentsView)
                  Tooltip(
                    message: 'Delete all torrents',
                    child: IconButton(
                      onPressed:
                          _sections.torrentDeleteActions.confirmDeleteAll,
                      iconSize: iconSize,
                      padding: iconPadding,
                      constraints: iconConstraints,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      color: theme.colorScheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
              if (isTorrentsView) ...[
                Tooltip(
                  message: _torrentSearch.isTorrentSearchActive
                      ? 'Close search'
                      : 'Search torrents',
                  child: IconButton(
                    focusNode: _focus.torrentSearchToggleFocusNode,
                    onPressed: _toggleTorrentSearch,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: Icon(
                      _torrentSearch.isTorrentSearchActive
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                    ),
                    color: _torrentSearch.isTorrentSearchActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                Tooltip(
                  message: 'Add magnet link',
                  child: IconButton(
                    onPressed: _sections.magnetActions.showAddMagnetDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.add_circle_outline),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else ...[
                Tooltip(
                  message: 'Add web download',
                  child: IconButton(
                    onPressed:
                        _sections.webCreateActions.showAddWebDownloadDialog,
                    iconSize: iconSize,
                    padding: iconPadding,
                    constraints: iconConstraints,
                    icon: const Icon(Icons.link),
                    color: theme.colorScheme.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Frozen original-code characterization accessor; production does not call it.
@visibleForTesting
Map<String, Object?> torboxDownloadsTestAccess(
  State<TorboxDownloadsScreen> state,
) {
  final s = state as _TorboxDownloadsScreenState;
  return {
    'handleBackNavigation': s._sections.backNavigation.handleBackNavigation,
    'navigateIntoTorrent': s._navigateIntoTorrent,
    'navigateIntoWebDownload': s._navigateIntoWebDownload,
    'navigateIntoFolder': s._navigateIntoFolder,
    'navigateUp': s._navigateUp,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleTorrentSearch': s._toggleTorrentSearch,
    'toggleSearch': s._toggleSearch,
    'performSearch': s._performSearch,
    'submitTorrentSearch': s._submitTorrentSearch,
    'fetchTorrents': s._sections.catalogLoading.fetchTorrents,
    'fetchWebDownloads': s._sections.catalogLoading.fetchWebDownloads,
    'loadMore': s._sections.catalogLoading.loadMore,
    'loadMoreWebDownloads': s._sections.catalogLoading.loadMoreWebDownloads,
    'confirmDeleteTorrent':
        s._sections.torrentDeleteActions.confirmDeleteTorrent,
    'confirmDeleteAll': s._sections.torrentDeleteActions.confirmDeleteAll,
    'confirmDeleteWebDownload':
        s._sections.webDeleteAction.confirmDeleteWebDownload,
    'handleDeleteSelected': s._sections.selectionActions.handleDeleteSelected,
    'showDeleteSelectedProgressDialog':
        s._sections.bulkDelete.showDeleteSelectedProgressDialog,
    'showAddWebDownloadDialog':
        s._sections.webCreateActions.showAddWebDownloadDialog,
    'showAddMagnetDialog': s._sections.magnetActions.showAddMagnetDialog,
    'addMagnetToTorbox': s._sections.magnetActions.addMagnetToTorbox,
    'handleAddToPlaylist':
        s._sections.torrentPlaylistActions.handleAddToPlaylist,
    'handleAddWebDownloadToPlaylist':
        s._sections.webLinkPlaylistActions.handleAddWebDownloadToPlaylist,
    'addFileOrFolderToPlaylist':
        s._sections.filePlaylistLinks.addFileOrFolderToPlaylist,
    'extractSeasonNumber': extractSeasonNumber,
    'extractLeadingNumber': extractLeadingNumber,
    'applySortedView': applySortedView,
    'applySeriesArrangedView': applySeriesArrangedView,
    'detectSeriesPattern': detectSeriesPattern,
    'setViewMode': s._setViewMode,
    'getCurrentViewMode': s._getCurrentViewMode,
    'torboxDisplayName': torboxDisplayName,
    'torboxFileLooksLikeVideo': torboxFileLooksLikeVideo,
    'findFirstEpisodeIndex': findFirstEpisodeIndex,
    'isValidMagnetLink': isValidMagnetLink,
    'focusFirstItemOrFallback':
        s._sections.focusActions.focusFirstItemOrFallback,
    'selectedView': s._catalog.selectedView,
    'scrollController': s._focus.scrollController,
    'torrents': s._catalog.torrents,
    'magnetController': s._addInput.magnetController,
    'tvContentFocusHandler': s._focus.tvContentFocusHandler,
    'isLoading': s._catalog.isLoading,
    'isLoadingMore': s._catalog.isLoadingMore,
    'hasMore': s._catalog.hasMore,
    'initialLoad': s._catalog.initialLoad,
    'offset': s._catalog.offset,
    'errorMessage': s._catalog.errorMessage,
    'apiKey': s._catalog.apiKey,
    'pendingInitialTorrent': s._catalog.pendingInitialTorrent,
    'initialActionHandled': s._catalog.initialActionHandled,
    'webDownloads': s._web.webDownloads,
    'webDownloadScrollController': s._focus.webDownloadScrollController,
    'isLoadingWebDownloads': s._web.isLoadingWebDownloads,
    'isLoadingMoreWebDownloads': s._web.isLoadingMoreWebDownloads,
    'hasMoreWebDownloads': s._web.hasMoreWebDownloads,
    'webDownloadOffset': s._web.webDownloadOffset,
    'webDownloadErrorMessage': s._web.webDownloadErrorMessage,
    'webLinkController': s._addInput.webLinkController,
    'webNameController': s._addInput.webNameController,
    'webPasswordController': s._addInput.webPasswordController,
    'currentTorrent': s._nav.currentTorrent,
    'currentWebDownload': s._nav.currentWebDownload,
    'currentPath': s._nav.currentPath,
    'currentFolderNode': s._nav.currentFolderNode,
    'navigationStack': s._nav.navigationStack,
    'torrentViewModes': s._view.torrentViewModes,
    'webDownloadViewModes': s._view.webDownloadViewModes,
    'currentViewNodes': s._view.currentViewNodes,
    'viewModeDropdownFocusNode': s._focus.viewModeDropdownFocusNode,
    'firstItemFocusNode': s._focus.firstItemFocusNode,
    'backButtonFocusNode': s._focus.backButtonFocusNode,
    'shouldFocusOnLoad': s._focus.shouldFocusOnLoad,
    'isSearchActive': s._folderSearch.isSearchActive,
    'searchController': s._folderSearch.searchController,
    'searchFocusNode': s._focus.searchFocusNode,
    'searchButtonFocusNode': s._focus.searchButtonFocusNode,
    'searchClearFocusNode': s._focus.searchClearFocusNode,
    'searchResults': s._folderSearch.searchResults,
    'isTorrentSearchActive': s._torrentSearch.isTorrentSearchActive,
    'torrentSearchController': s._torrentSearch.torrentSearchController,
    'torrentSearchFocusNode': s._focus.torrentSearchFocusNode,
    'torrentSearchClearFocusNode': s._focus.torrentSearchClearFocusNode,
    'torrentSearchToggleFocusNode': s._focus.torrentSearchToggleFocusNode,
    'torrentSearchQuery': s._torrentSearch.torrentSearchQuery,
    'allTorrentsForSearch': s._torrentSearch.allTorrentsForSearch,
    'isLoadingTorrentSearch': s._torrentSearch.isLoadingTorrentSearch,
    'hiddenFromNav': s._torrentSearch.hiddenFromNav,
    'isSelectionMode': s._selection.isSelectionMode,
    'selectedTorrentIds': s._selection.selectedTorrentIds,
    'selectedWebDownloadIds': s._selection.selectedWebDownloadIds,
    'deleteButtonFocusNode': s._focus.deleteButtonFocusNode,
    'torrentSearchSubmitFocus': s._focus.torrentSearchSubmitFocus,
    'isAtRoot': s._isAtRoot,
    'currentItems': s._currentItems,
    'filteredTorrentSearchResults': s._filteredTorrentSearchResults,
  };
}
