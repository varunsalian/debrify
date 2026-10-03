import 'package:debrify/features/pikpak_files/application/pikpak_playlist_titles.dart';
import 'package:debrify/features/pikpak_files/models/pikpak_playlist_item.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/pikpak_api_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';

typedef PikpakFolderPlaybackDeps = ({
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
  bool Function() mounted,
  BuildContext Function() context,
  PikpakCatalogState catalogState,
});

class PikpakFolderPlayback {
  PikpakFolderPlayback(this._deps);
  final PikpakFolderPlaybackDeps _deps;

  /// Play all videos in a folder (recursively scans subfolders)
  Future<void> playFolder(Map<String, dynamic> folder) async {
    final folderId = folder['id'] as String?;
    final folderName = folder['name'] ?? 'Folder';

    if (folderId == null) {
      _deps.showSnackBar('Invalid folder ID', isError: true);
      return;
    }

    // Show loading dialog
    if (!_deps.mounted()) return;
    showDialog(
      context: _deps.context(),
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
      if (_deps.mounted()) {
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }

      if (!_deps.mounted()) return;

      // Filter for videos only
      List<Map<String, dynamic>> videoFiles = allFiles.where((file) {
        final mimeType = file['mime_type'] ?? '';
        final phase = file['phase'] ?? '';
        final isVideo = mimeType.startsWith('video/');
        final isComplete = phase == 'PHASE_TYPE_COMPLETE';
        return isVideo && isComplete;
      }).toList();

      // Apply user settings filters
      if (_deps.catalogState.showVideosOnly) {
        // Already filtered for videos above
      }

      if (_deps.catalogState.ignoreSmallVideos) {
        videoFiles = videoFiles.where((file) {
          final size = file['size'];
          if (size == null) return true;
          final sizeBytes = int.tryParse(size.toString()) ?? 0;
          final sizeMB = sizeBytes / (1024 * 1024);
          return sizeMB >= 100;
        }).toList();
      }

      if (videoFiles.isEmpty) {
        _deps.showSnackBar(
          'This folder doesn\'t contain any videos',
          isError: true,
        );
        return;
      }

      // Same logic the retired TorrentSearchScreen used
      await playPikPakVideos(videoFiles, folderName);
    } catch (e) {
      print('Error playing folder: $e');
      if (_deps.mounted()) {
        // Close loading dialog if still open
        Navigator.of(_deps.context(), rootNavigator: true).pop();
      }
      _deps.showSnackBar('Failed to scan folder: $e', isError: true);
    }
  }

  /// Play PikPak videos (single or playlist) - mirrors the retired TorrentSearchScreen
  Future<void> playPikPakVideos(
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
        if (url != null && _deps.mounted()) {
          final sizeBytes = int.tryParse(file['size']?.toString() ?? '0') ?? 0;
          final title = file['name'] ?? collectionName;
          await VideoPlayerLauncher.push(
            _deps.context(),
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
        _deps.showSnackBar('Failed to play: ${e.toString()}', isError: true);
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
      _deps.showSnackBar(
        'Failed to prepare stream: ${e.toString()}',
        isError: true,
      );
      return;
    }

    if (initialUrl.isEmpty) {
      _deps.showSnackBar('Could not get streaming URL', isError: true);
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

    if (!_deps.mounted()) return;
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: collectionName,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
      ),
    );
  }
}
