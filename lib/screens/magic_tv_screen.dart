import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../models/torrent.dart';
import '../services/torrent_service.dart';
import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import 'video_player_screen.dart';

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  final TextEditingController _keywordsController = TextEditingController();
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> _queue = [];
  bool _isBusy = false;
  String _status = '';
  // Advanced options
  bool _startRandom = true;
  bool _hideSeekbar = true;
  bool _showWatermark = true;
  bool _showVideoTitle = false;
  bool _hideOptions = true;
  bool _hideBackButton = true;
  // De-dupe sets for RD-restricted entries
  final Set<String> _seenRestrictedLinks = {};
  final Set<String> _seenLinkWithTorrentId = {};
  // Prefetch state
  static const int _minPrepared = 6; // maintain at least 6 prepared items
  static const int _lookaheadWindow = 10; // window near head to keep prepared
  bool _prefetchRunning = false;
  bool _prefetchStopRequested = false;
  Future<void>? _prefetchTask;
  String? _activeApiKey;
  final Set<String> _inflightInfohashes = {};
  final List<PlaylistEntry> _tvPlaylist = [];
  final ValueNotifier<int> _playlistVersion = ValueNotifier<int>(0);
  final Set<String> _playlistUrlSet = {};
  int _currentPlaylistIndex = -1;
  bool _playlistEnsureRunning = false;
  final Random _random = Random();

  // Progress UI state
  final ValueNotifier<List<String>> _progress = ValueNotifier<List<String>>([]);
  BuildContext? _progressSheetContext;
  bool _progressOpen = false;
  int _lastQueueSize = 0;
  DateTime? _lastSearchAt;
  bool _launchedPlayer = false;
  bool _stage2Running = false;
  int? _originalMaxCap;
  bool _capRestoredByStage2 = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    // Ensure prefetch loop is stopped if this screen is disposed mid-run
    _prefetchStopRequested = true;
    _stopPrefetch();
    // Cancel Stage 2 if running
    _stage2Running = false;
    _playlistVersion.dispose();
    _progress.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final hideSeekbar = await StorageService.getDebrifyTvHideSeekbar();
    final showWatermark = await StorageService.getDebrifyTvShowWatermark();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    final hideOptions = await StorageService.getDebrifyTvHideOptions();
    final hideBackButton = await StorageService.getDebrifyTvHideBackButton();
    
    if (mounted) {
      setState(() {
        _startRandom = startRandom;
        _hideSeekbar = hideSeekbar;
        _showWatermark = showWatermark;
        _showVideoTitle = showVideoTitle;
        _hideOptions = hideOptions;
        _hideBackButton = hideBackButton;
      });
    }
  }

  List<String> _parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _clearPlaylistState() {
    _tvPlaylist.clear();
    _playlistUrlSet.clear();
    _currentPlaylistIndex = -1;
    _notifyPlaylistChanged();
  }

  void _notifyPlaylistChanged() {
    _playlistVersion.value = _playlistVersion.value + 1;
  }

  String _inferTitleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : url;
    return Uri.decodeComponent(lastSegment);
  }

  int _targetPlaylistLength([int? explicitTarget]) {
    if (explicitTarget != null) {
      return explicitTarget;
    }
    if (!_launchedPlayer || _currentPlaylistIndex < 0) {
      return 1;
    }
    return _currentPlaylistIndex + 1 + _minPrepared;
  }

  Future<void> _ensurePlaylistDepth([int? explicitTarget]) async {
    final int target = _targetPlaylistLength(explicitTarget);
    if (_playlistEnsureRunning) {
      while (_playlistEnsureRunning) {
        await Future.delayed(const Duration(milliseconds: 120));
      }
      if (_tvPlaylist.length >= target) {
        return;
      }
    }
    _playlistEnsureRunning = true;
    try {
      while (mounted && !_prefetchStopRequested && _tvPlaylist.length < target) {
        final int searchLimit = _queue.length < _lookaheadWindow ? _queue.length : _lookaheadWindow;
        int preparedIndex = -1;
        for (int i = 0; i < searchLimit; i++) {
          final item = _queue[i];
          if (item is Map && item['type'] == 'rd_restricted') {
            preparedIndex = i;
            break;
          }
        }
        if (preparedIndex == -1) {
          final int torrentIndex = _findUnpreparedTorrentIndexInLookahead();
          if (torrentIndex == -1) {
            break;
          }
          await _prefetchOneAtIndex(torrentIndex);
          continue;
        }

        final Map<String, dynamic> prepared = _queue.removeAt(preparedIndex) as Map<String, dynamic>;
        final playlistEntry = await _convertRestrictedMapToEntry(prepared);
        if (playlistEntry == null) {
          continue;
        }
        if (_playlistUrlSet.add(playlistEntry.url)) {
          _tvPlaylist.add(playlistEntry);
          _notifyPlaylistChanged();
        }
      }
    } finally {
      _playlistEnsureRunning = false;
    }
  }

  Future<PlaylistEntry?> _convertRestrictedMapToEntry(Map<String, dynamic> item) async {
    try {
      String directUrl = (item['downloadLink'] as String?) ?? '';
      if (directUrl.isEmpty) {
        final String? restricted = item['restrictedLink'] as String?;
        if (restricted == null || restricted.isEmpty) {
          return null;
        }
        final String? apiKey = _activeApiKey ?? await StorageService.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: Missing API key while unrestricting playlist entry.');
          return null;
        }
        final unrestrict = await DebridService.unrestrictLink(apiKey, restricted);
        directUrl = unrestrict['download'] as String? ?? '';
        if (directUrl.isEmpty) {
          debugPrint('DebrifyTV: Unrestrict returned empty download link.');
          return null;
        }
      }

      if (_playlistUrlSet.contains(directUrl)) {
        return null;
      }

      final displayName = (item['displayName'] as String?)?.trim() ?? '';
      final inferred = _inferTitleFromUrl(directUrl).trim();
      final title = inferred.isNotEmpty
          ? inferred
          : (displayName.isNotEmpty ? displayName : 'Debrify TV');

      final double? randomFraction = _startRandom ? (0.1 + (0.8 * _random.nextDouble())) : null;
      return PlaylistEntry(
        url: directUrl,
        title: title,
        restrictedLink: item['restrictedLink'] as String?,
        torrentHash: item['torrentHash'] as String?,
        sizeBytes: item['sizeBytes'] as int?,
        randomStartFraction: randomFraction,
      );
    } catch (e) {
      debugPrint('DebrifyTV: Failed to convert prepared entry: $e');
      return null;
    }
  }

  void _handlePlaylistIndexChanged(int index) {
    _currentPlaylistIndex = index;
    unawaited(_ensurePlaylistDepth());
  }

  Future<Map<String, String>?> _requestMagicNextForPlayer() async {
    final int desiredIndex = _currentPlaylistIndex < 0 ? 0 : _currentPlaylistIndex + 1;
    final int targetLength = desiredIndex + 1;
    await _ensurePlaylistDepth(targetLength);
    if (desiredIndex < _tvPlaylist.length) {
      final entry = _tvPlaylist[desiredIndex];
      return {'url': entry.url, 'title': entry.title};
    }
    return null;
  }

  Future<void> _watch() async {
    _launchedPlayer = false;
    _clearPlaylistState();
    _prefetchStopRequested = false;
    void _log(String m) {
      final copy = List<String>.from(_progress.value)..add(m);
      _progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }
    final text = _keywordsController.text.trim();
    debugPrint('DebrifyTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      setState(() {
        _status = 'Enter one or more keywords, separated by commas';
      });
      debugPrint('DebrifyTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = _parseKeywords(text);
    debugPrint('DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}');
    if (keywords.isEmpty) {
      setState(() {
        _status = 'Enter valid keywords';
      });
      debugPrint('DebrifyTV: Aborting. Parsed keywords became empty after trimming.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Searching...';
      _queue.clear();
    });

    // show non-dismissible loading modal
    _progress.value = [];
    _progressOpen = true;
    // ignore: unawaited_futures
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (ctx) {
        _progressSheetContext = ctx;
        return WillPopScope(
          onWillPop: () async => false, // Prevent dismissing with back button
          child: Dialog(
            backgroundColor: const Color(0xFF0F0F0F),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.9,
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Compact header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE50914), Color(0xFFB71C1C)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE50914).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Debrify TV', 
                          style: TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.w800, 
                            fontSize: 18
                          )
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Smaller loading animation
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE50914), Color(0xFFFF6B6B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE50914).withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Compact message
                    const Text(
                      'Debrify TV is working its magic...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    
                    // Compact timing information
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.access_time_rounded, color: Colors.blue[300], size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Usually takes 20-30 seconds',
                                style: TextStyle(
                                  color: Colors.blue[200],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rare keywords may take longer',
                            style: TextStyle(
                              color: Colors.blue[300],
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Compact cancel button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() {
                            _isBusy = false;
                            _status = '';
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() { _progressOpen = false; _progressSheetContext = null; });

    // Silent approach - no progress logging needed

    // Stage 1: Use a small cap to get the first playable quickly
    const int _stage1Cap = 50;
    _originalMaxCap = await StorageService.getMaxTorrentsCsvResults();
    debugPrint('DebrifyTV: Temporarily setting Torrents CSV max from ${_originalMaxCap} to $_stage1Cap for Stage 1');
    try {
      await StorageService.setMaxTorrentsCsvResults(_stage1Cap);

      // Require RD API key early so we can prefetch as soon as results arrive
      final apiKeyEarly = await StorageService.getApiKey();
      if (apiKeyEarly == null || apiKeyEarly.isEmpty) {
        if (!mounted) return;
        _log('❌ Real Debrid API key not found - please add it in Settings');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
        );
        debugPrint('DebrifyTV: Missing Real Debrid API key.');
        return;
      }

      _activeApiKey = apiKeyEarly;
      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        debugPrint('DebrifyTV: requestMagicNext() invoked. playlist=${_tvPlaylist.length}, currentIndex=$_currentPlaylistIndex');
        final result = await _requestMagicNextForPlayer();
        if (result != null) {
          final resolved = (result['title'] ?? '').trim();
          if (resolved.isNotEmpty) {
            firstTitle = resolved;
          }
        }
        return result;
      }

      final Map<String, Torrent> dedupByInfohash = {};

      // Silent approach - no progress logging needed
      
      // Launch per-keyword searches in parallel and process as they complete
      final futures = keywords.map((kw) {
        debugPrint('DebrifyTV: Searching engines for "$kw"...');
        return TorrentService.searchAllEngines(kw, useTorrentsCsv: true, usePirateBay: true);
      }).toList();

      await for (final result in Stream.fromFutures(futures)) {
        final List<Torrent> torrents = (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
        final engineCounts = (result['engineCounts'] as Map<String, int>?) ?? const {};
        debugPrint('DebrifyTV: Partial results received: total=${torrents.length}, engineCounts=$engineCounts');
        int added = 0;
        for (final t in torrents) {
          if (!dedupByInfohash.containsKey(t.infohash)) {
            dedupByInfohash[t.infohash] = t;
            added++;
          }
        }
        if (added > 0) {
          final combined = dedupByInfohash.values.toList();
          combined.shuffle(Random());
          _queue
            ..clear()
            ..addAll(combined);
          _lastQueueSize = _queue.length;
          _lastSearchAt = DateTime.now();
          // Silent approach - no progress logging needed
          setState(() {
            _status = 'Preparing your content...';
          });

          // Do not start prefetch until player launches

          // Try to launch player as soon as a playable stream is available
          if (!_launchedPlayer) {
            final first = await requestMagicNext();
            if (first != null && mounted && !_launchedPlayer) {
              _launchedPlayer = true;
              final firstUrl = first['url'] ?? '';
              final firstTitleResolved = (first['title'] ?? firstTitle).trim().isNotEmpty ? (first['title'] ?? firstTitle) : firstTitle;
              if (_progressOpen && _progressSheetContext != null) {
                Navigator.of(_progressSheetContext!).pop();
              }
              debugPrint('DebrifyTV: Launching player early. Remaining queue=${_queue.length}');

              // Start background prefetch only while player is active
              if (apiKeyEarly != null && apiKeyEarly.isNotEmpty) {
                _activeApiKey = apiKeyEarly;
                _startPrefetch();
                unawaited(_ensurePlaylistDepth());
              }

              // Stage 2: Expand search in background to full (500) WHILE user watches
              if (!_stage2Running) {
                _stage2Running = true;
                // ignore: unawaited_futures
                (() async {
                  debugPrint('DebrifyTV: Stage 2 expansion starting. Temporarily setting max to 500');
                  try {
                    await StorageService.setMaxTorrentsCsvResults(500);
                    final futures2 = keywords.map((kw) {
                      debugPrint('DebrifyTV: [Stage 2] Searching engines for "$kw"...');
                      return TorrentService.searchAllEngines(kw, useTorrentsCsv: true, usePirateBay: true);
                    }).toList();
                    await for (final res2 in Stream.fromFutures(futures2)) {
                      final List<Torrent> more = (res2['torrents'] as List<Torrent>?) ?? <Torrent>[];
                      int added2 = 0;
                      for (final t in more) {
                        if (!dedupByInfohash.containsKey(t.infohash)) {
                          dedupByInfohash[t.infohash] = t;
                          added2++;
                        }
                      }
                      if (added2 > 0) {
                        final combined2 = dedupByInfohash.values.toList();
                        combined2.shuffle(Random());
                        // Preserve already prepared RD links at the head
                        final preparedOld = _queue
                            .where((e) => e is Map && e['type'] == 'rd_restricted')
                            .take(_minPrepared)
                            .toList();
                        _queue
                          ..clear()
                          ..addAll(preparedOld)
                          ..addAll(combined2);
                        _lastQueueSize = _queue.length;
                        _lastSearchAt = DateTime.now();
                        debugPrint('DebrifyTV: [Stage 2] Queue expanded to ${_queue.length} (preserved ${preparedOld.length} prepared in head)');
                        unawaited(_ensurePlaylistDepth());
                      }
                    }
                  } catch (e) {
                    debugPrint('DebrifyTV: Stage 2 expansion failed: $e');
                  } finally {
                    final restoreTo = _originalMaxCap ?? 50;
                    await StorageService.setMaxTorrentsCsvResults(restoreTo);
                    _stage2Running = false;
                    _capRestoredByStage2 = true;
                    debugPrint('DebrifyTV: Stage 2 done. Restored Torrents CSV max to $restoreTo');
                  }
                })();
              }

              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => VideoPlayerScreen(
                    videoUrl: firstUrl,
                    title: firstTitleResolved,
                    playlist: _tvPlaylist,
                    startIndex: 0,
                    startFromRandom: _startRandom,
                    hideSeekbar: _hideSeekbar,
                    showWatermark: _showWatermark,
                    showVideoTitle: _showVideoTitle,
                    hideOptions: _hideOptions,
                    hideBackButton: _hideBackButton,
                    requestMagicNext: requestMagicNext,
                    externalPlaylistVersion: _playlistVersion,
                    onPlaylistIndexChanged: _handlePlaylistIndexChanged,
                  ),
                ),
              );

              // Stop prefetch when player exits
              await _stopPrefetch();
              _clearPlaylistState();
              _activeApiKey = null;
            }
          }
        }
      }

      // Final queue snapshot (if we didn't launch early)
      if (!_launchedPlayer) {
        debugPrint('DebrifyTV: Queue prepared. size=${_queue.length}');
        _lastQueueSize = _queue.length;
        _lastSearchAt = DateTime.now();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Search failed: $e';
      });
      debugPrint('DebrifyTV: Search failed: $e');
    } finally {
      // Restore only if Stage 2 didn't already restore
      if (!_stage2Running && !_capRestoredByStage2) {
        final restoreTo = _originalMaxCap ?? 50;
        await StorageService.setMaxTorrentsCsvResults(restoreTo);
        debugPrint('DebrifyTV: Restored Torrents CSV max to $restoreTo after Stage 1');
      }
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }

    if (!mounted) return;
    if (_queue.isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('❌ No results found - trying different search strategies');
      
      // Close popup and show user-friendly message
      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
        _progressOpen = false;
        _progressSheetContext = null;
      }
      
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = 'No results found. Try different keywords.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No results found. Try different keywords or check your internet connection.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // If we already launched the player early, we're done here
    if (_launchedPlayer) {
      if (!mounted) return;
      setState(() {
        _status = '';
      });
      return;
    }

    // Build a provider for "next" requests that reuses the same queue and keywords
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
      );
      debugPrint('MagicTV: Missing Real Debrid API key.');
      return;
    }

    String firstTitle = 'Debrify TV';
    _activeApiKey = apiKey;

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint('MagicTV: requestMagicNext() invoked. playlist=${_tvPlaylist.length}, currentIndex=$_currentPlaylistIndex');
      final result = await _requestMagicNextForPlayer();
      if (result != null) {
        final resolved = (result['title'] ?? '').trim();
        if (resolved.isNotEmpty) {
          firstTitle = resolved;
        }
      }
      return result;
    }

    setState(() {
      _status = 'Finding a playable stream...';
      _isBusy = true;
    });
    _log('🎬 Selecting the best quality stream for you');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        // Close popup and show user-friendly message
        if (_progressOpen && _progressSheetContext != null) {
          Navigator.of(_progressSheetContext!).pop();
          _progressOpen = false;
          _progressSheetContext = null;
        }
        
        if (mounted) {
          setState(() {
            _isBusy = false;
            _status = 'No playable torrents found. Try different keywords.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No playable streams found. Try different keywords or check your internet connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty ? (first['title'] ?? firstTitle) : firstTitle;
      // Navigate to the player with a Next callback
      if (!mounted) return;
      debugPrint('MagicTV: Launching player. Remaining queue=${_queue.length}');
      // Start background prefetch while player is active
      _startPrefetch();
      unawaited(_ensurePlaylistDepth());
      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            playlist: _tvPlaylist,
            startIndex: 0,
            startFromRandom: _startRandom,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestMagicNext,
            externalPlaylistVersion: _playlistVersion,
            onPlaylistIndexChanged: _handlePlaylistIndexChanged,
          ),
        ),
      );
      // Stop prefetch when player exits
      await _stopPrefetch();
      _clearPlaylistState();
      _activeApiKey = null;
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _status = '';
        });
        debugPrint('MagicTV: Watch flow finished.');
      }
    }
  }

  Future<void> _playNextFromQueue() async {
    if (_isBusy) return;
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add your Real Debrid API key in Settings first!')),
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Finding a playable stream...';
    });

    _activeApiKey = apiKey;
    _clearPlaylistState();
    _prefetchStopRequested = false;

    try {
      await _ensurePlaylistDepth(1);
      final first = await _requestMagicNextForPlayer();
      if (first == null) {
        if (!mounted) return;
        setState(() {
          _status = 'No playable torrents found. Try different keywords.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All torrents failed to process. Try different keywords or check your internet connection.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final firstUrl = first['url'] ?? '';
      if (firstUrl.isEmpty) {
        if (!mounted) return;
        setState(() {
          _status = 'No playable torrents found. Try different keywords.';
        });
        return;
      }

      final resolvedTitle = (first['title'] ?? 'Debrify TV').trim();
      final firstTitle = resolvedTitle.isNotEmpty ? resolvedTitle : 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() {
        return _requestMagicNextForPlayer();
      }

      _startPrefetch();
      unawaited(_ensurePlaylistDepth());

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            playlist: _tvPlaylist,
            startIndex: 0,
            startFromRandom: _startRandom,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestMagicNext,
            externalPlaylistVersion: _playlistVersion,
            onPlaylistIndexChanged: _handlePlaylistIndexChanged,
          ),
        ),
      );

      await _stopPrefetch();
      _clearPlaylistState();
      _activeApiKey = null;
    } finally {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _status = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        children: [
          const SizedBox(height: 32),
          // Logo + headline
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.auto_awesome_rounded, color: Colors.white70),
              SizedBox(width: 8),
              Text('Debrify TV', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 22, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 18),
          // Centered search card
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x221E3A8A), Color(0x2214B8A6)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _keywordsController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _watch(),
                    decoration: InputDecoration(
                      hintText: 'Comma separated keywords',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _isBusy ? null : () {
                          _keywordsController.clear();
                        },
                        color: Colors.white70,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: _isBusy ? null : _watch,
                      icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
                      label: const Text('Watch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        disabledBackgroundColor: const Color(0x66E50914),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Keyboard shortcuts tip
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lightbulb_outline_rounded, color: Colors.amber[300], size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'Quick Tips',
                              style: TextStyle(
                                color: Colors.amber[200],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Next Video: Android double tap far right, Mac/Windows press \'N\'',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Quit: Mac/Windows press ESC, Android use back button',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Stats removed as requested
          const SizedBox(height: 24),
          // Advanced options card
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F0F).withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.settings_rounded, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('Advanced options', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SwitchRow(
                    title: 'Start from random timestamp',
                    subtitle: 'Each Debrify TV video starts at a random point',
                    value: _startRandom,
                    onChanged: (v) async {
                      setState(() => _startRandom = v);
                      await StorageService.saveDebrifyTvStartRandom(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Hide seekbar',
                    subtitle: 'Disable progress slider and time; double-tap still works',
                    value: _hideSeekbar,
                    onChanged: (v) async {
                      setState(() => _hideSeekbar = v);
                      await StorageService.saveDebrifyTvHideSeekbar(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Show DebrifyTV watermark',
                    subtitle: 'Display a subtle DebrifyTV tag on the video',
                    value: _showWatermark,
                    onChanged: (v) async {
                      setState(() => _showWatermark = v);
                      await StorageService.saveDebrifyTvShowWatermark(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Show video title',
                    subtitle: 'Display video title and subtitle in player controls',
                    value: _showVideoTitle,
                    onChanged: (v) async {
                      setState(() => _showVideoTitle = v);
                      await StorageService.saveDebrifyTvShowVideoTitle(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Hide all options',
                    subtitle: 'Hide all bottom controls (next, audio, etc.) - back button stays',
                    value: _hideOptions,
                    onChanged: (v) async {
                      setState(() => _hideOptions = v);
                      await StorageService.saveDebrifyTvHideOptions(v);
                    },
                  ),
                  const SizedBox(height: 8),
                  _SwitchRow(
                    title: 'Hide back button',
                    subtitle: 'Hide back button - use device back gesture or escape key',
                    value: _hideBackButton,
                    onChanged: (v) async {
                      setState(() => _hideBackButton = v);
                      await StorageService.saveDebrifyTvHideBackButton(v);
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Reset to defaults button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        // Reset to defaults
                        setState(() {
                          _startRandom = true;
                          _hideSeekbar = true;
                          _showWatermark = true;
                          _showVideoTitle = false;
                          _hideOptions = true;
                          _hideBackButton = true;
                        });
                        
                        // Save to storage
                        await StorageService.saveDebrifyTvStartRandom(true);
                        await StorageService.saveDebrifyTvHideSeekbar(true);
                        await StorageService.saveDebrifyTvShowWatermark(true);
                        await StorageService.saveDebrifyTvShowVideoTitle(false);
                        await StorageService.saveDebrifyTvHideOptions(true);
                        await StorageService.saveDebrifyTvHideBackButton(true);
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Reset to defaults successful'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.restore_rounded, size: 18),
                      label: const Text('Reset to Defaults'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_status.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status, style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ===================== Prefetcher =====================

  void _startPrefetch() {
    if (_prefetchRunning || _activeApiKey == null || _activeApiKey!.isEmpty) {
      return;
    }
    _prefetchRunning = true;
    _prefetchStopRequested = false;
    debugPrint('MagicTV: Prefetch started.');
    _prefetchTask = _runPrefetchLoop();
  }

  Future<void> _stopPrefetch() async {
    if (!_prefetchRunning) return;
    _prefetchStopRequested = true;
    try {
      await _prefetchTask;
    } catch (_) {}
    _prefetchRunning = false;
    _prefetchTask = null;
    _inflightInfohashes.clear();
    debugPrint('MagicTV: Prefetch stopped.');
  }

  Future<void> _runPrefetchLoop() async {
    while (mounted && !_prefetchStopRequested) {
      try {
        final prepared = _countPreparedInLookahead();
        if (prepared >= _minPrepared) {
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        // Find first unprepared torrent within lookahead window and prefetch it
        final idx = _findUnpreparedTorrentIndexInLookahead();
        if (idx == -1) {
          // nothing to prefetch near head; small idle
          await Future.delayed(const Duration(milliseconds: 750));
          continue;
        }

        await _prefetchOneAtIndex(idx);
        // brief yield (faster when under target prepared)
        await Future.delayed(Duration(milliseconds: prepared <= 2 ? 75 : 150));
      } catch (e) {
        debugPrint('MagicTV: Prefetch loop error: $e');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  int _countPreparedInLookahead() {
    final end = _queue.length < _lookaheadWindow ? _queue.length : _lookaheadWindow;
    int count = 0;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Map && item['type'] == 'rd_restricted') {
        count++;
      }
    }
    return count;
  }

  int _findUnpreparedTorrentIndexInLookahead() {
    final end = _queue.length < _lookaheadWindow ? _queue.length : _lookaheadWindow;
    for (int i = 0; i < end; i++) {
      final item = _queue[i];
      if (item is Torrent && !_inflightInfohashes.contains(item.infohash)) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _prefetchOneAtIndex(int idx) async {
    if (_activeApiKey == null || _activeApiKey!.isEmpty) return;
    if (idx < 0 || idx >= _queue.length) return;
    final item = _queue[idx];
    if (item is! Torrent) return;
    final infohash = item.infohash;
    _inflightInfohashes.add(infohash);
    debugPrint('MagicTV: Prefetching torrent at idx=$idx name="${item.name}"');
    try {
      final magnetLink = 'magnet:?xt=urn:btih:$infohash';
      final result = await DebridService.addTorrentToDebridPreferVideos(_activeApiKey!, magnetLink);
      final String torrentId = result['torrentId'] as String? ?? '';
      final List<dynamic> rdLinks = (result['links'] as List<dynamic>? ?? const []);

      if (rdLinks.isEmpty) {
        // Nothing ready; move to tail to retry later
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
          _queue.add(item);
        }
        debugPrint('MagicTV: Prefetch: no links; moved torrent to tail idx=$idx');
        return;
      }

      // Convert this queue slot to rd_restricted using first link
      final String headLink = rdLinks.first.toString();
      final String primaryDownloadLink = result['downloadLink'] as String? ?? '';
      if (headLink.isNotEmpty) {
        if (!_seenRestrictedLinks.contains(headLink) && !_seenLinkWithTorrentId.contains('$torrentId|$headLink')) {
          _seenRestrictedLinks.add(headLink);
          _seenLinkWithTorrentId.add('$torrentId|$headLink');
        }
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue[idx] = {
            'type': 'rd_restricted',
            'restrictedLink': headLink,
            'torrentId': torrentId,
            'displayName': item.name,
            'downloadLink': primaryDownloadLink,
            'torrentHash': item.infohash,
            'sizeBytes': item.sizeBytes,
          };
        }
      }

      // Append remaining links to tail (dedup)
      if (rdLinks.length > 1) {
        int appended = 0;
        for (int i = 1; i < rdLinks.length; i++) {
          final String link = rdLinks[i]?.toString() ?? '';
          if (link.isEmpty) continue;
          final combo = '$torrentId|$link';
          if (_seenRestrictedLinks.contains(link) || _seenLinkWithTorrentId.contains(combo)) {
            continue;
          }
          _seenRestrictedLinks.add(link);
          _seenLinkWithTorrentId.add(combo);
          _queue.add({
            'type': 'rd_restricted',
            'restrictedLink': link,
            'torrentId': torrentId,
            'displayName': item.name,
            'torrentHash': item.infohash,
            'sizeBytes': item.sizeBytes,
          });
          appended++;
        }
        if (appended > 0) {
          debugPrint('MagicTV: Prefetch: appended $appended RD links to tail. queueSize=${_queue.length}');
        }
      }
      unawaited(_ensurePlaylistDepth());
    } catch (e) {
      // On failure, move to tail for retry later
      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue.removeAt(idx);
        _queue.add(item);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e (moved to tail)');
    } finally {
      _inflightInfohashes.remove(infohash);
    }
  }
}


class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoTile({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsTile extends StatelessWidget {
  final int queue;
  final DateTime? lastSearchedAt;
  const _StatsTile({required this.queue, required this.lastSearchedAt});
  @override
  Widget build(BuildContext context) {
    final last = lastSearchedAt == null ? '—' : '${lastSearchedAt!.hour.toString().padLeft(2,'0')}:${lastSearchedAt!.minute.toString().padLeft(2,'0')}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.insights_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Search snapshot', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('Queue prepared: $queue • Last search: $last', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFE50914),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      ),
    );
  }
}
