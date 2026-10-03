import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/rd_torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';

typedef DebridMultifilePlaybackDeps = ({
  DebridCatalogState catalogState,
  BuildContext Function() context,
  bool Function() mounted,
  void Function(String message) showError,
});

class DebridMultifilePlayback {
  DebridMultifilePlayback(this._deps);
  final DebridMultifilePlaybackDeps _deps;
  bool get mounted => _deps.mounted();

  Future<void> handlePlayMultiFileTorrent(RDTorrent torrent) async {
    if (_deps.catalogState.apiKey == null) return;
    try {
      // Show loading dialog
      showDialog(
        context: _deps.context(),
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: AppThemeScope.of(context).cloud.dialogSurface,
          content: const Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…'),
            ],
          ),
        ),
      );

      // Get torrent info to access file names and links
      final torrentInfo = await DebridService.getTorrentInfo(
        _deps.catalogState.apiKey!,
        torrent.id,
      );
      final files = torrentInfo['files'] as List<dynamic>?;
      final infoLinks = (torrentInfo['links'] as List<dynamic>? ?? [])
          .map((l) => l?.toString() ?? '')
          .toList();

      if (files == null || files.isEmpty) {
        if (mounted) Navigator.of(_deps.context()).pop(); // close loading
        if (mounted) {
          _deps.showError('Failed to get file information from torrent.');
        }
        return;
      }

      // Get selected files from the torrent info
      final selectedFiles = files
          .where((file) => file['selected'] == 1)
          .toList();

      // If no selected files, use all files (they might all be selected by default)
      final filesToUse = selectedFiles.isNotEmpty ? selectedFiles : files;

      // Check if this is an archive (multiple files, single link)
      bool isArchive = false;
      if (filesToUse.length > 1 && infoLinks.length == 1) {
        isArchive = true;
      }

      if (isArchive) {
        if (mounted) Navigator.of(_deps.context()).pop(); // close loading
        if (mounted) {
          _deps.showError(
            'This is an archived torrent. Please extract it first.',
          );
        }
        return;
      }

      // Multiple individual files - create playlist with true lazy loading
      final List<PlaylistEntry> entries = [];

      // Get filenames from files with null safety - try different possible field names
      final filenames = filesToUse.map((file) {
        // Try different possible field names for filename
        String? name =
            file['name']?.toString() ??
            file['filename']?.toString() ??
            file['path']?.toString();

        // If we got a path, extract just the filename
        if (name != null && name.startsWith('/')) {
          name = name.split('/').last;
        }

        return name ?? 'Unknown File';
      }).toList();

      // Check if this is a series
      final isSeries = SeriesParser.isSeriesPlaylist(filenames);

      if (isSeries) {
        // For series: find the first episode and unrestrict only that one
        final seriesInfos = SeriesParser.parsePlaylist(filenames);

        // Find the first episode (lowest season, lowest episode)
        int firstEpisodeIndex = 0;
        int lowestSeason = 999;
        int lowestEpisode = 999;

        for (int i = 0; i < seriesInfos.length; i++) {
          final info = seriesInfos[i];
          if (info.isSeries && info.season != null && info.episode != null) {
            if (info.season! < lowestSeason ||
                (info.season! == lowestSeason &&
                    info.episode! < lowestEpisode)) {
              lowestSeason = info.season!;
              lowestEpisode = info.episode!;
              firstEpisodeIndex = i;
            }
          }
        }

        // Create playlist entries with true lazy loading
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename =
              file['name']?.toString() ??
              file['filename']?.toString() ??
              file['path']?.toString();

          // Save full path for relativePath before stripping to filename
          String? relativePath = filename;
          if (relativePath != null && relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1); // Remove leading slash
          }

          // If we got a path, extract just the filename
          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          // Check if we have a corresponding link
          if (i >= infoLinks.length) {
            continue;
          }

          if (i == firstEpisodeIndex) {
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _deps.catalogState.apiKey!,
                infoLinks[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    relativePath: relativePath,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                entries.add(
                  PlaylistEntry(
                    url: '',
                    title: finalFilename,
                    relativePath: relativePath,
                    restrictedLink: infoLinks[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              entries.add(
                PlaylistEntry(
                  url: '',
                  title: finalFilename,
                  relativePath: relativePath,
                  restrictedLink: infoLinks[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            entries.add(
              PlaylistEntry(
                url: '',
                title: finalFilename,
                relativePath: relativePath,
                restrictedLink: infoLinks[i],
                sizeBytes: sizeBytes,
              ),
            );
          }
        }
      } else {
        // For movies: unrestrict only the first video
        for (int i = 0; i < filesToUse.length; i++) {
          final file = filesToUse[i];
          String? filename =
              file['name']?.toString() ??
              file['filename']?.toString() ??
              file['path']?.toString();

          String? relativePath = filename;
          if (relativePath != null && relativePath.startsWith('/')) {
            relativePath = relativePath.substring(1);
          }

          if (filename != null && filename.startsWith('/')) {
            filename = filename.split('/').last;
          }

          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (file is Map) ? (file['bytes'] as int?) : null;

          if (i >= infoLinks.length) {
            continue;
          }

          if (i == 0) {
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                _deps.catalogState.apiKey!,
                infoLinks[i],
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: finalFilename,
                    relativePath: relativePath,
                    sizeBytes: sizeBytes,
                  ),
                );
              } else {
                entries.add(
                  PlaylistEntry(
                    url: '',
                    title: finalFilename,
                    relativePath: relativePath,
                    restrictedLink: infoLinks[i],
                    sizeBytes: sizeBytes,
                  ),
                );
              }
            } catch (e) {
              entries.add(
                PlaylistEntry(
                  url: '',
                  title: finalFilename,
                  relativePath: relativePath,
                  restrictedLink: infoLinks[i],
                  sizeBytes: sizeBytes,
                ),
              );
            }
          } else {
            entries.add(
              PlaylistEntry(
                url: '',
                title: finalFilename,
                relativePath: relativePath,
                restrictedLink: infoLinks[i],
                sizeBytes: sizeBytes,
              ),
            );
          }
        }
      }

      if (mounted) Navigator.of(_deps.context()).pop(); // close loading

      if (entries.isEmpty) {
        if (mounted) {
          _deps.showError('No playable video files found in this torrent.');
        }
        return;
      }

      if (!mounted) return;

      // Determine the initial video URL - use the first unrestricted URL or empty string
      String initialVideoUrl = '';
      if (entries.isNotEmpty && entries.first.url.isNotEmpty) {
        initialVideoUrl = entries.first.url;
      }

      // isSeries is already detected earlier in this function (line 3126)
      await VideoPlayerLauncher.push(
        _deps.context(),
        VideoPlayerLaunchArgs(
          videoUrl: initialVideoUrl,
          title: torrent.filename,
          subtitle: '${entries.length} files',
          playlist: entries,
          startIndex: 0,
          viewMode: isSeries
              ? PlaylistViewMode.series
              : PlaylistViewMode.sorted,
        ),
      );
    } catch (e) {
      if (mounted) {
        if (Navigator.of(_deps.context()).canPop()) {
          Navigator.of(_deps.context()).pop();
        }
        _deps.showError('Failed to prepare playlist: $e');
      }
    }
  }
}
