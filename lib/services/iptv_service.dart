import 'dart:typed_data' show BytesBuilder;

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

  // Parsed playlists are large (a big M3U yields tens of thousands of channel
  // objects), so keep only a few resident — the TTL alone never frees memory
  // for distinct URLs.
  static const _maxCachedPlaylists = 3;

  // Refuse to buffer arbitrarily large playlists: a 100MB+ M3U held as bytes
  // + decoded string + parsed channels at once can OOM a low-RAM TV.
  static const _maxPlaylistBytes = 50 * 1024 * 1024; // 50 MB

  // Hard ceiling on the whole download so a slow-dripping server can't pin
  // the add/loading UI indefinitely (the per-chunk timeout below only catches
  // full stalls). More generous than the old flat 30s so big-but-healthy
  // playlists still succeed.
  static const _fetchDeadline = Duration(minutes: 2);

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

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers['User-Agent'] = 'Debrify/1.0';
      request.headers['Accept'] = '*/*';
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 30));

      if (streamed.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch playlist: HTTP ${streamed.statusCode}',
        );
      }

      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > _maxPlaylistBytes) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error:
              'Playlist is too large (${declaredLength ~/ (1024 * 1024)} MB, '
              'limit ${_maxPlaylistBytes ~/ (1024 * 1024)} MB)',
        );
      }

      // Stream the body so an over-limit (or lying Content-Length) download
      // aborts early instead of buffering the whole payload.
      final startedAt = DateTime.now();
      final builder = BytesBuilder(copy: false);
      await for (final chunk
          in streamed.stream.timeout(const Duration(seconds: 60))) {
        builder.add(chunk);
        if (DateTime.now().difference(startedAt) > _fetchDeadline) {
          return IptvParseResult(
            channels: [],
            categories: [],
            error: 'Playlist download timed out',
          );
        }
        if (builder.length > _maxPlaylistBytes) {
          return IptvParseResult(
            channels: [],
            categories: [],
            error:
                'Playlist is too large (over '
                '${_maxPlaylistBytes ~/ (1024 * 1024)} MB)',
          );
        }
      }

      final content = M3uParser.decodeBytes(builder.takeBytes());

      final result = await _parse(content);

      // Cache the result
      _cache[url] = _CachedPlaylist(
        result: result,
        fetchedAt: DateTime.now(),
      );
      _evictCache();

      debugPrint('IptvService: Parsed ${result.channels.length} channels, ${result.categories.length} categories');

      return result;
    } catch (e) {
      debugPrint('IptvService: Error fetching playlist: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch playlist: $e',
      );
    } finally {
      client.close();
    }
  }

  /// Drop expired entries, then the oldest beyond the cap.
  void _evictCache() {
    final now = DateTime.now();
    _cache.removeWhere(
      (_, c) => now.difference(c.fetchedAt) >= _cacheDuration,
    );
    while (_cache.length > _maxCachedPlaylists) {
      String? oldestKey;
      DateTime? oldestAt;
      _cache.forEach((key, cached) {
        if (oldestAt == null || cached.fetchedAt.isBefore(oldestAt!)) {
          oldestAt = cached.fetchedAt;
          oldestKey = key;
        }
      });
      _cache.remove(oldestKey);
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
  Future<IptvParseResult> parseContent(String content) async {
    debugPrint('IptvService: Parsing content directly (${content.length} chars)');
    final result = await _parse(content);
    debugPrint('IptvService: Parsed ${result.channels.length} channels, ${result.categories.length} categories');
    return result;
  }

  /// Parse large playlists off the UI isolate to avoid freezing the app
  Future<IptvParseResult> _parse(String content) async {
    return content.length > 100 * 1024
        ? await compute(M3uParser.parse, content)
        : M3uParser.parse(content);
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
