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
  bool _startRandom = false;
  bool _hideSeekbar = false;
  bool _showWatermark = true;
  bool _showVideoTitle = true;
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
    _progress.dispose();
    _keywordsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final startRandom = await StorageService.getDebrifyTvStartRandom();
    final hideSeekbar = await StorageService.getDebrifyTvHideSeekbar();
    final showWatermark = await StorageService.getDebrifyTvShowWatermark();
    final showVideoTitle = await StorageService.getDebrifyTvShowVideoTitle();
    
    if (mounted) {
      setState(() {
        _startRandom = startRandom;
        _hideSeekbar = hideSeekbar;
        _showWatermark = showWatermark;
        _showVideoTitle = showVideoTitle;
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

    // show progress modal
    _progress.value = [];
    _progressOpen = true;
    // ignore: unawaited_futures
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        _progressSheetContext = ctx;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFE50914).withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFFE50914), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Text('Debrify TV • Watch Status', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
                  const Spacer(),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_status, style: const TextStyle(color: Colors.white70))),
                ]),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12, width: 1)),
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: _progress,
                    builder: (context, logs, _) {
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: logs.length,
                        itemBuilder: (context, index) {
                          final line = logs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              const Icon(Icons.check_circle_outline, color: Colors.white54, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(line, style: const TextStyle(color: Colors.white, fontSize: 13))),
                            ]),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() { _progressOpen = false; _progressSheetContext = null; });

    _log('Searching providers with your keywords');

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
              final started = DateTime.now();
              final unrestrict = await DebridService.unrestrictLink(apiKeyEarly, link);
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint('DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s');
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
          setState(() {
            _status = 'Found ${_queue.length} results... preparing first play';
          });

          // Start prefetch early on first influx as soon as we have an API key
          if (!_prefetchRunning && apiKeyEarly != null && apiKeyEarly.isNotEmpty) {
            _activeApiKey = apiKeyEarly;
            _startPrefetch();
          }

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
      setState(() {
        _isBusy = false;
      });
    }

    if (!mounted) return;
    if (_queue.isEmpty) {
      setState(() {
        _status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('No results found');
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
    _log('Finding a playable stream...');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        setState(() {
          _status = 'No playable torrents found. Try different keywords.';
        });
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
        setState(() {
          _status = 'No playable torrents found. Try different keywords.';
        });
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
                      hintText: 'What mood are you in? (comma separated keywords)',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.play_circle_fill_rounded),
                        onPressed: _isBusy ? null : _watch,
                        color: const Color(0xFFE50914),
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
