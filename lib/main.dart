import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const TorrentSearchApp());
}

class TorrentSearchApp extends StatelessWidget {
  const TorrentSearchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torrent Search',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const TorrentSearchPage(),
    const DebridDownloadsPage(),
    const SettingsPage(),
  ];

  final List<String> _titles = [
    'Torrent Search',
    'Debrid Downloads',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, size: 24),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
            tooltip: 'Open menu',
          ),
        ),
        title: Text(
          _titles[_selectedIndex],
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        centerTitle: true,
      ),
      body: _pages[_selectedIndex],
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Text(
                    'Torrent Search',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search and manage torrents',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search'),
              selected: _selectedIndex == 0,
              onTap: () {
                setState(() {
                  _selectedIndex = 0;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Debrid Downloads'),
              selected: _selectedIndex == 1,
              onTap: () {
                setState(() {
                  _selectedIndex = 1;
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              selected: _selectedIndex == 2,
              onTap: () {
                setState(() {
                  _selectedIndex = 2;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class TorrentSearchPage extends StatefulWidget {
  const TorrentSearchPage({super.key});

  @override
  State<TorrentSearchPage> createState() => _TorrentSearchPageState();
}

class _TorrentSearchPageState extends State<TorrentSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Torrent> _torrents = [];
  bool _isLoading = false;
  String _errorMessage = '';
  bool _hasSearched = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _searchTorrents(String query) async {
    if (query.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _hasSearched = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://torrents-csv.com/service/search?q=${Uri.encodeComponent(query)}'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final torrentsList = data['torrents'] as List;
        
        setState(() {
          _torrents = torrentsList.map((json) => Torrent.fromJson(json)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load torrents. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  void _copyMagnetLink(String infohash) {
    final magnetLink = 'magnet:?xt=urn:btih:$infohash';
    Clipboard.setData(ClipboardData(text: magnetLink));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Magnet link copied to clipboard!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search Section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Search for torrents...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: _searchTorrents,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: () => _searchTorrents(_searchController.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Search'),
              ),
            ],
          ),
        ),
        
        // Content Section
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching for torrents...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Search for torrents to get started',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    if (_torrents.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No torrents found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _torrents.length,
      itemBuilder: (context, index) {
        final torrent = _torrents[index];
        return _buildTorrentCard(torrent);
      },
    );
  }

  Widget _buildTorrentCard(Torrent torrent) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _copyMagnetLink(torrent.infohash),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                torrent.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              
              // Stats Row
              Row(
                children: [
                  _buildStatChip(
                    Icons.storage,
                    _formatFileSize(torrent.sizeBytes),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.upload,
                    '${torrent.seeders}',
                    Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.download,
                    '${torrent.leechers}',
                    Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  _buildStatChip(
                    Icons.check_circle,
                    '${torrent.completed}',
                    Colors.purple,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // Date
              Text(
                'Created: ${_formatDate(torrent.createdUnix)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              
              // Tap hint
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to copy magnet link',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(int unixTimestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000);
    return DateFormat('MMM dd, yyyy').format(date);
  }
}

class DebridDownloadsPage extends StatefulWidget {
  const DebridDownloadsPage({super.key});

  @override
  State<DebridDownloadsPage> createState() => _DebridDownloadsPageState();
}

class _DebridDownloadsPageState extends State<DebridDownloadsPage> {
  List<DebridDownload> _downloads = [];
  bool _isLoading = false;
  String _errorMessage = '';
  String? _apiKey;

  @override
  void initState() {
    super.initState();
    _loadApiKeyAndDownloads();
  }

  Future<void> _loadApiKeyAndDownloads() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('real_debrid_api_key');
    
    setState(() {
      _apiKey = apiKey;
    });

    if (apiKey != null) {
      await _fetchDownloads(apiKey);
    } else {
      setState(() {
        _errorMessage = 'No API key configured. Please add your Real Debrid API key in Settings.';
      });
    }
  }

  Future<void> _fetchDownloads(String apiKey) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final response = await http.get(
        Uri.parse('https://api.real-debrid.com/rest/1.0/downloads?auth_token=$apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _downloads = data.map((json) => DebridDownload.fromJson(json)).toList();
          _isLoading = false;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = 'Invalid API key. Please check your Real Debrid API key in Settings.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Failed to load downloads. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Network error. Please check your connection.';
        _isLoading = false;
      });
    }
  }

  void _copyDownloadLink(String downloadLink) {
    Clipboard.setData(ClipboardData(text: downloadLink));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Download link copied to clipboard!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return 'Unknown size';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MMM dd, yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
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
                        'Real Debrid Downloads',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Your premium downloads from Real Debrid',
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
          
          const SizedBox(height: 16),
          
          // Refresh Button
          if (_apiKey != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : () => _fetchDownloads(_apiKey!),
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
          
          const SizedBox(height: 16),
          
          // Content
          if (_isLoading) ...[
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading your downloads...'),
                ],
              ),
            ),
          ] else if (_errorMessage.isNotEmpty) ...[
            // Error State
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
                    ),
                  ),
                  if (_apiKey == null) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Navigate to settings
                        setState(() {
                          // This will trigger navigation to settings
                        });
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Go to Settings'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else if (_downloads.isEmpty) ...[
            // Empty State
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.download_done,
                    color: Colors.blue,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Downloads Found',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your Real Debrid downloads will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // Downloads List
            Text(
              'Your Downloads (${_downloads.length})',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final download = _downloads[index];
                return _buildDownloadCard(download);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDownloadCard(DebridDownload download) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _copyDownloadLink(download.download),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // File Name
              Row(
                children: [
                  Expanded(
                    child: Text(
                      download.filename,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // File Info
              Row(
                children: [
                  _buildInfoChip(
                    Icons.storage,
                    _formatFileSize(download.filesize),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    Icons.web,
                    download.host,
                    Colors.green,
                  ),
                  if (download.type != null) ...[
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.high_quality,
                      download.type!,
                      Colors.purple,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              
              // Date
              Text(
                'Generated: ${_formatDate(download.generated)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              
              // Tap hint
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.copy,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to copy download link',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class DebridDownload {
  final String id;
  final String filename;
  final String mimeType;
  final int filesize;
  final String link;
  final String host;
  final int chunks;
  final String download;
  final String generated;
  final String? type;

  DebridDownload({
    required this.id,
    required this.filename,
    required this.mimeType,
    required this.filesize,
    required this.link,
    required this.host,
    required this.chunks,
    required this.download,
    required this.generated,
    this.type,
  });

  factory DebridDownload.fromJson(Map<String, dynamic> json) {
    return DebridDownload(
      id: json['id'] ?? '',
      filename: json['filename'] ?? '',
      mimeType: json['mimeType'] ?? '',
      filesize: json['filesize'] ?? 0,
      link: json['link'] ?? '',
      host: json['host'] ?? '',
      chunks: json['chunks'] ?? 0,
      download: json['download'] ?? '',
      generated: json['generated'] ?? '',
      type: json['type'],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _apiKeyController = TextEditingController();
  String? _savedApiKey;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedApiKey = prefs.getString('real_debrid_api_key');
      _isLoading = false;
    });
  }

  Future<void> _saveApiKey() async {
    if (_apiKeyController.text.trim().isEmpty) {
      _showSnackBar('Please enter a valid API key', isError: true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('real_debrid_api_key', _apiKeyController.text.trim());
    
    setState(() {
      _savedApiKey = _apiKeyController.text.trim();
      _isEditing = false;
      _apiKeyController.clear();
    });
    
    _showSnackBar('API key saved successfully!');
  }

  Future<void> _deleteApiKey() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete API Key'),
        content: const Text('Are you sure you want to delete your Real Debrid API key? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('real_debrid_api_key');
      
      setState(() {
        _savedApiKey = null;
        _isEditing = false;
        _apiKeyController.clear();
      });
      
      _showSnackBar('API key deleted successfully!');
    }
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _apiKeyController.text = _savedApiKey ?? '';
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _apiKeyController.clear();
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
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
                    Icons.settings,
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
                        'Settings',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configure your app preferences',
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
          
          const SizedBox(height: 24),
          
          // Real Debrid Section
          Text(
            'Real Debrid Configuration',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your Real Debrid account to enable premium downloads',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          // API Key Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.key,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'API Key',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_savedApiKey != null && !_isEditing)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Connected',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  if (_isEditing) ...[
                    // Edit Mode
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _obscureText,
                      decoration: InputDecoration(
                        labelText: 'Real Debrid API Key',
                        hintText: 'Enter your API key here',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureText ? Icons.visibility : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureText = !_obscureText;
                            });
                          },
                        ),
                        prefixIcon: const Icon(Icons.security),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveApiKey,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              foregroundColor: Theme.of(context).colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Save'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelEditing,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // View Mode
                    if (_savedApiKey != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '••••••••••••••••••••••••••••••••',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                            Icon(
                              Icons.visibility_off,
                              color: Colors.grey[500],
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _startEditing,
                              icon: const Icon(Icons.edit),
                              label: const Text('Edit'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _deleteApiKey,
                              icon: const Icon(Icons.delete),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // No API Key
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: Colors.orange,
                              size: 32,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'No API Key Configured',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add your Real Debrid API key to enable premium downloads',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.orange[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startEditing,
                          icon: const Icon(Icons.add),
                          label: const Text('Add API Key'),
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
                    ],
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Help Section
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.help_outline,
                        color: Theme.of(context).colorScheme.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'How to get your API key',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Go to real-debrid.com and log in\n'
                    '2. Navigate to your account settings\n'
                    '3. Find the API section\n'
                    '4. Copy your API key and paste it above',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Torrent {
  final int rowid;
  final String infohash;
  final String name;
  final int sizeBytes;
  final int createdUnix;
  final int seeders;
  final int leechers;
  final int completed;
  final int scrapedDate;

  Torrent({
    required this.rowid,
    required this.infohash,
    required this.name,
    required this.sizeBytes,
    required this.createdUnix,
    required this.seeders,
    required this.leechers,
    required this.completed,
    required this.scrapedDate,
  });

  factory Torrent.fromJson(Map<String, dynamic> json) {
    return Torrent(
      rowid: json['rowid'] ?? 0,
      infohash: json['infohash'] ?? '',
      name: json['name'] ?? '',
      sizeBytes: json['size_bytes'] ?? 0,
      createdUnix: json['created_unix'] ?? 0,
      seeders: json['seeders'] ?? 0,
      leechers: json['leechers'] ?? 0,
      completed: json['completed'] ?? 0,
      scrapedDate: json['scraped_date'] ?? 0,
    );
  }
}
