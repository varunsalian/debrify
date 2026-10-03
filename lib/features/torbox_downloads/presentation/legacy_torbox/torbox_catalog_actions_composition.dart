import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_back_navigation.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_bulk_delete.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_catalog_loading.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_focus_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_selection_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_delete_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_download_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_link_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_playlist_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_create_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_delete_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_file_downloads.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_link_playlist_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_web_zip_download.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/models/torbox_web_download.dart';
import 'package:flutter/material.dart';

import 'torbox_composition_bindings.dart';

void wireTorboxCatalogActions(
  TorboxSections sections,
  TorboxViewBindings view,
  TorboxCompositionStates states,
) {
  sections.focusActions = TorboxFocusActions((
    focusState: states.focusState,
    mounted: view.mounted,
    viewState: states.viewState,
    catalogState: states.catalogState,
    webState: states.webState,
  ));
  sections.torrentDownloadAction = TorboxTorrentDownloadAction((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    navigationState: states.navigationState,
    mounted: view.mounted,
    context: view.context,
    downloadSelectedTorboxFiles:
        (List<Map<String, dynamic>> selectedFiles, String folderName) =>
            sections.fileActions.downloadSelectedTorboxFiles(
              selectedFiles,
              folderName,
            ),
  ));
  sections.torrentPlaylistActions = TorboxTorrentPlaylistActions((
    mounted: view.mounted,
    context: view.context,
    torrentSearchState: states.torrentSearchState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
  ));
  sections.torrentLinkActions = TorboxTorrentLinkActions((
    showComingSoon: (String action) =>
        sections.magnetActions.showComingSoon(action),
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
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
    context: view.context,
  ));
  sections.torrentPlayback = TorboxTorrentPlayback((
    catalogState: states.catalogState,
    showComingSoon: (String action) =>
        sections.magnetActions.showComingSoon(action),
    mounted: view.mounted,
    context: view.context,
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
    catalogState: states.catalogState,
    showComingSoon: (String action) =>
        sections.magnetActions.showComingSoon(action),
    context: view.context,
    mounted: view.mounted,
    setState: view.setState,
    selectionState: states.selectionState,
  ));
  sections.backNavigation = TorboxBackNavigation((
    context: view.context,
    selectionState: states.selectionState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    torrentSearchState: states.torrentSearchState,
    toggleTorrentSearch: () => sections.torrentSearch.toggleTorrentSearch(),
    folderSearchState: states.folderSearchState,
    toggleSearch: () => sections.folderSearch.toggleSearch(),
    isAtRoot: () => sections.folderNavigation.isAtRoot,
    navigationState: states.navigationState,
    navigateUp: () => sections.folderNavigation.navigateUp(),
    selectSourceMode: view.selectSourceMode,
    isPushedRoute: view.isPushedRoute,
    initialTorrentToOpen: view.initialTorrentToOpen,
  ));
  sections.catalogLoading = TorboxCatalogLoading((
    focusState: states.focusState,
    catalogState: states.catalogState,
    webState: states.webState,
    mounted: view.mounted,
    setState: view.setState,
    submitTorrentSearch: () => sections.torrentSearch.submitTorrentSearch(),
    initialSearchQuery: view.initialSearchQuery,
    torrentSearchState: states.torrentSearchState,
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
    maybeTriggerInitialAction: () =>
        sections.initialAction.maybeTriggerInitialAction(),
  ));
  sections.webPlayback = TorboxWebPlayback((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    mounted: view.mounted,
    context: view.context,
  ));
  sections.webOptions = TorboxWebOptions((
    context: view.context,
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
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
  ));
  sections.webFileDownloads = TorboxWebFileDownloads((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    mounted: view.mounted,
    context: view.context,
  ));
  sections.webLinkPlaylistActions = TorboxWebLinkPlaylistActions((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    mounted: view.mounted,
  ));
  sections.webDeleteAction = TorboxWebDeleteAction((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    context: view.context,
    mounted: view.mounted,
    setState: view.setState,
    webState: states.webState,
  ));
  sections.selectionActions = TorboxSelectionActions((
    catalogState: states.catalogState,
    selectionState: states.selectionState,
    webState: states.webState,
    setState: view.setState,
    context: view.context,
    mounted: view.mounted,
    showDeleteSelectedProgressDialog: (Set<int> ids, bool isTorrents) =>
        sections.bulkDelete.showDeleteSelectedProgressDialog(ids, isTorrents),
  ));
  sections.bulkDelete = TorboxBulkDelete((
    context: view.context,
    catalogState: states.catalogState,
    mounted: view.mounted,
    setState: view.setState,
    webState: states.webState,
    selectionState: states.selectionState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
  ));
  sections.webCreateActions = TorboxWebCreateActions((
    catalogState: states.catalogState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    addInputState: states.addInputState,
    context: view.context,
    mounted: view.mounted,
    fetchWebDownloads: ({bool reset = false}) =>
        sections.catalogLoading.fetchWebDownloads(reset: reset),
  ));
}
