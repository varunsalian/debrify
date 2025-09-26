import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import '../models/series_playlist.dart';
import '../utils/series_parser.dart';
import '../utils/file_utils.dart';
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
    _loader = StorageService.getPlaylistItemsRaw();
  }

  Future<void> _refresh() async {
    setState(() {
      _loader = StorageService.getPlaylistItemsRaw();
    });
  }

  Future<void> _playItem(Map<String, dynamic> item) async {
    final String title = (item['title'] as String?) ?? 'Video';
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? torrentHash = item['torrent_hash'] as String?;
    final String kind = (item['kind'] as String?) ?? 'single';
    
    // Handle single file torrents (from Let me choose or direct adds)
    if (kind == 'single') {
      final String? restrictedLink = item['restrictedLink'] as String?;
      final String? apiKey = item['apiKey'] as String?;
      if (restrictedLink != null && restrictedLink.isNotEmpty && apiKey != null && apiKey.isNotEmpty) {
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
          if (!mounted) return;
          // Check if we can recover using torrent hash
          if (torrentHash != null && torrentHash.isNotEmpty) {
            await _attemptRecovery(item);
          } else {
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
      final String? apiKey = item['apiKey'] as String?;
      if (apiKey == null || apiKey.isEmpty) return;
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
                entries.add(PlaylistEntry(url: url, title: finalFilename, torrentHash: torrentHash));
              } else {
                entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey, torrentHash: torrentHash));
              }
            } catch (_) {
              entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey, torrentHash: torrentHash));
            }
          } else {
            entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey, torrentHash: torrentHash));
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
      } catch (_) {
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
        // Check if we can recover using torrent hash
        if (torrentHash != null && torrentHash.isNotEmpty) {
          await _attemptRecovery(item);
        } else {
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

  Future<void> _attemptRecovery(Map<String, dynamic> item) async {
    final String? torrentHash = item['torrent_hash'] as String?;
    final String? apiKey = item['apiKey'] as String?;
    final String title = (item['title'] as String?) ?? 'Video';
    
    if (torrentHash == null || torrentHash.isEmpty || apiKey == null || apiKey.isEmpty) {
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
      
      // Re-add torrent to Real Debrid
      final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
      final newTorrentId = result['torrentId'] as String?;
      final newLinks = result['links'] as List<dynamic>? ?? [];
      
      if (newTorrentId != null && newTorrentId.isNotEmpty && newLinks.isNotEmpty) {
        // Update playlist item with new torrent info
        await _updatePlaylistItemWithNewTorrent(item, newTorrentId, newLinks);
        
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
      // Close loading dialog
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Content no longer available')),
      );
    }
  }

  Future<void> _updatePlaylistItemWithNewTorrent(Map<String, dynamic> item, String newTorrentId, List<dynamic> newLinks) async {
    // Update the item with new torrent info
    item['rdTorrentId'] = newTorrentId;
    
    // For single files, update the restrictedLink with the first new link
    if (item['kind'] == 'single' && newLinks.isNotEmpty) {
      item['restrictedLink'] = newLinks[0].toString();
    }
    
    // Save updated playlist
    final items = await StorageService.getPlaylistItemsRaw();
    final itemIndex = items.indexWhere((playlistItem) => 
      StorageService.computePlaylistDedupeKey(playlistItem) == StorageService.computePlaylistDedupeKey(item));
    
    if (itemIndex != -1) {
      items[itemIndex] = item;
      await StorageService.savePlaylistItemsRaw(items);
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


