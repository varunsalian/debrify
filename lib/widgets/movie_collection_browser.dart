import 'package:flutter/material.dart';
import '../screens/video_player_screen.dart';
import '../services/storage_service.dart';
import '../models/rd_file_node.dart';
import 'view_mode_dropdown.dart';

enum MovieGroup { main, extras }

class MovieCollectionBrowser extends StatefulWidget {
  final List<PlaylistEntry> playlist;
  final int currentIndex;
  final void Function(int index) onSelectIndex;
  final FolderViewMode? viewMode;
  final RDFileNode? folderTree;

  const MovieCollectionBrowser({
    super.key,
    required this.playlist,
    required this.currentIndex,
    required this.onSelectIndex,
    this.viewMode,
    this.folderTree,
  });

  @override
  State<MovieCollectionBrowser> createState() => _MovieCollectionBrowserState();
}

class _MovieCollectionBrowserState extends State<MovieCollectionBrowser> {
  MovieGroup _group = MovieGroup.main;
  final Map<int, Map<String, dynamic>> _progressByIndex = {};
  int _lastCurrentIndex = -1;
  String? _selectedFolder; // Currently selected folder for folder view

  @override
  void initState() {
    super.initState();
    _loadProgress();
    _syncGroupWithCurrent();
  }

  @override
  void didUpdateWidget(covariant MovieCollectionBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlist != widget.playlist) {
      _progressByIndex.clear();
      _loadProgress();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      _syncGroupWithCurrent();
    }
  }

  Future<void> _loadProgress() async {
    final futures = <Future<void>>[];
    for (int i = 0; i < widget.playlist.length; i++) {
      final entry = widget.playlist[i];
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
    if (_lastCurrentIndex >= 0 && _lastCurrentIndex < widget.playlist.length) {
      final groupsNow = _groups();
      if (groupsNow[MovieGroup.extras]!.contains(_lastCurrentIndex)) {
        _group = MovieGroup.extras;
      } else {
        _group = MovieGroup.main;
      }
      if (mounted) setState(() {});
    }
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
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;
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

  bool _shouldUseFolderDropdown() {
    return widget.viewMode != null &&
           widget.folderTree != null &&
           (widget.viewMode == FolderViewMode.raw ||
            widget.viewMode == FolderViewMode.sortedAZ);
  }

  /// Get folder name from file path
  String _getFolderName(PlaylistEntry entry) {
    if (widget.folderTree == null) return 'All Files';

    try {
      final allFiles = widget.folderTree!.getAllFiles();
      if (allFiles.isEmpty) return 'All Files';

      final fileNode = allFiles.firstWhere(
        (node) => node.name == entry.title,
        orElse: () => RDFileNode.file(name: '', fileId: -1, path: '', bytes: 0, linkIndex: -1),
      );

      if (fileNode.name.isEmpty) return 'All Files';

      final pathToUse = fileNode.relativePath ?? fileNode.path;
      if (pathToUse == null || pathToUse.isEmpty) return 'All Files';

      final parts = pathToUse.split('/');
      if (parts.length <= 1) return 'All Files';

      // Return the folder name (skip top-level torrent name)
      return parts[1];
    } catch (e) {
      return 'All Files';
    }
  }

  /// Group playlist indices by folder
  Map<String, List<int>> _groupByFolder() {
    final groups = <String, List<int>>{};

    for (int i = 0; i < widget.playlist.length; i++) {
      final entry = widget.playlist[i];
      final folderName = _getFolderName(entry);
      groups.putIfAbsent(folderName, () => []).add(i);
    }

    return groups;
  }

  String? _extractFolderPath(PlaylistEntry entry) {
    if (widget.folderTree == null) {
      debugPrint('MovieCollectionBrowser: folderTree is null');
      return null;
    }

    try {
      // Find matching file node
      final allFiles = widget.folderTree!.getAllFiles();
      debugPrint('MovieCollectionBrowser: Found ${allFiles.length} files in tree');
      if (allFiles.isEmpty) return null;

      final fileNode = allFiles.firstWhere(
        (node) => node.name == entry.title,
        orElse: () => RDFileNode.file(name: '', fileId: -1, path: '', bytes: 0, linkIndex: -1),
      );

      if (fileNode.name.isEmpty) {
        debugPrint('MovieCollectionBrowser: File not found in tree: ${entry.title}');
        return null;
      }

      // Use relativePath if available
      final pathToUse = fileNode.relativePath ?? fileNode.path;
      debugPrint('MovieCollectionBrowser: File "${entry.title}" has path: $pathToUse');

      if (pathToUse == null || pathToUse.isEmpty) return null;

      // Parse path: "Series Name/Season 1/Episode 1.mkv"
      final parts = pathToUse.split('/');

      if (parts.length <= 1) {
        debugPrint('MovieCollectionBrowser: Flat structure detected');
        return null; // Flat structure, use filename
      }

      // Skip top-level folder (torrent/series name)
      // Show: "Season 1/Episode 1.mkv"
      final folderPath = parts.skip(1).join('/');
      debugPrint('MovieCollectionBrowser: Extracted folder path: $folderPath');
      return folderPath;
    } catch (e) {
      debugPrint('MovieCollectionBrowser: Error extracting folder path: $e');
      return null;
    }
  }

  /// Extract season number from folder name (e.g., "Season 1" -> 1)
  int? _extractSeasonNumber(String folderName) {
    final match = RegExp(r'[Ss]eason\s*(\d+)', caseSensitive: false).firstMatch(folderName);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  Widget _buildFolderDropdown() {
    final folderGroups = _groupByFolder();

    // Get folders in the correct order based on view mode
    final List<String> folders;
    if (widget.viewMode == FolderViewMode.raw) {
      // Raw view: preserve original order from playlist
      folders = folderGroups.keys.toList();
    } else {
      // Sort A-Z: sort with season number handling (same as playlist content view)
      folders = folderGroups.keys.toList();
      folders.sort((a, b) {
        final aNum = _extractSeasonNumber(a);
        final bNum = _extractSeasonNumber(b);

        // If both have season numbers, sort numerically
        if (aNum != null && bNum != null) {
          return aNum.compareTo(bNum);
        }

        // If only one has a season number, numbered folders come first
        if (aNum != null) return -1;
        if (bNum != null) return 1;

        // Otherwise sort alphabetically (case-insensitive)
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    }

    // Initialize selected folder if not set
    if (_selectedFolder == null && folders.isNotEmpty) {
      // Find folder containing current playing file
      for (final folder in folders) {
        if (folderGroups[folder]!.contains(widget.currentIndex)) {
          _selectedFolder = folder;
          break;
        }
      }
      _selectedFolder ??= folders.first;
    }

    return DropdownButton<String>(
      value: _selectedFolder ?? folders.firstOrNull,
      dropdownColor: const Color(0xFF1A1A1A),
      underline: const SizedBox.shrink(),
      items: folders.map((folder) {
        final fileCount = folderGroups[folder]!.length;
        return DropdownMenuItem(
          value: folder,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              '$folder ($fileCount files)',
              style: const TextStyle(color: Colors.white, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }).toList(),
      onChanged: (folder) {
        if (folder != null) {
          setState(() {
            _selectedFolder = folder;
          });
        }
      },
      icon: const Icon(Icons.folder, color: Colors.white, size: 18),
      style: const TextStyle(color: Colors.white, fontSize: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MovieCollectionBrowser: viewMode=${widget.viewMode}, folderTree=${widget.folderTree != null ? "present" : "null"}');
    final useFolderView = _shouldUseFolderDropdown();
    debugPrint('MovieCollectionBrowser: useFolderView=$useFolderView');

    // For folder view, show files from selected folder
    // For Main/Extras view, filter by group
    final List<int> visible;
    final groups = _groups();
    final mainCount = groups[MovieGroup.main]!.length;
    final extrasCount = groups[MovieGroup.extras]!.length;

    if (useFolderView) {
      // Show files from selected folder only
      final folderGroups = _groupByFolder();
      if (_selectedFolder != null && folderGroups.containsKey(_selectedFolder)) {
        visible = folderGroups[_selectedFolder]!;
      } else {
        // Fallback: show all files
        visible = List.generate(widget.playlist.length, (i) => i);
      }
    } else {
      // Show filtered by Main/Extras group
      visible = _group == MovieGroup.main ? groups[MovieGroup.main]! : groups[MovieGroup.extras]!;
    }

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
              if (useFolderView)
                _buildFolderDropdown()
              else
                PopupMenuButton<MovieGroup>(
                  color: const Color(0xFF1A1A1A),
                  initialValue: _group,
                  onSelected: (v) {
                    if (_group != v) {
                      setState(() => _group = v);
                    }
                  },
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

                // In folder view, just show filename (folder already shown in dropdown)
                // In Main/Extras view, show full title
                final displayTitle = e.title;

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
                              Text(displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
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
  if (provider == 'torbox' &&
      entry.torboxTorrentId != null &&
      entry.torboxFileId != null) {
    return 'torbox_${entry.torboxTorrentId}_${entry.torboxFileId}';
  }
  if (provider == 'pikpak' && entry.pikpakFileId != null) {
    return 'pikpak_${entry.pikpakFileId}';
  }
  // Use relativePath if available to avoid collisions (e.g., Season 1/Episode 1.mkv vs Season 2/Episode 1.mkv)
  if (entry.relativePath != null && entry.relativePath!.isNotEmpty) {
    return _filenameHash(entry.relativePath!);
  }
  return _filenameHash(entry.title);
}

int? _extractYear(String title) {
  final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(title);
  if (match != null) {
    return int.tryParse(match.group(0)!);
  }
  return null;
}
