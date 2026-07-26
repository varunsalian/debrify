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

/// One selectable video quality (a video-only track). All qualities of a
/// video share the same separate [YoutubeResolvedStreams.audioUrl], so switching
/// quality only swaps the video URL — the player re-muxes the same audio.
///
/// Entries are H.264 up to 1080p and VP9 above it (YouTube serves 1440p/2160p in
/// VP9/AV1 but never H.264); AV1 is never listed, as its decode is unreliable on
/// our player matrix. See [YoutubeService._resolveStreamsBlocking].
class YoutubeQuality {
  final int height;
  final String videoUrl;
  const YoutubeQuality({required this.height, required this.videoUrl});

  String get label => '${height}p';
}

/// Resolved playable/downloadable URLs for a single YouTube video.
class YoutubeResolvedStreams {
  /// Video stream to play. When [audioUrl] is set this is a *video-only*
  /// adaptive stream (always H.264, capped at the user's preferred height) and
  /// the player must mux in [audioUrl]; otherwise it is a muxed (audio+video)
  /// progressive stream. Higher-resolution VP9 rungs are offered via
  /// [qualities] for opt-in switching, but are never the default here.
  final String? playUrl;

  /// Separate audio track to play alongside a video-only [playUrl]. Null when
  /// [playUrl] is already muxed.
  final String? audioUrl;

  /// Single-file (muxed) stream for downloads — has audio, but caps at ~360p.
  final String? downloadUrl;

  /// Pixel height of [downloadUrl] (e.g. 720, 360), for surfacing the actual
  /// download quality to the user. Null if it couldn't be determined.
  final int? downloadHeight;

  /// Whether [downloadUrl] carries audio. True for a muxed stream (the normal
  /// case); false only in the rare fallback where the sole available stream is
  /// a video-only track (YouTube served no combined file for this video).
  final bool downloadHasAudio;

  final String? title;
  final String? thumbnailUrl;
  final int? durationSeconds;

  /// All video-only qualities available (highest first), for in-player quality
  /// switching. H.264 up to 1080p plus VP9 above it (1440p/2160p); AV1 excluded.
  /// Populated only in the separate-audio path (each entry pairs with the shared
  /// [audioUrl]); empty when only a muxed stream exists.
  final List<YoutubeQuality> qualities;

  const YoutubeResolvedStreams({
    this.playUrl,
    this.audioUrl,
    this.downloadUrl,
    this.downloadHeight,
    this.downloadHasAudio = true,
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
  /// 720p: crisp in the hero region (480p read soft once the edge feathers came
  /// off) while still lighter than a 1080p decode+composite on weak TV silicon.
  static const int ambientTrailerMaxHeight = 720;

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

      // Best muxed single-file stream (download + playback fallback). Keep the
      // stream object (not just its URL) so we can report its resolution as the
      // actual download quality to the user.
      final muxed = manifest.muxed.toList()
        ..sort((a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
      final muxedMp4 = muxed.where((s) => s.container.name.toLowerCase() == 'mp4');
      final bestMuxedStream = muxedMp4.isNotEmpty
          ? muxedMp4.first
          : (muxed.isNotEmpty ? muxed.first : null);
      final bestMuxed = bestMuxedStream?.url.toString();
      final bestMuxedHeight = bestMuxedStream?.videoResolution.height;

      // High-res playback: video-only track + best AAC audio (mp4). We allow
      // H.264 (avc) AND VP9, but deliberately EXCLUDE AV1 (av01) — AV1 decode is
      // unreliable across our player matrix (mpv on macOS stalls on it). VP9 is
      // what unlocks resolutions above 1080p: YouTube serves 1440p/2160p only in
      // VP9/AV1, never H.264.
      //
      // RISK CONTAINMENT — this must not regress existing playback:
      //  * The shipped default preference is 1080p, and every height <=1080p
      //    resolves to H.264 (the tie-break below keeps it), so out-of-the-box
      //    auto-play is byte-equivalent to before VP9 was allowed.
      //  * VP9 becomes the default pick ONLY when the user explicitly raises the
      //    Quality preference to 1440p/2160p — heights YouTube serves only in
      //    VP9. That is a deliberate opt-in they can lower again if their device
      //    can't decode it smoothly.
      //  * Every height is also offered in the in-player quality switcher for a
      //    per-video override, independent of the preference.
      bool isAvc(String c) => c.toLowerCase().contains('avc');
      bool isVp9(String c) {
        final l = c.toLowerCase();
        return l.contains('vp9') || l.contains('vp09');
      }

      String? playUrl;
      String? audioUrl;
      final qualities = <YoutubeQuality>[];
      final videoOnly = manifest.videoOnly
          .where((s) => isAvc(s.videoCodec) || isVp9(s.videoCodec))
          .toList();
      final audioStreams = manifest.audioOnly
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (videoOnly.isNotEmpty && audioStreams.isNotEmpty) {
        // Highest first; within a single height prefer H.264 so the <=1080p
        // rungs keep the exact stream they used before VP9 was allowed.
        videoOnly.sort((a, b) {
          final byHeight =
              b.videoResolution.height.compareTo(a.videoResolution.height);
          if (byHeight != 0) return byHeight;
          final aAvc = isAvc(a.videoCodec), bAvc = isAvc(b.videoCodec);
          if (aAvc == bAvc) return 0;
          return aAvc ? -1 : 1; // H.264 before VP9 at the same height
        });

        // One switchable entry per distinct height (highest first). Dedup keeps
        // the first, which — after the sort above — is H.264 wherever it exists.
        // The list is NOT filtered to maxHeight; the whole point of in-player
        // switching is to override the launch cap. YouTube can list several
        // bitrates per height; keep the first.
        final seenHeights = <int>{};
        for (final s in videoOnly) {
          final h = s.videoResolution.height;
          if (!seenHeights.add(h)) continue;
          qualities.add(YoutubeQuality(height: h, videoUrl: s.url.toString()));
        }

        // Default pick = highest quality at or below the user's preferred height
        // (the Quality dropdown); if the video has nothing that low, the lowest
        // available so it still plays. [qualities] is descending and H.264 sorts
        // first at equal heights, so any preference <=1080p resolves to the SAME
        // H.264 stream as before — VP9 is chosen only when the preference is
        // 1440p/2160p AND the video actually offers it. A video that lacks the
        // preferred height steps down to the next best automatically. Chosen FROM
        // [qualities] so [playUrl] always matches an entry (the in-player "now
        // playing" highlight matches by URL).
        final atOrBelow = qualities.where((q) => q.height <= maxHeight).toList();
        playUrl =
            (atOrBelow.isNotEmpty ? atOrBelow.first : qualities.last).videoUrl;

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

      // Describe the download stream for the user. Normally the muxed stream
      // (has audio, ≤720p). Only when no muxed stream exists do we fall back to
      // the video-only [playUrl] — a silent file whose height is its quality.
      final downloadUrl = bestMuxed ?? playUrl;
      int? downloadHeight;
      bool downloadHasAudio;
      if (bestMuxed != null) {
        downloadHeight = bestMuxedHeight;
        downloadHasAudio = true;
      } else {
        downloadHasAudio = false;
        final match = qualities.where((q) => q.videoUrl == playUrl);
        downloadHeight = match.isNotEmpty ? match.first.height : null;
      }

      return YoutubeResolvedStreams(
        playUrl: playUrl,
        audioUrl: audioUrl,
        downloadUrl: downloadUrl,
        downloadHeight: downloadHeight,
        downloadHasAudio: downloadHasAudio,
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
