import 'package:flutter/material.dart';

import 'storage_service.dart';
import 'debrid_service.dart';
import 'torbox_service.dart';
import 'video_player_launcher.dart';
import 'main_page_bridge.dart';
import 'pikpak_api_service.dart';
import 'webdav_service.dart';
import '../utils/series_parser.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../models/playlist_view_mode.dart';
import '../models/rd_file_node.dart';
import '../models/torbox_torrent.dart';
import '../models/torbox_file.dart';
import '../models/webdav_item.dart';
import '../screens/video_player_screen.dart';

/// Standalone service for playing playlist items.
/// Extracted from PlaylistScreen so it can be called from any screen.
/// All methods accept BuildContext for UI operations (dialogs, snackbars, navigation).
class PlaylistPlayerService {
  PlaylistPlayerService._();

  /// Play a playlist item. Routes to the correct provider handler.
  static Future<void> play(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    await StorageService.updatePlaylistItemLastPlayed(item);

    // Re-read from storage to pick up any fields saved by other screens
    // (e.g. imdbId saved by View Files or video player)
    final freshItems = await StorageService.getPlaylistItemsRaw();
    final dedupeKey = StorageService.computePlaylistDedupeKey(item);
    final freshItem = freshItems.firstWhere(
      (e) => StorageService.computePlaylistDedupeKey(e) == dedupeKey,
      orElse: () => item,
    );

    final String title = (freshItem['title'] as String?) ?? 'Video';
    final String provider = ((freshItem['provider'] as String?) ?? 'realdebrid')
        .toLowerCase();
    if (provider == 'torbox') {
      await _playTorboxItem(context, freshItem, fallbackTitle: title);
      return;
    }
    if (provider == 'pikpak') {
      await _playPikPakItem(context, freshItem, fallbackTitle: title);
      return;
    }
    if (provider == 'webdav') {
      await _playWebDavItem(context, freshItem, fallbackTitle: title);
      return;
    }
    await _playRealDebridItem(context, freshItem, title: title);
  }

  // ── Real-Debrid ──────────────────────────────────────────────────────────

  static Future<void> _playRealDebridItem(
    BuildContext context,
    Map<String, dynamic> item, {
    required String title,
  }) async {
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? torrentHash = item['torrent_hash'] as String?;
    final String kind = (item['kind'] as String?) ?? 'single';

    // Handle single file torrents
    if (kind == 'single') {
      final String? restrictedLink = item['restrictedLink'] as String?;
      final String? apiKey = await StorageService.getApiKey();
      if (restrictedLink != null &&
          restrictedLink.isNotEmpty &&
          apiKey != null &&
          apiKey.isNotEmpty) {
        try {
          final unrestrictResult = await DebridService.unrestrictLink(
            apiKey,
            restrictedLink,
          );
          final downloadLink = unrestrictResult['download']?.toString() ?? '';
          final mimeType = unrestrictResult['mimeType']?.toString() ?? '';
          if (downloadLink.isNotEmpty) {
            if (FileUtils.isVideoMimeType(mimeType)) {
              if (!context.mounted) return;
              MainPageBridge.notifyPlayerLaunching();
              final savedViewModeString =
                  await StorageService.getPlaylistItemViewMode(item);
              final viewMode = PlaylistViewModeStorage.fromStorageString(
                savedViewModeString,
              );
              await VideoPlayerLauncher.push(
                context,
                VideoPlayerLaunchArgs(
                  videoUrl: downloadLink,
                  title: title,
                  rdTorrentId: rdTorrentId,
                  viewMode: viewMode,
                  contentImdbId: item['imdbId'] as String?,
                  contentType: item['contentType'] as String?,
                  suppressTraktAutoSync: true,
                ),
              );
            } else {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selected file is not a video')),
              );
            }
          } else {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to unrestrict link')),
            );
          }
        } catch (e) {
          if (!context.mounted) return;
          if (torrentHash != null && torrentHash.isNotEmpty) {
            await _attemptRecovery(context, item);
          } else {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
          }
        }
        return;
      }
    }

    // Handle collection torrents (multi-file/series)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      final String? apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) return;

      try {
        if (!context.mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: Color(0xFF1E293B),
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text(
                  'Preparing playlist…',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        );

        final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
        final allFiles = (info['files'] as List<dynamic>? ?? const []);
        if (allFiles.isEmpty) {
          if (context.mounted && Navigator.of(context).canPop())
            Navigator.of(context).pop();
          return;
        }

        final links = (info['links'] as List<dynamic>? ?? const []);

        // Archive check
        final selectedFiles = allFiles
            .where((f) => f['selected'] == 1)
            .toList();
        final filesToUse = selectedFiles.isNotEmpty ? selectedFiles : allFiles;
        if (filesToUse.length > 1 && links.length == 1) {
          if (context.mounted && Navigator.of(context).canPop())
            Navigator.of(context).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This is an archived torrent. Please extract it first.',
                ),
              ),
            );
          }
          return;
        }

        final rootNode = RDFolderTreeBuilder.buildTree(
          allFiles.cast<Map<String, dynamic>>(),
        );
        final videoFiles = RDFolderTreeBuilder.collectVideoFiles(rootNode);

        if (videoFiles.isEmpty) {
          if (context.mounted && Navigator.of(context).canPop())
            Navigator.of(context).pop();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No playable video files found in this torrent.'),
              ),
            );
          }
          return;
        }

        final savedViewModeString =
            await StorageService.getPlaylistItemViewMode(item);

        // Apply Sort A-Z sorting if in sorted mode
        if (savedViewModeString == 'sortedAZ') {
          _sortRdVideoFilesAZ(videoFiles);
        }

        // Detect first episode index for series
        final filenames = videoFiles.map((f) => f.name).toList();
        final bool isSeries = SeriesParser.isSeriesPlaylist(filenames);
        int firstIndex = 0;
        if (isSeries) {
          final seriesInfos = SeriesParser.parsePlaylist(filenames);
          int lowestSeason = 999, lowestEpisode = 999;
          for (int i = 0; i < seriesInfos.length; i++) {
            final info = seriesInfos[i];
            if (info.isSeries && info.season != null && info.episode != null) {
              if (info.season! < lowestSeason ||
                  (info.season! == lowestSeason &&
                      info.episode! < lowestEpisode)) {
                lowestSeason = info.season!;
                lowestEpisode = info.episode!;
                firstIndex = i;
              }
            }
          }
        }

        final List<PlaylistEntry> entries = [];
        for (int i = 0; i < videoFiles.length; i++) {
          final file = videoFiles[i];
          final linkIndex = file.linkIndex;
          if (linkIndex < 0 || linkIndex >= links.length) continue;
          final restrictedLink = links[linkIndex]?.toString() ?? '';

          if (i == firstIndex) {
            try {
              final unrestrictResult = await DebridService.unrestrictLink(
                apiKey,
                restrictedLink,
              );
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(
                  PlaylistEntry(
                    url: url,
                    title: file.name,
                    relativePath: file.relativePath ?? file.path,
                    rdTorrentId: rdTorrentId,
                    rdLinkIndex: linkIndex,
                    torrentHash: torrentHash,
                    sizeBytes: file.bytes,
                  ),
                );
              } else {
                entries.add(
                  PlaylistEntry(
                    url: '',
                    title: file.name,
                    relativePath: file.relativePath ?? file.path,
                    restrictedLink: restrictedLink,
                    rdTorrentId: rdTorrentId,
                    rdLinkIndex: linkIndex,
                    torrentHash: torrentHash,
                    sizeBytes: file.bytes,
                  ),
                );
              }
            } catch (_) {
              entries.add(
                PlaylistEntry(
                  url: '',
                  title: file.name,
                  relativePath: file.relativePath ?? file.path,
                  restrictedLink: restrictedLink,
                  rdTorrentId: rdTorrentId,
                  rdLinkIndex: linkIndex,
                  torrentHash: torrentHash,
                  sizeBytes: file.bytes,
                ),
              );
            }
          } else {
            entries.add(
              PlaylistEntry(
                url: '',
                title: file.name,
                relativePath: file.relativePath ?? file.path,
                restrictedLink: restrictedLink,
                rdTorrentId: rdTorrentId,
                rdLinkIndex: linkIndex,
                torrentHash: torrentHash,
                sizeBytes: file.bytes,
              ),
            );
          }
        }

        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (entries.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No playable video files found in this torrent.'),
              ),
            );
          }
          return;
        }

        String initialVideoUrl = '';
        if (entries.first.url.isNotEmpty) initialVideoUrl = entries.first.url;

        if (!context.mounted) return;
        MainPageBridge.notifyPlayerLaunching();
        final viewMode = PlaylistViewModeStorage.fromStorageString(
          savedViewModeString,
        );
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: initialVideoUrl,
            title: title,
            subtitle: '${entries.length} files',
            playlist: entries,
            startIndex: 0,
            rdTorrentId: rdTorrentId,
            viewMode: viewMode,
            contentImdbId: item['imdbId'] as String?,
            contentType: item['contentType'] as String?,
            suppressTraktAutoSync: true,
          ),
        );
      } catch (e) {
        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (torrentHash != null && torrentHash.isNotEmpty) {
          await _attemptRecovery(context, item);
        }
      }
      return;
    }

    // Fallback: open single video directly (legacy items)
    final String url = (item['url'] as String?) ?? '';
    if (!context.mounted) return;
    MainPageBridge.notifyPlayerLaunching();
    final savedViewModeString = await StorageService.getPlaylistItemViewMode(
      item,
    );
    final viewMode = PlaylistViewModeStorage.fromStorageString(
      savedViewModeString,
    );
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: title,
        rdTorrentId: rdTorrentId,
        viewMode: viewMode,
        contentImdbId: item['imdbId'] as String?,
        contentType: item['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  // ── Torbox ───────────────────────────────────────────────────────────────

  static Future<void> _playTorboxItem(
    BuildContext context,
    Map<String, dynamic> item, {
    required String fallbackTitle,
  }) async {
    final String? apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Add your Torbox API key in Settings to play playlist items.',
          ),
        ),
      );
      return;
    }

    final int? torrentId = _asInt(item['torboxTorrentId']);
    if (torrentId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing Torbox torrent information.')),
      );
      return;
    }

    final String kind = (item['kind'] as String?) ?? 'single';

    if (kind == 'single') {
      final int? fileId = _asInt(item['torboxFileId']);
      if (fileId == null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing Torbox file information.')),
        );
        return;
      }

      try {
        final streamUrl = await TorboxService.requestFileDownloadLink(
          apiKey: apiKey,
          torrentId: torrentId,
          fileId: fileId,
        );

        final int? sizeBytes = _asInt(item['sizeBytes']);
        final String? subtitle = sizeBytes != null && sizeBytes > 0
            ? Formatters.formatFileSize(sizeBytes)
            : null;
        final String resolvedTitle =
            (item['title'] as String?)?.isNotEmpty == true
            ? item['title'] as String
            : fallbackTitle;

        if (!context.mounted) return;
        MainPageBridge.notifyPlayerLaunching();
        final savedViewModeString =
            await StorageService.getPlaylistItemViewMode(item);
        final viewMode = PlaylistViewModeStorage.fromStorageString(
          savedViewModeString,
        );
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: resolvedTitle,
            subtitle: subtitle,
            torboxTorrentId: torrentId.toString(),
            viewMode: viewMode,
            contentImdbId: item['imdbId'] as String?,
            contentType: item['contentType'] as String?,
            suppressTraktAutoSync: true,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to prepare Torbox stream: ${_formatTorboxError(e)}',
            ),
          ),
        );
      }
      return;
    }

    // Collection
    if (!context.mounted) return;
    bool dialogOpen = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogOpen = true;
        return const AlertDialog(
          backgroundColor: Color(0xFF1E293B),
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text(
                'Preparing playlist…',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );

    final previousKey = StorageService.computePlaylistDedupeKey(item);

    try {
      TorboxTorrent? torrent = await TorboxService.getTorrentById(
        apiKey,
        torrentId,
      );

      if (torrent == null) {
        torrent = await _recoverTorboxPlaylistTorrent(
          apiKey: apiKey,
          item: item,
          context: context,
        );
        if (torrent == null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Torbox torrent is no longer available.'),
              ),
            );
          }
          return;
        }
      }

      item['torboxTorrentId'] = torrent.id;
      if (torrent.hash.isNotEmpty) {
        item['torrent_hash'] = torrent.hash;
      }

      var files = torrent.files
          .where((file) => !file.zipped && _torboxFileLooksLikeVideo(file))
          .toList();

      final dynamic storedIdsRaw = item['torboxFileIds'];
      if (storedIdsRaw is List && storedIdsRaw.isNotEmpty) {
        final selectedIds = storedIdsRaw
            .map((value) => _asInt(value))
            .whereType<int>()
            .toSet();
        if (selectedIds.isNotEmpty) {
          final filtered = files
              .where((file) => selectedIds.contains(file.id))
              .toList();
          if (filtered.isNotEmpty) files = filtered;
        }
      }

      if (files.isEmpty) {
        files = torrent.files
            .where((file) => !file.zipped && _torboxFileLooksLikeVideo(file))
            .toList();
      }

      if (files.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No playable Torbox video files found.'),
          ),
        );
        return;
      }

      final savedViewModeString = await StorageService.getPlaylistItemViewMode(
        item,
      );

      if (savedViewModeString == 'sortedAZ') {
        _sortTorboxFilesAZ(files);
      }

      final entries = _buildTorboxPlaylistEntries(
        torrent: torrent,
        files: files,
        viewMode: savedViewModeString,
      );
      final playlistEntries = entries.playlistEntries;
      final startIndex = entries.startIndex;
      final subtitle = entries.subtitle;

      String initialUrl = '';
      try {
        initialUrl = await TorboxService.requestFileDownloadLink(
          apiKey: apiKey,
          torrentId: torrent.id,
          fileId: playlistEntries[startIndex].torboxFileId!,
        );
      } catch (e) {
        debugPrint('PlaylistPlayerService: Torbox initial link failed: $e');
      }

      if (initialUrl.isNotEmpty) {
        playlistEntries[startIndex] = PlaylistEntry(
          url: initialUrl,
          title: playlistEntries[startIndex].title,
          relativePath: playlistEntries[startIndex].relativePath,
          provider: playlistEntries[startIndex].provider,
          torboxTorrentId: playlistEntries[startIndex].torboxTorrentId,
          torboxFileId: playlistEntries[startIndex].torboxFileId,
          torrentHash: playlistEntries[startIndex].torrentHash,
          sizeBytes: playlistEntries[startIndex].sizeBytes,
        );
      }

      if ((item['kind'] ?? 'single') == 'single') {
        item['torboxFileId'] =
            playlistEntries[startIndex].torboxFileId ?? item['torboxFileId'];
        item.remove('torboxFileIds');
      } else {
        final fileIds = playlistEntries
            .map((entry) => entry.torboxFileId)
            .whereType<int>()
            .toList();
        if (fileIds.isNotEmpty) item['torboxFileIds'] = fileIds;
        item['count'] = playlistEntries.length;
      }

      await _persistPlaylistItemChanges(item, previousKey);

      if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }

      if (!context.mounted) return;
      MainPageBridge.notifyPlayerLaunching();
      final viewMode = PlaylistViewModeStorage.fromStorageString(
        savedViewModeString,
      );
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: initialUrl,
          title: fallbackTitle,
          subtitle: subtitle,
          playlist: playlistEntries,
          startIndex: startIndex,
          torboxTorrentId: torrentId.toString(),
          viewMode: viewMode,
          contentImdbId: item['imdbId'] as String?,
          contentType: item['contentType'] as String?,
          suppressTraktAutoSync: true,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to prepare Torbox playlist: ${_formatTorboxError(e)}',
          ),
        ),
      );
    } finally {
      if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  // ── PikPak ───────────────────────────────────────────────────────────────

  static Future<void> _playPikPakItem(
    BuildContext context,
    Map<String, dynamic> item, {
    required String fallbackTitle,
  }) async {
    final pikpak = PikPakApiService.instance;

    if (!await pikpak.isAuthenticated()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please login to PikPak in Settings to play playlist items.',
          ),
        ),
      );
      return;
    }

    final String kind = (item['kind'] as String?) ?? 'single';

    // Single items
    if (kind == 'single') {
      final String? pikpakFileId = item['pikpakFileId'] as String?;
      if (pikpakFileId == null || pikpakFileId.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing PikPak file information.')),
        );
        return;
      }

      try {
        final Map<String, dynamic>? storedFile =
            item['pikpakFile'] as Map<String, dynamic>?;
        final bool hasStoredMetadata =
            storedFile != null && storedFile.isNotEmpty;

        final fileData = await pikpak.getFileDetails(pikpakFileId);
        final url = pikpak.getStreamingUrl(fileData);

        if (url == null || url.isEmpty) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to get PikPak streaming URL.'),
            ),
          );
          return;
        }

        final String resolvedTitle = hasStoredMetadata
            ? ((storedFile['name'] as String?)?.isNotEmpty == true
                  ? storedFile['name'] as String
                  : fallbackTitle)
            : ((fileData['name'] as String?)?.isNotEmpty == true
                  ? fileData['name'] as String
                  : fallbackTitle);

        final int? sizeBytes = hasStoredMetadata
            ? _asInt(storedFile['size'])
            : _asInt(fileData['size']);
        final String? subtitle = sizeBytes != null && sizeBytes > 0
            ? Formatters.formatFileSize(sizeBytes)
            : null;

        if (!context.mounted) return;
        MainPageBridge.notifyPlayerLaunching();
        final savedViewModeString =
            await StorageService.getPlaylistItemViewMode(item);
        final viewMode = PlaylistViewModeStorage.fromStorageString(
          savedViewModeString,
        );

        final singleFileRelativePath = hasStoredMetadata
            ? ((storedFile['_fullPath'] as String?) ??
                  (storedFile['name'] as String?))
            : (fileData['name'] as String?);

        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: url,
            title: resolvedTitle,
            subtitle: subtitle,
            playlist: [
              PlaylistEntry(
                url: url,
                title: resolvedTitle,
                relativePath: singleFileRelativePath,
                provider: 'pikpak',
                pikpakFileId: pikpakFileId,
                sizeBytes: sizeBytes,
              ),
            ],
            startIndex: 0,
            pikpakCollectionId: pikpakFileId,
            viewMode: viewMode,
            contentImdbId: item['imdbId'] as String?,
            contentType: item['contentType'] as String?,
            suppressTraktAutoSync: true,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to play PikPak file: ${_formatPikPakError(e)}',
            ),
          ),
        );
      }
      return;
    }

    // Collection items
    final List<dynamic>? pikpakFiles = item['pikpakFiles'] as List<dynamic>?;
    final List<dynamic>? pikpakFileIds =
        item['pikpakFileIds'] as List<dynamic>?;

    if ((pikpakFiles == null || pikpakFiles.isEmpty) &&
        (pikpakFileIds == null || pikpakFileIds.isEmpty)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing PikPak files information.')),
      );
      return;
    }

    final bool hasStoredMetadata =
        pikpakFiles != null && pikpakFiles.isNotEmpty;
    if (!context.mounted) return;
    bool dialogOpen = false;

    if (!hasStoredMetadata) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          dialogOpen = true;
          return const AlertDialog(
            backgroundColor: Color(0xFF1E293B),
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text(
                  'Preparing playlist...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          );
        },
      );
    }

    try {
      final List<Map<String, dynamic>> videoFiles = [];

      if (hasStoredMetadata) {
        for (final file in pikpakFiles) {
          if (file is Map<String, dynamic>) {
            final mimeType = (file['mime_type'] as String?) ?? '';
            final fileName = (file['name'] as String?) ?? '';
            if (mimeType.startsWith('video/') ||
                FileUtils.isVideoFile(fileName)) {
              videoFiles.add(file);
            }
          }
        }
      } else {
        for (final fileId in pikpakFileIds!) {
          try {
            final fileData = await pikpak.getFileMetadata(fileId.toString());
            final mimeType = (fileData['mime_type'] as String?) ?? '';
            final fileName = (fileData['name'] as String?) ?? '';
            if (mimeType.startsWith('video/') ||
                FileUtils.isVideoFile(fileName)) {
              videoFiles.add(fileData);
            }
          } catch (e) {
            debugPrint(
              'PlaylistPlayerService: Failed to get PikPak file metadata for $fileId: $e',
            );
          }
        }
      }

      if (videoFiles.isEmpty) {
        if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          dialogOpen = false;
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No playable PikPak video files found.'),
          ),
        );
        return;
      }

      final List<_PikPakPlaylistCandidate> candidates = [];
      for (final file in videoFiles) {
        final displayName = (file['name'] as String?) ?? 'Unknown';
        final info = SeriesParser.parseFilename(displayName);
        candidates.add(
          _PikPakPlaylistCandidate(
            file: file,
            info: info,
            displayName: displayName,
          ),
        );
      }

      final filenames = candidates.map((c) => c.displayName).toList();
      final bool isSeriesCollection =
          candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

      final savedViewModeString = await StorageService.getPlaylistItemViewMode(
        item,
      );

      // Sort
      if (savedViewModeString == 'sortedAZ') {
        _sortPikPakCandidatesAZ(candidates);
      } else if (isSeriesCollection) {
        candidates.sort((a, b) {
          final aInfo = a.info;
          final bInfo = b.info;
          final aIsSeries =
              aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
          final bIsSeries =
              bInfo.isSeries && bInfo.season != null && bInfo.episode != null;
          if (aIsSeries && bIsSeries) {
            final seasonCompare = (aInfo.season ?? 0).compareTo(
              bInfo.season ?? 0,
            );
            if (seasonCompare != 0) return seasonCompare;
            final episodeCompare = (aInfo.episode ?? 0).compareTo(
              bInfo.episode ?? 0,
            );
            if (episodeCompare != 0) return episodeCompare;
          } else if (aIsSeries != bIsSeries) {
            return aIsSeries ? -1 : 1;
          }
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });
      } else {
        candidates.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
      }

      // Find first episode
      int startIndex = 0;
      if (isSeriesCollection) {
        final seriesInfos = candidates.map((c) => c.info).toList();
        startIndex = _findFirstEpisodeIndex(seriesInfos);
      }
      if (startIndex < 0 || startIndex >= candidates.length) startIndex = 0;

      // Resolve initial URL
      String initialUrl = '';
      try {
        final firstFileId = candidates[startIndex].file['id'] as String?;
        if (firstFileId != null) {
          final fullData = await pikpak.getFileDetails(firstFileId);
          initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
        }
      } catch (e) {
        debugPrint(
          'PlaylistPlayerService: PikPak initial URL resolution failed: $e',
        );
      }

      if (initialUrl.isEmpty) {
        if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          dialogOpen = false;
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get PikPak streaming URL.')),
        );
        return;
      }

      // Build PlaylistEntry list
      final List<PlaylistEntry> playlistEntries = [];
      for (int i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        final seriesInfo = candidate.info;
        final episodeLabel = _formatPikPakPlaylistTitle(
          info: seriesInfo,
          fallback: candidate.displayName,
          isSeriesCollection: isSeriesCollection,
        );
        final combinedTitle = _composePikPakEntryTitle(
          seriesTitle: seriesInfo.title,
          episodeLabel: episodeLabel,
          isSeriesCollection: isSeriesCollection,
          fallback: candidate.displayName,
        );

        final fileId = candidate.file['id'] as String?;
        final sizeBytes = _asInt(candidate.file['size']);
        final relativePath =
            (candidate.file['_fullPath'] as String?) ??
            (candidate.file['name'] as String?);

        playlistEntries.add(
          PlaylistEntry(
            url: i == startIndex ? initialUrl : '',
            title: combinedTitle,
            relativePath: relativePath,
            provider: 'pikpak',
            pikpakFileId: fileId,
            sizeBytes: sizeBytes,
          ),
        );
      }

      final totalBytes = candidates.fold<int>(
        0,
        (sum, c) => sum + (_asInt(c.file['size']) ?? 0),
      );
      final subtitle =
          '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

      if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }

      if (!context.mounted) return;

      final firstFileId = candidates.isNotEmpty
          ? (candidates[0].file['id'] as String?)
          : null;

      MainPageBridge.notifyPlayerLaunching();
      final viewMode = PlaylistViewModeStorage.fromStorageString(
        savedViewModeString,
      );
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: initialUrl,
          title: fallbackTitle,
          subtitle: subtitle,
          playlist: playlistEntries,
          startIndex: startIndex,
          pikpakCollectionId: firstFileId,
          viewMode: viewMode,
          contentImdbId: item['imdbId'] as String?,
          contentType: item['contentType'] as String?,
          suppressTraktAutoSync: true,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to prepare PikPak playlist: ${_formatPikPakError(e)}',
          ),
        ),
      );
    } finally {
      if (dialogOpen && context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  // ── WebDAV ─────────────────────────────────────────────────────────────────

  static Future<void> _playWebDavItem(
    BuildContext context,
    Map<String, dynamic> item, {
    required String fallbackTitle,
  }) async {
    final config = await _resolveWebDavConfig(item);
    if (!context.mounted) return;
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WebDAV server is no longer configured.')),
      );
      return;
    }

    final String kind = (item['kind'] as String?) ?? 'single';
    if (kind == 'single') {
      await _playSingleWebDavItem(context, item, config, fallbackTitle);
      return;
    }

    await _playWebDavCollection(context, item, config, fallbackTitle);
  }

  static Future<void> _playSingleWebDavItem(
    BuildContext context,
    Map<String, dynamic> item,
    WebDavConfig config,
    String fallbackTitle,
  ) async {
    final file = _asStringDynamicMap(item['webdavFile']);
    final path = (item['webdavPath'] ?? file?['path'] ?? '').toString().trim();
    if (path.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing WebDAV file information.')),
      );
      return;
    }

    final title = _webDavFileName(file, fallbackTitle);
    final sizeBytes = _asInt(item['sizeBytes'] ?? file?['sizeBytes']);
    final url = WebDavService.directUrl(config, path);
    final savedViewModeString = await StorageService.getPlaylistItemViewMode(
      item,
    );
    final viewMode =
        PlaylistViewModeStorage.fromStorageString(savedViewModeString) ??
        PlaylistViewMode.sorted;

    if (!context.mounted) return;
    await _openWebDavPlayer(
      context,
      config,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: title,
        subtitle: sizeBytes != null && sizeBytes > 0
            ? Formatters.formatFileSize(sizeBytes)
            : null,
        playlist: [
          PlaylistEntry(
            url: url,
            title: title,
            relativePath: path,
            provider: 'webdav',
            sizeBytes: sizeBytes,
          ),
        ],
        startIndex: 0,
        viewMode: viewMode,
        httpHeaders: WebDavService.authHeaders(config),
        contentImdbId: item['imdbId'] as String?,
        contentType: item['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  static Future<void> _playWebDavCollection(
    BuildContext context,
    Map<String, dynamic> item,
    WebDavConfig config,
    String fallbackTitle,
  ) async {
    final rawFiles = item['webdavFiles'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing WebDAV files information.')),
      );
      return;
    }

    final candidates = <_WebDavPlaylistCandidate>[];
    for (final raw in rawFiles) {
      final file = _asStringDynamicMap(raw);
      if (file == null) continue;
      final path = (file['path'] ?? '').toString().trim();
      if (path.isEmpty) continue;
      final name = _webDavFileName(file, path.split('/').last);
      if (!FileUtils.isVideoFile(name)) continue;
      candidates.add(
        _WebDavPlaylistCandidate(
          file: file,
          info: SeriesParser.parseFilename(name),
          displayName: name,
        ),
      );
    }

    if (candidates.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playable WebDAV video files found.')),
      );
      return;
    }

    final filenames = candidates
        .map((candidate) => candidate.displayName)
        .toList();
    final bool isSeriesCollection =
        candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);
    final savedViewModeString = await StorageService.getPlaylistItemViewMode(
      item,
    );

    if (savedViewModeString == 'sortedAZ') {
      candidates.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    } else if (savedViewModeString != 'raw' && isSeriesCollection) {
      candidates.sort((a, b) {
        final aInfo = a.info;
        final bInfo = b.info;
        final aIsSeries =
            aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
        final bIsSeries =
            bInfo.isSeries && bInfo.season != null && bInfo.episode != null;
        if (aIsSeries && bIsSeries) {
          final seasonCompare = (aInfo.season ?? 0).compareTo(
            bInfo.season ?? 0,
          );
          if (seasonCompare != 0) return seasonCompare;
          final episodeCompare = (aInfo.episode ?? 0).compareTo(
            bInfo.episode ?? 0,
          );
          if (episodeCompare != 0) return episodeCompare;
        } else if (aIsSeries != bIsSeries) {
          return aIsSeries ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    }

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = _findFirstEpisodeIndex(
        candidates.map((candidate) => candidate.info).toList(),
      );
    }
    if (startIndex < 0 || startIndex >= candidates.length) startIndex = 0;

    final playlistEntries = <PlaylistEntry>[];
    for (final candidate in candidates) {
      final file = candidate.file;
      final path = (file['path'] ?? '').toString();
      final seriesInfo = candidate.info;
      final episodeLabel = _formatWebDavPlaylistTitle(
        info: seriesInfo,
        fallback: candidate.displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final title = _composeWebDavEntryTitle(
        seriesTitle: seriesInfo.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: candidate.displayName,
      );

      playlistEntries.add(
        PlaylistEntry(
          url: WebDavService.directUrl(config, path),
          title: title,
          relativePath: path,
          provider: 'webdav',
          sizeBytes: _asInt(file['sizeBytes']),
        ),
      );
    }

    final totalBytes = playlistEntries.fold<int>(
      0,
      (sum, entry) => sum + (entry.sizeBytes ?? 0),
    );
    final subtitle = totalBytes > 0
        ? '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}'
        : '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'}';
    final viewMode =
        PlaylistViewModeStorage.fromStorageString(savedViewModeString) ??
        (isSeriesCollection
            ? PlaylistViewMode.series
            : PlaylistViewMode.sorted);

    if (!context.mounted) return;
    await _openWebDavPlayer(
      context,
      config,
      VideoPlayerLaunchArgs(
        videoUrl: playlistEntries[startIndex].url,
        title: fallbackTitle,
        subtitle: subtitle,
        playlist: playlistEntries,
        startIndex: startIndex,
        viewMode: viewMode,
        httpHeaders: WebDavService.authHeaders(config),
        contentImdbId: item['imdbId'] as String?,
        contentType: item['contentType'] as String?,
        suppressTraktAutoSync: true,
      ),
    );
  }

  static Future<WebDavConfig?> _resolveWebDavConfig(
    Map<String, dynamic> item,
  ) async {
    final serverId = (item['webdavServerId'] ?? '').toString();
    final baseUrl = (item['webdavBaseUrl'] ?? '').toString();
    final servers = await StorageService.getWebDavServers();
    for (final server in servers) {
      if (serverId.isNotEmpty && server.id == serverId) return server;
    }
    for (final server in servers) {
      if (baseUrl.isNotEmpty && server.baseUrl == baseUrl) return server;
    }
    if (serverId.isEmpty && baseUrl.isEmpty && servers.length == 1) {
      return servers.first;
    }
    return null;
  }

  static Future<void> _openWebDavPlayer(
    BuildContext context,
    WebDavConfig config,
    VideoPlayerLaunchArgs args,
  ) async {
    MainPageBridge.notifyPlayerLaunching();
    if (_hasWebDavCredentials(config)) {
      await Navigator.of(context).push<Map<String, dynamic>?>(
        MaterialPageRoute(builder: (_) => args.toWidget()),
      );
      return;
    }
    await VideoPlayerLauncher.push(context, args);
  }

  static bool _hasWebDavCredentials(WebDavConfig config) {
    return config.username.isNotEmpty || config.password.isNotEmpty;
  }

  static Map<String, dynamic>? _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static String _webDavFileName(Map<String, dynamic>? file, String fallback) {
    final name = (file?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    return fallback;
  }

  static String _formatWebDavPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }
    return fallback;
  }

  static String _composeWebDavEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty) {
      return '$cleanSeries $episodeLabel';
    }
    return fallback;
  }

  // ── Recovery ─────────────────────────────────────────────────────────────

  static Future<void> _attemptRecovery(
    BuildContext context,
    Map<String, dynamic> item,
  ) async {
    final String? torrentHash = item['torrent_hash'] as String?;
    final String? apiKey = await StorageService.getApiKey();

    if (torrentHash == null ||
        torrentHash.isEmpty ||
        apiKey == null ||
        apiKey.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content no longer available')),
      );
      return;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text(
              'Reconstructing playlist...',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    try {
      final magnetLink = 'magnet:?xt=urn:btih:$torrentHash';
      final result = await DebridService.addTorrentToDebridPreferVideos(
        apiKey,
        magnetLink,
      );
      final newTorrentId = result['torrentId'] as String?;
      final newLinks = result['links'] as List<dynamic>? ?? [];

      if (newTorrentId != null &&
          newTorrentId.isNotEmpty &&
          newLinks.isNotEmpty) {
        await _updatePlaylistItemWithNewTorrent(item, newTorrentId, newLinks);
        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        await play(context, item);
      } else {
        if (context.mounted && Navigator.of(context).canPop())
          Navigator.of(context).pop();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Content no longer available')),
        );
      }
    } catch (e) {
      if (context.mounted && Navigator.of(context).canPop())
        Navigator.of(context).pop();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content no longer available')),
      );
    }
  }

  static Future<void> _updatePlaylistItemWithNewTorrent(
    Map<String, dynamic> item,
    String newTorrentId,
    List<dynamic> newLinks,
  ) async {
    item['rdTorrentId'] = newTorrentId;
    if (item['kind'] == 'single' && newLinks.isNotEmpty) {
      item['restrictedLink'] = newLinks[0].toString();
    }

    final items = await StorageService.getPlaylistItemsRaw();
    final itemKey = StorageService.computePlaylistDedupeKey(item);
    final itemIndex = items.indexWhere(
      (playlistItem) =>
          StorageService.computePlaylistDedupeKey(playlistItem) == itemKey,
    );

    if (itemIndex != -1) {
      items[itemIndex] = item;
      await StorageService.savePlaylistItemsRaw(items);
    }
  }

  static Future<TorboxTorrent?> _recoverTorboxPlaylistTorrent({
    required String apiKey,
    required Map<String, dynamic> item,
    required BuildContext context,
  }) async {
    final hash = (item['torrent_hash'] ?? item['torrentHash'])?.toString();
    if (hash == null || hash.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot recover Torbox torrent – missing hash.'),
          ),
        );
      }
      return null;
    }

    try {
      final response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: 'magnet:?xt=urn:btih:$hash',
        seed: true,
        allowZip: true,
        addOnlyIfCached: true,
      );

      final success = response['success'] as bool? ?? false;
      if (!success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Torbox recovery failed: ${response['error']?.toString() ?? 'unknown error'}',
              ),
            ),
          );
        }
        return null;
      }

      final data = response['data'];
      final newId = _asIntMapValue(data, 'torrent_id');
      if (newId == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Torbox recovery failed: missing torrent id.'),
            ),
          );
        }
        return null;
      }

      TorboxTorrent? recovered;
      for (int attempt = 0; attempt < 5; attempt++) {
        recovered = await TorboxService.getTorrentById(apiKey, newId);
        if (recovered != null) break;
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (recovered == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Torbox recovery pending – try again in a moment.'),
            ),
          );
        }
        return null;
      }

      item['torboxTorrentId'] = recovered.id;
      item['torrent_hash'] = hash;
      return recovered;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Torbox recovery error: ${e.toString()}')),
        );
      }
      return null;
    }
  }

  // ── Sorting helpers ──────────────────────────────────────────────────────

  static void _sortRdVideoFilesAZ(List<RDFileNode> videoFiles) {
    final folderGroups = <String, List<RDFileNode>>{};
    for (final node in videoFiles) {
      final fullPath = (node.relativePath ?? node.path) ?? '';
      final lastSlashIndex = fullPath.lastIndexOf('/');
      final folderPath = lastSlashIndex >= 0
          ? fullPath.substring(0, lastSlashIndex)
          : '';
      folderGroups.putIfAbsent(folderPath, () => []);
      folderGroups[folderPath]!.add(node);
    }

    for (final group in folderGroups.values) {
      group.sort((a, b) {
        final aNum = _extractLeadingNumber(a.name);
        final bNum = _extractLeadingNumber(b.name);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        if (aNum != null) return -1;
        if (bNum != null) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    final folderPathsList = folderGroups.keys.toList();
    folderPathsList.sort((a, b) {
      String aFolderName = a.isEmpty ? 'Root' : a.split('/')[0];
      String bFolderName = b.isEmpty ? 'Root' : b.split('/')[0];
      final aNum = _extractSeasonNumber(aFolderName);
      final bNum = _extractSeasonNumber(bFolderName);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
    });

    videoFiles.clear();
    for (final folderPath in folderPathsList) {
      videoFiles.addAll(folderGroups[folderPath]!);
    }
  }

  static void _sortTorboxFilesAZ(List<TorboxFile> files) {
    final folderGroups = <String, List<TorboxFile>>{};
    for (final file in files) {
      final fullPath = file.name;
      final lastSlashIndex = fullPath.lastIndexOf('/');
      final folderPath = lastSlashIndex >= 0
          ? fullPath.substring(0, lastSlashIndex)
          : '';
      folderGroups.putIfAbsent(folderPath, () => []);
      folderGroups[folderPath]!.add(file);
    }

    for (final group in folderGroups.values) {
      group.sort((a, b) {
        final aName = a.name.split('/').last;
        final bName = b.name.split('/').last;
        final aNum = _extractLeadingNumber(aName);
        final bNum = _extractLeadingNumber(bName);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        if (aNum != null) return -1;
        if (bNum != null) return 1;
        return aName.toLowerCase().compareTo(bName.toLowerCase());
      });
    }

    final folderPathsList = folderGroups.keys.toList();
    folderPathsList.sort((a, b) {
      String aFolderName;
      String bFolderName;
      if (a.isEmpty) {
        aFolderName = 'Root';
      } else {
        final aParts = a.split('/');
        aFolderName = aParts.length > 1 ? aParts[1] : aParts[0];
      }
      if (b.isEmpty) {
        bFolderName = 'Root';
      } else {
        final bParts = b.split('/');
        bFolderName = bParts.length > 1 ? bParts[1] : bParts[0];
      }
      final aNum = _extractSeasonNumber(aFolderName);
      final bNum = _extractSeasonNumber(bFolderName);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
    });

    files.clear();
    for (final folderPath in folderPathsList) {
      files.addAll(folderGroups[folderPath]!);
    }
  }

  static void _sortPikPakCandidatesAZ(
    List<_PikPakPlaylistCandidate> candidates,
  ) {
    final folderGroups = <String, List<_PikPakPlaylistCandidate>>{};
    for (final candidate in candidates) {
      final fullPath =
          (candidate.file['name'] as String?) ?? candidate.displayName;
      final lastSlashIndex = fullPath.lastIndexOf('/');
      final folderPath = lastSlashIndex >= 0
          ? fullPath.substring(0, lastSlashIndex)
          : '';
      folderGroups.putIfAbsent(folderPath, () => []);
      folderGroups[folderPath]!.add(candidate);
    }

    for (final group in folderGroups.values) {
      group.sort((a, b) {
        final aNum = _extractLeadingNumber(a.displayName);
        final bNum = _extractLeadingNumber(b.displayName);
        if (aNum != null && bNum != null) return aNum.compareTo(bNum);
        if (aNum != null) return -1;
        if (bNum != null) return 1;
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    }

    final folderPathsList = folderGroups.keys.toList();
    folderPathsList.sort((a, b) {
      String aFolderName = a.isEmpty ? 'Root' : a.split('/')[0];
      String bFolderName = b.isEmpty ? 'Root' : b.split('/')[0];
      final aNum = _extractSeasonNumber(aFolderName);
      final bNum = _extractSeasonNumber(bFolderName);
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
    });

    candidates.clear();
    for (final folderPath in folderPathsList) {
      candidates.addAll(folderGroups[folderPath]!);
    }
  }

  // ── Pure helpers ─────────────────────────────────────────────────────────

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }

  static bool _torboxFileLooksLikeVideo(TorboxFile file) {
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    return FileUtils.isVideoFile(name) ||
        (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
  }

  static String _formatTorboxError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  static String _formatPikPakError(Object error) =>
      error.toString().replaceFirst('Exception: ', '').trim();

  static int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;
    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) continue;
      final bool isBetterSeason = bestSeason == null || season < bestSeason;
      final bool isBetterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);
      if (isBetterSeason || isBetterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }
    return startIndex;
  }

  static Future<void> _persistPlaylistItemChanges(
    Map<String, dynamic> item,
    String previousKey,
  ) async {
    final items = await StorageService.getPlaylistItemsRaw();
    final index = items.indexWhere(
      (playlistItem) =>
          StorageService.computePlaylistDedupeKey(playlistItem) == previousKey,
    );
    if (index == -1) return;
    items[index] = Map<String, dynamic>.from(item);
    await StorageService.savePlaylistItemsRaw(items);
  }

  static _TorboxPlaylistEntriesResult _buildTorboxPlaylistEntries({
    required TorboxTorrent torrent,
    required List<TorboxFile> files,
    String? viewMode,
  }) {
    final filenames = files
        .map(
          (file) => file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name),
        )
        .toList();
    final seriesInfos = SeriesParser.parsePlaylist(filenames);
    final bool isSeriesCollection = SeriesParser.isSeriesPlaylist(filenames);

    final List<_TorboxPlaylistCandidate> candidates = [];
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      final info = seriesInfos[i];
      final displayName = _composeTorboxEntryTitle(
        seriesTitle: info.title,
        episodeLabel: _formatTorboxPlaylistTitle(
          info: info,
          fallback: filenames[i],
          isSeriesCollection: isSeriesCollection,
        ),
        isSeriesCollection: isSeriesCollection,
        fallback: filenames[i],
      );
      candidates.add(
        _TorboxPlaylistCandidate(
          file: file,
          info: info,
          displayName: displayName,
        ),
      );
    }

    if (viewMode != 'raw' && viewMode != 'sortedAZ') {
      candidates.sort((a, b) {
        final aInfo = a.info;
        final bInfo = b.info;
        final aIsSeries =
            aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
        final bIsSeries =
            bInfo.isSeries && bInfo.season != null && bInfo.episode != null;
        if (aIsSeries && bIsSeries) {
          final seasonCompare = (aInfo.season ?? 0).compareTo(
            bInfo.season ?? 0,
          );
          if (seasonCompare != 0) return seasonCompare;
          final episodeCompare = (aInfo.episode ?? 0).compareTo(
            bInfo.episode ?? 0,
          );
          if (episodeCompare != 0) return episodeCompare;
        } else if (aIsSeries != bIsSeries) {
          return aIsSeries ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
    }

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = candidates.indexWhere(
        (c) =>
            c.info.isSeries && c.info.season != null && c.info.episode != null,
      );
      if (startIndex == -1) {
        startIndex = _findFirstEpisodeIndex(
          candidates.map((c) => c.info).toList(),
        );
      }
    }
    if (startIndex < 0 || startIndex >= candidates.length) startIndex = 0;

    final playlistEntries = <PlaylistEntry>[];
    for (final candidate in candidates) {
      String relativePath = candidate.file.name;
      final firstSlash = relativePath.indexOf('/');
      if (firstSlash > 0) relativePath = relativePath.substring(firstSlash + 1);
      playlistEntries.add(
        PlaylistEntry(
          url: '',
          title: candidate.displayName,
          relativePath: relativePath,
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: candidate.file.id,
          torrentHash: torrent.hash.isNotEmpty ? torrent.hash : null,
          sizeBytes: candidate.file.size,
        ),
      );
    }

    final totalBytes = candidates.fold<int>(0, (sum, c) => sum + c.file.size);
    final subtitle =
        '${playlistEntries.length} '
        '${isSeriesCollection ? 'episodes' : 'files'} • '
        '${Formatters.formatFileSize(totalBytes)}';

    return _TorboxPlaylistEntriesResult(
      playlistEntries: playlistEntries,
      startIndex: startIndex,
      subtitle: subtitle,
    );
  }

  static String _formatTorboxPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }
    return fallback;
  }

  static String _composeTorboxEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty)
      return '$cleanSeries $episodeLabel';
    return fallback;
  }

  static String _formatPikPakPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) return fallback;
    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }
    return fallback;
  }

  static String _composePikPakEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) return fallback;
    final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty)
      return '$cleanSeries $episodeLabel';
    return fallback;
  }

  static int? _extractSeasonNumber(String folderName) {
    final patterns = [
      RegExp(r'^(\d+)[\s._-]'),
      RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
      RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
    ];
    final lowerName = folderName.toLowerCase();
    for (final pattern in patterns) {
      final match = pattern.firstMatch(lowerName);
      if (match != null && match.groupCount >= 1)
        return int.tryParse(match.group(1)!);
    }
    return null;
  }

  static int? _extractLeadingNumber(String filename) {
    final pattern = RegExp(r'^(\d+)[\s._-]');
    final match = pattern.firstMatch(filename);
    if (match != null && match.groupCount >= 1)
      return int.tryParse(match.group(1)!);
    return null;
  }
}

// ── Internal types ─────────────────────────────────────────────────────────

class _TorboxPlaylistCandidate {
  final TorboxFile file;
  final SeriesInfo info;
  final String displayName;
  _TorboxPlaylistCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });
}

class _PikPakPlaylistCandidate {
  final Map<String, dynamic> file;
  final SeriesInfo info;
  final String displayName;
  _PikPakPlaylistCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });
}

class _WebDavPlaylistCandidate {
  final Map<String, dynamic> file;
  final SeriesInfo info;
  final String displayName;
  _WebDavPlaylistCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });
}

class _TorboxPlaylistEntriesResult {
  final List<PlaylistEntry> playlistEntries;
  final int startIndex;
  final String subtitle;
  const _TorboxPlaylistEntriesResult({
    required this.playlistEntries,
    required this.startIndex,
    required this.subtitle,
  });
}
