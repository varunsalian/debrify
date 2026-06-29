import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/extracted_media.dart';
import '../models/stream_providers.dart';
import '../services/stream_extractor.dart';
import '../services/storage_service.dart';
import '../services/video_player_launcher.dart';

class StreamingDetailsScreen extends StatefulWidget {
  final String title;
  final String? imdbId;
  final String? year;
  final String? posterUrl;
  final String contentType; // 'movie' or 'series'
  final int? season;
  final int? episode;

  const StreamingDetailsScreen({
    super.key,
    required this.title,
    this.imdbId,
    this.year,
    this.posterUrl,
    this.contentType = 'movie',
    this.season,
    this.episode,
  });

  @override
  State<StreamingDetailsScreen> createState() => _StreamingDetailsScreenState();
}

class _StreamingDetailsScreenState extends State<StreamingDetailsScreen> {
  bool _isExtracting = false;
  bool _extractionCancelled = false;
  String? _statusMessage;
  final StreamExtractor _extractor = StreamExtractor();
  final Map<String, dynamic> _providers = <String, dynamic>{
    ...StreamProviders.providers,
  };

  @override
  void initState() {
    super.initState();
    _startExtraction();
  }

  @override
  void dispose() {
    _extractor.dispose();
    super.dispose();
  }

  Future<void> _startExtraction() async {
    final order = await StorageService.getStreamProviderOrder();

    final orderedProviders = <String, dynamic>{
      for (final k in order)
        if (_providers.containsKey(k)) k: _providers[k],
      for (final k in _providers.keys)
        if (!order.contains(k)) k: _providers[k],
    };

    setState(() {
      _isExtracting = true;
      _statusMessage = 'Initializing…';
    });

    bool found = false;
    for (final key in orderedProviders.keys) {
      if (!mounted || _extractionCancelled) break;
      final provider = orderedProviders[key];
      final displayName = (provider?['name'] as String?) ?? key;
      if (mounted) {
        setState(() => _statusMessage = 'Searching $displayName…');
      }
      try {
        found = await _tryProvider(key, orderedProviders);
      } catch (e) {
        debugPrint('Error extracting from $key: $e');
      }
      if (found) break;
    }

    if (mounted) {
      setState(() {
        _isExtracting = false;
        _statusMessage = found ? 'Playing…' : 'No streams found.';
      });
      if (!found && Navigator.canPop(context)) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to find a working stream.')),
        );
      }
    }
  }

  Future<bool> _tryProvider(
      String key, Map<String, dynamic> orderedProviders) async {
    final isTv = widget.contentType == 'series';
    final title = isTv && widget.season != null && widget.episode != null
        ? '${widget.title} - S${widget.season!.toString().padLeft(2, '0')} E${widget.episode!.toString().padLeft(2, '0')}'
        : widget.title;

    void pushPlayer({
      required String streamUrl,
      Map<String, String>? headers,
      List<dynamic>? sources,
    }) {
      if (mounted && Navigator.canPop(context)) {
        final popContext = context;
        Navigator.pop(popContext);
      }
      final uri = Uri.tryParse(streamUrl);
      final resolvedUrl = uri?.toString() ?? streamUrl;
      VideoPlayerLauncher.push(
        context,
        VideoPlayerLaunchArgs(
          videoUrl: resolvedUrl,
          title: title,
          httpHeaders: headers,
          contentImdbId: widget.imdbId,
          contentType: widget.contentType,
          contentSeason: widget.season,
          contentEpisode: widget.episode,
          contentTitle: widget.title,
          posterUrl: widget.posterUrl,
          contentYear: widget.year,
        ),
      );
    }

    // Generic web-embed providers (vidlink/vixsrc/vidnest/…)
    final provider = orderedProviders[key];
    if (provider != null && provider['movie'] != null && provider['tv'] != null) {
      final String url = isTv
          ? provider['tv'](
              widget.imdbId ?? widget.title,
              (widget.season ?? 1).toString(),
              (widget.episode ?? 1).toString(),
            )
          : provider['movie'](widget.imdbId ?? widget.title);
      debugPrint('[StreamExtractor] Trying ${provider['name']} source: $url');
      final result = await _extractor.extract(url, timeout: const Duration(seconds: 45));
      if (_extractionCancelled || result == null || !mounted) return false;
      pushPlayer(streamUrl: result.url, headers: result.headers, sources: result.sources);
      return true;
    }

    if (key == 'videasy') {
      final result = await _extractVideasy(
        imdbId: widget.imdbId,
        isMovie: !isTv,
        season: isTv ? widget.season : null,
        episode: isTv ? widget.episode : null,
      );
      if (_extractionCancelled || result == null || !mounted) return false;
      pushPlayer(streamUrl: result.url, headers: result.headers);
      return true;
    }

    if (key == 'vidsrc') {
      final result = await _extractVidsrc(
        imdbId: widget.imdbId,
        isMovie: !isTv,
        season: isTv ? widget.season : null,
        episode: isTv ? widget.episode : null,
      );
      if (_extractionCancelled || result == null || !mounted) return false;
      pushPlayer(streamUrl: result.url, headers: result.headers);
      return true;
    }

    // service111477 and webstreamr need external services not yet ported
    if (key == 'service111477' || key == 'webstreamr') {
      return false;
    }

    return false;
  }

  Future<ExtractedMedia?> _extractVideasy({
    String? imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    if (imdbId == null || imdbId.isEmpty) return null;
    final baseUrl = isMovie
        ? 'https://player.videasy.net/movie/$imdbId'
        : 'https://player.videasy.net/tv/$imdbId/${season ?? 1}/${episode ?? 1}';
    try {
      final resp = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );
      final body = resp.body;
      final urlPattern = RegExp(
        'https?://[^"\'\\\\s]+(?:\\.m3u8|\\.mp4)[^"\'\\\\s]*',
      );
      final uriMatch = urlPattern.firstMatch(body);
      if (uriMatch == null) return null;
      return ExtractedMedia(
        url: uriMatch.group(0)!,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': baseUrl,
        },
        provider: 'videasy',
      );
    } catch (e) {
      debugPrint('[VideasyExtractor] Error: $e');
      return null;
    }
  }

  Future<ExtractedMedia?> _extractVidsrc({
    String? imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    if (imdbId == null || imdbId.isEmpty) return null;
    final baseUrl = isMovie
        ? 'https://vidsrc.to/embed/movie/$imdbId'
        : 'https://vidsrc.to/embed/tv/$imdbId/${season ?? 1}/${episode ?? 1}';
    try {
      final resp = await http.get(
        Uri.parse(baseUrl),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://vidsrc.to/',
        },
      );
      final body = resp.body;
      final urlPattern = RegExp(
        'https?://[^"\'\\\\s]+(?:\\.m3u8|\\.mp4)[^"\'\\\\s]*',
      );
      final uriMatch = urlPattern.firstMatch(body);
      if (uriMatch == null) {
        return _extractWithWebView(baseUrl);
      }
      return ExtractedMedia(
        url: uriMatch.group(0)!,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': baseUrl,
        },
        provider: 'vidsrc',
      );
    } catch (e) {
      debugPrint('[VidsrcExtractor] Error: $e');
      return _extractWithWebView(baseUrl);
    }
  }

  Future<ExtractedMedia?> _extractWithWebView(String url) async {
    return _extractor.extract(url, timeout: const Duration(seconds: 30));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  widget.posterUrl!,
                  width: 160,
                  height: 240,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 160,
                    height: 240,
                    child: Icon(Icons.movie, color: Colors.white24, size: 64),
                  ),
                ),
              )
            else
              const Icon(Icons.movie, color: Colors.white24, size: 80),
            const SizedBox(height: 24),
            Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.year != null) ...[
              const SizedBox(height: 4),
              Text(
                widget.year!,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
            const SizedBox(height: 32),
            if (_isExtracting) ...[
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Color(0xFF1565C0),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_statusMessage != null)
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            if (_isExtracting) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: () {
                  _extractionCancelled = true;
                  if (mounted && Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
