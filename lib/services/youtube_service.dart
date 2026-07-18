import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;
import 'storage_service.dart';

/// A YouTube video surfaced from a search.
class YoutubeVideo {
  final String id;
  final String title;
  final String author;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? views;

  /// Relative published label as YouTube returns it, e.g. "6 years ago".
  final String? publishedLabel;

  const YoutubeVideo({
    required this.id,
    required this.title,
    required this.author,
    this.thumbnailUrl,
    this.durationSeconds,
    this.views,
    this.publishedLabel,
  });

  /// Format views for display (e.g., 1.2M, 676K).
  String get formattedViews {
    final v = views;
    if (v == null || v < 0) return '';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M views';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K views';
    return '$v views';
  }
}

/// Result of a YouTube search request.
class YoutubeSearchResult {
  final List<YoutubeVideo> videos;
  final bool hasMore;

  const YoutubeSearchResult({required this.videos, this.hasMore = false});
}

/// One selectable video quality (an H.264 video-only track). All qualities of a
/// video share the same separate [YoutubeResolvedStreams.audioUrl], so switching
/// quality only swaps the video URL — the player re-muxes the same audio.
class YoutubeQuality {
  final int height;
  final String videoUrl;
  const YoutubeQuality({required this.height, required this.videoUrl});

  String get label => '${height}p';
}

/// Resolved playable/downloadable URLs for a single YouTube video.
class YoutubeResolvedStreams {
  /// Video stream to play. When [audioUrl] is set this is a *video-only*
  /// adaptive stream (up to 1080p) and the player must mux in [audioUrl];
  /// otherwise it is a muxed (audio+video) progressive stream.
  final String? playUrl;

  /// Separate audio track to play alongside a video-only [playUrl]. Null when
  /// [playUrl] is already muxed.
  final String? audioUrl;

  /// Single-file (muxed) stream for downloads — has audio, but caps at ~360p.
  final String? downloadUrl;
  final String? title;
  final String? thumbnailUrl;
  final int? durationSeconds;

  /// All H.264 video-only qualities available (highest first), for in-player
  /// quality switching. Populated only in the separate-audio path (each entry
  /// pairs with the shared [audioUrl]); empty when only a muxed stream exists.
  final List<YoutubeQuality> qualities;

  const YoutubeResolvedStreams({
    this.playUrl,
    this.audioUrl,
    this.downloadUrl,
    this.title,
    this.thumbnailUrl,
    this.durationSeconds,
    this.qualities = const [],
  });

  bool get hasPlayable => playUrl != null && playUrl!.isNotEmpty;
}

/// A resolved-streams cache entry with the time it was resolved (for TTL).
class _ResolvedCacheEntry {
  final YoutubeResolvedStreams streams;
  final DateTime at;
  const _ResolvedCacheEntry(this.streams, this.at);
}

/// Service for searching and resolving YouTube videos fully on-device.
///
/// - **Search** uses YouTube's internal InnerTube API directly (the same
///   endpoint the website uses). youtube_explode's own search parser is broken
///   in the current release, and public Piped/Invidious search proxies are
///   unreliable, so we call InnerTube ourselves with a parser we control.
/// - **Resolution** uses youtube_explode's stream extraction, which runs
///   against YouTube from the user's own IP — this avoids the "confirm you're
///   not a bot" datacenter-IP blocks that break public proxy instances.
///
/// No API key to manage and no third-party server in the path.
///
/// Shared: [LemmyService] uses [extractYouTubeId] + [resolveStreams] to make
/// Lemmy's many YouTube links playable in-app.
class YoutubeService {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  // Public InnerTube web-client key + context (well-known constants).
  static const String _innertubeKey =
      'AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8';
  static const String _clientName = 'WEB';
  static const String _clientVersion = '2.20240101.00.00';
  static const Duration _httpTimeout = Duration(seconds: 15);

  /// Continuation token for the current search (for pagination).
  static String? _continuationToken;

  // ============== Search (InnerTube) ==============

  static Map<String, dynamic> get _context => {
        'client': {
          'clientName': _clientName,
          'clientVersion': _clientVersion,
          'hl': 'en',
          'gl': 'US',
        },
      };

  static Future<Map<String, dynamic>> _innertube(
      String endpoint, Map<String, dynamic> body) async {
    final uri = Uri.parse(
        'https://www.youtube.com/youtubei/v1/$endpoint?key=$_innertubeKey&prettyPrint=false');
    final resp = await http
        .post(uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': _userAgent,
            },
            body: json.encode({'context': _context, ...body}))
        .timeout(_httpTimeout);

    if (resp.statusCode != 200) {
      throw Exception('YouTube search failed (HTTP ${resp.statusCode})');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  /// Run a fresh search. Resets pagination state.
  static Future<YoutubeSearchResult> search(String query) async {
    final data = await _innertube('search', {'query': query});
    return _parseSearchResponse(data);
  }

  /// Fetch the next page of the current search, if any.
  static Future<YoutubeSearchResult> searchMore() async {
    final token = _continuationToken;
    if (token == null || token.isEmpty) {
      return const YoutubeSearchResult(videos: [], hasMore: false);
    }
    final data = await _innertube('search', {'continuation': token});
    return _parseSearchResponse(data);
  }

  static YoutubeSearchResult _parseSearchResponse(Map<String, dynamic> data) {
    final renderers = <Map<String, dynamic>>[];
    String? continuation;

    void walk(dynamic node) {
      if (node is Map<String, dynamic>) {
        final vr = node['videoRenderer'];
        if (vr is Map<String, dynamic>) renderers.add(vr);
        // The results "load more" token lives specifically in the
        // continuationItemRenderer — other continuationCommands in the
        // response belong to unrelated UI chrome (filters, topbar, hotkeys).
        final contItem = node['continuationItemRenderer'];
        if (contItem is Map) {
          final token = contItem['continuationEndpoint']?['continuationCommand']
              ?['token'];
          if (token is String) continuation = token;
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(data);
    _continuationToken = continuation;

    final videos = <YoutubeVideo>[];
    for (final vr in renderers) {
      final video = _parseVideoRenderer(vr);
      if (video != null) videos.add(video);
    }

    return YoutubeSearchResult(
      videos: videos,
      hasMore: continuation != null && continuation!.isNotEmpty,
    );
  }

  static YoutubeVideo? _parseVideoRenderer(Map<String, dynamic> vr) {
    final id = vr['videoId']?.toString();
    if (id == null || id.isEmpty) return null;

    final title = _readText(vr['title']);
    if (title == null || title.isEmpty) return null;

    final author = _readText(vr['ownerText']) ?? _readText(vr['longBylineText']) ?? '';
    final lengthText = vr['lengthText']?['simpleText']?.toString();
    final viewsText = vr['viewCountText']?['simpleText']?.toString() ??
        _readText(vr['viewCountText']);
    final published = vr['publishedTimeText']?['simpleText']?.toString();

    return YoutubeVideo(
      id: id,
      title: title,
      author: author,
      thumbnailUrl: thumbnailForId(id),
      durationSeconds: _parseDuration(lengthText),
      views: _parseViews(viewsText),
      publishedLabel: published,
    );
  }

  /// Read a YouTube text object (`{simpleText}` or `{runs:[{text}]}`).
  static String? _readText(dynamic node) {
    if (node is! Map) return null;
    final simple = node['simpleText'];
    if (simple is String) return simple;
    final runs = node['runs'];
    if (runs is List) {
      return runs.map((r) => r is Map ? (r['text']?.toString() ?? '') : '').join();
    }
    return null;
  }

  /// Parse "1:01:14" / "6:10" into seconds.
  static int? _parseDuration(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(':');
    int secs = 0;
    for (final p in parts) {
      final n = int.tryParse(p.trim());
      if (n == null) return null;
      secs = secs * 60 + n;
    }
    return secs > 0 ? secs : null;
  }

  /// Parse "133,864,158 views" into an int.
  static int? _parseViews(String? s) {
    if (s == null) return null;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  // ============== Stream resolution (youtube_explode) ==============

  /// Short-lived cache of successful resolves, keyed by videoId. googlevideo
  /// stream URLs stay valid far longer than this TTL, so a hit is safe to play —
  /// and it spares a second isolate + extraction when the detail page's trailer
  /// prefetch and its Trailer button (or a re-open) resolve the same id.
  static final Map<String, _ResolvedCacheEntry> _resolveCache = {};
  static const Duration _resolveCacheTtl = Duration(minutes: 10);

  /// Resolves in flight, keyed by videoId, so concurrent callers for the same id
  /// (prefetch + Trailer button) share one isolate instead of spawning two.
  static final Map<String, Future<YoutubeResolvedStreams?>> _resolveInFlight = {};

  /// Resolution cap for ambient backdrop trailers (Home hero, Discover rail).
  /// They render in a small region, so a 480p decode looks identical there while
  /// being far lighter than a 720/1080p decode+composite on weak TV silicon.
  static const int ambientTrailerMaxHeight = 480;

  /// Resolve a YouTube [videoId] into playable/downloadable stream URLs.
  ///
  /// For playback this prefers a high-res *video-only* H.264 stream at or below
  /// the user's preferred resolution (see [StorageService.getYoutubeMaxHeight])
  /// paired with a separate AAC audio stream (the player muxes them). For
  /// downloads it returns the best muxed single-file stream (has audio, ~360p).
  ///
  /// Deduped by in-flight id + cached briefly; the heavy extraction runs off the
  /// main isolate (see [_resolveStreamsBlocking]).
  /// [maxHeightOverride] forces the default-quality cap instead of the user's
  /// playback preference — the ambient hero/Discover trailers pass a low value
  /// (they render in a small region, so a 480p decode is plenty and far lighter
  /// on weak TV silicon: less decode, less buffering, less per-frame GPU upload).
  /// Cached separately from the un-capped resolve so it never collides with the
  /// fullscreen player resolving the same video at full quality.
  static Future<YoutubeResolvedStreams?> resolveStreams(
    String videoId, {
    int? maxHeightOverride,
  }) {
    final key = _resolveKey(videoId, maxHeightOverride);
    final cached = _resolveCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < _resolveCacheTtl) {
      return Future.value(cached.streams);
    }
    final inFlight = _resolveInFlight[key];
    if (inFlight != null) return inFlight;
    final future = _resolveUncached(videoId, maxHeightOverride: maxHeightOverride);
    _resolveInFlight[key] = future;
    return future.whenComplete(() => _resolveInFlight.remove(key));
  }

  static String _resolveKey(String videoId, int? maxHeightOverride) =>
      maxHeightOverride == null ? videoId : '$videoId#h$maxHeightOverride';

  static Future<YoutubeResolvedStreams?> _resolveUncached(
    String videoId, {
    int? maxHeightOverride,
  }) async {
    // Read the user's resolution cap on the MAIN isolate — SharedPreferences is
    // a platform channel and isn't available in the background isolate below.
    // An explicit override (ambient trailers) skips the pref entirely.
    final maxHeight =
        maxHeightOverride ?? await StorageService.getYoutubeMaxHeight();
    try {
      // youtube_explode fetches the watch page, deciphers the signature cipher
      // and parses a large player-response JSON — all synchronous CPU that would
      // otherwise freeze the UI isolate (blocking DPAD/focus) for ~1s per client
      // it tries. Run it in a throwaway background isolate so the main isolate
      // only awaits (the network calls are already async).
      final streams =
          await Isolate.run(() => _resolveStreamsBlocking(videoId, maxHeight));
      if (streams != null) {
        // Prune expired entries so the cache stays bounded to the active window.
        _resolveCache
            .removeWhere((_, e) => DateTime.now().difference(e.at) >= _resolveCacheTtl);
        _resolveCache[_resolveKey(videoId, maxHeightOverride)] =
            _ResolvedCacheEntry(streams, DateTime.now());
      }
      return streams;
    } catch (e) {
      // Covers both isolate-spawn failures and any error rethrown from the
      // extraction (the isolate lets errors propagate rather than swallowing
      // them) — so a YouTube cipher/player-response break is still diagnosable.
      debugPrint('YoutubeService: resolve failed for $videoId — $e');
      return null;
    }
  }

  /// The heavy resolution, run OFF the main isolate. Pure Dart (youtube_explode
  /// is HTTP-only, no plugins/platform channels), so it's isolate-safe. The
  /// [yt_explode.YoutubeExplode] instance (and any sockets) die with the isolate.
  /// Errors propagate to [_resolveUncached] on the main isolate (where logging
  /// works); only [yt_explode.YoutubeExplode.close] is guarded so a teardown
  /// failure can't discard a valid result.
  static Future<YoutubeResolvedStreams?> _resolveStreamsBlocking(
    String videoId,
    int maxHeight,
  ) async {
    final yt = yt_explode.YoutubeExplode();
    try {
      // Use the ANDROID_VR client: its googlevideo stream URLs open directly in
      // ffmpeg/mpv, whereas the default (ANDROID) client's URLs return HTTP 403
      // unless the request carries a Range header (which media_kit's bundled
      // ffmpeg omits on initial open). Fall back to the default client if VR
      // extraction fails for a given video.
      yt_explode.StreamManifest manifest;
      try {
        manifest = await yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [yt_explode.YoutubeApiClient.androidVr],
        );
      } catch (_) {
        manifest = await yt.videos.streamsClient.getManifest(videoId);
      }

      // Best muxed single-file stream (download + playback fallback).
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      final muxedMp4 = muxed.where((s) => s.container.name.toLowerCase() == 'mp4');
      final bestMuxed =
          (muxedMp4.isNotEmpty ? muxedMp4.first : (muxed.isNotEmpty ? muxed.first : null))
              ?.url
              .toString();

      // High-res playback: best H.264 video-only (<= cap) + best AAC audio.
      // We deliberately require H.264 (avc) and AAC (mp4): VP9 and especially
      // AV1 video-only streams fail to decode on many players/devices (mpv on
      // macOS stalls on AV1), and would otherwise be picked at higher
      // resolutions. When no H.264 stream exists we fall back to the muxed
      // 360p stream below (also H.264).
      String? playUrl;
      String? audioUrl;
      final qualities = <YoutubeQuality>[];
      final videoOnly = manifest.videoOnly
          .where((s) => s.videoCodec.toLowerCase().contains('avc'))
          .toList();
      final audioStreams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (videoOnly.isNotEmpty && audioStreams.isNotEmpty) {
        videoOnly.sort(
            (a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

        // Expose every distinct height (highest first) as a switchable quality —
        // the whole point of in-player switching is to override the launch cap,
        // so the list is NOT filtered to maxHeight (only the default pick below
        // is). YouTube can list several bitrates per height; keep the first.
        final seenHeights = <int>{};
        for (final s in videoOnly) {
          final h = s.videoResolution.height;
          if (!seenHeights.add(h)) continue;
          qualities.add(YoutubeQuality(height: h, videoUrl: s.url.toString()));
        }

        // Default pick = highest quality at or below the preferred height; if
        // none that low, the lowest available. Chosen FROM the deduped list so
        // [playUrl] is always one of [qualities] (the in-player "now playing"
        // highlight matches by URL).
        final atOrBelow =
            qualities.where((q) => q.height <= maxHeight).toList();
        final chosen = atOrBelow.isNotEmpty ? atOrBelow.first : qualities.last;
        playUrl = chosen.videoUrl;

        audioStreams.sort(
            (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
        audioUrl = audioStreams.first.url.toString();
      }

      // Fall back to muxed if adaptive streams are unavailable.
      if (playUrl == null) {
        playUrl = bestMuxed;
        audioUrl = null;
      }
      if (playUrl == null) return null;

      String? title;
      String? thumb;
      int? duration;
      try {
        final video = await yt.videos.get(videoId);
        title = video.title;
        thumb = video.thumbnails.highResUrl;
        duration = video.duration?.inSeconds;
      } catch (_) {
        // Metadata is best-effort; the stream URL is what matters.
      }

      return YoutubeResolvedStreams(
        playUrl: playUrl,
        audioUrl: audioUrl,
        downloadUrl: bestMuxed ?? playUrl,
        title: title,
        thumbnailUrl: thumb,
        durationSeconds: duration,
        qualities: qualities,
      );
    } finally {
      // Guarded: a close() failure must not replace a valid return value (or a
      // legitimately-propagating extraction error) with a teardown exception.
      try {
        yt.close();
      } catch (_) {}
    }
  }

  // ============== URL helpers (shared with Lemmy) ==============

  static final List<RegExp> _idPatterns = [
    RegExp(r'[?&]v=([a-zA-Z0-9_-]{11})'),
    RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
    RegExp(r'/shorts/([a-zA-Z0-9_-]{11})'),
    RegExp(r'/embed/([a-zA-Z0-9_-]{11})'),
    RegExp(r'/live/([a-zA-Z0-9_-]{11})'),
  ];

  /// Extract a YouTube video id from any common YouTube URL form.
  static String? extractYouTubeId(String url) {
    if (url.isEmpty) return null;
    for (final pattern in _idPatterns) {
      final match = pattern.firstMatch(url);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Whether a URL points to YouTube.
  static bool isYouTubeUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('youtube.com') || lower.contains('youtu.be');
  }

  /// A YouTube-hosted thumbnail for a video id.
  static String thumbnailForId(String videoId) =>
      'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
}
