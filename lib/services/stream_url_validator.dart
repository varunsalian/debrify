import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// HEAD-probe validation for direct stream URLs — "is this link actually
/// alive before we launch a player at it?".
///
/// Extracted from the Stremio TV screen's private `_isValidStreamUrl` so
/// quick-play's direct-link path shares the exact same check. Rules:
///
///  • HEAD request, following redirects manually across up to [_maxRedirects]
///    requests total (so the FINAL url is what gets judged), [timeout] per
///    hop — see the lenient carve-out below for what an unanswered hop means.
///  • Any non-2xx terminal response, a redirect without a location, or an
///    exhausted redirect budget → dead.
///  • An HLS playlist (by content-type or a .m3u8 path) is alive on any 2xx —
///    playlists have no meaningful content-length.
///  • Anything else must report a content-length of at least [minBytes]:
///    dead hosts love serving tiny placeholder/error videos with a 200.
///
/// Known trade-off (inherited from Stremio TV): hosts that reject HEAD or
/// omit content-length on real videos read as dead. Callers sit this check
/// in front of a try-the-next-candidate ladder, so a false negative costs a
/// candidate, not the play.
///
/// One exception to that trade-off is carved out for [lenient] callers: a
/// request that TIMES OUT is not judged dead. Slow-to-first-byte origins are
/// real (a Plex server waking up behind an addon routinely needs longer than
/// [timeout]), and rejecting them loses a play the unvalidated flow would
/// have delivered — the one thing lenient mode promises never to do.
class StreamUrlValidator {
  StreamUrlValidator._();

  /// Minimum content size (50 MB) to consider a direct stream a real video.
  static const int minContentBytes = 50 * 1024 * 1024;

  /// Per-hop request timeout. Mutable purely as a test seam (same idea as
  /// [clientFactory]) so timeout cases don't cost real seconds in the suite.
  @visibleForTesting
  static Duration timeout = const Duration(seconds: 5);

  static const int _maxRedirects = 5;

  /// Test seam: swapped for a mock client factory in unit tests.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  static bool _isHlsPlaylist(String url, Map<String, String> headers) {
    final type = (headers['content-type'] ?? '').toLowerCase();
    if (type.contains('mpegurl')) return true; // application/x-mpegurl & co.
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.m3u8');
  }

  /// Whether [url] looks like a playable video stream.
  ///
  /// [lenient] is for callers that must never lose a play the unvalidated
  /// flow would have delivered (quick-play): only positive evidence of death
  /// rejects — a host that refuses HEAD (405/501), answers 2xx without a
  /// content-length (chunked), or leaves any hop unanswered for [timeout]
  /// counts as alive, since those give no signal either way and whole CDNs
  /// fail them identically. Strict mode (the default — Stremio TV's original
  /// behavior) treats missing evidence as dead.
  static Future<bool> isPlayableVideoUrl(
    String url, {
    int minBytes = minContentBytes,
    bool lenient = false,
  }) async {
    // Tracks the hop actually in flight so a timeout can name the host that
    // stalled rather than the URL the chain started from.
    var lastUrl = url;
    try {
      final client = clientFactory();
      try {
        var currentUrl = url;
        for (int i = 0; i < _maxRedirects; i++) {
          lastUrl = currentUrl;
          final request = http.Request('HEAD', Uri.parse(currentUrl));
          // LOAD-BEARING even though MockClient tests can't exercise it: the
          // real IOClient auto-follows redirects, which would hide the hop
          // cap, the no-location check, and the final-url .m3u8 judgment.
          request.followRedirects = false;
          final streamed = await client.send(request).timeout(timeout);
          // Drain response stream to release resources. Bounded by the same
          // per-hop budget: a HEAD carries no body, so an intermediary that
          // stalls here would otherwise hang the probe forever — no timeout,
          // no rejection, and the caller's overlay never advances.
          await streamed.stream.drain().timeout(timeout);

          if (streamed.statusCode >= 300 && streamed.statusCode < 400) {
            final location = streamed.headers['location'];
            if (location == null || location.isEmpty) {
              debugPrint(
                'StreamUrlValidator: HEAD $currentUrl → '
                '${streamed.statusCode} (redirect, no location)',
              );
              return false;
            }
            // Resolve relative redirects
            currentUrl = Uri.parse(currentUrl).resolve(location).toString();
            debugPrint(
              'StreamUrlValidator: HEAD → ${streamed.statusCode}, '
              'following redirect',
            );
            continue;
          }

          // Reject non-2xx responses. 405/501 mean "HEAD not supported" —
          // the host answered, so leniently that's alive, not dead.
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            if (lenient &&
                (streamed.statusCode == 405 || streamed.statusCode == 501)) {
              debugPrint(
                'StreamUrlValidator: HEAD $currentUrl → '
                '${streamed.statusCode}, host refuses HEAD — accepting (lenient)',
              );
              return true;
            }
            debugPrint(
              'StreamUrlValidator: HEAD $currentUrl → '
              '${streamed.statusCode}, rejecting non-2xx',
            );
            return false;
          }

          // HLS playlists are alive on any 2xx — no meaningful length.
          if (_isHlsPlaylist(currentUrl, streamed.headers)) {
            debugPrint(
              'StreamUrlValidator: HEAD $currentUrl → '
              '${streamed.statusCode}, HLS playlist — accepting',
            );
            return true;
          }

          final contentLength = int.tryParse(
            streamed.headers['content-length'] ?? '',
          );
          if (contentLength == null) {
            if (lenient) {
              debugPrint(
                'StreamUrlValidator: HEAD $currentUrl → '
                '${streamed.statusCode}, no content-length — accepting (lenient)',
              );
              return true;
            }
            debugPrint(
              'StreamUrlValidator: HEAD $currentUrl → '
              '${streamed.statusCode}, no content-length',
            );
            return false;
          }
          final sizeMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
          debugPrint(
            'StreamUrlValidator: HEAD $currentUrl → '
            '${streamed.statusCode}, size: ${sizeMb}MB',
          );
          return contentLength >= minBytes;
        }
        // Too many redirects
        debugPrint(
          'StreamUrlValidator: HEAD $url → too many redirects, rejecting',
        );
        return false;
      } finally {
        client.close();
      }
    } on TimeoutException {
      // Absence of an answer is not evidence of death — see the carve-out in
      // the class doc. Strict callers keep the original behavior.
      if (lenient) {
        debugPrint(
          'StreamUrlValidator: HEAD $lastUrl did not answer within '
          '${timeout.inSeconds}s — accepting (lenient)',
        );
        return true;
      }
      debugPrint('StreamUrlValidator: HEAD $lastUrl timed out, rejecting');
      return false;
    } catch (e) {
      // Everything else is a refusal the host (or the stack) actively
      // returned — connection refused, TLS rejection, failed host lookup.
      // Only a silent non-answer gets the benefit of the doubt above.
      debugPrint('StreamUrlValidator: HEAD $lastUrl failed: $e');
      return false;
    }
  }
}
