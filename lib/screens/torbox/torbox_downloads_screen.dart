import 'dart:convert';

import 'package:flutter/material.dart';
import '../../models/torbox_torrent.dart';
import '../../services/download_service.dart';
import '../../services/torbox_service.dart';
import '../../services/torbox_torrent_control_service.dart';
import '../../services/storage_service.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_chip.dart';

class TorboxDownloadsScreen extends StatefulWidget {
  const TorboxDownloadsScreen({super.key});

  @override
  State<TorboxDownloadsScreen> createState() => _TorboxDownloadsScreenState();
}

class _TorboxDownloadsScreenState extends State<TorboxDownloadsScreen>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  final List<TorboxTorrent> _torrents = [];

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _initialLoad = true;
  int _offset = 0;
  String _errorMessage = '';
  String? _apiKey;

  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _scrollController.addListener(_onScroll);
    _loadApiKeyAndTorrents();
  }

  Future<void> _handleTorrentAction(
    String action,
    TorboxTorrent torrent,
  ) async {
    switch (action) {
      case 'Download':
        await _showDownloadOptions(torrent);
        break;
      case 'Delete':
        await _confirmDeleteTorrent(torrent);
        break;
      default:
        _showComingSoon(action);
    }
  }

  Future<void> _showDownloadOptions(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        bool isLoadingZip = false;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.archive_outlined),
                      title: const Text('Download whole torrent as ZIP'),
                      subtitle: const Text(
                        'Create a single archive for offline use',
                      ),
                      trailing: isLoadingZip
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      enabled: !isLoadingZip,
                      onTap: isLoadingZip
                          ? null
                          : () async {
                              setSheetState(() => isLoadingZip = true);
                              try {
                                final permalink =
                                    TorboxService.createZipPermalink(
                                      key,
                                      torrent.id,
                                    );

                                final baseName = torrent.name.trim().isEmpty
                                    ? 'torbox_${torrent.id}'
                                    : torrent.name.trim();
                                final suggestedName = baseName.endsWith('.zip')
                                    ? baseName
                                    : '$baseName.zip';

                                await DownloadService.instance.enqueueDownload(
                                  url: permalink,
                                  fileName: suggestedName,
                                  context: this.context,
                                  torrentName: torrent.name,
                                  meta: jsonEncode({
                                    'source': 'torbox',
                                    'torrent_id': torrent.id,
                                    'zip': true,
                                  }),
                                );

                                if (!mounted) return;
                                Navigator.of(sheetContext).pop();
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Added "${torrent.name}" to downloads',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setSheetState(() => isLoadingZip = false);
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text('Download failed: $e'),
                                  ),
                                );
                              }
                            },
                    ),
                    ListTile(
                      leading: const Icon(Icons.list_alt),
                      title: const Text('Select files to download'),
                      subtitle: const Text('Coming soon'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showComingSoon('Select files');
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteAll() async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    if (_torrents.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all torrents?'),
        content: Text(
          'Are you sure you want to delete all ${_torrents.length} cached torrents from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        deleteAll: true,
      );

      if (!mounted) return;

      setState(() {
        _torrents.clear();
        _hasMore = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All Torbox torrents deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrents: $e')));
    }
  }

  Future<void> _confirmDeleteTorrent(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete torrent?'),
        content: Text(
          'Are you sure you want to delete "${torrent.name}" from Torbox? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await TorboxTorrentControlService.deleteTorrent(
        apiKey: key,
        torrentId: torrent.id,
      );

      if (!mounted) return;

      setState(() {
        _torrents.removeWhere((item) => item.id == torrent.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent deleted from Torbox.')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete torrent: $e')));
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadApiKeyAndTorrents() async {
    final key = await StorageService.getTorboxApiKey();
    if (!mounted) return;

    setState(() {
      _apiKey = key;
    });

    if (key == null || key.isEmpty) {
      setState(() {
        _initialLoad = false;
        _errorMessage =
            'Add your Torbox API key in Settings to view cached torrents.';
      });
      return;
    }

    await _fetchTorrents(reset: true);
  }

  Future<void> _fetchTorrents({bool reset = false}) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) return;

    if (reset) {
      setState(() {
        _isLoading = true;
        _initialLoad = true;
        _errorMessage = '';
        _offset = 0;
        _hasMore = true;
        _torrents.clear();
      });
    } else {
      setState(() {
        _isLoadingMore = true;
      });
    }

    try {
      final result = await TorboxService.getTorrents(
        key,
        offset: _offset,
        limit: _limit,
      );
      final List<TorboxTorrent> fetched = (result['torrents'] as List)
          .cast<TorboxTorrent>();
      final bool hasMore = result['hasMore'] as bool? ?? false;
      final bool shouldFetchMore = fetched.isEmpty && hasMore;

      if (!mounted) return;

      setState(() {
        _torrents.addAll(fetched);
        _hasMore = hasMore;
        _offset += _limit;
        _isLoading = false;
        _isLoadingMore = false;
        _initialLoad = false;
        if (_torrents.isNotEmpty) {
          _errorMessage = '';
        } else if (!hasMore) {
          _errorMessage =
              'No cached torrents found yet. Add torrents via Torbox to see them here.';
        }
      });

      if (shouldFetchMore) {
        await _fetchTorrents();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
        _isLoadingMore = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    await _fetchTorrents();
  }

  Future<void> _refresh() async {
    await _fetchTorrents(reset: true);
  }

  void _showComingSoon(String action) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$action support coming soon'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openSettings() {
    MainPageBridge.switchTab?.call(6);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Torrents')],
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(vertical: 10),
              indicatorPadding: const EdgeInsets.all(6),
              overlayColor: MaterialStateProperty.all(Colors.transparent),
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Theme.of(context).colorScheme.onPrimaryContainer,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onPrimaryContainer.withValues(alpha: 0.7),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                Column(
                  children: [
                    _buildToolbar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _refresh,
                        child: _buildTorrentList(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showComingSoon('Add torrent'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTorrentList() {
    if (_isLoading && _torrents.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading your Torbox torrents...'),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty && _torrents.isEmpty && !_initialLoad) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.flash_on_rounded,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(_errorMessage, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (_apiKey == null || _apiKey!.isEmpty)
            FilledButton(
              onPressed: _openSettings,
              child: const Text('Open Torbox Settings'),
            ),
        ],
      );
    }

    if (_torrents.isEmpty && !_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'No cached torrents yet. Add torrents via Torbox to see them here.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: _torrents.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _torrents.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final torrent = _torrents[index];
        return _TorboxTorrentCard(
          torrent: torrent,
          onAction: (action) => _handleTorrentAction(action, torrent),
        );
      },
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1F2937), width: 1)),
      ),
      child: Row(
        children: [
          const Spacer(),
          TextButton.icon(
            onPressed: _torrents.isEmpty ? null : _confirmDeleteAll,
            icon: const Icon(Icons.delete_sweep),
            label: const Text('Delete All'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
            ),
          ),
        ],
      ),
    );
  }
}

class _TorboxTorrentCard extends StatelessWidget {
  final TorboxTorrent torrent;
  final void Function(String action) onAction;

  const _TorboxTorrentCard({required this.torrent, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = torrent.downloadState.toLowerCase() == 'cached'
        ? const Color(0xFF10B981)
        : theme.colorScheme.primary;
    final cachedAt = torrent.cachedAt ?? torrent.createdAt;
    final safeProgress = torrent.progress.clamp(0, 1);
    final progressPercent = (safeProgress * 100).round();
    final isSingleFile = torrent.files.length <= 1;

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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        torrent.name,
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.download_done,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            torrent.downloadState.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    StatChip(
                      icon: Icons.storage,
                      text: Formatters.formatFileSize(torrent.size),
                      color: const Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.link,
                      text:
                          '${torrent.files.length} file${torrent.files.length == 1 ? '' : 's'}',
                      color: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    StatChip(
                      icon: Icons.download_done,
                      text: '$progressPercent%',
                      color: const Color(0xFF10B981),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.flash_on_rounded,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Server ${torrent.server} • ${torrent.owner.isEmpty ? 'Torbox' : torrent.owner}',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cached ${Formatters.formatDateTime(cachedAt.toIso8601String())}',
                      style: TextStyle(color: Colors.grey[400], fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0F172A),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionIcon(
                  icon: Icons.play_arrow,
                  color: const Color(0xFFE50914),
                  label: isSingleFile ? 'Play' : 'Play (multi)',
                  onTap: () => onAction('Play'),
                ),
                _ActionIcon(
                  icon: Icons.playlist_add,
                  color: const Color(0xFF8B5CF6),
                  label: isSingleFile ? 'Add to playlist' : 'Add collection',
                  onTap: () => onAction('Add to playlist'),
                ),
                _ActionIcon(
                  icon: isSingleFile ? Icons.copy : Icons.more_horiz,
                  color: const Color(0xFF6366F1),
                  label: isSingleFile ? 'Copy link' : 'Show files',
                  onTap: () => onAction('File options'),
                ),
                _ActionIcon(
                  icon: Icons.download_rounded,
                  color: const Color(0xFF10B981),
                  label: 'Download',
                  onTap: () => onAction('Download'),
                ),
                _ActionIcon(
                  icon: Icons.delete_outline,
                  color: const Color(0xFFEF4444),
                  label: 'Delete',
                  onTap: () => onAction('Delete'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: const Color(0xFF475569).withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Tooltip(
        message: label,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(icon, size: 18),
          style: IconButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }
}
