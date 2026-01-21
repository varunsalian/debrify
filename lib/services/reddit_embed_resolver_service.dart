import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolved video info from embedded content
class ResolvedEmbed {
  final String id;
  final String? hdUrl;
  final String? sdUrl;
  final String? thumbnailUrl;
  final double? duration;
  final int? width;
  final int? height;

  const ResolvedEmbed({
    required this.id,
    this.hdUrl,
    this.sdUrl,
    this.thumbnailUrl,
    this.duration,
    this.width,
    this.height,
  });

  /// Get the best available video URL (HD preferred)
  String? get videoUrl => hdUrl ?? sdUrl;

  /// Duration in seconds as int
  int? get durationSeconds => duration?.toInt();
}

/// Service for resolving embedded video URLs from Reddit posts
class RedditEmbedResolverService {
  static const String _baseUrl = 'https://api.redgifs.com/v2';
  static const String _userAgent = 'Debrify/1.0 (Flutter; Video Player)';

  // Cached token and expiry
  static String? _cachedToken;
  static DateTime? _tokenExpiry;

  /// Extract video ID from various embed URL formats
  static String? extractVideoId(String url) {
    // Formats:
    // https://www.redgifs.com/watch/videoname
    // https://redgifs.com/watch/videoname
    // https://v3.redgifs.com/watch/videoname
    // https://www.redgifs.com/ifr/videoname
    final patterns = [
      RegExp(r'redgifs\.com/watch/([a-zA-Z]+)', caseSensitive: false),
      RegExp(r'redgifs\.com/ifr/([a-zA-Z]+)', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1)?.toLowerCase();
      }
    }
    return null;
  }

  /// Check if a URL is a supported embed URL
  static bool isSupportedEmbedUrl(String url) {
    return url.contains('redgifs.com');
  }

  /// Get a temporary auth token (cached)
  static Future<String?> _getToken() async {
    // Return cached token if still valid (with 5 min buffer)
    if (_cachedToken != null && _tokenExpiry != null) {
      if (DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
        return _cachedToken;
      }
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/auth/temporary'),
        headers: {'User-Agent': _userAgent},
      );

      if (response.statusCode != 200) {
        debugPrint('RedditEmbedResolver: Failed to get token (HTTP ${response.statusCode})');
        return null;
      }

      final data = json.decode(response.body);
      _cachedToken = data['token'];

      // Token is valid for ~24 hours, but we'll refresh more often
      _tokenExpiry = DateTime.now().add(const Duration(hours: 12));

      debugPrint('RedditEmbedResolver: Got new token');
      return _cachedToken;
    } catch (e) {
      debugPrint('RedditEmbedResolver: Error getting token: $e');
      return null;
    }
  }

  /// Fetch video info from embed
  static Future<ResolvedEmbed?> getVideo(String videoId) async {
    final token = await _getToken();
    if (token == null) {
      debugPrint('RedditEmbedResolver: No token available');
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/gifs/$videoId'),
        headers: {
          'User-Agent': _userAgent,
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode != 200) {
        debugPrint('RedditEmbedResolver: Failed to get video (HTTP ${response.statusCode})');
        return null;
      }

      final data = json.decode(response.body);
      final gif = data['gif'];
      if (gif == null) {
        debugPrint('RedditEmbedResolver: No data in response');
        return null;
      }

      final urls = gif['urls'] ?? {};
      return ResolvedEmbed(
        id: videoId,
        hdUrl: urls['hd'],
        sdUrl: urls['sd'],
        thumbnailUrl: urls['thumbnail'] ?? urls['poster'],
        duration: (gif['duration'] as num?)?.toDouble(),
        width: gif['width'] as int?,
        height: gif['height'] as int?,
      );
    } catch (e) {
      debugPrint('RedditEmbedResolver: Error fetching video: $e');
      return null;
    }
  }

  /// Get video URL directly from an embed page URL
  static Future<String?> resolveVideoUrl(String pageUrl) async {
    final videoId = extractVideoId(pageUrl);
    if (videoId == null) {
      debugPrint('RedditEmbedResolver: Could not extract video ID from $pageUrl');
      return null;
    }

    final video = await getVideo(videoId);
    return video?.videoUrl;
  }
}
