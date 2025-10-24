import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/torbox_file.dart';
import '../../models/torbox_torrent.dart';
import '../../services/torbox_service.dart';
import '../../services/torbox_torrent_control_service.dart';
import '../../services/storage_service.dart';
import '../../services/main_page_bridge.dart';
import '../../utils/formatters.dart';
import '../../utils/file_utils.dart';
import '../../utils/series_parser.dart';
import '../../widgets/stat_chip.dart';
import '../video_player_screen.dart';

class TorboxDownloadsScreen extends StatefulWidget {
  const TorboxDownloadsScreen({
    super.key,
    this.initialTorrentForAction,
    this.initialAction,
  });

  final TorboxTorrent? initialTorrentForAction;
  final TorboxQuickAction? initialAction;

  @override
  State<TorboxDownloadsScreen> createState() => _TorboxDownloadsScreenState();
}

class _TorboxDownloadsScreenState extends State<TorboxDownloadsScreen> {
  final ScrollController _scrollController = ScrollController();
  final List<TorboxTorrent> _torrents = [];
  final TextEditingController _magnetController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _initialLoad = true;
  int _offset = 0;
  String _errorMessage = '';
  String? _apiKey;
  TorboxTorrent? _pendingInitialTorrent;
  TorboxQuickAction? _pendingInitialAction;
  bool _initialActionHandled = false;

  static const int _limit = 50;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _pendingInitialTorrent = widget.initialTorrentForAction;
    _pendingInitialAction = widget.initialAction;
    _loadApiKeyAndTorrents();
  }

  @override
  void didUpdateWidget(TorboxDownloadsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTorrentForAction != null &&
        widget.initialAction != null) {
      _pendingInitialTorrent = widget.initialTorrentForAction;
      _pendingInitialAction = widget.initialAction;
      _initialActionHandled = false;
      _maybeTriggerInitialAction();
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
                          : () {
                              Navigator.of(sheetContext).pop();
                              _showComingSoon('Torbox ZIP download');
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

  Future<void> _handleAddToPlaylist(TorboxTorrent torrent) async {
    final videoFiles = torrent.files.where(_torboxFileLooksLikeVideo).toList();
    if (videoFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No playable Torbox video files found.')),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      final displayName = file.shortName.isNotEmpty
          ? file.shortName
          : FileUtils.getFileName(file.name);
      final added = await StorageService.addPlaylistItemRaw({
        'provider': 'torbox',
        'title': displayName.isNotEmpty ? displayName : torrent.name,
        'kind': 'single',
        'torboxTorrentId': torrent.id,
        'torboxFileId': file.id,
        'torrent_hash': torrent.hash,
        'sizeBytes': file.size,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added ? 'Added to playlist' : 'Already in playlist'),
          backgroundColor: added ? null : const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final ids = videoFiles.map((file) => file.id).toList();
    final added = await StorageService.addPlaylistItemRaw({
      'provider': 'torbox',
      'title': torrent.name,
      'kind': 'collection',
      'torboxTorrentId': torrent.id,
      'torboxFileIds': ids,
      'torrent_hash': torrent.hash,
      'count': videoFiles.length,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'Added collection to playlist' : 'Already in playlist',
        ),
        backgroundColor: added ? null : const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _copyTorrentLink(TorboxTorrent torrent) async {
    if (torrent.files.isEmpty) {
      _showComingSoon('No files available');
      return;
    }

    final file = torrent.files.firstWhere(
      (file) => !file.zipped,
      orElse: () => torrent.files.first,
    );

    await _copyTorboxFileLink(torrent, file);
  }

  Future<void> _copyTorboxFileLink(
    TorboxTorrent torrent,
    TorboxFile file,
  ) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final link = await TorboxService.requestFileDownloadLink(
        apiKey: key,
        torrentId: torrent.id,
        fileId: file.id,
      );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: link));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Download link copied to clipboard.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy link: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _copyTorrentZipLink(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    try {
      final zipUrl = TorboxService.createZipPermalink(key, torrent.id);
      await Clipboard.setData(ClipboardData(text: zipUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ZIP download link copied to clipboard.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy ZIP link: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  void _showTorboxTorrentMoreOptions(TorboxTorrent torrent) {
    final isMultiFile = torrent.files.length > 1;
    final options = <_TorboxMoreOption>[
      _TorboxMoreOption(
        icon: Icons.playlist_add,
        label: 'Add to Playlist',
        onTap: () => _handleAddToPlaylist(torrent),
      ),
      _TorboxMoreOption(
        icon: Icons.copy,
        label: 'Copy Link',
        onTap: isMultiFile
            ? () => _copyTorrentZipLink(torrent)
            : () => _copyTorrentLink(torrent),
      ),
      _TorboxMoreOption(
        icon: Icons.delete_outline,
        label: 'Delete Torrent',
        onTap: () => _confirmDeleteTorrent(torrent),
        destructive: true,
      ),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (final option in options) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: InkWell(
                          onTap: option.enabled
                              ? () async {
                                  Navigator.of(sheetContext).pop();
                                  await option.onTap();
                                }
                              : null,
                          borderRadius: BorderRadius.circular(16),
                          splashColor: option.enabled
                              ? const Color(0xFF6366F1).withValues(alpha: 0.2)
                              : Colors.transparent,
                          highlightColor: option.enabled
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.transparent,
                          child: Opacity(
                            opacity: option.enabled ? 1.0 : 0.45,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF111C32),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(
                                    0xFF475569,
                                  ).withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    option.icon,
                                    size: 20,
                                    color: option.destructive
                                        ? const Color(0xFFEF4444)
                                        : Colors.white,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option.label,
                                      style: TextStyle(
                                        color: option.destructive
                                            ? const Color(0xFFEF4444)
                                            : Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handlePlayTorrent(TorboxTorrent torrent) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final videoFiles = torrent.files.where((file) {
      if (file.zipped) return false;
      return _torboxFileLooksLikeVideo(file);
    }).toList();

    debugPrint(
      'TorboxPlay: torrentId=${torrent.id} files=${videoFiles.length} name="${torrent.name}"',
    );

    if (videoFiles.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No playable video files found in this torrent.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    if (videoFiles.length == 1) {
      final file = videoFiles.first;
      try {
        final streamUrl = await _requestTorboxStreamUrl(
          apiKey: key,
          torrent: torrent,
          file: file,
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => VideoPlayerScreen(
              videoUrl: streamUrl,
              title: torrent.name,
              subtitle: Formatters.formatFileSize(file.size),
            ),
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to play file: ${_formatTorboxError(e)}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
      return;
    }

    final candidates = videoFiles.map((file) {
      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      return _TorboxEpisodeCandidate(
        file: file,
        displayName: displayName,
        info: info,
      );
    }).toList();

    final filenames = candidates.map((entry) => entry.displayName).toList();
    final bool isSeriesCollection =
        candidates.length > 1 && SeriesParser.isSeriesPlaylist(filenames);

    final sortedCandidates = [...candidates];
    sortedCandidates.sort((a, b) {
      final aInfo = a.info;
      final bInfo = b.info;

      final aIsSeries =
          aInfo.isSeries && aInfo.season != null && aInfo.episode != null;
      final bIsSeries =
          bInfo.isSeries && bInfo.season != null && bInfo.episode != null;

      if (aIsSeries && bIsSeries) {
        final seasonCompare = (aInfo.season ?? 0).compareTo(bInfo.season ?? 0);
        if (seasonCompare != 0) return seasonCompare;

        final episodeCompare = (aInfo.episode ?? 0).compareTo(
          bInfo.episode ?? 0,
        );
        if (episodeCompare != 0) return episodeCompare;
      } else if (aIsSeries != bIsSeries) {
        return aIsSeries ? -1 : 1;
      }

      final aName = a.displayName.toLowerCase();
      final bName = b.displayName.toLowerCase();
      return aName.compareTo(bName);
    });

    int startIndex = 0;
    if (isSeriesCollection) {
      startIndex = sortedCandidates.indexWhere(
        (candidate) =>
            candidate.info.isSeries &&
            candidate.info.season != null &&
            candidate.info.episode != null,
      );
      if (startIndex == -1) {
        startIndex = 0;
      }
    }

    final seriesInfos = sortedCandidates
        .map((candidate) => candidate.info)
        .toList();

    debugPrint(
      'TorboxPlay: isSeries=$isSeriesCollection startIndex=$startIndex (season=${startIndex < seriesInfos.length ? seriesInfos[startIndex].season : 'n/a'} episode=${startIndex < seriesInfos.length ? seriesInfos[startIndex].episode : 'n/a'})',
    );

    String initialUrl = '';
    try {
      initialUrl = await _requestTorboxStreamUrl(
        apiKey: key,
        torrent: torrent,
        file: sortedCandidates[startIndex].file,
      );
    } catch (e) {
      debugPrint(
        'TorboxDownloadsScreen: failed to prefetch initial stream for torrent=${torrent.id} fileIndex=$startIndex error=$e',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to prepare stream: ${_formatTorboxError(e)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    final playlistEntries = <PlaylistEntry>[];
    for (int i = 0; i < sortedCandidates.length; i++) {
      final candidate = sortedCandidates[i];
      final info = candidate.info;
      final displayName = candidate.displayName;
      final episodeLabel = _formatTorboxPlaylistTitle(
        info: info,
        fallback: displayName,
        isSeriesCollection: isSeriesCollection,
      );
      final combinedTitle = _composeTorboxEntryTitle(
        seriesTitle: info.title,
        episodeLabel: episodeLabel,
        isSeriesCollection: isSeriesCollection,
        fallback: displayName,
      );
      playlistEntries.add(
        PlaylistEntry(
          url: i == startIndex ? initialUrl : '',
          title: combinedTitle,
          provider: 'torbox',
          torboxTorrentId: torrent.id,
          torboxFileId: candidate.file.id,
          sizeBytes: candidate.file.size,
          torrentHash: torrent.hash.isNotEmpty ? torrent.hash : null,
        ),
      );

      debugPrint(
        'TorboxPlay: entry[$i] title="$combinedTitle" season=${info.season} episode=${info.episode}',
      );
    }

    final totalBytes = sortedCandidates.fold<int>(
      0,
      (sum, entry) => sum + entry.file.size,
    );
    final subtitle =
        '${playlistEntries.length} ${isSeriesCollection ? 'episodes' : 'files'} • ${Formatters.formatFileSize(totalBytes)}';

    debugPrint(
      'TorboxDownloadsScreen: Play torrent ${torrent.id} (${playlistEntries.length} entries, startIndex=$startIndex, isSeries=$isSeriesCollection)',
    );

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(
          videoUrl: initialUrl,
          title: torrent.name,
          subtitle: subtitle,
          playlist: playlistEntries,
          startIndex: startIndex,
        ),
      ),
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
    _scrollController.dispose();
    _magnetController.dispose();
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

      _maybeTriggerInitialAction();

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

  String _torboxDisplayName(TorboxFile file) {
    if (file.shortName.isNotEmpty) {
      return file.shortName;
    }
    if (file.name.isNotEmpty) {
      return FileUtils.getFileName(file.name);
    }
    return 'File ${file.id}';
  }

  int _findFirstEpisodeIndex(List<SeriesInfo> infos) {
    int startIndex = 0;
    int? bestSeason;
    int? bestEpisode;

    for (int i = 0; i < infos.length; i++) {
      final info = infos[i];
      final season = info.season;
      final episode = info.episode;
      if (!info.isSeries || season == null || episode == null) {
        continue;
      }

      final bool isBetterSeason = bestSeason == null || season < bestSeason;
      final bool isBetterEpisode =
          bestSeason != null &&
          season == bestSeason &&
          (bestEpisode == null || episode < bestEpisode);

      if (isBetterSeason || isBetterEpisode) {
        bestSeason = season;
        bestEpisode = episode;
        startIndex = i;
      }
    }

    return startIndex;
  }

  void _maybeTriggerInitialAction() {
    if (_initialActionHandled) {
      return;
    }
    final pendingTorrent = _pendingInitialTorrent;
    final pendingAction = _pendingInitialAction;
    if (pendingTorrent == null || pendingAction == null) {
      return;
    }

    TorboxTorrent? target;
    for (final torrent in _torrents) {
      if (torrent.id == pendingTorrent.id) {
        target = torrent;
        break;
      }
    }

    if (target == null) {
      return;
    }

    _initialActionHandled = true;
    _pendingInitialTorrent = null;
    _pendingInitialAction = null;

    final selected = target;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (pendingAction) {
        case TorboxQuickAction.play:
          _handlePlayTorrent(selected);
          break;
        case TorboxQuickAction.download:
          _showDownloadOptions(selected);
          break;
        case TorboxQuickAction.files:
          _showTorboxFileSelectionSheet(selected);
          break;
      }
    });
  }

  Future<String> _requestTorboxStreamUrl({
    required String apiKey,
    required TorboxTorrent torrent,
    required TorboxFile file,
  }) async {
    final url = await TorboxService.requestFileDownloadLink(
      apiKey: apiKey,
      torrentId: torrent.id,
      fileId: file.id,
    );
    if (url.isEmpty) {
      throw Exception('Torbox returned an empty stream URL');
    }
    return url;
  }

  String _formatTorboxPlaylistTitle({
    required SeriesInfo info,
    required String fallback,
    required bool isSeriesCollection,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final season = info.season;
    final episode = info.episode;
    if (info.isSeries && season != null && episode != null) {
      final seasonLabel = season.toString().padLeft(2, '0');
      final episodeLabel = episode.toString().padLeft(2, '0');
      final description = info.episodeTitle?.trim().isNotEmpty == true
          ? info.episodeTitle!.trim()
          : info.title?.trim().isNotEmpty == true
          ? info.title!.trim()
          : fallback;
      return 'S${seasonLabel}E$episodeLabel · $description';
    }

    return fallback;
  }

  String _composeTorboxEntryTitle({
    required String? seriesTitle,
    required String episodeLabel,
    required bool isSeriesCollection,
    required String fallback,
  }) {
    if (!isSeriesCollection) {
      return fallback;
    }

    final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
    if (cleanSeries != null && cleanSeries.isNotEmpty) {
      return '$cleanSeries $episodeLabel';
    }

    return fallback;
  }

  String _formatTorboxError(Object error) {
    final raw = error.toString();
    return raw.replaceFirst('Exception: ', '').trim();
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
    bool isProcessing = false;
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
              final selectedEntries =
                  entries
                      .where((entry) => selectedIndices.contains(entry.index))
                      .toList()
                    ..sort((a, b) => a.index.compareTo(b.index));
              final selectedBytes = selectedEntries.fold<int>(
                0,
                (previousValue, entry) => previousValue + entry.file.size,
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
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
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
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
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
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
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
                  onCopy: (entry) => _copyTorboxFileLink(torrent, entry.file),
                );
              }

              final selectedCount = selectedEntries.length;
              final totalCount = entries.length;
              final selectionSummary = totalCount == 0
                  ? 'No files available'
                  : selectedCount == totalCount
                  ? 'All $totalCount files selected'
                  : '$selectedCount of $totalCount files selected';
              final selectedSizeText = selectedCount == 0
                  ? '0 B'
                  : Formatters.formatFileSize(selectedBytes);

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
                          vertical: 12,
                        ),
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[600],
                            borderRadius: BorderRadius.circular(2),
                          ),
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
                                    'Selected size: $selectedSizeText',
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
                                    onPressed: isProcessing
                                        ? null
                                        : () async {
                                            setSheetState(
                                              () => isProcessing = true,
                                            );
                                            final closed =
                                                await _enqueueTorboxDownloads(
                                                  torrent: torrent,
                                                  entriesToDownload: entries,
                                                  sheetContext: sheetContext,
                                                );
                                            if (!closed) {
                                              setSheetState(
                                                () => isProcessing = false,
                                              );
                                            }
                                          },
                                    icon: const Icon(Icons.download_rounded),
                                    label: Text(
                                      isProcessing
                                          ? 'Preparing…'
                                          : 'Download All',
                                    ),
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
                                if (selectedEntries.isNotEmpty) ...[
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: isProcessing
                                          ? null
                                          : () async {
                                              setSheetState(
                                                () => isProcessing = true,
                                              );
                                              final closed =
                                                  await _enqueueTorboxDownloads(
                                                    torrent: torrent,
                                                    entriesToDownload:
                                                        selectedEntries,
                                                    sheetContext: sheetContext,
                                                  );
                                              if (!closed) {
                                                setSheetState(
                                                  () => isProcessing = false,
                                                );
                                              }
                                            },
                                      icon: const Icon(Icons.checklist_rounded),
                                      label: Text(
                                        isProcessing
                                            ? 'Preparing…'
                                            : 'Download Selected',
                                      ),
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

  Future<bool> _enqueueTorboxDownloads({
    required TorboxTorrent torrent,
    required List<_TorboxFileEntry> entriesToDownload,
    required BuildContext sheetContext,
  }) async {
    final key = _apiKey;
    if (key == null || key.isEmpty) {
      Navigator.of(sheetContext).pop();
      if (mounted) {
        _showComingSoon('Add Torbox API key');
      }
      return true;
    }

    Navigator.of(sheetContext).pop();

    if (!mounted) {
      return true;
    }

    final count = entriesToDownload.length;
    debugPrint(
      'TorboxDownloadsScreen: download placeholder triggered for torrent ${torrent.id} ($count item(s)).',
    );
    if (count == 0) {
      _showComingSoon('No files selected');
      return true;
    }

    _showComingSoon('Torbox downloads');
    return true;
  }

  Widget _buildTorboxRawList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
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
            onCopy: onCopy == null ? null : () => onCopy(entry),
          ),
        );
      },
    );
  }

  Widget _buildTorboxGenericList({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
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
              onCopy: onCopy == null ? null : () => onCopy(entries[i]),
            ),
          ),
      ],
    );
  }

  Widget _buildTorboxMovieView({
    required List<_TorboxFileEntry> entries,
    required Set<int> selectedIndices,
    required ValueChanged<int> onToggle,
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
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
                onCopy: onCopy == null ? null : () => onCopy(sectionEntries[i]),
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
    Future<void> Function(_TorboxFileEntry entry)? onCopy,
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
                  onCopy: onCopy == null ? null : () => onCopy(otherEntries[i]),
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
                  onCopy: onCopy == null ? null : () => onCopy(entry),
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
    Future<void> Function()? onCopy,
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
                  if (onCopy != null) ...[
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          if (onCopy != null) {
                            await onCopy();
                          }
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text(
                          'Copy',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
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

  Future<void> _showAddMagnetDialog() async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    await _autoPasteMagnetLink();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Magnet Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _magnetController,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Paste magnet link here…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => _handleAddMagnet(dialogContext),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _autoPasteMagnetLink() async {
    if (_magnetController.text.trim().isNotEmpty) return;
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboardData?.text?.trim();
    if (text != null && text.startsWith('magnet:?')) {
      _magnetController.text = text;
    }
  }

  void _handleAddMagnet(BuildContext dialogContext) {
    final magnetLink = _magnetController.text.trim();
    if (magnetLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link.')),
      );
      return;
    }

    if (!_isValidMagnetLink(magnetLink)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid magnet link.')),
      );
      return;
    }

    Navigator.of(dialogContext).pop();
    _addMagnetToTorbox(magnetLink);
  }

  bool _isValidMagnetLink(String link) {
    final trimmed = link.trim();
    if (!trimmed.startsWith('magnet:?')) return false;
    if (!trimmed.toLowerCase().contains('xt=urn:btih:')) return false;
    return trimmed.length >= 50;
  }

  Future<void> _addMagnetToTorbox(String magnetLink) async {
    final apiKey = _apiKey;
    if (apiKey == null || apiKey.isEmpty) {
      _showComingSoon('Add Torbox API key');
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);
    var dialogClosed = false;

    void closeDialogIfOpen() {
      if (!dialogClosed && navigator.canPop()) {
        navigator.pop();
        dialogClosed = true;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const AlertDialog(
          title: Text('Adding torrent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Submitting magnet to Torbox…'),
            ],
          ),
        );
      },
    );

    try {
      final response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: true,
        addOnlyIfCached: true,
      );

      if (!mounted) return;

      closeDialogIfOpen();

      final success = response['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = (response['error'] ?? 'Failed to add magnet')
            .toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: const Color(0xFFB91C1C),
          ),
        );
        return;
      }

      _magnetController.clear();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Magnet added to Torbox.')));

      await _refresh();
    } catch (e) {
      if (!mounted) return;
      closeDialogIfOpen();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to add magnet: ${e.toString().replaceFirst('Exception: ', '')}',
          ),
          backgroundColor: const Color(0xFFB91C1C),
        ),
      );
    }
  }

  void _openSettings() {
    MainPageBridge.switchTab?.call(6);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const SizedBox(height: 8),
          _buildToolbar(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildTorrentList(),
            ),
          ),
        ],
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
          onPlay: () => _handlePlayTorrent(torrent),
          onDownload: () => _showDownloadOptions(torrent),
          onMoreOptions: () => _showTorboxTorrentMoreOptions(torrent),
        );
      },
    );
  }

  Widget _buildViewSelector() {
    final theme = Theme.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.1),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: 'Torrents',
          dropdownColor: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          iconEnabledColor: theme.colorScheme.onPrimaryContainer,
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
          ),
          items: const [
            DropdownMenuItem(value: 'Torrents', child: Text('Torrents')),
          ],
          onChanged: (_) {},
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Row(
        children: [
          _buildViewSelector(),
          const Spacer(),
          Tooltip(
            message: 'Add magnet link',
            child: IconButton(
              onPressed: _showAddMagnetDialog,
              icon: const Icon(Icons.add_circle_outline),
              color: theme.colorScheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Delete all torrents',
            child: IconButton(
              onPressed: _torrents.isEmpty ? null : _confirmDeleteAll,
              icon: const Icon(Icons.delete_sweep),
              color: const Color(0xFFEF4444),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}

class _TorboxTorrentCard extends StatelessWidget {
  const _TorboxTorrentCard({
    required this.torrent,
    required this.onPlay,
    required this.onDownload,
    required this.onMoreOptions,
  });

  final TorboxTorrent torrent;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final VoidCallback onMoreOptions;

  @override
  Widget build(BuildContext context) {
    final cachedAt = torrent.cachedAt ?? torrent.createdAt;
    final safeProgress = torrent.progress.clamp(0, 1);
    final progressPercent = (safeProgress * 100).round();
    final borderColor = Colors.white.withValues(alpha: 0.08);
    final glowColor = const Color(0xFF6366F1).withValues(alpha: 0.08);

    const playColor = Color(0xFF7F1D1D);
    const downloadColor = Color(0xFF065F46);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2A44), Color(0xFF111C32)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: glowColor,
            blurRadius: 26,
            offset: const Offset(0, 6),
          ),
        ],
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
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(width: 8),
                    _buildMoreOptionsButton(onMoreOptions),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF131E33), Color(0xFF0B1224)],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border(
                top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 380;
                  final playButton = _buildPrimaryButton(
                    icon: Icons.play_arrow,
                    label: 'Play',
                    backgroundColor: playColor,
                    onPressed: onPlay,
                  );
                  final downloadButton = _buildPrimaryButton(
                    icon: Icons.download_rounded,
                    label: 'Download',
                    backgroundColor: downloadColor,
                    onPressed: onDownload,
                  );

                  if (isCompact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: double.infinity, child: playButton),
                        const SizedBox(height: 8),
                        SizedBox(width: double.infinity, child: downloadButton),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: playButton),
                      const SizedBox(width: 12),
                      Expanded(child: downloadButton),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMoreOptionsButton(VoidCallback onPressed) {
    return IconButton(
      onPressed: onPressed,
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'More options',
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF111C32),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: const Color(0xFF475569).withValues(alpha: 0.3),
          ),
        ),
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

class _TorboxEpisodeCandidate {
  final TorboxFile file;
  final SeriesInfo info;
  final String displayName;

  _TorboxEpisodeCandidate({
    required this.file,
    required this.info,
    required this.displayName,
  });

  int get size => file.size;
}

class _TorboxMoreOption {
  const _TorboxMoreOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;
  final bool destructive;
  final bool enabled;
}
