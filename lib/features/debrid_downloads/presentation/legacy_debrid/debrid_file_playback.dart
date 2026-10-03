import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_file_node.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/formatters.dart';
import 'package:debrify/utils/rd_folder_tree_builder.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridFilePlaybackDeps = ({
  DebridCatalogState catalogState,
  DebridNavigationState navigationState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(String message) showError,
});

class DebridFilePlayback {
  DebridFilePlayback(this._deps);
  final DebridFilePlaybackDeps _deps;
  DebridCatalogState get _catalog => _deps.catalogState;
  DebridNavigationState get _nav => _deps.navigationState;

  /// Play a single file from the folder browser
  Future<void> playFile(RDFileNode file) async {
    if (_catalog.apiKey == null || _nav.currentTorrentId == null) return;

    try {
      // Show loading dialog
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Get download URL for the file
      final downloadUrl = await DebridService.getFileDownloadUrl(
        _catalog.apiKey!,
        _nav.currentTorrentId!,
        file.linkIndex,
      );

      // Close loading dialog
      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      // Launch video player
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: downloadUrl,
          title: file.name,
          subtitle: Formatters.formatFileSize(file.bytes ?? 0),
          viewMode: PlaylistViewMode.sorted, // Single file - not series
        ),
      );
    } catch (e) {
      if (_deps.mounted()) {
        Navigator.of(_deps.context()).pop();
        _deps.showError('Failed to play file: ${e.toString()}');
      }
    }
  }

  /// Play all videos in a folder with a playlist
  Future<void> playFolder(RDFileNode folder) async {
    if (_catalog.apiKey == null ||
        _nav.currentTorrentId == null ||
        _nav.currentTorrent == null) {
      return;
    }

    try {
      // Show loading dialog
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Collect all video files in the folder
      final videoFiles = RDFolderTreeBuilder.collectVideoFiles(folder);
      if (videoFiles.isEmpty) {
        if (_deps.mounted()) {
          Navigator.of(_deps.context()).pop();
          _deps.showError('No video files found in this folder');
        }
        return;
      }

      // Sort videos using series parser to handle episode ordering
      final fileNames = videoFiles.map((f) => f.name).toList();
      final parsedVideos = SeriesParser.parsePlaylist(fileNames);

      // Sort by season and episode if available, otherwise by name
      final sortedVideoFiles = List<RDFileNode>.from(videoFiles)
        ..sort((a, b) {
          final aIndex = fileNames.indexOf(a.name);
          final bIndex = fileNames.indexOf(b.name);

          if (aIndex >= 0 &&
              aIndex < parsedVideos.length &&
              bIndex >= 0 &&
              bIndex < parsedVideos.length) {
            final aInfo = parsedVideos[aIndex];
            final bInfo = parsedVideos[bIndex];

            // Compare seasons first
            final seasonCompare = (aInfo.season ?? 0).compareTo(
              bInfo.season ?? 0,
            );
            if (seasonCompare != 0) return seasonCompare;

            // Then compare episodes
            final episodeCompare = (aInfo.episode ?? 0).compareTo(
              bInfo.episode ?? 0,
            );
            if (episodeCompare != 0) return episodeCompare;
          }

          // Finally compare by filename
          return a.name.compareTo(b.name);
        });

      // Get the first video URL to start playing
      final firstVideoUrl = await DebridService.getFileDownloadUrl(
        _catalog.apiKey!,
        _nav.currentTorrentId!,
        sortedVideoFiles[0].linkIndex,
      );

      // Close loading dialog
      if (_deps.mounted()) Navigator.of(_deps.context()).pop();

      // Create playlist entries using restrictedLink (like _handlePlayMultiFileTorrent)
      final playlist = sortedVideoFiles.map((file) {
        return PlaylistEntry(
          title: file.name,
          url: '', // Will be loaded on demand
          restrictedLink: _nav.currentTorrent!.links[file.linkIndex],
          sizeBytes: file.bytes ?? 0,
        );
      }).toList();

      // Detect if it's a series collection
      final filenames = playlist.map((e) => e.title).toList();
      final isSeries =
          playlist.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

      // Launch video player with playlist
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: firstVideoUrl,
          title: folder.name,
          subtitle: '${videoFiles.length} videos',
          playlist: playlist,
          startIndex: 0,
          viewMode: isSeries
              ? PlaylistViewMode.series
              : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (_deps.mounted()) {
        Navigator.of(_deps.context()).pop();
        _deps.showError('Failed to play folder: ${e.toString()}');
      }
    }
  }
}
