import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../services/download_service.dart';
import '../../services/torbox_service.dart';
import '../../services/torbox_torrent_control_service.dart';
import '../../services/storage_service.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/formatters.dart';
import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';
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
                      subtitle: const Text('Choose specific files to download'),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showTorboxFileSelectionSheet(torrent);
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

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    return FileUtils.isVideoFile(name) ||
        (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
  }

  bool _isLikelySeries(List<_TorboxFileEntry> entries) {
    if (entries.length < 2) return false;

    final episodeEntries = entries.where((entry) {
      final info = entry.seriesInfo;
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries) return false;
      if (season == null || season <= 0) return false;
      if (episode == null || episode <= 0) return false;
      return true;
    }).toList();

    if (episodeEntries.length < 2) return false;

    final uniqueEpisodeKeys = episodeEntries
        .map(
          (entry) => '${entry.seriesInfo.season}:${entry.seriesInfo.episode}',
        )
        .toSet();
    if (uniqueEpisodeKeys.length < 2) return false;

    final ratio = episodeEntries.length / entries.length;
    if (ratio < 0.6) return false;

    return true;
  }

  Future<void> _showTorboxFileSelectionSheet(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _showComingSoon('No files available');
      return;
    }

    final files = torrent.files;
    final filenames = files
        .map(
          (file) => file.shortName.isNotEmpty
              ? file.shortName
              : FileUtils.getFileName(file.name),
        )
        .toList();
    final seriesInfos = SeriesParser.parsePlaylist(filenames);

    final entries = List<_TorboxFileEntry>.generate(
      files.length,
      (index) => _TorboxFileEntry(
        file: files[index],
        index: index,
        seriesInfo: index < seriesInfos.length
            ? seriesInfos[index]
            : SeriesParser.parseFilename(files[index].shortName),
      ),
    );

    final Set<int> selectedIndices = <int>{};

    bool showRaw = false;
    int? currentSeason;
    final bool isSeries = _isLikelySeries(entries);
    final bool hasVideo = entries.any(
      (entry) => _torboxFileLooksLikeVideo(entry.file),
    );
    final bool isMovieCollection = !isSeries && hasVideo;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              final selectedBytes = selectedIndices.fold<int>(
                0,
                (previousValue, index) =>
                    previousValue + entries[index].file.size.toInt(),
              );

              Widget content;
              if (showRaw) {
                content = _buildTorboxRawList(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                );
              } else if (isSeries) {
                content = _buildTorboxSeriesView(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  currentSeason: currentSeason,
                  onSeasonChange: (season) {
                    setSheetState(() {
                      currentSeason = season;
                    });
                  },
                  onToggleFile: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                  onToggleSeason: (season, seasonIndices) {
                    setSheetState(() {
                      final hasAll = seasonIndices.every(
                        (index) => selectedIndices.contains(index),
                      );
                      if (hasAll) {
                        for (final idx in seasonIndices) {
                          selectedIndices.remove(idx);
                        }
                      } else {
                        selectedIndices.addAll(seasonIndices);
                      }
                    });
                  },
                );
              } else if (isMovieCollection) {
                content = _buildTorboxMovieView(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                );
              } else {
                content = _buildTorboxGenericList(
                  entries: entries,
                  selectedIndices: selectedIndices,
                  onToggle: (index) {
                    setSheetState(() {
                      if (selectedIndices.contains(index)) {
                        selectedIndices.remove(index);
                      } else {
                        selectedIndices.add(index);
                      }
                    });
                  },
                );
              }

              final selectedCount = selectedIndices.length;
              final totalCount = entries.length;
              final selectionSummary = selectedCount == totalCount
                  ? 'All $totalCount files selected'
                  : '$selectedCount of $totalCount files selected';

              return SafeArea(
                top: false,
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.9,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0F172A).withValues(alpha: 0.98),
                        const Color(0xFF1E293B).withValues(alpha: 0.98),
                      ],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 30,
                        offset: const Offset(0, -10),
                      ),
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[600],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              torrent.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${entries.length} file${entries.length == 1 ? '' : 's'} • ${Formatters.formatFileSize(torrent.size)}',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(
                              0xFF475569,
                            ).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectionSummary,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Selected size: ${Formatters.formatFileSize(selectedBytes)}',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'Raw',
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch.adaptive(
                                  value: showRaw,
                                  activeColor: const Color(0xFF6366F1),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      showRaw = value;
                                      currentSeason = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(child: content),
                      Container(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(28),
                          ),
                          border: Border(
                            top: BorderSide(
                              color: const Color(
                                0xFF1F2937,
                              ).withValues(alpha: 0.6),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _showComingSoon('Download all');
                                    },
                                    icon: const Icon(Icons.download_rounded),
                                    label: const Text('Download All'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(
                                        0xFF10B981,
                                      ).withValues(alpha: 0.2),
                                      foregroundColor: const Color(0xFF10B981),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 14,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                ),
                                if (selectedIndices.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        Navigator.of(sheetContext).pop();
                                        _showComingSoon('Download selected');
                                      },
                                      icon: const Icon(Icons.checklist_rounded),
                                      label: const Text('Download Selected'),
                                      style: FilledButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Close',
                                  style: TextStyle(
                                    color: Color(0xFF6366F1),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTorboxRawList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
  }) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      itemCount: entries.length,
      itemBuilder: (context, listIndex) {
        final entry = entries[listIndex];
        final isSelected = selectedIndices.contains(entry.index);
        final subtitle = entry.file.name != entry.file.shortName
            ? entry.file.name
            : entry.file.absolutePath;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: _buildTorboxFileCard(
            entry: entry,
            isSelected: isSelected,
            onToggle: () => onToggle(entry.index),
            animationIndex: listIndex,
            subtitle: subtitle,
          ),
        );
      },
    );
  }

  Widget _buildTorboxGenericList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
  }) {
    if (entries.isEmpty) {
      return _buildEmptyFilesState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        _buildSectionHeader('All Files'),
        const SizedBox(height: 12),
        for (int i = 0; i < entries.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            child: _buildTorboxFileCard(
              entry: entries[i],
              isSelected: selectedIndices.contains(entries[i].index),
              onToggle: () => onToggle(entries[i].index),
              animationIndex: i,
              subtitle: entries[i].file.name != entries[i].file.shortName
                  ? entries[i].file.name
                  : entries[i].file.absolutePath,
            ),
          ),
      ],
    );
  }

  Widget _buildTorboxMovieView({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
  }) {
    final mainEntries = <_TorboxFileEntry>[];
    final sampleEntries = <_TorboxFileEntry>[];
    final extraEntries = <_TorboxFileEntry>[];

    for (final entry in entries) {
      final fileNameLower = entry.file.shortName.toLowerCase();
      if (_torboxFileLooksLikeVideo(entry.file)) {
        if (fileNameLower.contains('sample')) {
          sampleEntries.add(entry);
        } else {
          mainEntries.add(entry);
        }
      } else {
        extraEntries.add(entry);
      }
    }

    if (mainEntries.isEmpty && sampleEntries.isEmpty && extraEntries.isEmpty) {
      return _buildEmptyFilesState();
    }

    Widget buildSection(
      String title,
      List<_TorboxFileEntry> sectionEntries, {
      String? badge,
    }) {
      if (sectionEntries.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title),
          const SizedBox(height: 12),
          for (int i = 0; i < sectionEntries.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              child: _buildTorboxFileCard(
                entry: sectionEntries[i],
                isSelected: selectedIndices.contains(sectionEntries[i].index),
                onToggle: () => onToggle(sectionEntries[i].index),
                animationIndex: i,
                badge: badge,
                subtitle:
                    sectionEntries[i].file.name !=
                        sectionEntries[i].file.shortName
                    ? sectionEntries[i].file.name
                    : null,
              ),
            ),
          const SizedBox(height: 16),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        buildSection('Main', mainEntries, badge: 'Main'),
        buildSection('Sample', sampleEntries, badge: 'Sample'),
        buildSection('Extras', extraEntries, badge: 'Extra'),
      ],
    );
  }

  Widget _buildTorboxSeriesView({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required int? currentSeason,
    required ValueChanged<int?> onSeasonChange,
    required ValueChanged<int> onToggleFile,
    required void Function(int season, List<int> indices) onToggleSeason,
  }) {
    final seasonMap = <int, List<_TorboxFileEntry>>{};
    final otherEntries = <_TorboxFileEntry>[];

    for (final entry in entries) {
      final info = entry.seriesInfo;
      if (info.isSeries && info.season != null && info.episode != null) {
        seasonMap.putIfAbsent(info.season!, () => []).add(entry);
      } else {
        otherEntries.add(entry);
      }
    }

    for (final seasonEntries in seasonMap.values) {
      seasonEntries.sort((a, b) {
        final epA = a.seriesInfo.episode ?? 0;
        final epB = b.seriesInfo.episode ?? 0;
        return epA.compareTo(epB);
      });
    }

    final sortedSeasons = seasonMap.keys.toList()..sort();

    if (currentSeason != null && !seasonMap.containsKey(currentSeason)) {
      onSeasonChange(null);
    }

    if (currentSeason == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        children: [
          _buildSectionHeader('Seasons'),
          const SizedBox(height: 12),
          for (final seasonNumber in sortedSeasons)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1E293B).withValues(alpha: 0.8),
                    const Color(0xFF111827).withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF475569).withValues(alpha: 0.3),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onSeasonChange(seasonNumber),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            onToggleSeason(
                              seasonNumber,
                              seasonMap[seasonNumber]!
                                  .map((entry) => entry.index)
                                  .toList(),
                            );
                          },
                          child: Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(
                                alpha:
                                    seasonMap[seasonNumber]!.every(
                                      (entry) =>
                                          selectedIndices.contains(entry.index),
                                    )
                                    ? 0.9
                                    : seasonMap[seasonNumber]!.any(
                                        (entry) => selectedIndices.contains(
                                          entry.index,
                                        ),
                                      )
                                    ? 0.4
                                    : 0,
                              ),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFF10B981),
                                width: 2,
                              ),
                            ),
                            child:
                                seasonMap[seasonNumber]!.every(
                                  (entry) =>
                                      selectedIndices.contains(entry.index),
                                )
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : seasonMap[seasonNumber]!.any(
                                    (entry) =>
                                        selectedIndices.contains(entry.index),
                                  )
                                ? const Icon(
                                    Icons.remove,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Season $seasonNumber',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${seasonMap[seasonNumber]!.length} episodes',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: Colors.grey[500],
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (otherEntries.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSectionHeader('Extras'),
            const SizedBox(height: 12),
            for (int i = 0; i < otherEntries.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: _buildTorboxFileCard(
                  entry: otherEntries[i],
                  isSelected: selectedIndices.contains(otherEntries[i].index),
                  onToggle: () => onToggleFile(otherEntries[i].index),
                  animationIndex: i,
                  subtitle: otherEntries[i].file.name,
                  badge: 'Extra',
                ),
              ),
          ],
        ],
      );
    }

    final chosenSeasonEntries = seasonMap[currentSeason] ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () => onSeasonChange(null),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF6366F1),
                ),
                label: const Text(
                  'Back to seasons',
                  style: TextStyle(
                    color: Color(0xFF6366F1),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'Season $currentSeason',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            itemCount: chosenSeasonEntries.length,
            itemBuilder: (context, index) {
              final entry = chosenSeasonEntries[index];
              final info = entry.seriesInfo;
              final badge = info.episode != null
                  ? 'E${info.episode.toString().padLeft(2, '0')}'
                  : null;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                child: _buildTorboxFileCard(
                  entry: entry,
                  isSelected: selectedIndices.contains(entry.index),
                  onToggle: () => onToggleFile(entry.index),
                  animationIndex: index,
                  badge: badge,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTorboxFileCard({
    required _TorboxFileEntry entry,
    required bool isSelected,
    required VoidCallback onToggle,
    required int animationIndex,
    String? badge,
    String? subtitle,
  }) {
    final file = entry.file;
    final fileName = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    final isVideo = _torboxFileLooksLikeVideo(file);
    final sizeText = Formatters.formatFileSize(file.size);

    final selectionColor = isSelected
        ? const Color(0xFF8B5CF6).withValues(alpha: 0.5)
        : const Color(0xFF475569).withValues(alpha: 0.3);

    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 250 + (animationIndex * 40)),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1E293B).withValues(alpha: 0.85),
              const Color(0xFF111827).withValues(alpha: 0.7),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selectionColor, width: isSelected ? 2 : 1),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isVideo
                                ? [
                                    const Color(0xFFE50914),
                                    const Color(0xFFDC2626),
                                  ]
                                : [
                                    const Color(0xFFF59E0B),
                                    const Color(0xFFD97706),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  (isVideo
                                          ? const Color(0xFFE50914)
                                          : const Color(0xFFF59E0B))
                                      .withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          isVideo
                              ? Icons.play_arrow_rounded
                              : Icons.insert_drive_file_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    fileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(
                                            0xFF8B5CF6,
                                          ).withValues(alpha: 0.9)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF8B5CF6)
                                          : Colors.grey[600]!,
                                      width: 2,
                                    ),
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  sizeText,
                                  style: TextStyle(
                                    color: Colors.grey[300],
                                    fontSize: 12,
                                  ),
                                ),
                                if (badge != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xFF6366F1,
                                      ).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Text(
                                      badge,
                                      style: const TextStyle(
                                        color: Color(0xFF6366F1),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    );
  }

  Widget _buildEmptyFilesState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.folder_off_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No files available yet',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'We could not find any files for this torrent.',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
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

class _TorboxFileEntry {
  final TorboxFile file;
  final int index;
  final SeriesInfo seriesInfo;

  _TorboxFileEntry({
    required this.file,
    required this.index,
    required this.seriesInfo,
  });
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
