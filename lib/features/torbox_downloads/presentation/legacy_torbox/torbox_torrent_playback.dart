import 'package:debrify/features/torbox_downloads/application/torbox_file_policy.dart';
import 'package:debrify/features/torbox_downloads/models/torbox_episode_candidate.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/models/torbox_torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';

typedef TorboxTorrentPlaybackDeps = ({
  TorboxCatalogState catalogState,
  // TEMP(torbox): showComingSoon -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_magnet_actions.dart at step 4.
  void Function(String action) showComingSoon,
  bool Function() mounted,
  BuildContext Function() context,
  // TEMP(torbox): requestTorboxStreamUrl -> lib/features/torbox_downloads/presentation/legacy_torbox/torbox_stream_request.dart at step 4.
  Future<String> Function({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  })
  requestTorboxStreamUrl,
});

class TorboxTorrentPlayback {
  TorboxTorrentPlayback(this._deps);
  final TorboxTorrentPlaybackDeps _deps;

  Future<void> handlePlayTorrent(TorboxTorrent torrent) async {
    final key = _deps.catalogState.apiKey;
    if (key == null || key.isEmpty) {
      _deps.showComingSoon('Add Torbox API key');
      return;
    }

    final videoFiles = torrent.files.where((file) {
      if (file.zipped) return false;
      return torboxFileLooksLikeVideo(file);
    }).toList();

    debugPrint(
      'TorboxPlay: torrentId=${torrent.id} files=${videoFiles.length} name="${torrent.name}"',
    );

    if (videoFiles.isEmpty) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text('No playable video files found in this torrent.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await _deps.requestTorboxStreamUrl(
          apiKey: key,
          torrent: torrent,
          file: file,
        );
        if (!_deps.mounted()) return;
        await VideoPlayerLauncher.push(
          _deps.context(),
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: torrent.name,
            subtitle: Formatters.formatFileSize(file.size),
          ),
        );
      } catch (e) {
        if (!_deps.mounted()) return;
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text('Failed to play file: ${formatTorboxError(e)}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

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

    final seriesInfos = sortedCandidates
        .map((candidate) => candidate.info)
        .toList();

    debugPrint(
      'TorboxPlay: isSeries=$isSeriesCollection startIndex=$startIndex (season=${startIndex < seriesInfos.length ? seriesInfos[startIndex].season : 'n/a'} episode=${startIndex < seriesInfos.length ? seriesInfos[startIndex].episode : 'n/a'})',
    );

    String initialUrl = '';
    try {
      initialUrl = await _deps.requestTorboxStreamUrl(
        apiKey: key,
        torrent: torrent,
        file: sortedCandidates[startIndex].file,
      );
    } catch (e) {
      debugPrint(
        'TorboxDownloadsScreen: failed to prefetch initial stream for torrent=${torrent.id} fileIndex=$startIndex error=$e',
      );
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        SnackBar(
          content: Text('Failed to prepare stream: ${formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
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
          relativePath: relativePath, // Now excludes torrent name folder
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: candidate.file.id,
          sizeBytes: candidate.file.size,
          torrentHash: torrent.hash.isNotEmpty ? torrent.hash : null,
        ),
      );

      debugPrint(
        'TorboxPlay: entry[$i] title="$combinedTitle" season=${info.season} episode=${info.episode}',
      );
    }

    final totalBytes = sortedCandidates.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    debugPrint(
      'TorboxDownloadsScreen: Play torrent ${torrent.id} (${playlistEntries.length} entries, startIndex=$startIndex, isSeries=$isSeriesCollection)',
    );

    if (!_deps.mounted()) return;
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: torrent.name,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
      ),
    );
  }
}
