import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_explode;

/// InnerTube client and URL checks used by `YoutubeService` while it
/// resolves a video's streams.
final class YoutubeStreamProbes {
  const YoutubeStreamProbes._();

  /// Probe the primary pair and muxed fallback separately. An explicit HTTP
  /// 403 marks that path unusable — the signature of YouTube's PO-token/Range
  /// gating — while timeouts and transport errors fail open so a flaky probe
  /// can never take down playback that would have worked.
  static Future<({bool primary, bool muxedFallback})> chosenUrlsUsable(
    String playUrl,
    String? audioUrl,
    String? muxedFallbackUrl,
  ) async {
    final primaryCheck = Future.wait([
      urlUsable(playUrl),
      if (audioUrl != null && audioUrl.isNotEmpty) urlUsable(audioUrl),
    ]).then((checks) => !checks.contains(false));
    final fallbackCheck =
        audioUrl != null &&
            audioUrl.isNotEmpty &&
            muxedFallbackUrl != null &&
            muxedFallbackUrl.isNotEmpty
        ? urlUsable(muxedFallbackUrl)
        : Future<bool>.value(true);
    final checks = await Future.wait([primaryCheck, fallbackCheck]);
    return (primary: checks[0], muxedFallback: checks[1]);
  }

  /// False only on an explicit HTTP 403; timeouts and transport errors fail
  /// open (see [chosenUrlsUsable]).
  static Future<bool> urlUsable(String url) async {
    try {
      final resp = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      return resp.statusCode != 403;
    } catch (_) {
      return true;
    }
  }

  /// The YouTube app for Apple Vision Pro, mirroring yt-dlp's `visionos`
  /// InnerTube client. Not in youtube_explode 3.1.0 (upstream PRs #389/#390
  /// are unmerged); its client constructor is public, so it lives here.
  /// Version strings come from yt-dlp — bump them from there if YouTube
  /// starts rejecting this identity.
  static const visionOs = yt_explode.YoutubeApiClient({
    'context': {
      'client': {
        'clientName': 'VISIONOS',
        'clientVersion': '1.02',
        'deviceMake': 'Apple',
        'deviceModel': 'RealityDevice17,1',
        'osName': 'visionOS',
        'osVersion': '26.5.23O471',
        'userAgent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 '
            'Safari/605.1.15',
        'hl': 'en',
        'timeZone': 'UTC',
        'utcOffsetMinutes': 0,
      },
    },
  }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

  /// Best muxed single-file stream in [manifest]: MP4 first, then bitrate.
  static yt_explode.MuxedStreamInfo? bestMuxedOf(
    yt_explode.StreamManifest manifest,
  ) {
    final muxed = manifest.muxed.toList()
      ..sort(
        (a, b) => b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond),
      );
    final muxedMp4 = muxed.where(
      (s) => s.container.name.toLowerCase() == 'mp4',
    );
    return muxedMp4.isNotEmpty
        ? muxedMp4.first
        : (muxed.isNotEmpty ? muxed.first : null);
  }

  /// A muxed stream from [client] that does not answer 403, for a selection
  /// whose own client served none. Never throws; null when unavailable.
  static Future<({String url, int height})?> muxedFallbackFrom(
    yt_explode.YoutubeExplode yt,
    String videoId,
    yt_explode.YoutubeApiClient client,
  ) async {
    try {
      final manifest = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [client],
      );
      final stream = bestMuxedOf(manifest);
      if (stream == null) return null;
      final url = stream.url.toString();
      if (!await urlUsable(url)) return null;
      return (url: url, height: stream.videoResolution.height);
    } catch (e) {
      debugPrint('YoutubeService: $videoId muxed fallback failed — $e');
      return null;
    }
  }
}
