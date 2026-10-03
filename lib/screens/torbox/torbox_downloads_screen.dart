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
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_navigation.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_modes.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_folder_search.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
import 'package:debrify/features/torbox_downloads/presentation/folder_view_mode.dart';
import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
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
      toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
      folderSearchState: _folderSearch,
      toggleSearch: () => sections.folderSearch.toggleSearch(),
      isAtRoot: () => sections.folderNavigation.isAtRoot,
      navigationState: _nav,
      navigateUp: () => sections.folderNavigation.navigateUp(),
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
      submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
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
          sections.folderNavigation.navigateIntoTorrent(torrent),
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
    sections.folderNavigation = TorboxFolderNavigation((
      exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
      focusState: _focus,
      resetListScroll: () => sections.catalogLoading.resetListScroll(),
      viewState: _view,
      setState: setState,
      navigationState: _nav,
      focusFirstItemOrFallback: () =>
          sections.focusActions.focusFirstItemOrFallback(),
      getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
    ));
    sections.viewModes = TorboxViewModes((
      navigationState: _nav,
      viewState: _view,
      context: () => context,
      setState: setState,
      focusState: _focus,
    ));
    sections.torrentSearch = TorboxTorrentSearch((
      setState: setState,
      torrentSearchState: _torrentSearch,
      focusState: _focus,
      selectSourceMode: () => widget.selectSourceMode,
      initialSearchQuery: () => widget.initialSearchQuery,
      context: () => context,
      mounted: () => mounted,
      catalogState: _catalog,
    ));
    sections.folderSearch = TorboxFolderSearch((
      setState: setState,
      folderSearchState: _folderSearch,
      focusState: _focus,
      navigationState: _nav,
      context: () => context,
      playVideoFile: (RDFileNode fileNode) =>
          sections.fileActions.playVideoFile(fileNode),
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
            _sections.folderNavigation.isAtRoot) {
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

  // ============ Torrent-Level Search Methods ============

  // ============ File Search Methods ============

  /// Get items to display (torrents/web downloads or files/folders)
  List<dynamic> get _currentItems {
    if (_sections.folderNavigation.isAtRoot) {
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
        _sections.folderNavigation.isAtRoot) {
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

    final currentMode = _sections.viewModes.getCurrentViewMode();
    final showSearch =
        !_sections.folderNavigation.isAtRoot &&
        currentMode != FolderViewMode.seriesArrange;

    return CloudScaffold(
      appBar: _sections.folderNavigation.isAtRoot
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
              title: Text(_sections.folderNavigation.currentFolderName),
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
                      onPressed: _sections.folderSearch.toggleSearch,
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
          if (_sections.folderNavigation.isAtRoot && !widget.selectSourceMode)
            _buildToolbar(),
          if (_sections.folderNavigation.isAtRoot) _buildViewSelectorBar(),
          if (_sections.folderNavigation.isAtRoot &&
              _torrentSearch.isTorrentSearchActive)
            _buildTorrentSearchBar(),
          if (_sections.folderNavigation.isAtRoot && _selection.isSelectionMode)
            _buildSelectionBar(),
          if (!_sections.folderNavigation.isAtRoot)
            _sections.viewModes.buildViewModeDropdown(),
          if (_folderSearch.isSearchActive && showSearch)
            _sections.folderSearch.buildSearchBar(),
          Expanded(
            child:
                _torrentSearch.isTorrentSearchActive &&
                    _sections.folderNavigation.isAtRoot
                ? _buildTorrentSearchResults()
                : _folderSearch.isSearchActive
                ? _sections.folderSearch.buildSearchResults()
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
        _sections.folderNavigation.isAtRoot &&
        _catalog.selectedView == TorboxDownloadsView.webDownloads;

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
      final isRoot = _sections.folderNavigation.isAtRoot;
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

        if (_sections.folderNavigation.isAtRoot) {
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
        onSelected: () =>
            _sections.folderNavigation.navigateIntoWebDownload(webDownload),
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
      onTap: () =>
          _sections.folderNavigation.navigateIntoWebDownload(webDownload),
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
        onSelected: () =>
            _sections.folderNavigation.navigateIntoTorrent(torrent),
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
      onTap: () => _sections.folderNavigation.navigateIntoTorrent(torrent),
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
          ? () => _sections.folderNavigation.navigateIntoFolder(node)
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
              onSubmitted: (_) => _sections.torrentSearch.submitTorrentSearch(),
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

    final results = _sections.torrentSearch.filteredTorrentSearchResults;

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
                    onPressed: _sections.torrentSearch.toggleTorrentSearch,
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
    'navigateIntoTorrent': s._sections.folderNavigation.navigateIntoTorrent,
    'navigateIntoWebDownload':
        s._sections.folderNavigation.navigateIntoWebDownload,
    'navigateIntoFolder': s._sections.folderNavigation.navigateIntoFolder,
    'navigateUp': s._sections.folderNavigation.navigateUp,
    'toggleSelectionMode': s._sections.selectionActions.toggleSelectionMode,
    'exitSelectionMode': s._sections.selectionActions.exitSelectionMode,
    'toggleTorrentSearch': s._sections.torrentSearch.toggleTorrentSearch,
    'toggleSearch': s._sections.folderSearch.toggleSearch,
    'performSearch': s._sections.folderSearch.performSearch,
    'submitTorrentSearch': s._sections.torrentSearch.submitTorrentSearch,
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
    'setViewMode': s._sections.viewModes.setViewMode,
    'getCurrentViewMode': s._sections.viewModes.getCurrentViewMode,
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
    'isAtRoot': s._sections.folderNavigation.isAtRoot,
    'currentItems': s._currentItems,
    'filteredTorrentSearchResults':
        s._sections.torrentSearch.filteredTorrentSearchResults,
  };
}
