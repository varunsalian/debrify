import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/rd_torrent.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../utils/formatters.dart';
import '../utils/file_utils.dart';
import '../widgets/stat_chip.dart';
import 'video_player_screen.dart';

class DebridDownloadsScreen extends StatefulWidget {
  const DebridDownloadsScreen({super.key});

  @override
  State<DebridDownloadsScreen> createState() => _DebridDownloadsScreenState();
}

class _DebridDownloadsScreenState extends State<DebridDownloadsScreen> {
  final List<RDTorrent> _torrents = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String _errorMessage = '';
  String? _apiKey;
  int _page = 1;
  bool _hasMore = true;
  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _loadApiKeyAndTorrents();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoadingMore && _hasMore) {
        _loadMoreTorrents();
      }
    }
  }

  Future<void> _loadApiKeyAndTorrents() async {
    final apiKey = await StorageService.getApiKey();
    
    setState(() {
      _apiKey = apiKey;
    });

    if (apiKey != null) {
      await _fetchTorrents(apiKey, reset: true);
    } else {
      setState(() {
        _errorMessage = 'No API key configured. Please add your Real Debrid API key in Settings.';
      });
    }
  }

  Future<void> _fetchTorrents(String apiKey, {bool reset = false}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _hasMore = true;
        _torrents.clear();
      });
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final result = await DebridService.getTorrents(
        apiKey,
        page: _page,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      setState(() {
        if (reset) {
          _torrents.clear();
        }
        // Filter to show only downloaded torrents
        final downloadedTorrents = newTorrents.where((torrent) => torrent.isDownloaded).toList();
        _torrents.addAll(downloadedTorrents);
        _hasMore = hasMore;
        _page++;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _getUserFriendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreTorrents() async {
    if (_apiKey == null || _isLoadingMore || !_hasMore) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final result = await DebridService.getTorrents(
        _apiKey!,
        page: _page,
        limit: _limit,
        // filter: 'downloaded', // Temporarily removed to test
      );

      final List<RDTorrent> newTorrents = result['torrents'];
      final bool hasMore = result['hasMore'];

      setState(() {
        // Filter to show only downloaded torrents
        final downloadedTorrents = newTorrents.where((torrent) => torrent.isDownloaded).toList();
        _torrents.addAll(downloadedTorrents);
        _hasMore = hasMore;
        _page++;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = _getUserFriendlyErrorMessage(e);
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _handleFileOptions(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single link - unrestrict and copy directly
      try {
        final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[0]);
        final downloadLink = unrestrictResult['download'];
        _copyToClipboard(downloadLink);
      } catch (e) {
        _showError('Failed to unrestrict link: ${e.toString()}');
      }
    } else {
      // Multiple links - show popup with all files
      _showMultipleLinksDialog(torrent, showPlayButtons: true);
    }
  }

  Future<void> _handlePlayVideo(RDTorrent torrent) async {
    if (_apiKey == null) return;

    if (torrent.links.length == 1) {
      // Single video file - play directly
      try {
        final unrestrictResult = await DebridService.unrestrictLink(_apiKey!, torrent.links[0]);
        final downloadLink = unrestrictResult['download'];
        
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => VideoPlayerScreen(
                videoUrl: downloadLink,
                title: torrent.filename,
                subtitle: Formatters.formatFileSize(torrent.bytes),
              ),
            ),
          );
        }
      } catch (e) {
        _showError('Failed to load video: ${e.toString()}');
      }
    } else {
      // Multiple files - show popup with play options
      _showMultipleLinksDialog(torrent, showPlayButtons: true);
    }
  }

  Future<void> _showMultipleLinksDialog(RDTorrent torrent, {bool showPlayButtons = false}) async {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: DebridService.unrestrictLinks(_apiKey!, torrent.links),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: const Text('Processing Files'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Unrestricting download links...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Error'),
                content: Text('Failed to unrestrict links: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              );
            }

            final unrestrictedLinks = snapshot.data!;
            
                                     return Dialog(
               backgroundColor: const Color(0xFF1E293B),
               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
               child: Container(
                 width: MediaQuery.of(context).size.width * 0.9,
                 constraints: BoxConstraints(
                   maxHeight: MediaQuery.of(context).size.height * 0.8,
                   maxWidth: MediaQuery.of(context).size.width * 0.9,
                 ),
                 padding: const EdgeInsets.all(20),
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     // Header
                     Row(
                       children: [
                         Container(
                           padding: const EdgeInsets.all(8),
                           decoration: BoxDecoration(
                             color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Icon(
                             showPlayButtons ? Icons.play_circle : Icons.download,
                             color: const Color(0xFF6366F1),
                             size: 20,
                           ),
                         ),
                         const SizedBox(width: 12),
                         Expanded(
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(
                                 showPlayButtons ? 'File Options' : 'Download Files',
                                 style: TextStyle(
                                   fontSize: 18,
                                   fontWeight: FontWeight.bold,
                                   color: Colors.white,
                                 ),
                               ),
                               Text(
                                 torrent.filename,
                                 style: TextStyle(
                                   fontSize: 14,
                                   color: Colors.grey[400],
                                 ),
                                 maxLines: 1,
                                 overflow: TextOverflow.ellipsis,
                               ),
                             ],
                           ),
                         ),
                       ],
                     ),
                    
                    const SizedBox(height: 20),
                    
                    // File count and copy all button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF475569).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.file_copy,
                                  size: 16,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    '${unrestrictedLinks.length} files available',
                                    style: TextStyle(
                                      color: Colors.grey[300],
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                                                     ElevatedButton.icon(
                             onPressed: () => _copyAllLinks(unrestrictedLinks),
                             icon: const Icon(Icons.copy_all, size: 16),
                             label: Text(showPlayButtons ? 'Copy All Links' : 'Copy All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Files list
                    Flexible(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF475569).withValues(alpha: 0.3),
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: unrestrictedLinks.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            color: const Color(0xFF475569).withValues(alpha: 0.3),
                            indent: 16,
                            endIndent: 16,
                          ),
                          itemBuilder: (context, index) {
                            final link = unrestrictedLinks[index];
                            final fileName = link['filename'] ?? 'Unknown file';
                            final fileSize = link['filesize'] ?? 0;
                            final isVideo = FileUtils.isVideoFile(fileName);
                            
                            return Container(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  // File icon
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isVideo 
                                        ? const Color(0xFFE50914).withValues(alpha: 0.2)
                                        : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isVideo ? Icons.play_arrow : Icons.insert_drive_file,
                                      color: isVideo ? const Color(0xFFE50914) : const Color(0xFFF59E0B),
                                      size: 20,
                                    ),
                                  ),
                                  
                                  const SizedBox(width: 12),
                                  
                                  // File info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          fileName,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          Formatters.formatFileSize(fileSize),
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  const SizedBox(width: 12),
                                  
                                  // Action buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Play button (only for video files)
                                      if (isVideo && showPlayButtons) ...[
                                        Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE50914).withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: const Icon(
                                              Icons.play_arrow,
                                              color: Color(0xFFE50914),
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              final downloadLink = link['download'];
                                              if (downloadLink != null) {
                                                Navigator.of(context).pop();
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) => VideoPlayerScreen(
                                                      videoUrl: downloadLink,
                                                      title: fileName,
                                                      subtitle: Formatters.formatFileSize(fileSize),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            tooltip: 'Play video',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      
                                      // Copy button
                                      Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: IconButton(
                                          icon: const Icon(
                                            Icons.copy,
                                            color: Color(0xFF10B981),
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            final downloadLink = link['download'];
                                            if (downloadLink != null) {
                                              _copyToClipboard(downloadLink);
                                              Navigator.of(context).pop();
                                            }
                                          },
                                          tooltip: 'Copy download link',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[400],
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _copyAllLinks(List<Map<String, dynamic>> links) {
    final downloadLinks = links
        .map((link) => link['download'])
        .where((link) => link != null)
        .join('\n');
    
    _copyToClipboard(downloadLinks);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Download link(s) copied to clipboard!');
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    if (errorString.contains('invalid api key') || errorString.contains('401')) {
      return 'Invalid API key. Please check your Real Debrid settings.';
    } else if (errorString.contains('network error') || errorString.contains('connection')) {
      return 'Network connection error. Please check your internet connection.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please try again.';
    } else if (errorString.contains('long') || errorString.contains('int')) {
      return 'Data format error. Please refresh and try again.';
    } else if (errorString.contains('json')) {
      return 'Invalid response format. Please try again.';
    } else if (errorString.contains('failed to load torrents')) {
      return 'Unable to load downloads. Please check your connection and try again.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.error,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RD Downloads',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your downloaded torrents from Real Debrid',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Refresh Button
          if (_apiKey != null) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : () => _fetchTorrents(_apiKey!, reset: true),
                  icon: _isLoading 
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                  label: Text(_isLoading ? 'Loading...' : 'Refresh Downloads'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
          ],
          
          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _torrents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your downloads...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty && _torrents.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Error Loading Downloads',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.red[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetchTorrents(_apiKey!, reset: true),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_torrents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_done,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Your downloaded torrents will appear here',
              style: TextStyle(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _torrents.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _torrents.length) {
          // Loading more indicator
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final torrent = _torrents[index];
        return _buildTorrentCard(torrent);
      },
    );
  }

  Widget _buildTorrentCard(RDTorrent torrent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF475569).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and status
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        torrent.filename,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text(
                        'Downloaded',
                        style: TextStyle(
                          color: Color(0xFF10B981),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Stats row
                Row(
                  children: [
                                                              StatChip(
                       icon: Icons.storage,
                       text: Formatters.formatFileSize(torrent.bytes),
                       color: const Color(0xFF6366F1),
                     ),
                     const SizedBox(width: 8),
                     StatChip(
                       icon: Icons.link,
                       text: '${torrent.links.length} file${torrent.links.length > 1 ? 's' : ''}',
                       color: const Color(0xFFF59E0B),
                     ),
                     const SizedBox(width: 8),
                     StatChip(
                       icon: Icons.download_done,
                       text: '100%',
                       color: const Color(0xFF10B981),
                     ),
                  ],
                ),
                
                const SizedBox(height: 12),
                
                // Host info
                Row(
                  children: [
                    Icon(
                      Icons.computer,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      torrent.host,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                                         Text(
                       'Added ${Formatters.formatDateString(torrent.added)}',
                       style: TextStyle(
                         color: Colors.grey[400],
                         fontSize: 12,
                       ),
                     ),
                  ],
                ),
              ],
            ),
          ),
          
                     // Action buttons
           Container(
             decoration: BoxDecoration(
               color: const Color(0xFF0F172A),
               borderRadius: const BorderRadius.only(
                 bottomLeft: Radius.circular(12),
                 bottomRight: Radius.circular(12),
               ),
             ),
             child: Row(
               children: [
                 // File options button
                 Expanded(
                   child: TextButton.icon(
                     onPressed: () => _handleFileOptions(torrent),
                     icon: const Icon(Icons.more_horiz, size: 18),
                     label: Text(
                       torrent.links.length > 1 
                         ? 'File Options (${torrent.links.length})'
                         : 'Copy Download Link',
                     ),
                     style: TextButton.styleFrom(
                       foregroundColor: const Color(0xFF6366F1),
                       padding: const EdgeInsets.symmetric(vertical: 12),
                     ),
                   ),
                 ),
                 
                 // Play button (only for single video files)
                 if (torrent.links.length == 1 && FileUtils.isVideoFile(torrent.filename)) ...[
                   Container(
                     decoration: BoxDecoration(
                       border: Border(
                         left: BorderSide(
                           color: const Color(0xFF475569).withValues(alpha: 0.3),
                         ),
                       ),
                     ),
                     child: TextButton.icon(
                       onPressed: () => _handlePlayVideo(torrent),
                       icon: const Icon(Icons.play_arrow, size: 18),
                       label: const Text('Play'),
                       style: TextButton.styleFrom(
                         foregroundColor: const Color(0xFFE50914),
                         padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                       ),
                     ),
                   ),
                 ],
               ],
             ),
           ),
        ],
      ),
    );
  }
} 