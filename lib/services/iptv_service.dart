import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/iptv_playlist.dart';
import '../utils/m3u_parser.dart';

/// Service for fetching and managing IPTV M3U playlists
class IptvService {
  static final IptvService _instance = IptvService._internal();
  static IptvService get instance => _instance;
  IptvService._internal();

  // Cache for parsed playlists (URL -> result)
  final Map<String, _CachedPlaylist> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  /// Fetch and parse an M3U playlist from URL
  Future<IptvParseResult> fetchPlaylist(String url, {bool forceRefresh = false}) async {
    // Check cache
    if (!forceRefresh && _cache.containsKey(url)) {
      final cached = _cache[url]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint('IptvService: Using cached playlist for $url');
        return cached.result;
      }
    }

    debugPrint('IptvService: Fetching playlist from $url');

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Debrify/1.0',
          'Accept': '*/*',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch playlist: HTTP ${response.statusCode}',
        );
      }

      // Try to decode as UTF-8, fallback to latin1
      String content;
      try {
        content = utf8.decode(response.bodyBytes);
      } catch (e) {
        content = latin1.decode(response.bodyBytes);
      }

      final result = M3uParser.parse(content);

      // Cache the result
      _cache[url] = _CachedPlaylist(
        result: result,
        fetchedAt: DateTime.now(),
      );

      debugPrint('IptvService: Parsed ${result.channels.length} channels, ${result.categories.length} categories');

      return result;
    } catch (e) {
      debugPrint('IptvService: Error fetching playlist: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch playlist: $e',
      );
    }
  }

  /// Filter channels by category
  List<IptvChannel> filterByCategory(List<IptvChannel> channels, String? category) {
    if (category == null || category.isEmpty) {
      return channels;
    }
    return channels.where((c) => c.group == category).toList();
  }

  /// Search channels by name
  List<IptvChannel> searchChannels(List<IptvChannel> channels, String query) {
    if (query.isEmpty) {
      return channels;
    }
    final lowerQuery = query.toLowerCase();
    return channels.where((c) =>
      c.name.toLowerCase().contains(lowerQuery) ||
      (c.group?.toLowerCase().contains(lowerQuery) ?? false)
    ).toList();
  }

  /// Clear cache for a specific URL or all
  void clearCache([String? url]) {
    if (url != null) {
      _cache.remove(url);
    } else {
      _cache.clear();
    }
  }

  /// Validate if a URL looks like a valid M3U URL
  static bool isValidPlaylistUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) {
        return false;
      }
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Parse M3U content directly (for file-based playlists)
  IptvParseResult parseContent(String content) {
    debugPrint('IptvService: Parsing content directly (${content.length} chars)');
    final result = M3uParser.parse(content);
    debugPrint('IptvService: Parsed ${result.channels.length} channels, ${result.categories.length} categories');
    return result;
  }
}

class _CachedPlaylist {
  final IptvParseResult result;
  final DateTime fetchedAt;

  _CachedPlaylist({
    required this.result,
    required this.fetchedAt,
  });
}
