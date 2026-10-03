import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_file_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_seasons_list.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_series_browser.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_dormant_torrent_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_file_downloads.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_file_playback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_navigation.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_folder_search.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_link_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_magnet_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_modern_file_card.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_multifile_playback.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_node_playlist_links.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_sections.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_download_action.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_playlist_actions.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_torrent_search.dart';
import 'package:debrify/features/debrid_downloads/presentation/legacy_debrid/debrid_view_modes.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:flutter/material.dart';

import 'debrid_composition_bindings.dart';

void wireDebridFileWorkflows(
  DebridSections sections,
  DebridViewBindings view,
  DebridCompositionStates states,
) {
  sections.folderNavigation = DebridFolderNavigation((
    catalogState: states.catalogState,
    exitSelectionMode: () => sections.selectionActions.exitSelectionMode(),
    focusState: states.focusState,
    resetListScroll: () => sections.catalogLoading.resetListScroll(),
    setState: view.setState,
    navigationState: states.navigationState,
    mounted: view.mounted,
    context: view.context,
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
    showError: (String message) => sections.feedback.showError(message),
    viewState: states.viewState,
    focusFirstItemOrFallback: () =>
        sections.focusActions.focusFirstItemOrFallback(),
    getCurrentViewMode: () => sections.viewModes.getCurrentViewMode(),
  ));
  sections.viewModes = DebridViewModes((
    navigationState: states.navigationState,
    viewState: states.viewState,
    setState: view.setState,
    context: view.context,
  ));
  sections.folderSearch = DebridFolderSearch((
    setState: view.setState,
    folderSearchState: states.folderSearchState,
    focusState: states.focusState,
    navigationState: states.navigationState,
  ));
  sections.torrentSearch = DebridTorrentSearch((
    setState: view.setState,
    torrentSearchState: states.torrentSearchState,
    selectSourceMode: view.selectSourceMode,
    initialSearchQuery: view.initialSearchQuery,
    focusState: states.focusState,
    context: view.context,
    mounted: view.mounted,
    catalogState: states.catalogState,
  ));
  sections.torrentDownloadAction = DebridTorrentDownloadAction((
    catalogState: states.catalogState,
    context: view.context,
    mounted: view.mounted,
    showError: (String message) => sections.feedback.showError(message),
    downloadSelectedRealDebridFiles:
        ({
          required List<Map<String, dynamic>> selectedFiles,
          required List<String> links,
          required String folderName,
        }) => sections.fileDownloads.downloadSelectedRealDebridFiles(
          selectedFiles: selectedFiles,
          links: links,
          folderName: folderName,
        ),
  ));
  sections.torrentPlaylistActions = DebridTorrentPlaylistActions((
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
    showError: (String message) => sections.feedback.showError(message),
    torrentSearchState: states.torrentSearchState,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
  ));
  sections.multifilePlayback = DebridMultifilePlayback((
    catalogState: states.catalogState,
    context: view.context,
    mounted: view.mounted,
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.magnetActions = DebridMagnetActions((
    context: view.context,
    addInputState: states.addInputState,
    showError: (String message) => sections.feedback.showError(message),
    mounted: view.mounted,
    setState: view.setState,
    catalogState: states.catalogState,
    fetchTorrents: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchTorrents(apiKey, reset: reset),
  ));
  sections.linkActions = DebridLinkActions((
    context: view.context,
    addInputState: states.addInputState,
    showError: (String message) => sections.feedback.showError(message),
    mounted: view.mounted,
    setState: view.setState,
    catalogState: states.catalogState,
    fetchDownloads: (String apiKey, {bool reset = false}) =>
        sections.catalogLoading.fetchDownloads(apiKey, reset: reset),
  ));
  sections.filePlayback = DebridFilePlayback((
    catalogState: states.catalogState,
    navigationState: states.navigationState,
    context: view.context,
    mounted: view.mounted,
    showError: (String message) => sections.feedback.showError(message),
  ));
  sections.fileDownloads = DebridFileDownloads((
    catalogState: states.catalogState,
    navigationState: states.navigationState,
    showError: (String message) => sections.feedback.showError(message),
    context: view.context,
    mounted: view.mounted,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
  ));
  sections.nodePlaylistLinks = DebridNodePlaylistLinks((
    navigationState: states.navigationState,
    mounted: view.mounted,
    showSuccess: (String message) => sections.feedback.showSuccess(message),
    showError: (String message) => sections.feedback.showError(message),
    catalogState: states.catalogState,
  ));
  sections.dormantTorrentActions = DebridDormantTorrentActions((
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
    showError: (String message) => sections.feedback.showError(message),
    navigateIntoTorrent: (RDTorrent torrent) =>
        sections.folderNavigation.navigateIntoTorrent(torrent),
    showSuccess: (String message) => sections.feedback.showSuccess(message),
  ));
  sections.dormantFileActions = DebridDormantFileActions((
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
    showError: (String message) => sections.feedback.showError(message),
    copyToClipboard: (String text) => sections.feedback.copyToClipboard(text),
  ));
  sections.modernFileCard = DebridModernFileCard();
  sections.dormantSeriesBrowser = DebridDormantSeriesBrowser((
    context: view.context,
    buildSeasonsList:
        ({
          required Map<int, List<Map<String, dynamic>>> seasonMap,
          required List<int> sortedSeasons,
          required Set<int> selectedFiles,
          required Set<int> added,
          required Map<int, bool> unrestrictingFiles,
          required bool showPlayButtons,
          required RDTorrent torrent,
          required StateSetter setLocal,
          required StateSetter setBrowserState,
          required Function(int?) onSeasonChanged,
        }) => sections.dormantSeasonsList.buildSeasonsList(
          seasonMap: seasonMap,
          sortedSeasons: sortedSeasons,
          selectedFiles: selectedFiles,
          added: added,
          unrestrictingFiles: unrestrictingFiles,
          showPlayButtons: showPlayButtons,
          torrent: torrent,
          setLocal: setLocal,
          setBrowserState: setBrowserState,
          onSeasonChanged: onSeasonChanged,
        ),
    buildEpisodesList:
        ({
          required List<Map<String, dynamic>> seasonFiles,
          required Set<int> selectedFiles,
          required Set<int> added,
          required Map<int, bool> unrestrictingFiles,
          required bool showPlayButtons,
          required RDTorrent torrent,
          required StateSetter setLocal,
        }) => sections.dormantSeasonsList.buildEpisodesList(
          seasonFiles: seasonFiles,
          selectedFiles: selectedFiles,
          added: added,
          unrestrictingFiles: unrestrictingFiles,
          showPlayButtons: showPlayButtons,
          torrent: torrent,
          setLocal: setLocal,
        ),
  ));
  sections.dormantSeasonsList = DebridDormantSeasonsList((
    context: view.context,
    buildModernFileCard:
        ({
          required String fileName,
          required int fileSize,
          required bool isVideo,
          required bool isAdded,
          required bool isSelected,
          required bool isUnrestricting,
          required bool showPlayButtons,
          required VoidCallback onPlay,
          required VoidCallback onAddToPlaylist,
          required VoidCallback onDownload,
          required VoidCallback onCopy,
          required VoidCallback onSelect,
          required int index,
          required Color surface,
          String? episodeInfo,
        }) => sections.modernFileCard.buildModernFileCard(
          fileName: fileName,
          fileSize: fileSize,
          isVideo: isVideo,
          isAdded: isAdded,
          isSelected: isSelected,
          isUnrestricting: isUnrestricting,
          showPlayButtons: showPlayButtons,
          onPlay: onPlay,
          onAddToPlaylist: onAddToPlaylist,
          onDownload: onDownload,
          onCopy: onCopy,
          onSelect: onSelect,
          index: index,
          surface: surface,
          episodeInfo: episodeInfo,
        ),
    playFileOnDemand:
        (
          RDTorrent torrent,
          int index,
          StateSetter setLocal,
          Map<int, bool> unrestrictingFiles,
        ) => sections.dormantFileActions.playFileOnDemand(
          torrent,
          index,
          setLocal,
          unrestrictingFiles,
        ),
    addFileToPlaylist: (RDTorrent torrent, int index, StateSetter setLocal) =>
        sections.dormantFileActions.addFileToPlaylist(torrent, index, setLocal),
    downloadFileOnDemand:
        (
          RDTorrent torrent,
          int index,
          String fileName,
          StateSetter setLocal,
          Set<int> added,
          Map<int, bool> unrestrictingFiles,
        ) => sections.dormantFileActions.downloadFileOnDemand(
          torrent,
          index,
          fileName,
          setLocal,
          added,
          unrestrictingFiles,
        ),
    copyFileLinkOnDemand:
        (
          RDTorrent torrent,
          int index,
          StateSetter setLocal,
          Map<int, bool> unrestrictingFiles,
        ) => sections.dormantFileActions.copyFileLinkOnDemand(
          torrent,
          index,
          setLocal,
          unrestrictingFiles,
        ),
  ));
}
