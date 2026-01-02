import 'package:flutter/material.dart';
import '../models/movie_collection.dart';
import '../screens/video_player/models/playlist_entry.dart';
import '../services/storage_service.dart';

class MovieCollectionBrowser extends StatefulWidget {
  final MovieCollection collection;
  final int currentIndex;
  final void Function(int index) onSelectIndex;

  const MovieCollectionBrowser({
    super.key,
    required this.collection,
    required this.currentIndex,
    required this.onSelectIndex,
  });

  @override
  State<MovieCollectionBrowser> createState() => _MovieCollectionBrowserState();
}

class _MovieCollectionBrowserState extends State<MovieCollectionBrowser> {
  int _group = 0; // Current group index
  final Map<int, Map<String, dynamic>> _progressByIndex = {};
  int _lastCurrentIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _syncGroupWithCurrent();
  }

  @override
  void didUpdateWidget(covariant MovieCollectionBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection) {
      _progressByIndex.clear();
      _loadProgress();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      _syncGroupWithCurrent();
    }
  }

  Future<void> _loadProgress() async {
    final futures = <Future<void>>[];
    for (int i = 0; i < widget.collection.allFiles.length; i++) {
      final entry = widget.collection.allFiles[i];
      futures.add(() async {
        final key = _resumeIdForEntry(entry);
        final state = await StorageService.getVideoPlaybackState(videoTitle: key);
        if (state != null) {
          _progressByIndex[i] = state;
        }
      }());
    }
    await Future.wait(futures);
    if (mounted) setState(() {});
  }

  void _syncGroupWithCurrent() {
    if (widget.currentIndex == _lastCurrentIndex) return;
    _lastCurrentIndex = widget.currentIndex;
    if (_lastCurrentIndex >= 0 && _lastCurrentIndex < widget.collection.allFiles.length) {
      // Find which group contains the current index
      for (int i = 0; i < widget.collection.groups.length; i++) {
        if (widget.collection.groups[i].fileIndices.contains(_lastCurrentIndex)) {
          _group = i;
          break;
        }
      }
      if (mounted) setState(() {});
    }
  }


  @override
  Widget build(BuildContext context) {
    // no auto group switching during build; handled on index change
    final currentGroup = widget.collection.groups[_group];
    final visible = currentGroup.fileIndices;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_movies, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Movie Files', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
              const Spacer(),
              PopupMenuButton<int>(
                color: const Color(0xFF1A1A1A),
                initialValue: _group,
                onSelected: (v) {
                  if (_group != v) {
                    setState(() => _group = v);
                  }
                },
                itemBuilder: (context) => [
                  for (int i = 0; i < widget.collection.groups.length; i++)
                    PopupMenuItem(
                      value: i,
                      child: Text(
                        '${widget.collection.groups[i].name} (${widget.collection.groups[i].fileCount})',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${currentGroup.name} (${currentGroup.fileCount})',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 3.0,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: visible.length,
              itemBuilder: (context, idx) {
                final i = visible[idx];
                final e = widget.collection.allFiles[i];
                final active = i == widget.currentIndex;
                final sizeText = e.sizeBytes != null ? _formatBytes(e.sizeBytes!) : '';

                final prog = _progressByIndex[i];
                final int positionMs = prog?['positionMs'] as int? ?? 0;
                final int durationMs = prog?['durationMs'] as int? ?? 0;
                final double progress = (durationMs > 0) ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;
                final bool finished = durationMs > 0 && (positionMs >= (durationMs * 0.90) || (durationMs - positionMs) <= 120000);
                final bool resumable = !finished && progress >= 0.05;

                return InkWell(
                  onTap: () {
                    Navigator.of(context).pop();
                    widget.onSelectIndex(i);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: active ? const Color(0xFF6366F1).withOpacity(0.15) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: active ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.1), width: 1.5),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: active ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(active ? Icons.play_arrow_rounded : Icons.movie_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  if (sizeText.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                      child: Text(sizeText, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                    ),
                                  if (finished) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFF059669).withOpacity(0.15), borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0xFF059669).withOpacity(0.6))),
                                      child: Row(children: const [Icon(Icons.check_circle, size: 12, color: Color(0xFF10B981)), SizedBox(width: 4), Text('Finished', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w600))]),
                                    ),
                                  ] else if (resumable) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                      child: Text('Resume ${(progress * 100).round()}%', style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: SizedBox(
                                  height: 3,
                                  child: Stack(
                                    children: [
                                      Container(color: Colors.white.withOpacity(0.08)),
                                      FractionallySizedBox(
                                        widthFactor: progress,
                                        child: Container(color: finished ? const Color(0xFF10B981) : const Color(0xFF6366F1)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (active)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFF6366F1), borderRadius: BorderRadius.circular(8)),
                            child: Text(finished ? 'Replay' : 'Now Playing', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}

String _filenameHash(String filename) {
  final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]*$'), '');
  return nameWithoutExt.hashCode.toString();
}

String _resumeIdForEntry(PlaylistEntry entry) {
  final provider = entry.provider?.toLowerCase();
  if (provider == 'torbox') {
    if (entry.torboxWebDownloadId != null && entry.torboxFileId != null) {
      return 'torbox_web_${entry.torboxWebDownloadId}_${entry.torboxFileId}';
    }
    if (entry.torboxTorrentId != null && entry.torboxFileId != null) {
      return 'torbox_${entry.torboxTorrentId}_${entry.torboxFileId}';
    }
  }
  return _filenameHash(entry.title);
}
