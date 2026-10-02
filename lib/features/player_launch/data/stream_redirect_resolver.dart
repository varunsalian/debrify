import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final class StreamRedirectResolver {
  static final Map<String, String> resolvedStreamCache = <String, String>{};

  static final Map<String, String> redirectCache = <String, String>{};

  static void cacheResolvedStream(String? resumeId, String url) {
    if (resumeId == null) return;
    if (url.isEmpty) return;
    StreamRedirectResolver.resolvedStreamCache[resumeId] = url;
  }

  static
  /// Resolve redirects for a URL (for TV player HLS streams).
  /// Returns the final URL after following redirects, or original URL if no redirect.
  /// Only resolves URLs that look like they might be short redirect URLs.
  Future<String>
  resolveRedirectUrl(
    String url, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return '';
    debugPrint('[RedirectResolver] Input URL: $url');

    // Check cache first
    if (StreamRedirectResolver.redirectCache.containsKey(url)) {
      final cached = StreamRedirectResolver.redirectCache[url]!;
      debugPrint('[RedirectResolver] Cache HIT: $url -> $cached');
      return cached;
    }
    debugPrint('[RedirectResolver] Cache MISS, checking URL...');

    // Skip resolution for URLs that are unlikely to be redirects:
    // - Already have media extensions
    // - Known debrid CDN domains
    final uri = Uri.tryParse(url);
    if (uri == null) {
      debugPrint('[RedirectResolver] SKIP: Invalid URL, using original');
      return url;
    }

    final path = uri.path.toLowerCase();
    final host = uri.host.toLowerCase();
    debugPrint('[RedirectResolver] Host: $host, Path: $path');

    // Skip if already has a media extension
    if (path.endsWith('.m3u8') ||
        path.endsWith('.mp4') ||
        path.endsWith('.mkv') ||
        path.endsWith('.ts') ||
        path.endsWith('.mpd')) {
      debugPrint('[RedirectResolver] SKIP: Has media extension, using original');
      return url;
    }

    // Skip known debrid CDN domains (they don't redirect)
    if (host.contains('real-debrid') ||
        host.contains('torbox') ||
        host.contains('pikpak') ||
        host.contains('1fichier') ||
        host.contains('rapidgator')) {
      debugPrint(
        '[RedirectResolver] SKIP: Known debrid CDN domain, using original',
      );
      return url;
    }

    debugPrint(
      '[RedirectResolver] Attempting HEAD request to resolve redirects...',
    );

    try {
      // Use a client that doesn't follow redirects automatically
      final client = http.Client();
      try {
        final request = http.Request('HEAD', uri);
        request.followRedirects = false;
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

        final response = await client.send(request).timeout(const Duration(seconds: 5));

        if (canContinue?.call() == false) return '';
        debugPrint('[RedirectResolver] Response status: ${response.statusCode}');
        debugPrint('[RedirectResolver] Response headers: ${response.headers}');

        // Check if it's a redirect
        if (response.statusCode == 301 ||
            response.statusCode == 302 ||
            response.statusCode == 303 ||
            response.statusCode == 307 ||
            response.statusCode == 308) {
          final location = response.headers['location'];
          debugPrint('[RedirectResolver] Redirect detected! Location: $location');

          if (location != null && location.isNotEmpty) {
            // Handle relative URLs
            final resolvedUri = uri.resolve(location);
            final resolvedUrl = resolvedUri.toString();
            debugPrint(
              '[RedirectResolver] SUCCESS: Resolved $url -> $resolvedUrl',
            );

            // Cache the result
            StreamRedirectResolver.redirectCache[url] = resolvedUrl;
            return resolvedUrl;
          } else {
            debugPrint(
              '[RedirectResolver] WARNING: Redirect but no Location header',
            );
          }
        } else {
          debugPrint(
            '[RedirectResolver] No redirect (status ${response.statusCode}), using original',
          );
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('[RedirectResolver] ERROR: $e');
      debugPrint('[RedirectResolver] Falling back to original URL');
    }

    // No redirect or error - use original URL
    if (canContinue?.call() == false) return '';
    StreamRedirectResolver.redirectCache[url] = url;
    debugPrint('[RedirectResolver] Final URL (no change): $url');
    return url;
  }

  static void clearResolvedStreams(Iterable<String?> resumeIds) {
    for (final id in resumeIds) {
      if (id == null) continue;
      StreamRedirectResolver.resolvedStreamCache.remove(id);
    }
  }
}
