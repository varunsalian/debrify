import 'package:flutter/material.dart';
import '../screens/video_player_screen.dart';
import '../services/storage_service.dart';

enum MovieGroup { main, extras }

class MovieCollectionBrowser extends StatefulWidget {
  final List<PlaylistEntry> playlist;
  final int currentIndex;
  final void Function(int index) onSelectIndex;

  const MovieCollectionBrowser({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onSelectIndex,
  });

  @override
  State<MovieCollectionBrowser> createState() => _MovieCollectionBrowserState();
}

class _MovieCollectionBrowserState extends State<MovieCollectionBrowser> {
  MovieGroup _group = MovieGroup.main;
  final Map<int, Map<String, dynamic>> _progressByIndex = {};

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  @override
  void didUpdateWidget(covariant MovieCollectionBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist != widget.playlist) {
      _progressByIndex.clear();
      _loadProgress();
    }
  }

  Future<void> _loadProgress() async {
    final futures = <Future<void>>[];
    for (int i = 0; i < widget.playlist.length; i++) {
      final entry = widget.playlist[i];
      final key = _filenameHash(entry.title);
      futures.add(StorageService.getVideoPlaybackState(videoTitle: key).then((state) {
        if (state != null) {
          _progressByIndex[i] = state;
        }
      }));
    }
    await Future.wait(futures);
    if (mounted) setState(() {});
  }

  Map<MovieGroup, List<int>> _groups() {
    final entries = widget.playlist;
    final main = <int>[];
    final extras = <int>[];
    int maxSize = -1;
    for (int i = 0; i < entries.length; i++) {
      final s = entries[i].sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }
    final double threshold = maxSize > 0 ? maxSize * 0.70 : -1;
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall = threshold > 0 && (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (isSmall) {
        extras.add(i);
      } else {
        main.add(i);
      }
    }
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) => _extractYear(entries[idx].title);
    main.sort((a, b) {
      final ya = yearOf(a);
      final yb = yearOf(b);
      if (ya != null && yb != null) {
        return ya.compareTo(yb); // older first
      }
      return sizeOf(b).compareTo(sizeOf(a));
    });
    extras.sort((a, b) {
      final sa = entries[a].sizeBytes ?? 0;
      final sb = entries[b].sizeBytes ?? 0;
      return sa.compareTo(sb);
    });
    return {MovieGroup.main: main, MovieGroup.extras: extras};
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups();
    final visible = _group == MovieGroup.main ? groups[MovieGroup.main]! : groups[MovieGroup.extras]!;
    final mainCount = groups[MovieGroup.main]!.length;
    final extrasCount = groups[MovieGroup.extras]!.length;

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
              PopupMenuButton<MovieGroup>(
                color: const Color(0xFF1A1A1A),
                initialValue: _group,
                onSelected: (v) => setState(() => _group = v),
                itemBuilder: (context) => [
                  PopupMenuItem(value: MovieGroup.main, child: Text('Main ($mainCount)', style: const TextStyle(color: Colors.white))),
                  PopupMenuItem(value: MovieGroup.extras, child: Text('Extras ($extrasCount)', style: const TextStyle(color: Colors.white))),
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
                      Text(_group == MovieGroup.main ? 'Main ($mainCount)' : 'Extras ($extrasCount)', style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                final e = widget.playlist[i];
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

int? _extractYear(String title) {
  final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(title);
  if (match != null) {
    return int.tryParse(match.group(0)!);
  }
  return null;
}


