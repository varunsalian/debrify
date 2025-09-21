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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}')),
          );
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
                entries.add(PlaylistEntry(url: url, title: finalFilename));
              } else {
                entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey));
              }
            } catch (_) {
              entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey));
            }
          } else {
            entries.add(PlaylistEntry(url: '', title: finalFilename, restrictedLink: links[linkIndex], apiKey: apiKey));
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
        // Silent fail for MVP
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

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 16 / 9,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final String title = (item['title'] as String?) ?? 'Video';
              return _PlaylistCard(
                title: title,
                posterUrl: item['posterUrl'] as String?,
                onPlay: () => _playItem(item),
                onRemove: () => _removeItem(item),
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
    return GestureDetector(
      onTap: onPlay,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF374151)),
        ),
        child: Stack(
          children: [
            // Show poster if available, otherwise show title
            if (posterUrl != null && posterUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.network(
                      posterUrl!,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        // Fallback to title display if image fails to load
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        );
                      },
                    ),
                    // Show title overlay on poster
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withOpacity(0.8),
                              Colors.transparent,
                            ],
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
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
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.red),
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 8,
              right: 8,
              child: Icon(Icons.play_arrow_rounded, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}


