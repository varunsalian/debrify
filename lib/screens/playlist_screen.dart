import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import '../services/torbox_service.dart';
import '../utils/series_parser.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import '../models/torbox_torrent.dart';
import '../models/torbox_file.dart';
import 'video_player_screen.dart';

class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key});

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late Future<List<Map<String, dynamic>>> _loader;

  @override
  void initState() {
    super.initState();
    _loader = _syncAndLoadPlaylist();
  }

  Future<List<Map<String, dynamic>>> _syncAndLoadPlaylist() async {
    // Load and return playlist data
    return await StorageService.getPlaylistItemsRaw();
  }

  Future<void> _refresh() async {
    setState(() {
      _loader = StorageService.getPlaylistItemsRaw();
    });
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    final String title = (item['title'] as String?) ?? 'Video';
    final String provider =
        ((item['provider'] as String?) ?? 'realdebrid').toLowerCase();
    if (provider == 'torbox') {
      await _playTorboxItem(item, fallbackTitle: title);
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
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                    videoUrl: downloadLink,
                    title: finalTitle,
                    rdTorrentId: rdTorrentId,
                  ),
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

        // Use selected files if marked; otherwise all
        final selectedFiles = allFiles.where((f) => f['selected'] == 1).toList();
        final filesToUse = selectedFiles.isNotEmpty ? selectedFiles : allFiles;

        final links = (info['links'] as List<dynamic>? ?? const []);

        // Archive check: multiple files but only one RD link
        if (filesToUse.length > 1 && links.length == 1) {
          if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('This is an archived torrent. Please extract it first.')),
          );
          return;
        }

        // Build filenames list
        final filenames = filesToUse.map((file) {
          String? name = file['name']?.toString() ?? file['filename']?.toString() ?? file['path']?.toString();
          if (name != null && name.startsWith('/')) name = name.split('/').last;
          return name ?? 'Unknown File';
        }).toList();

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

        // Map from original file index in allFiles to its index within selected/used files (for links[] mapping)
        final List<int> usedOriginalIndices = [];
        for (int i = 0; i < allFiles.length; i++) {
          if (filesToUse.contains(allFiles[i])) usedOriginalIndices.add(i);
        }

        final List<PlaylistEntry> entries = [];
        for (int i = 0; i < filesToUse.length; i++) {
          final f = filesToUse[i];
          String? filename = f['name']?.toString() ?? f['filename']?.toString() ?? f['path']?.toString();
          if (filename != null && filename.startsWith('/')) filename = filename.split('/').last;
          final finalFilename = filename ?? 'Unknown File';
          final int? sizeBytes = (f is Map) ? (f['bytes'] as int?) : null;

          // Map to original index to pick RD link via usedOriginalIndices position
          final originalIndex = allFiles.indexOf(f);
          final linkIndex = usedOriginalIndices.indexOf(originalIndex);
          if (originalIndex < 0 || linkIndex < 0 || linkIndex >= links.length) continue;

          if (i == firstIndex) {
            // Try unrestrict first for immediate start
            try {
              final unrestrictResult = await DebridService.unrestrictLink(apiKey, links[linkIndex]);
              final url = unrestrictResult['download']?.toString() ?? '';
              if (url.isNotEmpty) {
                entries.add(PlaylistEntry(url: url, title: finalFilename, torrentHash: torrentHash, sizeBytes: sizeBytes));
              } else {
                entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], torrentHash: torrentHash, sizeBytes: sizeBytes));
              }
            } catch (_) {
              entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], torrentHash: torrentHash, sizeBytes: sizeBytes));
            }
          } else {
            entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], torrentHash: torrentHash, sizeBytes: sizeBytes));
          }
        }

        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        if (entries.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No playable video files found in this torrent.')),
          );
          return;
        }

        String initialVideoUrl = '';
        if (entries.first.url.isNotEmpty) initialVideoUrl = entries.first.url;

        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: initialVideoUrl,
              title: title,
              subtitle: '${entries.length} files',
              playlist: entries,
              startIndex: 0,
              rdTorrentId: rdTorrentId,
            ),
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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoUrl: url,
          title: title,
          rdTorrentId: rdTorrentId,
        ),
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
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: streamUrl,
              title: resolvedTitle,
              subtitle: subtitle,
            ),
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

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: initialUrl,
            title: fallbackTitle,
            subtitle: subtitle,
            playlist: playlistEntries,
            startIndex: startIndex,
          ),
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
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loader,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snapshot.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return ListView(
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.playlist_add_rounded, size: 48, color: Colors.white70),
                        SizedBox(height: 12),
                        Text('Your playlist is empty', style: TextStyle(fontSize: 16)),
                        SizedBox(height: 6),
                        Text('Add items from Debrid or Let me choose', style: TextStyle(color: Colors.white60)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          items.sort((a, b) => ((b['addedAt'] ?? 0) as int).compareTo((a['addedAt'] ?? 0) as int));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final String title = (item['title'] as String?) ?? 'Video';
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PlaylistCard(
                  title: title,
                  posterUrl: item['posterUrl'] as String?,
                  onPlay: () => _playItem(item),
                  onRemove: () => _removeItem(item),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final String title;
  final String? posterUrl;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  const _PlaylistCard({
    required this.title,
    this.posterUrl,
    required this.onPlay,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E293B),
                Color(0xFF334155),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              // Image section
              Container(
                width: 80,
                height: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFF475569),
                ),
                child: posterUrl != null && posterUrl!.isNotEmpty
                    ? Image.network(
                        posterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildImagePlaceholder();
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return _buildImagePlaceholder();
                        },
                      )
                    : _buildImagePlaceholder(),
              ),
              
              // Content section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Title
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      // Bottom row with play button and remove button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Play button
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE50914),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          
                          // Remove button
                          GestureDetector(
                            onTap: () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E293B),
                                  title: const Text(
                                    'Remove from Playlist',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  content: Text(
                                    'Are you sure you want to remove "$title" from your playlist?',
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(false),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.1),
                                        foregroundColor: Colors.white70,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: Colors.white.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.of(context).pop(true),
                                      style: TextButton.styleFrom(
                                        backgroundColor: Colors.red.withOpacity(0.2),
                                        foregroundColor: Colors.red,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          side: BorderSide(
                                            color: Colors.red.withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        'Remove',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                onRemove();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.red,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF475569),
      child: const Icon(
        Icons.video_library_rounded,
        color: Colors.white54,
        size: 32,
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
