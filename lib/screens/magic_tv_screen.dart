import 'dart:math';
import 'package:flutter/material.dart';
import '../models/torrent.dart';
import '../services/torrent_service.dart';
import '../services/storage_service.dart';
import '../services/debrid_service.dart';
import 'video_player_screen.dart';

class MagicTVScreen extends StatefulWidget {
  const MagicTVScreen({super.key});

  @override
  State<MagicTVScreen> createState() => _MagicTVScreenState();
}

class _MagicTVScreenState extends State<MagicTVScreen> {
  final TextEditingController _keywordsController = TextEditingController();
  // Mixed queue: can contain Torrent items or RD-restricted link maps
  final List<dynamic> _queue = [];
  bool _isBusy = false;
  String _status = '';
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

  @override
  void dispose() {
    _keywordsController.dispose();
    super.dispose();
  }

  List<String> _parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<void> _watch() async {
    final text = _keywordsController.text.trim();
    debugPrint('MagicTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      setState(() {
        _status = 'Enter one or more keywords, separated by commas';
      });
      debugPrint('MagicTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = _parseKeywords(text);
    debugPrint('MagicTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}');
    if (keywords.isEmpty) {
      setState(() {
        _status = 'Enter valid keywords';
      });
      debugPrint('MagicTV: Aborting. Parsed keywords became empty after trimming.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Searching...';
      _queue.clear();
    });

    // Force 500 results from Torrents CSV during this search, without permanently changing user settings
    final prevMax = await StorageService.getMaxTorrentsCsvResults();
    debugPrint('MagicTV: Temporarily bumping Torrents CSV max from $prevMax to 500');
    try {
      await StorageService.setMaxTorrentsCsvResults(500);

      final Map<String, Torrent> dedupByInfohash = {};

      for (final kw in keywords) {
        debugPrint('MagicTV: Searching engines for "$kw"...');
        final result = await TorrentService.searchAllEngines(kw, useTorrentsCsv: true, usePirateBay: true);
        final List<Torrent> torrents = (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
        final engineCounts = (result['engineCounts'] as Map<String, int>?) ?? const {};
        debugPrint('MagicTV: "$kw" results: total=${torrents.length}, engineCounts=$engineCounts');
        for (final t in torrents) {
          if (!dedupByInfohash.containsKey(t.infohash)) {
            dedupByInfohash[t.infohash] = t;
          }
        }
      }

      final combined = dedupByInfohash.values.toList();
      combined.shuffle(Random());

      _queue.addAll(combined);
      debugPrint('MagicTV: Queue prepared. size=${_queue.length}');
    } catch (e) {
      setState(() {
        _status = 'Search failed: $e';
      });
      debugPrint('MagicTV: Search failed: $e');
    } finally {
      await StorageService.setMaxTorrentsCsvResults(prevMax);
      debugPrint('MagicTV: Restored Torrents CSV max to $prevMax');
      setState(() {
        _isBusy = false;
      });
    }

    if (!mounted) return;
    if (_queue.isEmpty) {
      setState(() {
        _status = 'No results found';
      });
      debugPrint('MagicTV: No results found after combining.');
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

    Future<String?> requestMagicNext() async {
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
              return videoUrl;
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
                });
              }
              if (rdLinks.length > 1) {
                debugPrint('MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_queue.length}');
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('MagicTV: Success. Got unrestricted URL in ${elapsed}s');
              return videoUrl;
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

    try {
      final firstUrl = await requestMagicNext();
      if (firstUrl == null) {
        setState(() {
          _status = 'No playable torrents found. Try different keywords.';
        });
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      // Navigate to the player with a Next callback
      if (!mounted) return;
      debugPrint('MagicTV: Launching player. Remaining queue=${_queue.length}');
      // Start background prefetch while player is active
      _activeApiKey = apiKey;
      _startPrefetch();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: 'Magic TV',
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _keywordsController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _watch(),
            decoration: const InputDecoration(
              hintText: 'Enter keywords (comma separated)',
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isBusy ? null : _watch,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Watch'),
          ),
          const SizedBox(height: 8),
          Text(
            _status,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
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
        // brief yield
        await Future.delayed(const Duration(milliseconds: 50));
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
        // Nothing ready; drop this torrent from queue
        if (idx < _queue.length && identical(_queue[idx], item)) {
          _queue.removeAt(idx);
        }
        debugPrint('MagicTV: Prefetch: no links; removed torrent at idx=$idx');
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
          });
          appended++;
        }
        if (appended > 0) {
          debugPrint('MagicTV: Prefetch: appended $appended RD links to tail. queueSize=${_queue.length}');
        }
      }
    } catch (e) {
      // On failure, drop this torrent so we don't block the window
      if (idx < _queue.length && identical(_queue[idx], item)) {
        _queue.removeAt(idx);
      }
      debugPrint('MagicTV: Prefetch failed for $infohash: $e');
    } finally {
      _inflightInfohashes.remove(infohash);
    }
  }
}


