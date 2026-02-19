import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/iptv_playlist.dart';

/// Result of Xtream Codes authentication
class XcAuthResult {
  final bool success;
  final String? error;
  final String? status;
  final DateTime? expDate;
  final int? maxConnections;
  final int? activeConnections;

  const XcAuthResult({
    required this.success,
    this.error,
    this.status,
    this.expDate,
    this.maxConnections,
    this.activeConnections,
  });
}

/// Service for fetching IPTV content via Xtream Codes API
class XtreamCodesService {
  static final XtreamCodesService instance = XtreamCodesService._();
  XtreamCodesService._();

  // Cache for parsed results (key -> result)
  final Map<String, _CachedResult> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  String _baseUrl(String serverUrl, String username, String password) {
    return '$serverUrl/player_api.php?username=$username&password=$password';
  }

  /// Authenticate and return account info
  Future<XcAuthResult> authenticate(String serverUrl, String username, String password) async {
    try {
      final url = _baseUrl(serverUrl, username, password);
      debugPrint('XtreamCodesService: Authenticating with $serverUrl');

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Debrify/1.0'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return XcAuthResult(
          success: false,
          error: 'Server returned HTTP ${response.statusCode}',
        );
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final userInfo = data['user_info'] as Map<String, dynamic>?;

      if (userInfo == null) {
        return const XcAuthResult(
          success: false,
          error: 'Invalid response from server',
        );
      }

      final status = userInfo['status']?.toString();
      if (status?.toLowerCase() != 'active') {
        return XcAuthResult(
          success: false,
          error: 'Account status: ${status ?? 'Unknown'}',
          status: status,
        );
      }

      DateTime? expDate;
      final expStr = userInfo['exp_date']?.toString();
      if (expStr != null && expStr.isNotEmpty) {
        final expTimestamp = int.tryParse(expStr);
        if (expTimestamp != null) {
          expDate = DateTime.fromMillisecondsSinceEpoch(expTimestamp * 1000);
        }
      }

      return XcAuthResult(
        success: true,
        status: status,
        expDate: expDate,
        maxConnections: int.tryParse(userInfo['max_connections']?.toString() ?? ''),
        activeConnections: int.tryParse(userInfo['active_cons']?.toString() ?? ''),
      );
    } catch (e) {
      debugPrint('XtreamCodesService: Auth error: $e');
      return XcAuthResult(
        success: false,
        error: 'Connection failed: $e',
      );
    }
  }

  /// Fetch live channels, converted to IptvChannel list + categories
  Future<IptvParseResult> fetchLiveStreams(String serverUrl, String username, String password) async {
    final cacheKey = '$serverUrl:$username:live';

    // Check cache
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint('XtreamCodesService: Using cached live streams for $serverUrl');
        return cached.result;
      }
    }

    try {
      final base = _baseUrl(serverUrl, username, password);

      // Fetch categories and streams in parallel
      final responses = await Future.wait([
        http.get(Uri.parse('$base&action=get_live_categories'), headers: {'User-Agent': 'Debrify/1.0'}).timeout(const Duration(seconds: 30)),
        http.get(Uri.parse('$base&action=get_live_streams'), headers: {'User-Agent': 'Debrify/1.0'}).timeout(const Duration(seconds: 60)),
      ]);

      if (responses[0].statusCode != 200 || responses[1].statusCode != 200) {
        final failedCode = responses[0].statusCode != 200
            ? responses[0].statusCode
            : responses[1].statusCode;
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch live streams: HTTP $failedCode',
        );
      }

      final categoriesData = json.decode(responses[0].body) as List<dynamic>;
      final streamsData = json.decode(responses[1].body) as List<dynamic>;

      // Build category ID -> name map
      final categoryMap = <String, String>{};
      final categoryNames = <String>[];
      for (final cat in categoriesData) {
        final id = cat['category_id']?.toString() ?? '';
        final name = cat['category_name']?.toString() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          categoryMap[id] = name;
          categoryNames.add(name);
        }
      }

      // Convert streams to IptvChannel
      final channels = <IptvChannel>[];
      for (final stream in streamsData) {
        final streamId = stream['stream_id']?.toString() ?? '';
        final name = stream['name']?.toString() ?? '';
        if (streamId.isEmpty || name.isEmpty) continue;

        final categoryId = stream['category_id']?.toString() ?? '';
        final group = categoryMap[categoryId];

        channels.add(IptvChannel(
          name: name,
          url: '$serverUrl/$username/$password/$streamId.m3u8',
          logoUrl: stream['stream_icon']?.toString(),
          group: group,
          duration: -1, // live
          contentType: 'live',
          attributes: {
            if (stream['epg_channel_id'] != null)
              'tvg-id': stream['epg_channel_id'].toString(),
            'stream_id': streamId,
          },
        ));
      }

      debugPrint('XtreamCodesService: Fetched ${channels.length} live channels, ${categoryNames.length} categories');

      final result = IptvParseResult(
        channels: channels,
        categories: categoryNames,
      );

      _cache[cacheKey] = _CachedResult(result: result, fetchedAt: DateTime.now());
      return result;
    } catch (e) {
      debugPrint('XtreamCodesService: Error fetching live streams: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch live streams: $e',
      );
    }
  }

  /// Fetch VOD items, converted to IptvChannel list + categories
  Future<IptvParseResult> fetchVodStreams(String serverUrl, String username, String password) async {
    final cacheKey = '$serverUrl:$username:vod';

    // Check cache
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint('XtreamCodesService: Using cached VOD streams for $serverUrl');
        return cached.result;
      }
    }

    try {
      final base = _baseUrl(serverUrl, username, password);

      // Fetch categories and streams in parallel
      final responses = await Future.wait([
        http.get(Uri.parse('$base&action=get_vod_categories'), headers: {'User-Agent': 'Debrify/1.0'}).timeout(const Duration(seconds: 30)),
        http.get(Uri.parse('$base&action=get_vod_streams'), headers: {'User-Agent': 'Debrify/1.0'}).timeout(const Duration(seconds: 60)),
      ]);

      if (responses[0].statusCode != 200 || responses[1].statusCode != 200) {
        final failedCode = responses[0].statusCode != 200
            ? responses[0].statusCode
            : responses[1].statusCode;
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch VOD streams: HTTP $failedCode',
        );
      }

      final categoriesData = json.decode(responses[0].body) as List<dynamic>;
      final streamsData = json.decode(responses[1].body) as List<dynamic>;

      // Build category ID -> name map
      final categoryMap = <String, String>{};
      final categoryNames = <String>[];
      for (final cat in categoriesData) {
        final id = cat['category_id']?.toString() ?? '';
        final name = cat['category_name']?.toString() ?? '';
        if (id.isNotEmpty && name.isNotEmpty) {
          categoryMap[id] = name;
          categoryNames.add(name);
        }
      }

      // Convert streams to IptvChannel
      final channels = <IptvChannel>[];
      for (final stream in streamsData) {
        final streamId = stream['stream_id']?.toString() ?? '';
        final name = stream['name']?.toString() ?? '';
        if (streamId.isEmpty || name.isEmpty) continue;

        final categoryId = stream['category_id']?.toString() ?? '';
        final group = categoryMap[categoryId];
        final extension = stream['container_extension']?.toString() ?? 'mp4';

        channels.add(IptvChannel(
          name: name,
          url: '$serverUrl/movie/$username/$password/$streamId.$extension',
          logoUrl: stream['stream_icon']?.toString(),
          group: group,
          duration: null, // not live
          contentType: 'vod',
          attributes: {
            if (stream['rating'] != null)
              'rating': stream['rating'].toString(),
            'stream_id': streamId,
          },
        ));
      }

      debugPrint('XtreamCodesService: Fetched ${channels.length} VOD items, ${categoryNames.length} categories');

      final result = IptvParseResult(
        channels: channels,
        categories: categoryNames,
      );

      _cache[cacheKey] = _CachedResult(result: result, fetchedAt: DateTime.now());
      return result;
    } catch (e) {
      debugPrint('XtreamCodesService: Error fetching VOD streams: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch VOD streams: $e',
      );
    }
  }

  /// Clear cache for a specific server or all
  void clearCache([String? serverUrl]) {
    if (serverUrl != null) {
      _cache.removeWhere((key, _) => key.startsWith(serverUrl));
    } else {
      _cache.clear();
    }
  }
}

class _CachedResult {
  final IptvParseResult result;
  final DateTime fetchedAt;

  _CachedResult({required this.result, required this.fetchedAt});
}
