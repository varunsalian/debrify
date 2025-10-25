import 'dart:math';
import 'package:flutter/material.dart';
import '../models/torrent.dart';
import '../models/torbox_file.dart';
import '../models/torbox_torrent.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/torrent_service.dart';
import '../utils/file_utils.dart';
import '../utils/series_parser.dart';
import 'video_player_screen.dart';

class DebrifyTVScreen extends StatefulWidget {
  const DebrifyTVScreen({super.key});

  @override
  State<DebrifyTVScreen> createState() => _DebrifyTVScreenState();
}

class _DebrifyTVScreenState extends State<DebrifyTVScreen> {
  static const String _providerRealDebrid = 'real_debrid';
  static const String _providerTorbox = 'torbox';
  static const String _torboxFileEntryType = 'torbox_file';
  static const int _torboxMinVideoSizeBytes = 50 * 1024 * 1024; // 50 MB filter threshold

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
  String _provider = _providerRealDebrid;
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
    _progress.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _updateProvider(String value) async {
    if (_provider == value) return;
    setState(() {
      _provider = value;
    });
    await StorageService.saveDebrifyTvProvider(value);
  }

  void _closeProgressDialog() {
    if (!_progressOpen || _progressSheetContext == null) {
      return;
    }
    try {
      Navigator.of(_progressSheetContext!).pop();
    } catch (_) {}
    _progressOpen = false;
    _progressSheetContext = null;
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final hideSeekbar = await StorageService.getDebrifyTvHideSeekbar();
    final showWatermark = await StorageService.getDebrifyTvShowWatermark();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    final hideOptions = await StorageService.getDebrifyTvHideOptions();
    final hideBackButton = await StorageService.getDebrifyTvHideBackButton();
    final storedProvider = await StorageService.getDebrifyTvProvider();
    final provider =
        storedProvider == _providerTorbox ? _providerTorbox : _providerRealDebrid;

    if (mounted) {
      setState(() {
        _startRandom = startRandom;
        _hideSeekbar = hideSeekbar;
        _showWatermark = showWatermark;
        _showVideoTitle = showVideoTitle;
        _hideOptions = hideOptions;
        _hideBackButton = hideBackButton;
        _provider = provider;
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

  Future<void> _watch() async {
    _launchedPlayer = false;
    await _stopPrefetch();
    _prefetchStopRequested = false;
    _stage2Running = false;
    _capRestoredByStage2 = false;
    _originalMaxCap = null;
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

    if (_provider == _providerTorbox) {
      await _watchWithTorbox(keywords, _log);
      return;
    }

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

      // Helper to infer a filename-like title from a URL
      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        debugPrint('DebrifyTV: requestMagicNext() called. queueSize=${_queue.length}');
        while (_queue.isNotEmpty) {
          final item = _queue.removeAt(0);
          // Case 1: RD-restricted entry (append-only items)
          if (item is Map && item['type'] == 'rd_restricted') {
            final String link = item['restrictedLink'] as String? ?? '';
            final String rdTid = item['torrentId'] as String? ?? '';
            debugPrint('DebrifyTV: Trying RD link from queue: torrentId=$rdTid');
            if (link.isEmpty) continue;
            try {
              // Silent approach - no progress logging needed
              final started = DateTime.now();
              final unrestrict = await DebridService.unrestrictLink(apiKeyEarly, link);
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint('DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s');
                // Silent approach - no progress logging needed
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty ? inferred : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: RD link failed to unrestrict: $e');
              continue;
            }
          }

          // Case 2: Torrent entry
          if (item is Torrent) {
            debugPrint('DebrifyTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}');
            final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
            try {
              // Silent approach - no progress logging needed
              final started = DateTime.now();
              final result = await DebridService.addTorrentToDebridPreferVideos(apiKeyEarly, magnetLink);
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = result['downloadLink'] as String?;
              // Append other RD-restricted links from this torrent to the END of the queue
              final String torrentId = result['torrentId'] as String? ?? '';
              final List<dynamic> rdLinks = (result['links'] as List<dynamic>? ?? const []);
              if (rdLinks.isNotEmpty) {
                for (int i = 1; i < rdLinks.length; i++) {
                  final String link = rdLinks[i]?.toString() ?? '';
                  if (link.isEmpty) continue;
                  final String combined = '$torrentId|$link';
                  if (_seenRestrictedLinks.contains(link) || _seenLinkWithTorrentId.contains(combined)) {
                    continue;
                  }
                  _seenRestrictedLinks.add(link);
                  _seenLinkWithTorrentId.add(combined);
                  _queue.add({
                    'type': 'rd_restricted',
                    'restrictedLink': link,
                    'torrentId': torrentId,
                    'displayName': item.name,
                  });
                }
              }
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint('DebrifyTV: Success. Got unrestricted URL in ${elapsed}s');
                // Silent approach - no progress logging needed
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty ? inferred : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: Debrid add failed for ${item.infohash}: $e');
            }
          }
        }
        debugPrint('DebrifyTV: requestMagicNext() queue exhausted.');
        return null;
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
                    startFromRandom: _startRandom,
                    hideSeekbar: _hideSeekbar,
                    showWatermark: _showWatermark,
                    showVideoTitle: _showVideoTitle,
                    hideOptions: _hideOptions,
                    hideBackButton: _hideBackButton,
                    requestMagicNext: requestMagicNext,
                  ),
                ),
              );

              // Stop prefetch when player exits
              await _stopPrefetch();
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

    // Helper to infer a filename-like title from a URL
    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
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

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint('MagicTV: requestMagicNext() called. queueSize=${_queue.length}');
      while (_queue.isNotEmpty) {
        final item = _queue.removeAt(0);
        // Case 1: RD-restricted entry (append-only items)
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('MagicTV: Trying RD link from queue: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('MagicTV: Success (RD link). Unrestricted in ${elapsed}s');
              // Prefer filename inferred from URL; fallback to any stored displayName
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty ? inferred : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: RD link failed to unrestrict: $e');
            continue;
          }
        }

        // Case 2: Torrent entry
        if (item is Torrent) {
          debugPrint('MagicTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}');
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = result['downloadLink'] as String?;
            // Append other RD-restricted links from this torrent to the END of the queue
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<dynamic> rdLinks = (result['links'] as List<dynamic>? ?? const []);
            if (rdLinks.isNotEmpty) {
              // We assume we used rdLinks[0] to play; enqueue remaining
              for (int i = 1; i < rdLinks.length; i++) {
                final String link = rdLinks[i]?.toString() ?? '';
                if (link.isEmpty) continue;
                final String combined = '$torrentId|$link';
                if (_seenRestrictedLinks.contains(link) || _seenLinkWithTorrentId.contains(combined)) {
                  continue;
                }
                _seenRestrictedLinks.add(link);
                _seenLinkWithTorrentId.add(combined);
                _queue.add({
                  'type': 'rd_restricted',
                  'restrictedLink': link,
                  'torrentId': torrentId,
                  'displayName': item.name,
                });
              }
              if (rdLinks.length > 1) {
                debugPrint('MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_queue.length}');
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('MagicTV: Success. Got unrestricted URL in ${elapsed}s');
              // Prefer filename inferred from URL; fallback to torrent name
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty ? inferred : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: Debrid add failed for ${item.infohash}: $e');
          }
        }
      }
      debugPrint('MagicTV: requestMagicNext() queue exhausted.');
      return null;
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
      _activeApiKey = apiKey;
      _startPrefetch();
      if (_progressOpen && _progressSheetContext != null) {
        Navigator.of(_progressSheetContext!).pop();
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _startRandom,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestMagicNext,
          ),
        ),
      );
      // Stop prefetch when player exits
      await _stopPrefetch();
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

  Future<void> _watchWithTorbox(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await StorageService.getTorboxIntegrationEnabled();
    if (!integrationEnabled) {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _status = 'Enable Torbox in Settings to use this provider.';
        _isBusy = false;
      });
      _showSnack(
        'Enable Torbox in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _closeProgressDialog();
      if (!mounted) return;
      setState(() {
        _status = 'Add your Torbox API key in Settings to use this provider.';
        _isBusy = false;
      });
      _showSnack(
        'Please add your Torbox API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Torbox: searching for cached torrents...');
    final originalCap = await StorageService.getMaxTorrentsCsvResults();
    final Map<String, Torrent> dedup = <String, Torrent>{};

    try {
      await StorageService.setMaxTorrentsCsvResults(500);

      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              useTorrentsCsv: true,
              usePirateBay: true,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);
        int added = 0;
        for (final torrent in torrents) {
          final normalizedHash = _normalizeInfohash(torrent.infohash);
          if (normalizedHash.isEmpty) continue;
          if (!dedup.containsKey(normalizedHash)) {
            dedup[normalizedHash] = torrent;
            added++;
          }
        }
        if (added > 0) {
          final combined = dedup.values.toList();
          combined.shuffle(Random());
          _queue
            ..clear()
            ..addAll(combined);
          _lastQueueSize = _queue.length;
          _lastSearchAt = DateTime.now();
          if (mounted) {
            setState(() {
              _status = 'Checking Torbox cache...';
            });
          }
        }
      }

      final combinedList = dedup.values.toList();
      if (combinedList.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No results found. Try different keywords.';
          });
          _showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      final uniqueHashes = combinedList
          .map((torrent) => _normalizeInfohash(torrent.infohash))
          .where((hash) => hash.isNotEmpty)
          .toList();

      if (uniqueHashes.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No valid torrents found for Torbox.';
          });
        }
        return;
      }

      Set<String> cachedHashes;
      try {
        cachedHashes = await TorboxService.checkCachedTorrents(
          apiKey: apiKey,
          infoHashes: uniqueHashes,
          listFiles: false,
        );
      } catch (e) {
        log('❌ Torbox cache check failed: $e');
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'Torbox cache check failed. Try again.';
          });
          _showSnack(
            'Torbox cache check failed: ${_formatTorboxError(e)}',
            color: Colors.red,
          );
        }
        return;
      }

      final filtered = combinedList
          .where(
            (torrent) =>
                cachedHashes.contains(_normalizeInfohash(torrent.infohash)),
          )
          .toList();

      if (filtered.isEmpty) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'Torbox has no cached results for these keywords.';
          });
          _showSnack(
            'Torbox has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      filtered.shuffle(Random());
      _queue
        ..clear()
        ..addAll(filtered);
      _lastQueueSize = _queue.length;
      _lastSearchAt = DateTime.now();
      if (mounted) {
        setState(() {
          _status =
              'Found ${_queue.length} cached Torbox result${_queue.length == 1 ? '' : 's'}';
        });
      }
      log('✅ Found ${_queue.length} cached Torbox torrent(s)');

      final random = Random();

      Future<Map<String, String>?> requestTorboxNext() async {
        while (_queue.isNotEmpty) {
          final item = _queue.removeAt(0);
          if (item is Map && item['type'] == _torboxFileEntryType) {
            final resolved = await _resolveTorboxQueuedFile(
              entry: item as Map<String, dynamic>,
              apiKey: apiKey,
              log: log,
            );
            if (resolved != null) {
              if (mounted) {
                setState(() {
                  _status =
                      _queue.isEmpty ? '' : 'Queue has ${_queue.length} remaining';
                });
              }
              return resolved;
            }
            continue;
          }

          if (item is Torrent) {
            final result = await _prepareTorboxTorrent(
              candidate: item,
              apiKey: apiKey,
              log: log,
            );
            if (result != null) {
              if (result.extraEntries.isNotEmpty) {
                _queue.addAll(result.extraEntries);
                _queue.shuffle(random);
              }
              if (mounted) {
                setState(() {
                  _status = _queue.isEmpty
                      ? ''
                      : 'Queue has ${_queue.length} remaining';
                });
              }
              return {
                'url': result.streamUrl,
                'title': result.title,
              };
            }
          }
        }
        if (mounted) {
          setState(() {
            _status = 'No more cached Torbox streams available.';
          });
        }
        return null;
      }

      final first = await requestTorboxNext();
      if (first == null) {
        _closeProgressDialog();
        if (mounted) {
          setState(() {
            _status = 'No playable Torbox streams found. Try different keywords.';
          });
          _showSnack(
            'No playable Torbox streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      _closeProgressDialog();
      if (!mounted) return;

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _startRandom,
            hideSeekbar: _hideSeekbar,
            showWatermark: _showWatermark,
            showVideoTitle: _showVideoTitle,
            hideOptions: _hideOptions,
            hideBackButton: _hideBackButton,
            requestMagicNext: requestTorboxNext,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _status = _queue.isEmpty ? '' : 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      await StorageService.setMaxTorrentsCsvResults(originalCap);
      _closeProgressDialog();
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
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

    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        final magnetLink = 'magnet:?xt=urn:btih:${next.infohash}';
        try {
          final result = await DebridService.addTorrentToDebridPreferVideos(apiKey, magnetLink);
          final videoUrl = result['downloadLink'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            if (!mounted) return;
            setState(() {
              _status = 'Playing: ${next.name}';
            });
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => VideoPlayerScreen(
                  videoUrl: videoUrl,
                  title: next.name,
                  startFromRandom: _startRandom,
                  hideSeekbar: _hideSeekbar,
                  showWatermark: _showWatermark,
                  showVideoTitle: _showVideoTitle,
                  hideOptions: _hideOptions,
                  hideBackButton: _hideBackButton,
                ),
              ),
            );
            break;
          }
        } catch (_) {
          // Skip not readily available / failed items and continue
          continue;
        }
      }

      if (_queue.isEmpty) {
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
              content: Text('All torrents failed to process. Try different keywords or check your internet connection.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      } else {
        setState(() {
          _status = 'Queue has ${_queue.length} remaining';
        });
      }
    } finally {
      setState(() {
        _isBusy = false;
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
                  Text(
                    'Content provider',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Real Debrid'),
                        selected: _provider == _providerRealDebrid,
                        onSelected: _isBusy
                            ? null
                            : (selected) {
                                if (selected) {
                                  _updateProvider(_providerRealDebrid);
                                }
                              },
                      ),
                      ChoiceChip(
                        label: const Text('Torbox'),
                        selected: _provider == _providerTorbox,
                        onSelected: _isBusy
                            ? null
                            : (selected) {
                                if (selected) {
                                  _updateProvider(_providerTorbox);
                                }
                              },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                          _provider = _providerRealDebrid;
                        });
                        
                        // Save to storage
                        await StorageService.saveDebrifyTvStartRandom(true);
                        await StorageService.saveDebrifyTvHideSeekbar(true);
                        await StorageService.saveDebrifyTvShowWatermark(true);
                        await StorageService.saveDebrifyTvShowVideoTitle(false);
                        await StorageService.saveDebrifyTvHideOptions(true);
                        await StorageService.saveDebrifyTvHideBackButton(true);
                        await StorageService.saveDebrifyTvProvider(
                          _providerRealDebrid,
                        );
                        
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

  Future<Map<String, String>?> _resolveTorboxQueuedFile({
    required Map<String, dynamic> entry,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final torrentId = entry['torrentId'] as int?;
    final TorboxFile? file = entry['file'] as TorboxFile?;
    final String? title = entry['title'] as String?;
    if (torrentId == null || file == null) {
      return null;
    }
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torrentId,
        fileId: file.id,
      );
      final resolvedTitle = title ?? _torboxDisplayName(file);
      log('➡️ Torbox: streaming $resolvedTitle');
      return {
        'url': streamUrl,
        'title': resolvedTitle,
      };
    } catch (e) {
      log('❌ Torbox stream failed: $e');
      return null;
    }
  }

  Future<_TorboxPreparedTorrent?> _prepareTorboxTorrent({
    required Torrent candidate,
    required String apiKey,
    required void Function(String message) log,
  }) async {
    final infohash = _normalizeInfohash(candidate.infohash);
    if (infohash.isEmpty) {
      return null;
    }

    log('⏳ Torbox: preparing ${candidate.name}');

    final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';
    Map<String, dynamic> response;
    try {
      response = await TorboxService.createTorrent(
        apiKey: apiKey,
        magnet: magnetLink,
        seed: true,
        allowZip: false,
        addOnlyIfCached: true,
      );
    } catch (e) {
      log('❌ Torbox createtorrent failed: $e');
      return null;
    }

    final success = response['success'] as bool? ?? false;
    if (!success) {
      final error = (response['error'] ?? '').toString();
      log('⚠️ Torbox createtorrent error: $error');
      return null;
    }

    final data = response['data'];
    final torrentId = _asIntMapValue(data, 'torrent_id');
    if (torrentId == null) {
      log('⚠️ Torbox createtorrent missing torrent_id');
      return null;
    }

    TorboxTorrent? torboxTorrent;
    for (int attempt = 0; attempt < 6; attempt++) {
      torboxTorrent = await TorboxService.getTorrentById(
        apiKey,
        torrentId,
        attempts: 1,
        pageSize: 100,
      );
      if (torboxTorrent != null && torboxTorrent.files.isNotEmpty) {
        break;
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }

    if (torboxTorrent == null || torboxTorrent.files.isEmpty) {
      log('⚠️ Torbox torrent details not ready for ${candidate.name}');
      return null;
    }

    final playableEntries = _buildTorboxPlayableEntries(
      torboxTorrent,
      candidate.name,
    );
    if (playableEntries.isEmpty) {
      log('⚠️ Torbox torrent has no playable files ${candidate.name}');
      return null;
    }

    final random = Random();
    final workingEntries = List<_TorboxPlayableEntry>.from(playableEntries)
      ..shuffle(random);
    final next = workingEntries.removeAt(0);
    workingEntries.shuffle(random);
    try {
      final streamUrl = await TorboxService.requestFileDownloadLink(
        apiKey: apiKey,
        torrentId: torboxTorrent.id,
        fileId: next.file.id,
      );
      log('🎬 Torbox: streaming ${next.title}');
      final torrentIdValue = torboxTorrent.id;
      final nextExtras = workingEntries
          .map(
            (entry) => {
              'type': _torboxFileEntryType,
              'file': entry.file,
              'title': entry.title,
              'torrentId': torrentIdValue,
            },
          )
          .toList();
      return _TorboxPreparedTorrent(
        streamUrl: streamUrl,
        title: next.title,
        extraEntries: nextExtras,
      );
    } catch (e) {
      log('❌ Torbox requestdl failed: $e');
      return null;
    }
  }

  List<_TorboxPlayableEntry> _buildTorboxPlayableEntries(
    TorboxTorrent torrent,
    String fallbackTitle,
  ) {
    final entries = <_TorboxPlayableEntry>[];
    final seriesCandidates = <_TorboxPlayableEntry>[];
    final otherCandidates = <_TorboxPlayableEntry>[];

    for (final file in torrent.files) {
      if (!_torboxFileLooksLikeVideo(file)) continue;
      if (file.size < _torboxMinVideoSizeBytes) continue;
      final displayName = _torboxDisplayName(file);
      final info = SeriesParser.parseFilename(displayName);
      final title = info.isSeries
          ? _formatTorboxSeriesTitle(info, fallbackTitle)
          : (displayName.isNotEmpty ? displayName : fallbackTitle);
      final entry = _TorboxPlayableEntry(
        file: file,
        title: title,
        info: info,
      );
      if (info.isSeries && info.season != null && info.episode != null) {
        seriesCandidates.add(entry);
      } else {
        otherCandidates.add(entry);
      }
    }

    seriesCandidates.sort((a, b) {
      final seasonCompare = (a.info.season ?? 0).compareTo(b.info.season ?? 0);
      if (seasonCompare != 0) return seasonCompare;
      return (a.info.episode ?? 0).compareTo(b.info.episode ?? 0);
    });

    otherCandidates.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );

    entries
      ..addAll(seriesCandidates)
      ..addAll(otherCandidates);
    entries.shuffle(Random());
    return entries;
  }

  bool _torboxFileLooksLikeVideo(TorboxFile file) {
    if (file.zipped) return false;
    final name = file.shortName.isNotEmpty
        ? file.shortName
        : FileUtils.getFileName(file.name);
    if (FileUtils.isVideoFile(name)) return true;
    final mime = file.mimetype?.toLowerCase();
    return mime != null && mime.startsWith('video/');
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

  String _formatTorboxSeriesTitle(SeriesInfo info, String fallback) {
    final season = info.season?.toString().padLeft(2, '0');
    final episode = info.episode?.toString().padLeft(2, '0');
    final descriptor = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : (info.title?.trim().isNotEmpty == true ? info.title!.trim() : fallback);
    if (season != null && episode != null) {
      return 'S${season}E${episode} · $descriptor';
    }
    return fallback;
  }

  String _normalizeInfohash(String hash) {
    return hash.trim().toLowerCase();
  }

  void _showSnack(String message, {Color color = Colors.blueGrey}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  int? _asIntMapValue(dynamic data, String key) {
    if (data is Map<String, dynamic>) {
      final value = data[key];
      if (value is int) return value;
      if (value is String) return int.tryParse(value);
      if (value is num) return value.toInt();
    }
    return null;
  }

  String _formatTorboxError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
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
          });
          appended++;
        }
        if (appended > 0) {
          debugPrint('MagicTV: Prefetch: appended $appended RD links to tail. queueSize=${_queue.length}');
        }
      }
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

class _TorboxPreparedTorrent {
  final String streamUrl;
  final String title;
  final List<Map<String, dynamic>> extraEntries;

  _TorboxPreparedTorrent({
    required this.streamUrl,
    required this.title,
    this.extraEntries = const [],
  });
}

class _TorboxPlayableEntry {
  final TorboxFile file;
  final String title;
  final SeriesInfo info;

  _TorboxPlayableEntry({
    required this.file,
    required this.title,
    required this.info,
  });
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
