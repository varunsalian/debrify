import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_episode_candidate.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/torbox_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_navigation_state.dart';

typedef TorboxFilePlaybackDeps = ({
  TorboxCatalogState catalogState,
  TorboxNavigationState navigationState,
  void Function(String message, {bool isError}) showSnackBar,
  Future<String> Function({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  })
  requestTorboxStreamUrl,
  bool Function() mounted,
  BuildContext Function() context,
});

class TorboxFilePlayback {
  TorboxFilePlayback(this._deps);
  final TorboxFilePlaybackDeps _deps;

  /// Helper: Play torbox files (reuse existing logic)
  Future<void> playTorboxFiles(
    List<TorboxFile> files,
    String collectionName,
  ) async {
    // This will reuse the existing _handlePlayTorrent logic
    // but with just the files subset
    final key = _deps.catalogState.apiKey;
    if (key == null ||
        key.isEmpty ||
        (_deps.navigationState.currentTorrent == null &&
            _deps.navigationState.currentWebDownload == null)) {
      return;
    }

    final videoFiles = files.where((file) {
      if (file.zipped) return false;
      return torboxFileLooksLikeVideo(file);
    }).toList();

    if (videoFiles.isEmpty) {
      _deps.showSnackBar('No playable video files found');
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        String streamUrl;
        if (_deps.navigationState.currentWebDownload != null) {
          streamUrl = await TorboxService.requestWebDownloadFileLink(
            apiKey: key,
            webId: _deps.navigationState.currentWebDownload!.id,
            fileId: file.id,
          );
        } else {
          streamUrl = await _deps.requestTorboxStreamUrl(
            apiKey: key,
            torrent: _deps.navigationState.currentTorrent!,
            file: file,
          );
        }
        if (!_deps.mounted()) return;
        await VideoPlayerLauncher.push(
          _deps.context(),
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: collectionName,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!_deps.mounted()) return;
        _deps.showSnackBar('Failed to play file: ${formatTorboxError(e)}');
      }
      return;
    }

    // Multiple videos - build playlist (reuse existing logic from _handlePlayTorrent)
    final candidates = videoFiles.map((file) {
      final displayName = torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      return TorboxEpisodeCandidate(
        file: file,
        displayName: displayName,
        info: info,
      );
    }).toList();

    final filenames = candidates.map((entry) => entry.displayName).toList();
    final bool isSeriesCollection =
        candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final sortedCandidates = [...candidates];
    sortedCandidates.sort((a, b) {
      final aInfo = a.info;
      final bInfo = b.info;

      final aIsSeries =
          aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
      final bIsSeries =
          bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

      if (aIsSeries && bIsSeries) {
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;

        final episodeCompare = (aInfo.episode ?? 0).compareTo(
          bInfo.episode ?? 0,
        );
        if (episodeCompare != 0) return episodeCompare;
      } else if (aIsSeries != bIsSeries) {
        return aIsSeries ? -1 : 1;
      }

      final aName = a.displayName.toLowerCase();
      final bName = b.displayName.toLowerCase();
      return aName.compareTo(bName);
    });

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = sortedCandidates.indexWhere(
        (candidate) =>
            candidate.info.isSeries &&
            candidate.info.season != null &&
            candidate.info.episode != null,
      );
      if (startIndex == -1) {
        startIndex = 0;
      }
    }

    String initialUrl = '';
    try {
      if (_deps.navigationState.currentWebDownload != null) {
        initialUrl = await TorboxService.requestWebDownloadFileLink(
          apiKey: key,
          webId: _deps.navigationState.currentWebDownload!.id,
          fileId: sortedCandidates[startIndex].file.id,
        );
      } else {
        initialUrl = await _deps.requestTorboxStreamUrl(
          apiKey: key,
          torrent: _deps.navigationState.currentTorrent!,
          file: sortedCandidates[startIndex].file,
        );
      }
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.showSnackBar('Failed to prepare stream: ${formatTorboxError(e)}');
      return;
    }

    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedCandidates.length; i++) {
      final candidate = sortedCandidates[i];
      final info = candidate.info;
      final displayName = candidate.displayName;
      final episodeLabel = formatTorboxPlaylistTitle(
        info: info,
        fallback: displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = composeTorboxEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: displayName,
      );

      // Strip first folder level (torrent name) from path
      String relativePath = candidate.file.name;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) {
        relativePath = relativePath.substring(firstSlash + 1);
      }

      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath:
              relativePath, // Now excludes torrent/web download name folder
          provider: 'torbox',
          torboxTorrentId: _deps.navigationState.currentTorrent?.id,
          torboxWebDownloadId: _deps.navigationState.currentWebDownload?.id,
          torboxFileId: candidate.file.id,
          sizeBytes: candidate.file.size,
          torrentHash:
              _deps.navigationState.currentTorrent?.hash.isNotEmpty == true
              ? _deps.navigationState.currentTorrent!.hash
              : null,
        ),
      );
    }

    final totalBytes = sortedCandidates.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
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
