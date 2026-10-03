import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_download_options.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_downloads.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_list_layouts.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playback.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_playlist_links.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_card.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_file_selection_sheet.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_initial_action.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_notifications.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_sections.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_series_layout.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_stream_request.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_enqueue.dart';
import 'package:debrify/features/torbox_downloads/presentation/legacy_torbox/torbox_torrent_zip_download.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:flutter/material.dart';

import 'torbox_composition_bindings.dart';

void wireTorboxFileWorkflows(
  TorboxSections sections,
  TorboxViewBindings view,
  TorboxCompositionStates states,
) {
  sections.initialAction = TorboxInitialAction((
    catalogState: states.catalogState,
    mounted: view.mounted,
    navigateIntoTorrent: (TorboxTorrent torrent) =>
        sections.folderNavigation.navigateIntoTorrent(torrent),
  ));
  sections.streamRequest = TorboxStreamRequest();
  sections.fileSelectionSheet = TorboxFileSelectionSheet((
    showComingSoon: (String action) =>
        sections.magnetActions.showComingSoon(action),
    context: view.context,
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
          required void Function(int season, List<int> indices) onToggleSeason,
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
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
  ));
  sections.torrentZipDownload = TorboxTorrentZipDownload((
    catalogState: states.catalogState,
    mounted: view.mounted,
    context: view.context,
  ));
  sections.downloadOptions = TorboxDownloadOptions((
    context: view.context,
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
    context: view.context,
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
    context: view.context,
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
    mounted: view.mounted,
    context: view.context,
    catalogState: states.catalogState,
    addInputState: states.addInputState,
    refresh: () => sections.catalogLoading.refresh(),
  ));
  sections.fileActions = TorboxFileActions((
    navigationState: states.navigationState,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    playTorboxFiles: (List<TorboxFile> files, String collectionName) =>
        sections.filePlayback.playTorboxFiles(files, collectionName),
    catalogState: states.catalogState,
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
    mounted: view.mounted,
    context: view.context,
    downloadSingleFile: (TorboxFile file) =>
        sections.fileDownloads.downloadSingleFile(file),
  ));
  sections.filePlaylistLinks = TorboxFilePlaylistLinks((
    navigationState: states.navigationState,
    currentFiles: () => sections.fileActions.currentFiles,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
    copyTorboxFileLink: (TorboxTorrent torrent, TorboxFile file) =>
        sections.torrentLinkActions.copyTorboxFileLink(torrent, file),
    catalogState: states.catalogState,
    mounted: view.mounted,
  ));
  sections.fileDownloads = TorboxFileDownloads((
    catalogState: states.catalogState,
    navigationState: states.navigationState,
    mounted: view.mounted,
    context: view.context,
    showSnackBar: (String message, {bool isError = true}) =>
        sections.notifications.showSnackBar(message, isError: isError),
  ));
  sections.filePlayback = TorboxFilePlayback((
    catalogState: states.catalogState,
    navigationState: states.navigationState,
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
    mounted: view.mounted,
    context: view.context,
  ));
  sections.notifications = TorboxNotifications((
    mounted: view.mounted,
    context: view.context,
  ));
}
