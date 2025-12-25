import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import '../services/torbox_service.dart';
import '../services/video_player_launcher.dart';
import '../services/android_native_downloader.dart';
import '../utils/series_parser.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../utils/rd_folder_tree_builder.dart';
import '../models/playlist_view_mode.dart';
import '../models/rd_file_node.dart';
import '../models/torbox_torrent.dart';
import '../models/torbox_file.dart';
import '../services/pikpak_api_service.dart';
import '../services/main_page_bridge.dart';
import 'video_player_screen.dart';
import 'playlist_content_view_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<List<Map<String, dynamic>>> _loader;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  String _searchTerm = '';
  bool _searchFocused = false;
  bool _isTelevision = false;
  bool _searchVisible = false;

  @override
  void initState() {
    super.initState();
    _loader = _syncAndLoadPlaylist();
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
    _searchFocusNode = FocusNode(debugLabel: 'playlist-search')
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _searchFocused = _searchFocusNode.hasFocus;
        });
      });
    _detectTelevision();

    // Register playlist item playback handler
    MainPageBridge.playPlaylistItem = _playItem;

    // Check if there's a pending auto-play item
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final itemToPlay = MainPageBridge.getAndClearPlaylistItemToAutoPlay();
      if (itemToPlay != null) {
        _playItem(itemToPlay);
      }
    });
  }

  Future<void> _detectTelevision() async {
    final isTv = await AndroidNativeDownloader.isTelevision();
    if (mounted) {
      setState(() {
        _isTelevision = isTv;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _syncAndLoadPlaylist() async {
    // Load playlist data
    final items = await StorageService.getPlaylistItemsRaw();

    // Apply poster overrides for items that have saved custom posters
    for (var item in items) {
      final posterOverride = await StorageService.getPlaylistPosterOverride(item);
      if (posterOverride != null && posterOverride.isNotEmpty) {
        // Override the poster URL with the saved custom poster
        item['posterUrl'] = posterOverride;
      }
    }

    return items;
  }

  Future<void> _refresh() async {
    setState(() {
      _loader = _syncAndLoadPlaylist();
    });
  }

  void _handleSearchChanged() {
    setState(() {
      _searchTerm = _searchController.text;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();

    // Unregister playlist item playback handler
    MainPageBridge.playPlaylistItem = null;

    super.dispose();
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    final String title = (item['title'] as String?) ?? 'Video';
    final String provider =
        ((item['provider'] as String?) ?? 'realdebrid').toLowerCase();
    if (provider == 'torbox') {
      await _playTorboxItem(item, fallbackTitle: title);
      return;
    }
    if (provider == 'pikpak') {
      await _playPikPakItem(item, fallbackTitle: title);
      return;
    }
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? torrentHash = item['torrent_hash'] as String?;
    final String kind = (item['kind'] as String?) ?? 'single';
    
    // Handle single file torrents (from Let me choose or direct adds)
    if (kind == 'single') {
      final String? restrictedLink = item['restrictedLink'] as String?;
      final String? apiKey = await StorageService.getApiKey();
      if (restrictedLink != null && restrictedLink.isNotEmpty && apiKey != null && apiKey.isNotEmpty) {
        print('🎬 PLAY: Attempting to play single file, title="$title"');
        try {
          final unrestrictResult = await DebridService.unrestrictLink(apiKey, restrictedLink);
          final downloadLink = unrestrictResult['download']?.toString() ?? '';
          final mimeType = unrestrictResult['mimeType']?.toString() ?? '';
          // Match Debrid: keep the stored title (typically torrent.filename) for resume key parity
          final String finalTitle = title;
          if (downloadLink.isNotEmpty) {
            if (FileUtils.isVideoMimeType(mimeType)) {
              if (!mounted) return;
              // Hide auto-launch overlay before launching player
              MainPageBridge.notifyPlayerLaunching();
              // Read saved view mode
              final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);
              final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
              await VideoPlayerLauncher.push(
                context,
                VideoPlayerLaunchArgs(
                  videoUrl: downloadLink,
                  title: finalTitle,
                  rdTorrentId: rdTorrentId,
                  viewMode: viewMode,
                ),
              );
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Selected file is not a video')),
              );
            }
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to unrestrict link')),
            );
          }
        } catch (e) {
          print('❌ PLAY ERROR: Failed to unrestrict single file, error=$e');
          if (!mounted) return;
          // Check if we can recover using torrent hash
          if (torrentHash != null && torrentHash.isNotEmpty) {
            print('🔄 PLAY: Triggering recovery for single file, torrentHash="$torrentHash"');
            await _attemptRecovery(item);
          } else {
            print('❌ PLAY: No torrent hash available for single file recovery');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: ${e.toString()}')),
            );
          }
        }
        return;
      }
    }
    
    // Handle collection torrents (multi-file/series)
    if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
      final String? apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) return;
      
      print('🎬 PLAY: Attempting to play collection torrentId="$rdTorrentId", title="$title"');
      try {
        // Show loading (non-blocking)
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const AlertDialog(
            backgroundColor: Color(0xFF1E293B),
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Preparing playlist…', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        );

        final info = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
        final allFiles = (info['files'] as List<dynamic>? ?? const []);
        if (allFiles.isEmpty) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          return;
        }

        final links = (info['links'] as List<dynamic>? ?? const []);

        // Archive check: multiple files but only one RD link
        final selectedFiles = allFiles.where((f) => f['selected'] == 1).toList();
        final filesToUse = selectedFiles.isNotEmpty ? selectedFiles : allFiles;
        if (filesToUse.length > 1 && links.length == 1) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This is an archived torrent. Please extract it first.')),
          );
          return;
        }

        // Build folder tree (preserves structure)
        final rootNode = RDFolderTreeBuilder.buildTree(allFiles.cast<Map<String, dynamic>>());

        // Collect video files with folder info
        final videoFiles = RDFolderTreeBuilder.collectVideoFiles(rootNode);

        if (videoFiles.isEmpty) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No playable video files found in this torrent.')),
          );
          return;
        }

        // Read saved view mode to determine if sorting is needed
        final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);

        // Apply Sort A-Z sorting if in sorted mode
        if (savedViewModeString == 'sortedAZ') {
          // Group files by their folder path
          final folderGroups = <String, List<RDFileNode>>{};
          for (final node in videoFiles) {
            final fullPath = (node.relativePath ?? node.path) ?? '';
            final lastSlashIndex = fullPath.lastIndexOf('/');
            final folderPath = lastSlashIndex >= 0 ? fullPath.substring(0, lastSlashIndex) : '';

            folderGroups.putIfAbsent(folderPath, () => []);
            folderGroups[folderPath]!.add(node);
          }

          // Sort files within each folder group
          for (final group in folderGroups.values) {
            group.sort((a, b) {
              final aNum = _extractLeadingNumber(a.name);
              final bNum = _extractLeadingNumber(b.name);

              if (aNum != null && bNum != null) {
                return aNum.compareTo(bNum);
              }
              if (aNum != null) return -1;
              if (bNum != null) return 1;

              return a.name.toLowerCase().compareTo(b.name.toLowerCase());
            });
          }

          // Sort folder paths
          final folderPathsList = folderGroups.keys.toList();
          folderPathsList.sort((a, b) {
            String aFolderName = a.isEmpty ? 'Root' : a.split('/')[0];
            String bFolderName = b.isEmpty ? 'Root' : b.split('/')[0];

            final aNum = _extractSeasonNumber(aFolderName);
            final bNum = _extractSeasonNumber(bFolderName);

            if (aNum != null && bNum != null) {
              return aNum.compareTo(bNum);
            }
            if (aNum != null) return -1;
            if (bNum != null) return 1;

            return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
          });

          // Rebuild videoFiles list with sorted folders and files
          videoFiles.clear();
          for (final folderPath in folderPathsList) {
            videoFiles.addAll(folderGroups[folderPath]!);
          }
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
              if (info.season! < lowestSeason || (info.season! == lowestSeason && info.episode! < lowestEpisode)) {
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
            // Try unrestrict first for immediate start
            try {
              final unrestrictResult = await DebridService.unrestrictLink(apiKey, restrictedLink);
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(PlaylistEntry(
                  url: url,
                  title: file.name,
                  relativePath: file.relativePath ?? file.path,
                  rdTorrentId: rdTorrentId,
                  rdLinkIndex: linkIndex,
                  torrentHash: torrentHash,
                  sizeBytes: file.bytes,
                ));
              } else {
                entries.add(PlaylistEntry(
                  url: '',
                  title: file.name,
                  relativePath: file.relativePath ?? file.path,
                  restrictedLink: restrictedLink,
                  rdTorrentId: rdTorrentId,
                  rdLinkIndex: linkIndex,
                  torrentHash: torrentHash,
                  sizeBytes: file.bytes,
                ));
              }
            } catch (_) {
              entries.add(PlaylistEntry(
                url: '',
                title: file.name,
                relativePath: file.relativePath ?? file.path,
                restrictedLink: restrictedLink,
                rdTorrentId: rdTorrentId,
                rdLinkIndex: linkIndex,
                torrentHash: torrentHash,
                sizeBytes: file.bytes,
              ));
            }
          } else {
            entries.add(PlaylistEntry(
              url: '',
              title: file.name,
              relativePath: file.relativePath ?? file.path,
              restrictedLink: restrictedLink,
              rdTorrentId: rdTorrentId,
              rdLinkIndex: linkIndex,
              torrentHash: torrentHash,
              sizeBytes: file.bytes,
            ));
          }
        }

        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (entries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No playable video files found in this torrent.')),
          );
          return;
        }

        // Debug logging to verify relativePath is populated
        debugPrint('🎯 PlaylistScreen (RD): Playing with ${entries.length} entries');
        for (int i = 0; i < (entries.length < 5 ? entries.length : 5); i++) {
          debugPrint('  Entry[$i]: title="${entries[i].title}", relativePath="${entries[i].relativePath}"');
        }

        String initialVideoUrl = '';
        if (entries.first.url.isNotEmpty) initialVideoUrl = entries.first.url;

        if (!mounted) return;
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();
        // Convert saved view mode string to enum (already read earlier for sorting)
        final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
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
          ),
        );
      } catch (e) {
        print('❌ PLAY ERROR: Failed to get torrent info for torrentId="$rdTorrentId", error=$e');
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        // Check if we can recover using torrent hash
        if (torrentHash != null && torrentHash.isNotEmpty) {
          print('🔄 PLAY: Triggering recovery for torrentHash="$torrentHash"');
          await _attemptRecovery(item);
        } else {
          print('❌ PLAY: No torrent hash available for recovery');
          // Silent fail for MVP
        }
      }
      return;
    }

    // Fallback: open single video directly without playlist (for legacy items)
    final String url = (item['url'] as String?) ?? '';
    if (!mounted) return;
    // Hide auto-launch overlay before launching player
    MainPageBridge.notifyPlayerLaunching();
    // Read saved view mode
    final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);
    final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: title,
        rdTorrentId: rdTorrentId,
        viewMode: viewMode,
      ),
    );
  }

  Future<void> _playTorboxItem(
    Map<String, dynamic> item, {
    required String fallbackTitle,
  }) async {
    final String? apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add your Torbox API key in Settings to play playlist items.')),
      );
      return;
    }

    final int? torrentId = _asInt(item['torboxTorrentId']);
    if (torrentId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing Torbox torrent information.')),
      );
      return;
    }

    final String kind = (item['kind'] as String?) ?? 'single';

    if (kind == 'single') {
      final int? fileId = _asInt(item['torboxFileId']);
      if (fileId == null) {
        if (!mounted) return;
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
        final String? subtitle =
            sizeBytes != null && sizeBytes > 0 ? Formatters.formatFileSize(sizeBytes) : null;
        final String resolvedTitle =
            (item['title'] as String?)?.isNotEmpty == true ? item['title'] as String : fallbackTitle;

        if (!mounted) return;
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();
        // Read saved view mode
        final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);
        final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
        await VideoPlayerLauncher.push(
          context,
          VideoPlayerLaunchArgs(
            videoUrl: streamUrl,
            title: resolvedTitle,
            subtitle: subtitle,
            viewMode: viewMode,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to prepare Torbox stream: ${_formatTorboxError(e)}')),
        );
      }
      return;
    }

    if (!mounted) return;
    bool dialogOpen = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogOpen = true;
        return const AlertDialog(
          backgroundColor: Color(0xFF1E293B),
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Preparing playlist…', style: TextStyle(color: Colors.white)),
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Torbox torrent is no longer available.')),
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
          final filtered = files.where((file) => selectedIds.contains(file.id)).toList();
          if (filtered.isNotEmpty) {
            files = filtered;
          }
        }
      }

      if (files.isEmpty) {
        files = torrent.files
            .where((file) => !file.zipped && _torboxFileLooksLikeVideo(file))
            .toList();
      }

      if (files.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable Torbox video files found.')),
        );
        return;
      }

      // Read saved view mode to determine if sorting is needed
      final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);

      // Apply Sort A-Z sorting if in sorted mode
      if (savedViewModeString == 'sortedAZ') {
        // Group files by their folder path (name contains full path with slashes)
        final folderGroups = <String, List<TorboxFile>>{};
        for (final file in files) {
          final fullPath = file.name;
          final lastSlashIndex = fullPath.lastIndexOf('/');
          final folderPath = lastSlashIndex >= 0 ? fullPath.substring(0, lastSlashIndex) : '';

          folderGroups.putIfAbsent(folderPath, () => []);
          folderGroups[folderPath]!.add(file);
        }

        // Sort files within each folder group
        for (final group in folderGroups.values) {
          group.sort((a, b) {
            // Extract filename from full path
            final aName = a.name.split('/').last;
            final bName = b.name.split('/').last;

            final aNum = _extractLeadingNumber(aName);
            final bNum = _extractLeadingNumber(bName);

            if (aNum != null && bNum != null) {
              return aNum.compareTo(bNum);
            }
            if (aNum != null) return -1;
            if (bNum != null) return 1;

            return aName.toLowerCase().compareTo(bName.toLowerCase());
          });
        }

        // Sort folder paths
        final folderPathsList = folderGroups.keys.toList();
        folderPathsList.sort((a, b) {
          String aFolderName = a.isEmpty ? 'Root' : a.split('/')[0];
          String bFolderName = b.isEmpty ? 'Root' : b.split('/')[0];

          final aNum = _extractSeasonNumber(aFolderName);
          final bNum = _extractSeasonNumber(bFolderName);

          if (aNum != null && bNum != null) {
            return aNum.compareTo(bNum);
          }
          if (aNum != null) return -1;
          if (bNum != null) return 1;

          return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
        });

        // Rebuild files list with sorted folders and files
        files.clear();
        for (final folderPath in folderPathsList) {
          files.addAll(folderGroups[folderPath]!);
        }
      }

      final entries = _buildTorboxPlaylistEntries(
        torrent: torrent,
        files: files,
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
        debugPrint('PlaylistScreen: Torbox initial link failed: $e');
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
        if (fileIds.isNotEmpty) {
          item['torboxFileIds'] = fileIds;
        }
        item['count'] = playlistEntries.length;
      }

      await _persistPlaylistItemChanges(item, previousKey);

      if (dialogOpen && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }

      // Debug logging to verify relativePath is populated
      debugPrint('🎯 PlaylistScreen (Torbox): Playing with ${playlistEntries.length} entries');
      for (int i = 0; i < (playlistEntries.length < 5 ? playlistEntries.length : 5); i++) {
        debugPrint('  Entry[$i]: title="${playlistEntries[i].title}", relativePath="${playlistEntries[i].relativePath}"');
      }

      if (!mounted) return;
      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();
      // Convert saved view mode string to enum (already read earlier for sorting)
      final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: initialUrl,
          title: fallbackTitle,
          subtitle: subtitle,
          playlist: playlistEntries,
          startIndex: startIndex,
          viewMode: viewMode,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to prepare Torbox playlist: ${_formatTorboxError(e)}')),
      );
    } finally {
      if (dialogOpen && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _playPikPakItem(
    Map<String, dynamic> item, {
    required String fallbackTitle,
  }) async {
    final pikpak = PikPakApiService.instance;

    // Check if PikPak is authenticated
    if (!await pikpak.isAuthenticated()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to PikPak in Settings to play playlist items.')),
      );
      return;
    }

    final String kind = (item['kind'] as String?) ?? 'single';

    // Handle SINGLE items
    if (kind == 'single') {
      final String? pikpakFileId = item['pikpakFileId'] as String?;
      if (pikpakFileId == null || pikpakFileId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing PikPak file information.')),
        );
        return;
      }

      try {
        // Check if we have stored metadata for instant access
        final Map<String, dynamic>? storedFile = item['pikpakFile'] as Map<String, dynamic>?;
        final bool hasStoredMetadata = storedFile != null && storedFile.isNotEmpty;

        debugPrint('PlaylistScreen: Playing PikPak single file, fileId=$pikpakFileId, hasStoredMetadata=$hasStoredMetadata');

        // Always need to get streaming URL, but can skip metadata fetch if we have it stored
        final Map<String, dynamic> fileData;
        if (hasStoredMetadata) {
          // Use stored metadata and only fetch streaming URL
          fileData = await pikpak.getFileDetails(pikpakFileId);
        } else {
          // Fetch full metadata (backward compatibility)
          fileData = await pikpak.getFileDetails(pikpakFileId);
        }

        final url = pikpak.getStreamingUrl(fileData);

        if (url == null || url.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to get PikPak streaming URL.')),
          );
          return;
        }

        // Use stored metadata if available, otherwise use fetched data
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

        final String? subtitle =
            sizeBytes != null && sizeBytes > 0 ? Formatters.formatFileSize(sizeBytes) : null;

        if (!mounted) return;
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();
        // Read saved view mode
        final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);
        final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);

        // Extract relativePath from stored metadata for single file too
        final singleFileRelativePath = hasStoredMetadata
            ? ((storedFile['_fullPath'] as String?) ?? (storedFile['name'] as String?))
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
          ),
        );
      } catch (e) {
        debugPrint('PlaylistScreen: PikPak single file playback error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play PikPak file: ${_formatPikPakError(e)}')),
        );
      }
      return;
    }

    // Handle COLLECTION items
    // Check for new format with metadata first, fallback to old format
    final List<dynamic>? pikpakFiles = item['pikpakFiles'] as List<dynamic>?;
    final List<dynamic>? pikpakFileIds = item['pikpakFileIds'] as List<dynamic>?;

    if ((pikpakFiles == null || pikpakFiles.isEmpty) &&
        (pikpakFileIds == null || pikpakFileIds.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing PikPak files information.')),
      );
      return;
    }

    // Use stored metadata if available (instant), otherwise fetch it (backward compatibility)
    final bool hasStoredMetadata = pikpakFiles != null && pikpakFiles.isNotEmpty;

    if (!mounted) return;
    bool dialogOpen = false;

    // Only show loading dialog if we need to fetch metadata
    if (!hasStoredMetadata) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          dialogOpen = true;
          return const AlertDialog(
            backgroundColor: Color(0xFF1E293B),
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Preparing playlist...', style: TextStyle(color: Colors.white)),
              ],
            ),
          );
        },
      );
    }

    try {
      final List<Map<String, dynamic>> videoFiles = [];

      if (hasStoredMetadata) {
        // NEW: Use stored metadata - instant, no API calls needed!
        debugPrint('PlaylistScreen: Using stored metadata for ${pikpakFiles.length} PikPak files (instant playback)');

        for (final file in pikpakFiles) {
          if (file is Map<String, dynamic>) {
            final mimeType = (file['mime_type'] as String?) ?? '';
            final fileName = (file['name'] as String?) ?? '';

            // Filter to video files only
            if (mimeType.startsWith('video/') || FileUtils.isVideoFile(fileName)) {
              videoFiles.add(file);
            }
          }
        }
      } else {
        // OLD: Fallback to fetching metadata for backward compatibility
        debugPrint('PlaylistScreen: Fetching metadata for ${pikpakFileIds!.length} PikPak files (legacy format)');

        for (final fileId in pikpakFileIds) {
          try {
            final fileData = await pikpak.getFileMetadata(fileId.toString());
            final mimeType = (fileData['mime_type'] as String?) ?? '';
            final fileName = (fileData['name'] as String?) ?? '';

            // Filter to video files only
            if (mimeType.startsWith('video/') || FileUtils.isVideoFile(fileName)) {
              videoFiles.add(fileData);
            }
          } catch (e) {
            debugPrint('PlaylistScreen: Failed to get PikPak file metadata for $fileId: $e');
            // Continue with other files
          }
        }
      }

      if (videoFiles.isEmpty) {
        if (dialogOpen && mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          dialogOpen = false;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable PikPak video files found.')),
        );
        return;
      }

      // Build playlist entries with series parsing
      final List<_PikPakPlaylistCandidate> candidates = [];
      for (final file in videoFiles) {
        final displayName = (file['name'] as String?) ?? 'Unknown';
        final info = SeriesParser.parseFilename(displayName);
        candidates.add(_PikPakPlaylistCandidate(
          file: file,
          info: info,
          displayName: displayName,
        ));
      }

      // Detect if it's a series collection
      final filenames = candidates.map((c) => c.displayName).toList();
      final bool isSeriesCollection =
          candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

      // Read saved view mode to determine sorting strategy
      final savedViewModeString = await StorageService.getPlaylistItemViewMode(item);

      // Sort entries based on view mode
      if (savedViewModeString == 'sortedAZ') {
        // Sort A-Z mode: Use folder-based sorting
        // Group files by folder path (extracted from file name)
        final folderGroups = <String, List<_PikPakPlaylistCandidate>>{};
        for (final candidate in candidates) {
          // Get the full path from the file metadata
          final fullPath = (candidate.file['name'] as String?) ?? candidate.displayName;
          final lastSlashIndex = fullPath.lastIndexOf('/');
          final folderPath = lastSlashIndex >= 0 ? fullPath.substring(0, lastSlashIndex) : '';

          folderGroups.putIfAbsent(folderPath, () => []);
          folderGroups[folderPath]!.add(candidate);
        }

        // Sort files within each folder group
        for (final group in folderGroups.values) {
          group.sort((a, b) {
            final aNum = _extractLeadingNumber(a.displayName);
            final bNum = _extractLeadingNumber(b.displayName);

            if (aNum != null && bNum != null) {
              return aNum.compareTo(bNum);
            }
            if (aNum != null) return -1;
            if (bNum != null) return 1;

            return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
          });
        }

        // Sort folder paths
        final folderPathsList = folderGroups.keys.toList();
        folderPathsList.sort((a, b) {
          String aFolderName = a.isEmpty ? 'Root' : a.split('/')[0];
          String bFolderName = b.isEmpty ? 'Root' : b.split('/')[0];

          final aNum = _extractSeasonNumber(aFolderName);
          final bNum = _extractSeasonNumber(bFolderName);

          if (aNum != null && bNum != null) {
            return aNum.compareTo(bNum);
          }
          if (aNum != null) return -1;
          if (bNum != null) return 1;

          return aFolderName.toLowerCase().compareTo(bFolderName.toLowerCase());
        });

        // Rebuild candidates list with sorted folders and files
        candidates.clear();
        for (final folderPath in folderPathsList) {
          candidates.addAll(folderGroups[folderPath]!);
        }
      } else if (isSeriesCollection) {
        // Series mode: Sort by season/episode
        candidates.sort((a, b) {
          final aInfo = a.info;
          final bInfo = b.info;

          final aIsSeries =
              aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
          final bIsSeries =
              bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

          if (aIsSeries && bIsSeries) {
            final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
            if (seasonCompare != 0) return seasonCompare;

            final episodeCompare =
                (aInfo.episode ?? 0).compareTo(bInfo.episode ?? 0);
            if (episodeCompare != 0) return episodeCompare;
          } else if (aIsSeries != bIsSeries) {
            return aIsSeries ? -1 : 1;
          }

          return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
        });
      } else {
        candidates.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
        );
      }

      // Find first episode to start from
      int startIndex = 0;
      if (isSeriesCollection) {
        final seriesInfos = candidates.map((c) => c.info).toList();
        startIndex = _findFirstEpisodeIndex(seriesInfos);
      }
      if (startIndex < 0 || startIndex >= candidates.length) {
        startIndex = 0;
      }

      // Resolve URL ONLY for the starting episode (lazy loading for rest)
      // This requires calling getFileDetails with usage=FETCH to get streaming URL
      String initialUrl = '';
      try {
        final firstFileId = candidates[startIndex].file['id'] as String?;
        if (firstFileId != null) {
          final fullData = await pikpak.getFileDetails(firstFileId);
          initialUrl = pikpak.getStreamingUrl(fullData) ?? '';
        }
      } catch (e) {
        debugPrint('PlaylistScreen: PikPak initial URL resolution failed: $e');
      }

      if (initialUrl.isEmpty) {
        if (dialogOpen && mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          dialogOpen = false;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get PikPak streaming URL.')),
        );
        return;
      }

      // Build PlaylistEntry list
      final List<PlaylistEntry> playlistEntries = [];
      debugPrint('🎯 PlaylistScreen (PikPak): Building ${candidates.length} playlist entries');
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

        // Extract relativePath from stored PikPak metadata
        // Priority: _fullPath (includes folder structure) > name (filename only)
        final relativePath = (candidate.file['_fullPath'] as String?) ??
                            (candidate.file['name'] as String?);

        playlistEntries.add(PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          relativePath: relativePath,
          provider: 'pikpak',
          pikpakFileId: fileId,
          sizeBytes: sizeBytes,
        ));

        // Debug log for first 5 entries to verify relativePath is populated
        if (i < 5) {
          debugPrint('  Entry[$i]: title="$combinedTitle", relativePath="$relativePath"');
        }
      }

      // Calculate subtitle
      final totalBytes = candidates.fold<int>(
        0,
        (sum, c) => sum + (_asInt(c.file['size']) ?? 0),
      );
      final subtitle =
          '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

      if (dialogOpen && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        dialogOpen = false;
      }

      if (!mounted) return;

      // Use the first file ID as the collection identifier for poster support
      final firstFileId = candidates.isNotEmpty
          ? (candidates[0].file['id'] as String?)
          : null;

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();
      // Convert saved view mode string to enum (already read earlier for sorting)
      final viewMode = PlaylistViewModeStorage.fromStorageString(savedViewModeString);
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
        ),
      );
    } catch (e) {
      debugPrint('PlaylistScreen: PikPak collection playback error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to prepare PikPak playlist: ${_formatPikPakError(e)}')),
      );
    } finally {
      if (dialogOpen && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  String _formatPikPakError(Object error) {
    final raw = error.toString();
    return raw.replaceFirst('Exception: ', '').trim();
  }

  String _formatPikPakPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

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

  String _composePikPakEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final cleanSeries = seriesTitle
        ?.replaceAll(RegExp(r'[._\-]+$'), '')
        .trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty) {
      return '$cleanSeries $episodeLabel';
    }

    return fallback;
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    return FileUtils.isVideoFile(name) ||
        (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
  }

  String _formatTorboxError(Object error) {
    final raw = error.toString();
    return raw.replaceFirst('Exception: ', '').trim();
  }

  String _prettifyProvider(String? raw) {
    if (raw == null || raw.isEmpty) return 'Real-Debrid';
    switch (raw.toLowerCase()) {
      case 'realdebrid':
      case 'real-debrid':
      case 'real_debrid':
        return 'Real-Debrid';
      case 'torbox':
        return 'TorBox';
      case 'pikpak':
      case 'pik-pak':
      case 'pik_pak':
        return 'PikPak';
      case 'alldebrid':
      case 'all-debrid':
      case 'all_debrid':
        return 'AllDebrid';
      default:
        return _titleCase(raw);
    }
  }

  String _prettifyKind(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    switch (raw.toLowerCase()) {
      case 'single':
        return 'Single File';
      case 'collection':
        return 'Collection';
      case 'series':
        return 'Series';
      case 'season':
        return 'Season Pack';
      default:
        return _titleCase(raw);
    }
  }

  String _titleCase(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\-_]+'), ' ');
    final parts = sanitized.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts
        .map((part) {
          final lower = part.toLowerCase();
          if (lower.isEmpty) return lower;
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ')
        .trim();
  }

  int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;

    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) {
        continue;
      }

      final bool isBetterSeason = bestSeason == null || season < bestSeason;
      final bool isBetterEpisode =
          bestSeason != null && season == bestSeason &&
              (bestEpisode == null || episode < bestEpisode);

      if (isBetterSeason || isBetterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }

    return startIndex;
  }

  Future<void> _attemptRecovery(Map<String, dynamic> item) async {
    final String? torrentHash = item['torrent_hash'] as String?;
    final String? apiKey = await StorageService.getApiKey();
    final String title = (item['title'] as String?) ?? 'Video';
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    
    print('🔄 RECOVERY START: title="$title", rdTorrentId="$rdTorrentId", torrentHash="$torrentHash"');
    
    if (torrentHash == null || torrentHash.isEmpty || apiKey == null || apiKey.isEmpty) {
      print('❌ RECOVERY FAILED: Missing torrentHash or apiKey');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content no longer available')),
      );
      return;
    }

    // Show recovery loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        backgroundColor: Color(0xFF1E293B),
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Reconstructing playlist...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    try {
      // Reconstruct magnet link
      final magnetLink = 'magnet:?xt=urn:btih:$torrentHash';
      print('🔗 RECOVERY: Reconstructing magnet link: $magnetLink');
      
      // Re-add torrent to Real Debrid
      print('📤 RECOVERY: Adding torrent to Real Debrid...');
      final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
      final newTorrentId = result['torrentId'] as String?;
      final newLinks = result['links'] as List<dynamic>? ?? [];
      
      print('✅ RECOVERY: Got new torrentId="$newTorrentId", linksCount=${newLinks.length}');
      
      if (newTorrentId != null && newTorrentId.isNotEmpty && newLinks.isNotEmpty) {
        print('💾 RECOVERY: Updating playlist item with new torrent info...');
        // Update playlist item with new torrent info
        await _updatePlaylistItemWithNewTorrent(item, newTorrentId, newLinks);
        
        print('🔄 RECOVERY: Item updated, retrying playback...');
        // Close loading dialog
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        
        // Retry playback with updated item
        await _playItem(item);
      } else {
        // Close loading dialog
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Content no longer available')),
        );
      }
    } catch (e) {
      print('❌ RECOVERY ERROR: $e');
      // Close loading dialog
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content no longer available')),
      );
    }
  }

  Future<void> _updatePlaylistItemWithNewTorrent(Map<String, dynamic> item, String newTorrentId, List<dynamic> newLinks) async {
    print('💾 UPDATE: Starting update for item with title="${item['title']}"');
    print('💾 UPDATE: Old rdTorrentId="${item['rdTorrentId']}" -> New rdTorrentId="$newTorrentId"');
    
    // Update the item with new torrent info
    item['rdTorrentId'] = newTorrentId;
    
    // For single files, update the restrictedLink with the first new link
    if (item['kind'] == 'single' && newLinks.isNotEmpty) {
      item['restrictedLink'] = newLinks[0].toString();
      print('💾 UPDATE: Updated restrictedLink for single file');
    }
    
    // Save updated playlist
    final items = await StorageService.getPlaylistItemsRaw();
    final itemKey = StorageService.computePlaylistDedupeKey(item);
    final itemIndex = items.indexWhere((playlistItem) => 
      StorageService.computePlaylistDedupeKey(playlistItem) == itemKey);
    
    print('💾 UPDATE: Found item at index $itemIndex with key="$itemKey"');
    
    if (itemIndex != -1) {
      items[itemIndex] = item;
      await StorageService.savePlaylistItemsRaw(items);
      print('✅ UPDATE: Successfully saved updated item to storage');
    } else {
      print('❌ UPDATE: Item not found in storage for update');
    }
  }

  /// View playlist item contents
  Future<void> _viewItem(Map<String, dynamic> item) async {
    if (!mounted) return;

    // Import the screen
    final screen = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          // Dynamically import to avoid circular dependencies
          return PlaylistContentViewScreen(
            playlistItem: item,
            onPlaybackStarted: () {
              // Hide auto-launch overlay if active
              MainPageBridge.notifyPlayerLaunching();
            },
          );
        },
      ),
    );

    // Refresh playlist in case anything changed
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _removeItem(Map<String, dynamic> item) async {
    final key = StorageService.computePlaylistDedupeKey(item);
    await StorageService.removePlaylistItemByKey(key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Removed from playlist')),
    );
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF020617)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFFE50914),
            backgroundColor: const Color(0xFF0F172A),
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _loader,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = (snapshot.data ?? const <Map<String, dynamic>>[]).toList();

                if (items.isEmpty) {
                  return CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.queue_music_rounded,
                                  size: 48,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'Nothing queued up yet',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Add shows or movies from Debrid or Let me choose and they will appear here ready to stream.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }

                items.sort((a, b) {
                  final bAdded = _asInt(b['addedAt']) ?? 0;
                  final aAdded = _asInt(a['addedAt']) ?? 0;
                  return bAdded.compareTo(aAdded);
                });

                final query = _searchTerm.trim().toLowerCase();
                final filteredItems = query.isEmpty
                    ? items
                    : items.where((item) {
                        final title = ((item['title'] as String?) ?? '').toLowerCase();
                        final series = ((item['seriesTitle'] as String?) ?? '').toLowerCase();
                        final combined = '$title $series'.trim();
                        return combined.contains(query);
                      }).toList();

                final totalCount = items.length;
                final shownCount = filteredItems.length;
                final bool isFiltering = query.isNotEmpty;
                final headerSubtitle = isFiltering
                    ? 'Showing $shownCount of $totalCount saved ${totalCount == 1 ? 'item' : 'items'}'
                    : '$totalCount saved ${totalCount == 1 ? 'item' : 'items'} ready to play';

                return FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Your Playlist',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    headerSubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isTelevision && _searchTerm.isEmpty && !_searchVisible)
                              IconButton(
                                icon: const Icon(
                                  Icons.search_rounded,
                                  color: Colors.white70,
                                  size: 28,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _searchVisible = true;
                                  });
                                  // Request focus after the widget is visible
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    _searchFocusNode.requestFocus();
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!_isTelevision || _searchVisible)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Shortcuts(
                            shortcuts: const <ShortcutActivator, Intent>{
                              SingleActivator(LogicalKeyboardKey.arrowDown): NextFocusIntent(),
                              SingleActivator(LogicalKeyboardKey.arrowUp): PreviousFocusIntent(),
                            },
                            child: Actions(
                              actions: <Type, Action<Intent>>{
                                NextFocusIntent: CallbackAction<NextFocusIntent>(
                                  onInvoke: (intent) {
                                    FocusScope.of(context).nextFocus();
                                    return null;
                                  },
                                ),
                                PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
                                  onInvoke: (intent) {
                                    FocusScope.of(context).previousFocus();
                                    return null;
                                  },
                                ),
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                curve: Curves.easeOutCubic,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: _searchFocused
                                        ? const Color(0xFFE50914)
                                        : Colors.transparent,
                                    width: 1.6,
                                  ),
                                  boxShadow: _searchFocused
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFE50914).withValues(alpha: 0.25),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: TextField(
                                  focusNode: _searchFocusNode,
                                  controller: _searchController,
                                  textInputAction: TextInputAction.search,
                                  onSubmitted: (_) {
                                    if (_isTelevision && _searchTerm.isEmpty) {
                                      setState(() {
                                        _searchVisible = false;
                                      });
                                      FocusScope.of(context).unfocus();
                                    }
                                  },
                                  decoration: InputDecoration(
                                    hintText: 'Search playlist...',
                                    hintStyle: const TextStyle(color: Colors.white54),
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      color: Colors.white60,
                                    ),
                                    suffixIcon: _searchTerm.isEmpty
                                        ? (_isTelevision
                                            ? IconButton(
                                                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                                                onPressed: () {
                                                  setState(() {
                                                    _searchVisible = false;
                                                  });
                                                  FocusScope.of(context).unfocus();
                                                },
                                              )
                                            : null)
                                        : IconButton(
                                            icon: const Icon(Icons.close_rounded, color: Colors.white60),
                                            onPressed: () {
                                              _searchController.clear();
                                              if (_isTelevision) {
                                                setState(() {
                                                  _searchVisible = false;
                                                });
                                                FocusScope.of(context).unfocus();
                                              } else {
                                                _searchFocusNode.requestFocus();
                                              }
                                            },
                                          ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.08),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: BorderSide.none,
                                    ),
                                  ),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    if (filteredItems.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: 0.05),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.search_off_rounded,
                                  size: 44,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 24),
                              const Text(
                                'No matches found',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Try a different title or clear your search to see everything again.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (isFiltering) ...[
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: () => _searchController.clear(),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFFE50914),
                                  ),
                                  child: const Text('Clear search'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                        sliver: SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final item = filteredItems[index];
                                    final String title = (item['title'] as String?) ?? 'Video';
                                    final String? posterUrl = item['posterUrl'] as String?;
                                    final int? sizeBytes = _asInt(item['sizeBytes']);
                                    final String? sizeLabel =
                                        sizeBytes != null && sizeBytes > 0 ? Formatters.formatFileSize(sizeBytes) : null;
                                    final int? addedAt = _asInt(item['addedAt']);
                                    final String? addedLabel = (addedAt != null && addedAt > 0)
                                        ? 'Added ${Formatters.formatDate(addedAt)}'
                                        : null;
                                    final String providerLabel = _prettifyProvider(item['provider'] as String?);
                                    final String kindLabel = _prettifyKind(item['kind'] as String?);
                                    final String? subtitle = item['seriesTitle'] as String?;
                                    final metadata = <String>[
                                      if (providerLabel.isNotEmpty) providerLabel,
                                      if (kindLabel.isNotEmpty) kindLabel,
                                      if (sizeLabel != null) sizeLabel,
                                    ];

                                    return Padding(
                                      padding: EdgeInsets.only(
                                        bottom: index == filteredItems.length - 1 ? 0 : 20,
                                      ),
                                      child: _PlaylistCard(
                                        title: title,
                                        subtitle: subtitle,
                                        posterUrl: posterUrl,
                                        metadata: metadata,
                                        addedLabel: addedLabel,
                                        isFirstCard: index == 0,
                                        onPlay: () => _playItem(item),
                                        onRemove: () => _removeItem(item),
                                        onView: () => _viewItem(item),
                                      ),
                                    );
                                  },
                                  childCount: filteredItems.length,
                                ),
                              ),
                      ),
                  ],
                ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? posterUrl;
  final List<String> metadata;
  final String? addedLabel;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final VoidCallback onView;
  final bool isFirstCard;

  const _PlaylistCard({
    required this.title,
    this.subtitle,
    this.posterUrl,
    this.metadata = const <String>[],
    this.addedLabel,
    this.isFirstCard = false,
    required this.onPlay,
    required this.onRemove,
    required this.onView,
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
  late final FocusNode _focusNode;
  late final FocusNode _removeFocusNode;
  late final FocusNode _viewFocusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'playlist-card-${widget.title}')
      ..addListener(_handleCardFocusChange);
    _removeFocusNode = FocusNode(debugLabel: 'playlist-card-remove-${widget.title}');
    _viewFocusNode = FocusNode(debugLabel: 'playlist-card-view-${widget.title}');
  }

  @override
  void didUpdateWidget(covariant _PlaylistCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != oldWidget.title) {
      _focusNode.debugLabel = 'playlist-card-${widget.title}';
      _removeFocusNode.debugLabel = 'playlist-card-remove-${widget.title}';
      _viewFocusNode.debugLabel = 'playlist-card-view-${widget.title}';
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleCardFocusChange);
    _focusNode.dispose();
    _removeFocusNode.dispose();
    _viewFocusNode.dispose();
    super.dispose();
  }

  void _handleCardFocusChange() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.05,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  Future<void> _handleRemovePressed(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        title: const Text(
          'Remove from playlist?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '“${widget.title}” will be removed from your playlist. You can always add it again later.',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE50914),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onRemove();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 32,
              spreadRadius: -4,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPlay,
            borderRadius: BorderRadius.circular(24),
            canRequestFocus: false,
            splashColor: Colors.white.withValues(alpha: 0.08),
            highlightColor: Colors.white.withValues(alpha: 0.04),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 190),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF1F2937),
                      Color(0xFF0F172A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildPosterLayer(),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: LinearGradient(
                            begin: Alignment.bottomLeft,
                            end: Alignment.topRight,
                            colors: [
                              Colors.black.withValues(alpha: 0.65),
                              Colors.black.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: -60,
                      right: -40,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFE50914).withValues(alpha: 0.45),
                              const Color(0xFF9333EA).withValues(alpha: 0.25),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.subtitle != null &&
                                  widget.subtitle!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              if (widget.metadata.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: widget.metadata
                                      .map(
                                        (label) => _MetadataTag(label: label),
                                      )
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              // Play Now Button - Gets initial focus on first card only
                              Focus(
                                autofocus: widget.isFirstCard,
                                child: ElevatedButton.icon(
                                  focusNode: _focusNode,
                                  onPressed: widget.onPlay,
                                  icon: const Icon(Icons.play_arrow_rounded, size: 24),
                                  label: const Text(
                                    'Play now',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFE50914),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    elevation: 0,
                                  ),
                                ),
                              ),
                              // View Button
                              ElevatedButton.icon(
                                focusNode: _viewFocusNode,
                                onPressed: widget.onView,
                                icon: const Icon(Icons.folder_open, size: 20),
                                label: const Text(
                                  'View',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                              // Delete Button
                              ElevatedButton.icon(
                                focusNode: _removeFocusNode,
                                onPressed: () => _handleRemovePressed(context),
                                icon: const Icon(Icons.delete_outline, size: 20),
                                label: const Text(
                                  'Delete',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    );
  }

  Widget _buildPosterLayer() {
    final radius = BorderRadius.circular(24);
    if (widget.posterUrl == null || widget.posterUrl!.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: _buildFallbackBackground(),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        widget.posterUrl!,
        fit: BoxFit.cover,
        color: Colors.black.withValues(alpha: 0.35),
        colorBlendMode: BlendMode.darken,
        errorBuilder: (context, error, stackTrace) => _buildFallbackBackground(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _buildFallbackBackground();
        },
      ),
    );
  }

  Widget _buildFallbackBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF1D4ED8),
            Color(0xFF9333EA),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
      ),
    );
  }

}

class _MetadataTag extends StatelessWidget {
  final String label;

  const _MetadataTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

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

_TorboxPlaylistEntriesResult _buildTorboxPlaylistEntries({
  required TorboxTorrent torrent,
  required List<TorboxFile> files,
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
    candidates.add(_TorboxPlaylistCandidate(
      file: file,
      info: info,
      displayName: displayName,
    ));
  }

  candidates.sort((a, b) {
    final aInfo = a.info;
    final bInfo = b.info;

    final aIsSeries =
        aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
    final bIsSeries =
        bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

    if (aIsSeries && bIsSeries) {
      final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;

      final episodeCompare =
          (aInfo.episode ?? 0).compareTo(bInfo.episode ?? 0);
      if (episodeCompare != 0) return episodeCompare;
    } else if (aIsSeries != bIsSeries) {
      return aIsSeries ? -1 : 1;
    }

    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  });

  int startIndex = 0;
  if (isSeriesCollection) {
    startIndex = candidates.indexWhere(
      (candidate) => candidate.info.isSeries &&
          candidate.info.season != null &&
          candidate.info.episode != null,
    );
    if (startIndex == -1) {
      final infos = candidates.map((candidate) => candidate.info).toList();
      startIndex = _computeFirstEpisodeIndex(infos);
    }
  }
  if (startIndex < 0 || startIndex >= candidates.length) {
    startIndex = 0;
  }

  final playlistEntries = <PlaylistEntry>[];
  for (final candidate in candidates) {
      playlistEntries.add(
        PlaylistEntry(
          url: '',
          title: candidate.displayName,
          relativePath: candidate.file.name, // Preserves folder structure
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: candidate.file.id,
          torrentHash:
              torrent.hash.isNotEmpty ? torrent.hash : null,
          sizeBytes: candidate.file.size,
        ),
      );
    }

  final totalBytes =
      candidates.fold<int>(0, (sum, candidate) => sum + candidate.file.size);
  final subtitle = '${playlistEntries.length} '
      '${isSeriesCollection ? 'episodes' : 'files'} • '
      '${Formatters.formatFileSize(totalBytes)}';

  return _TorboxPlaylistEntriesResult(
    playlistEntries: playlistEntries,
    startIndex: startIndex,
    subtitle: subtitle,
  );
}

String _formatTorboxPlaylistTitle({
  required SeriesInfo info,
  required String fallback,
  required bool isSeriesCollection,
}) {
  if (!isSeriesCollection) {
    return fallback;
  }

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

String _composeTorboxEntryTitle({
  required String? seriesTitle,
  required String episodeLabel,
  required bool isSeriesCollection,
  required String fallback,
}) {
  if (!isSeriesCollection) {
    return fallback;
  }

  final cleanSeries = seriesTitle
      ?.replaceAll(RegExp(r'[._\-]+$'), '')
      .trim();
  if (cleanSeries != null && cleanSeries.isNotEmpty) {
    return '$cleanSeries $episodeLabel';
  }

  return fallback;
}

int _computeFirstEpisodeIndex(List<SeriesInfo> infos) {
  int startIndex = 0;
  int? bestSeason;
  int? bestEpisode;

  for (int i = 0; i < infos.length; i++) {
    final info = infos[i];
    final season = info.season;
    final episode = info.episode;
    if (!info.isSeries || season == null || episode == null) {
      continue;
    }

    final bool isBetterSeason = bestSeason == null || season < bestSeason;
    final bool isBetterEpisode =
        bestSeason != null && season == bestSeason &&
            (bestEpisode == null || episode < bestEpisode);

    if (isBetterSeason || isBetterEpisode) {
      bestSeason = season;
      bestEpisode = episode;
      startIndex = i;
    }
  }

  return startIndex;
}

Future<TorboxTorrent?> _recoverTorboxPlaylistTorrent({
  required String apiKey,
  required Map<String, dynamic> item,
  required BuildContext context,
}) async {
  final hash = (item['torrent_hash'] ?? item['torrentHash'])?.toString();
  if (hash == null || hash.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cannot recover Torbox torrent – missing hash.')),
    );
    return null;
  }

  try {
    debugPrint('PlaylistScreen: re-adding Torbox torrent with hash=$hash');
    final response = await TorboxService.createTorrent(
      apiKey: apiKey,
      magnet: 'magnet:?xt=urn:btih:$hash',
      seed: true,
      allowZip: true,
      addOnlyIfCached: true,
    );

    final success = response['success'] as bool? ?? false;
    if (!success) {
      debugPrint('PlaylistScreen: Torbox recovery failed: ${response['error']}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Torbox recovery failed: ${response['error']?.toString() ?? 'unknown error'}',
          ),
        ),
      );
      return null;
    }

    final data = response['data'];
    final newId = _asIntMapValue(data, 'torrent_id');
    if (newId == null) {
      debugPrint('PlaylistScreen: Torbox recovery missing torrent_id');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torbox recovery failed: missing torrent id.')),
      );
      return null;
    }

    TorboxTorrent? recovered;
    for (int attempt = 0; attempt < 5; attempt++) {
      recovered = await TorboxService.getTorrentById(apiKey, newId);
      if (recovered != null) break;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (recovered == null) {
      debugPrint('PlaylistScreen: Torbox recovery succeeded but details not ready yet');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torbox recovery pending – try again in a moment.')),
      );
      return null;
    }

    item['torboxTorrentId'] = recovered.id;
    item['torrent_hash'] = hash;
    return recovered;
  } catch (e) {
    debugPrint('PlaylistScreen: Torbox recovery threw $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Torbox recovery error: ${e.toString()}')),
    );
    return null;
  }
}

Future<void> _persistPlaylistItemChanges(
  Map<String, dynamic> item,
  String previousKey,
) async {
  final items = await StorageService.getPlaylistItemsRaw();
  final index = items.indexWhere(
    (playlistItem) =>
        StorageService.computePlaylistDedupeKey(playlistItem) == previousKey,
  );
  if (index == -1) {
    return;
  }

  items[index] = Map<String, dynamic>.from(item);
  await StorageService.savePlaylistItemsRaw(items);
}

int? _asIntMapValue(dynamic data, String key) {
  if (data is Map<String, dynamic>) {
    final value = data[key];
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    if (value is num) return value.toInt();
  }
  return null;
}

/// Extract number from folder name for numerical sorting
/// Handles: "1. Introduction", "10. Chapter", "Season 10", "Chapter_12", "Episode 5", "Part 3", etc.
int? _extractSeasonNumber(String folderName) {
  final patterns = [
    // Leading numbers: "1. ", "10-", "5_", etc.
    RegExp(r'^(\d+)[\s._-]'),
    // Season/Chapter/Episode/Part keywords: "Season 10", "Chapter_12", etc.
    RegExp(r'season[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'chapter[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'episode[\s_-]*(\d+)', caseSensitive: false),
    RegExp(r'part[\s_-]*(\d+)', caseSensitive: false),
    // Generic word followed by number: "Lesson_5", "Module-3"
    RegExp(r'^[a-z]+[\s_-]*(\d+)', caseSensitive: false),
  ];

  final lowerName = folderName.toLowerCase();

  for (final pattern in patterns) {
    final match = pattern.firstMatch(lowerName);
    if (match != null && match.groupCount >= 1) {
      return int.tryParse(match.group(1)!);
    }
  }

  return null;
}

/// Extract leading number from filename for numerical sorting
/// Handles: "10. Video.mp4", "9 - Title.mkv", "05_Episode.mp4", etc.
int? _extractLeadingNumber(String filename) {
  final pattern = RegExp(r'^(\d+)[\s._-]');
  final match = pattern.firstMatch(filename);

  if (match != null && match.groupCount >= 1) {
    return int.tryParse(match.group(1)!);
  }

  return null;
}
