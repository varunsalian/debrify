import 'package:flutter/material.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/video_player_launcher.dart';
import '../utils/file_utils.dart';
import '../utils/formatters.dart';
import 'video_player_screen.dart';

class PlaylistFileBrowserScreen extends StatefulWidget {
  final Map<String, dynamic> playlistItem;

  const PlaylistFileBrowserScreen({
    super.key,
    required this.playlistItem,
  });

  @override
  State<PlaylistFileBrowserScreen> createState() => _PlaylistFileBrowserScreenState();
}

enum SortOption { name, size, dateAdded }

class _PlaylistFileBrowserScreenState extends State<PlaylistFileBrowserScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<dynamic> _allFiles = [];
  List<dynamic> _allTorrentFiles = [];
  List<dynamic> _links = [];
  bool _isLoading = true;
  String? _error;
  SortOption _selectedSort = SortOption.name;
  Map<String, dynamic>? _lastPlayedFile;

  String get _playlistId {
    // Try multiple fields to get a unique ID
    return (widget.playlistItem['rdTorrentId'] as String?) ??
           (widget.playlistItem['id'] as String?) ??
           (widget.playlistItem['hash'] as String?) ??
           widget.playlistItem['playlistName'] as String? ??
           'unknown_${widget.playlistItem.hashCode}';
  }

  @override
  void initState() {
    super.initState();
    _loadFiles();
    _loadLastPlayedFile();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
      if (rdTorrentId == null || rdTorrentId.isEmpty) {
        throw Exception('No torrent ID found');
      }

      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API key not found');
      }

      final torrentInfo = await DebridService.getTorrentInfo(apiKey, rdTorrentId);
      if (torrentInfo == null) {
        throw Exception('Failed to fetch torrent info');
      }

      final files = torrentInfo['files'] as List?;
      final links = torrentInfo['links'] as List?;
      
      if (files == null || files.isEmpty) {
        throw Exception('No files found in torrent');
      }
      
      if (links == null || links.isEmpty) {
        throw Exception('No links found in torrent');
      }

      // Filter only video files
      final videoFiles = files.where((file) {
        final path = file['path'] as String? ?? '';
        return FileUtils.isVideoFile(path);
      }).toList();

      setState(() {
        _allFiles = videoFiles;
        _allTorrentFiles = files;
        _links = links;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLastPlayedFile() async {
    try {
      final lastPlayed = await StorageService.getLastPlayedFile(_playlistId);
      if (mounted && lastPlayed != null && lastPlayed.isNotEmpty) {
        // Only set if it has valid data (path exists)
        final path = lastPlayed['path'] as String?;
        if (path != null && path.isNotEmpty) {
          setState(() {
            _lastPlayedFile = lastPlayed;
          });
        }
      }
    } catch (e) {
      // Ignore errors for last played
    }
  }

  List<dynamic> get _filteredAndSortedFiles {
    var files = _allFiles.where((file) {
      if (_searchQuery.isEmpty) return true;
      final path = (file['path'] as String? ?? '').toLowerCase();
      return path.contains(_searchQuery.toLowerCase());
    }).toList();

    // Sort files
    files.sort((a, b) {
      switch (_selectedSort) {
        case SortOption.name:
          final nameA = (a['path'] as String? ?? '').toLowerCase();
          final nameB = (b['path'] as String? ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        case SortOption.size:
          final sizeA = a['bytes'] as int? ?? 0;
          final sizeB = b['bytes'] as int? ?? 0;
          return sizeB.compareTo(sizeA); // Descending
        case SortOption.dateAdded:
          // If files have a date field, use it; otherwise keep original order
          return 0;
      }
    });

    return files;
  }

  Future<void> _playFile(dynamic file) async {
    try {
      final fileId = file['id'];
      final rdTorrentId = widget.playlistItem['rdTorrentId'] as String?;
      
      if (fileId == null || rdTorrentId == null) {
        throw Exception('Invalid file or torrent ID');
      }

      // Find the index of this file in the original torrent files list
      final fileIndex = _allTorrentFiles.indexWhere((f) => f['id'] == fileId);
      if (fileIndex == -1 || fileIndex >= _links.length) {
        throw Exception('File link not found');
      }

      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('API key not found');
      }

      // Save as last played BEFORE launching video player (without setState to avoid issues)
      await StorageService.saveLastPlayedFile(_playlistId, {
        'path': file['path'],
        'bytes': file['bytes'],
        'id': file['id'],
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Unrestrict the link
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        _links[fileIndex],
      );

      final downloadLink = unrestrictResult['download']?.toString() ?? '';
      if (downloadLink.isEmpty) {
        throw Exception('Failed to unrestrict link');
      }

      // Launch video player
      final path = file['path'] as String? ?? 'Video';
      final bytes = file['bytes'] as int?;
      
      if (!mounted) return;
      
      await VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: downloadLink,
          title: path,
          subtitle: bytes != null ? Formatters.formatFileSize(bytes) : null,
          rdTorrentId: rdTorrentId,
          playlist: [
            PlaylistEntry(
              url: downloadLink,
              title: path,
              sizeBytes: bytes,
            ),
          ],
          startIndex: 0,
        ),
      );
      
      // Reload last played file after returning from video player
      if (mounted) {
        _loadLastPlayedFile();
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.playlistItem['title'] as String? ?? 'Browse Files',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: const Color(0xFF1E293B),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search files...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0F172A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
              ),
            ),
          ),

          // Sort options
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Sort by:',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 6),
                _buildSortChip('Name', SortOption.name),
                const SizedBox(width: 6),
                _buildSortChip('Size', SortOption.size),
                const SizedBox(width: 6),
                _buildSortChip('Date', SortOption.dateAdded),
              ],
            ),
          ),

          // Last played section
          if (_lastPlayedFile != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => _playFile(_lastPlayedFile),
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_circle_filled,
                          color: Color(0xFFE50914),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (_lastPlayedFile!['path'] as String? ?? '').split('/').last,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    color: Colors.white54,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _lastPlayedFile = null;
                      });
                      StorageService.saveLastPlayedFile(_playlistId, {});
                    },
                  ),
                ],
              ),
            ),

          // File list
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6366F1),
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading files',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : _filteredAndSortedFiles.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.video_library_outlined,
                                    size: 48,
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'No video files found'
                                        : 'No files matching "$_searchQuery"',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.7),
                                      fontSize: 16,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _filteredAndSortedFiles.length,
                            itemBuilder: (context, index) {
                              final file = _filteredAndSortedFiles[index];
                              return _buildFileItem(file);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, SortOption option) {
    final isSelected = _selectedSort == option;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedSort = option;
        });
      },
      backgroundColor: const Color(0xFF0F172A),
      selectedColor: const Color(0xFF6366F1),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.white70,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFF6366F1) : Colors.white24,
        width: 1,
      ),
    );
  }

  Widget _buildFileItem(dynamic file) {
    final path = file['path'] as String? ?? '';
    final bytes = file['bytes'] as int? ?? 0;
    final fileName = path.split('/').last;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _playFile(file),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Color(0xFF6366F1),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Formatters.formatFileSize(bytes),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.5),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
