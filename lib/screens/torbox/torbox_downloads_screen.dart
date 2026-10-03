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
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_root_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_library_lists.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_row.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_row.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_row.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_view_selector.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_bar.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_search_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_toolbar.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
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
    sections.rootLayout = TorboxRootLayout((
      isAtRoot: () => sections.folderNavigation.isAtRoot,
      catalogState: _catalog,
      webState: _web,
      viewState: _view,
      navigationState: _nav,
      getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
      focusState: _focus,
      handleBackNavigation: () =>
          sections.backNavigation.handleBackNavigation(),
      currentFolderName: () => sections.folderNavigation.currentFolderName,
      folderSearchState: _folderSearch,
      toggleSearch: () => sections.folderSearch.toggleSearch(),
      buildToolbar: () => sections.toolbar.buildToolbar(),
      buildViewSelectorBar: () => sections.viewSelector.buildViewSelectorBar(),
      torrentSearchState: _torrentSearch,
      buildTorrentSearchBar: () =>
          sections.torrentSearchLayout.buildTorrentSearchBar(),
      selectionState: _selection,
      buildSelectionBar: () => sections.selectionBar.buildSelectionBar(),
      buildViewModeDropdown: () => sections.viewModes.buildViewModeDropdown(),
      buildSearchBar: () => sections.folderSearch.buildSearchBar(),
      buildTorrentSearchResults: () =>
          sections.torrentSearchLayout.buildTorrentSearchResults(),
      buildSearchResults: () => sections.folderSearch.buildSearchResults(),
      refresh: () => sections.catalogLoading.refresh(),
      buildFilesFoldersList: () =>
          sections.libraryLists.buildFilesFoldersList(),
      isPushedRoute: () => widget.isPushedRoute,
      selectSourceMode: () => widget.selectSourceMode,
      initialTorrentToOpen: () => widget.initialTorrentToOpen,
    ));
    sections.libraryLists = TorboxLibraryLists((
      isAtRoot: () => sections.folderNavigation.isAtRoot,
      catalogState: _catalog,
      currentItems: () => sections.rootLayout.currentItems,
      context: () => context,
      openSettings: () => sections.magnetActions.openSettings(),
      focusState: _focus,
      buildTorrentFolderCard: (TorboxTorrent torrent, int index) =>
          sections.torrentRow.buildTorrentFolderCard(torrent, index),
      buildFileOrFolderCard: (RDFileNode node, int index) =>
          sections.fileRow.buildFileOrFolderCard(node, index),
      webState: _web,
      buildWebDownloadCard: (TorboxWebDownload webDownload, int index) =>
          sections.webRow.buildWebDownloadCard(webDownload, index),
    ));
    sections.webRow = TorboxWebRow((
      context: () => context,
      focusState: _focus,
      handlePlayWebDownload: (TorboxWebDownload webDownload) =>
          sections.webPlayback.handlePlayWebDownload(webDownload),
      showWebDownloadOptionsDialog: (TorboxWebDownload webDownload) =>
          sections.webOptions.showWebDownloadOptionsDialog(webDownload),
      navigateIntoWebDownload: (TorboxWebDownload webDownload) =>
          sections.folderNavigation.navigateIntoWebDownload(webDownload),
      copyWebDownloadLink: (TorboxWebDownload webDownload) =>
          sections.webLinkPlaylistActions.copyWebDownloadLink(webDownload),
      confirmDeleteWebDownload: (TorboxWebDownload webDownload) =>
          sections.webDeleteAction.confirmDeleteWebDownload(webDownload),
      selectionState: _selection,
      toggleWebDownloadSelection: (int id) =>
          sections.selectionActions.toggleWebDownloadSelection(id),
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ));
    sections.torrentRow = TorboxTorrentRow((
      torrentSearchState: _torrentSearch,
      focusState: _focus,
      context: () => context,
      handlePlayTorrent: (TorboxTorrent torrent) =>
          sections.torrentPlayback.handlePlayTorrent(torrent),
      showDownloadOptionsDialog: (TorboxTorrent torrent) =>
          sections.downloadOptions.showDownloadOptionsDialog(torrent),
      navigateIntoTorrent: (TorboxTorrent torrent) =>
          sections.folderNavigation.navigateIntoTorrent(torrent),
      copyTorboxZipLink: (TorboxTorrent torrent) =>
          sections.torrentLinkActions.copyTorboxZipLink(torrent),
      handleAddToPlaylist: (TorboxTorrent torrent) =>
          sections.torrentPlaylistActions.handleAddToPlaylist(torrent),
      handleAddToDebrifyTv: (TorboxTorrent torrent) =>
          sections.torrentPlaylistActions.handleAddToDebrifyTv(torrent),
      confirmDeleteTorrent: (TorboxTorrent torrent) =>
          sections.torrentDeleteActions.confirmDeleteTorrent(torrent),
      selectionState: _selection,
      toggleTorrentSelection: (int id) =>
          sections.selectionActions.toggleTorrentSelection(id),
      selectSourceMode: () => widget.selectSourceMode,
      onSourceSelected: () => widget.onSourceSelected,
    ));
    sections.fileRow = TorboxFileRow((
      playFolderVideos: (RDFileNode folderNode) =>
          sections.fileActions.playFolderVideos(folderNode),
      playVideoFile: (RDFileNode fileNode) =>
          sections.fileActions.playVideoFile(fileNode),
      downloadFileOrFolder: (RDFileNode node) =>
          sections.fileActions.downloadFileOrFolder(node),
      navigationState: _nav,
      addFileOrFolderToPlaylist: (RDFileNode node) =>
          sections.filePlaylistLinks.addFileOrFolderToPlaylist(node),
      copyFileLink: (RDFileNode node) =>
          sections.filePlaylistLinks.copyFileLink(node),
      navigateIntoFolder: (RDFileNode folderNode) =>
          sections.folderNavigation.navigateIntoFolder(folderNode),
      focusState: _focus,
    ));
    sections.viewSelector = TorboxViewSelector((
      catalogState: _catalog,
      resetListScroll: () => sections.catalogLoading.resetListScroll(),
      setState: setState,
      torrentSearchState: _torrentSearch,
      selectionState: _selection,
    ));
    sections.selectionBar = TorboxSelectionBar((
      context: () => context,
      activeSelectedIds: () => sections.selectionActions.activeSelectedIds,
      toggleSelectAll: () => sections.selectionActions.toggleSelectAll(),
      isAllSelected: () => sections.selectionActions.isAllSelected,
      focusState: _focus,
      handleDeleteSelected: () =>
          sections.selectionActions.handleDeleteSelected(),
    ));
    sections.torrentSearchLayout = TorboxTorrentSearchLayout((
      context: () => context,
      torrentSearchState: _torrentSearch,
      focusState: _focus,
      submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
      setState: setState,
      filteredTorrentSearchResults: () =>
          sections.torrentSearch.filteredTorrentSearchResults,
      buildTorrentFolderCard: (TorboxTorrent torrent, int index) =>
          sections.torrentRow.buildTorrentFolderCard(torrent, index),
    ));
    sections.toolbar = TorboxToolbar((
      isPushedRoute: () => widget.isPushedRoute,
      selectSourceMode: () => widget.selectSourceMode,
      initialTorrentToOpen: () => widget.initialTorrentToOpen,
      context: () => context,
      catalogState: _catalog,
      webState: _web,
      selectionState: _selection,
      toggleSelectionMode: () =>
          sections.selectionActions.toggleSelectionMode(),
      confirmDeleteAll: () => sections.torrentDeleteActions.confirmDeleteAll(),
      torrentSearchState: _torrentSearch,
      focusState: _focus,
      toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
      showAddMagnetDialog: () => sections.magnetActions.showAddMagnetDialog(),
      showAddWebDownloadDialog: () =>
          sections.webCreateActions.showAddWebDownloadDialog(),
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

  @override
  Widget build(BuildContext context) => _sections.rootLayout.build(context);
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
    'currentItems': s._sections.rootLayout.currentItems,
    'filteredTorrentSearchResults':
        s._sections.torrentSearch.filteredTorrentSearchResults,
  };
}
