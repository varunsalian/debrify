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

  static const _headers = {'User-Agent': 'Debrify/1.0'};

  // Cache for parsed results (key -> result)
  final Map<String, _CachedResult> _cache = {};
  static const _cacheDuration = Duration(minutes: 30);

  // Parsed panel lists are large (tens of thousands of channels); keep only a
  // few resident — the TTL alone never frees memory for distinct keys.
  static const _maxCachedResults = 3;

  // Per-server probe result: true if the panel only serves the legacy
  // un-prefixed live URL form instead of the standard /live/ one.
  final Map<String, bool> _legacyLiveUrlCache = {};

  String _baseUrl(String serverUrl, String username, String password) {
    final user = Uri.encodeQueryComponent(username);
    final pass = Uri.encodeQueryComponent(password);
    return '$serverUrl/player_api.php?username=$user&password=$pass';
  }

  /// GET that reports failure as null instead of throwing, for requests whose
  /// results are optional.
  Future<http.Response?> _tryGet(String url, Duration timeout) async {
    try {
      return await http.get(Uri.parse(url), headers: _headers).timeout(timeout);
    } catch (e) {
      debugPrint('XtreamCodesService: Optional request failed ($url): $e');
      return null;
    }
  }

  // Stream lists from large providers can be tens of MB; decode those off the
  // UI isolate so the app doesn't freeze.
  static const _computeDecodeThreshold = 100 * 1024;

  /// Safely decode a JSON response body as a List, returning a user-friendly error
  /// if the server returns non-JSON or non-array data.
  Future<(List<dynamic>?, String?)> _decodeJsonList(String body, String label) async {
    dynamic decoded;
    try {
      decoded = body.length > _computeDecodeThreshold
          ? await compute(jsonDecode, body)
          : jsonDecode(body);
    } catch (_) {
      // Server returned non-JSON (e.g. plain-text error message)
      final preview = body.length > 200 ? body.substring(0, 200) : body;
      return (null, 'Server returned invalid response for $label: $preview');
    }

    if (decoded is List<dynamic>) {
      return (decoded, null);
    }

    // Some XC servers return a map with an error message instead of an array
    if (decoded is Map<String, dynamic>) {
      final errorMsg = decoded['error'] ?? decoded['message'];
      if (errorMsg != null) {
        return (null, 'Server error: $errorMsg');
      }
      return (null, 'Server returned unexpected format for $label');
    }

    return (null, 'Server returned unexpected format for $label');
  }

  /// Authenticate and return account info
  Future<XcAuthResult> authenticate(String serverUrl, String username, String password) async {
    try {
      final url = _baseUrl(serverUrl, username, password);
      debugPrint('XtreamCodesService: Authenticating with $serverUrl');

      final response = await http.get(
        Uri.parse(url),
        headers: _headers,
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
  Future<IptvParseResult> fetchLiveStreams(String serverUrl, String username, String password) {
    return _fetchStreams(serverUrl, username, password, contentType: 'live');
  }

  /// Fetch VOD items, converted to IptvChannel list + categories
  Future<IptvParseResult> fetchVodStreams(String serverUrl, String username, String password) {
    return _fetchStreams(serverUrl, username, password, contentType: 'vod');
  }

  /// Shared fetch pipeline for live and VOD content.
  Future<IptvParseResult> _fetchStreams(
    String serverUrl,
    String username,
    String password, {
    required String contentType,
  }) async {
    final isLive = contentType == 'live';
    final label = isLive ? 'live' : 'VOD';
    final cacheKey = '$serverUrl:$username:$contentType';

    // Check cache
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
        debugPrint('XtreamCodesService: Using cached $label streams for $serverUrl');
        return cached.result;
      }
    }

    try {
      final base = _baseUrl(serverUrl, username, password);
      final categoriesAction = isLive ? 'get_live_categories' : 'get_vod_categories';
      final streamsAction = isLive ? 'get_live_streams' : 'get_vod_streams';

      // Kick off both requests in parallel, but only the stream list is
      // required: a category failure (network or malformed body) must not
      // take down the whole fetch.
      final categoriesFuture =
          _tryGet('$base&action=$categoriesAction', const Duration(seconds: 30));
      final streamsResponse = await http
          .get(Uri.parse('$base&action=$streamsAction'), headers: _headers)
          .timeout(const Duration(seconds: 60));
      final categoriesResponse = await categoriesFuture;

      if (streamsResponse.statusCode != 200) {
        return IptvParseResult(
          channels: [],
          categories: [],
          error: 'Failed to fetch $label streams: HTTP ${streamsResponse.statusCode}',
        );
      }

      final (streamsData, streamsError) =
          await _decodeJsonList(streamsResponse.body, 'streams');
      if (streamsError != null) {
        return IptvParseResult(channels: [], categories: [], error: streamsError);
      }

      // Build category ID -> name map; degrade to ungrouped channels (with a
      // user-visible warning) when categories are unavailable.
      String? warning;
      final categoryMap = <String, String>{};
      final categoryNames = <String>[];
      if (categoriesResponse == null || categoriesResponse.statusCode != 200) {
        warning = 'Could not load $label categories — showing channels ungrouped';
      } else {
        final (categoriesData, catError) =
            await _decodeJsonList(categoriesResponse.body, 'categories');
        if (categoriesData == null) {
          warning = 'Could not load $label categories — showing channels ungrouped';
          debugPrint('XtreamCodesService: Ignoring $label categories: $catError');
        } else {
          for (final cat in categoriesData) {
            final id = cat['category_id']?.toString() ?? '';
            final name = cat['category_name']?.toString() ?? '';
            if (id.isNotEmpty && name.isNotEmpty) {
              categoryMap[id] = name;
              categoryNames.add(name);
            }
          }
        }
      }

      final encodedUser = Uri.encodeComponent(username);
      final encodedPass = Uri.encodeComponent(password);

      // Standard live URLs use the /live/ prefix, but some legacy panels only
      // route the un-prefixed form; probe once per server and remember.
      var useLegacyLiveUrls = false;
      if (isLive && streamsData!.isNotEmpty) {
        final sampleId = streamsData
            .map((s) => s['stream_id']?.toString() ?? '')
            .firstWhere((id) => id.isNotEmpty, orElse: () => '');
        if (sampleId.isNotEmpty) {
          useLegacyLiveUrls = await _shouldUseLegacyLiveUrls(
              serverUrl, encodedUser, encodedPass, sampleId);
        }
      }

      // Convert streams to IptvChannel
      final channels = <IptvChannel>[];
      for (final stream in streamsData!) {
        final streamId = stream['stream_id']?.toString() ?? '';
        final name = stream['name']?.toString() ?? '';
        if (streamId.isEmpty || name.isEmpty) continue;

        final categoryId = stream['category_id']?.toString() ?? '';
        final group = categoryMap[categoryId];

        if (isLive) {
          channels.add(IptvChannel(
            name: name,
            url: useLegacyLiveUrls
                ? '$serverUrl/$encodedUser/$encodedPass/$streamId.m3u8'
                : '$serverUrl/live/$encodedUser/$encodedPass/$streamId.m3u8',
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
        } else {
          final extension = stream['container_extension']?.toString() ?? 'mp4';
          channels.add(IptvChannel(
            name: name,
            url: '$serverUrl/movie/$encodedUser/$encodedPass/$streamId.$extension',
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
      }

      debugPrint('XtreamCodesService: Fetched ${channels.length} $label channels, ${categoryNames.length} categories');

      // Cache without the warning so it surfaces once per fresh fetch rather
      // than on every cached load for the next 30 minutes.
      _cache[cacheKey] = _CachedResult(
        result: IptvParseResult(channels: channels, categories: categoryNames),
        fetchedAt: DateTime.now(),
      );
      _evictCache();
      return IptvParseResult(
        channels: channels,
        categories: categoryNames,
        warning: warning,
      );
    } catch (e) {
      debugPrint('XtreamCodesService: Error fetching $label streams: $e');
      return IptvParseResult(
        channels: [],
        categories: [],
        error: 'Failed to fetch $label streams: $e',
      );
    }
  }

  /// Probe whether this panel serves the standard /live/ URL form; fall back
  /// to the legacy un-prefixed form when /live/ fails but the legacy form
  /// works.
  Future<bool> _shouldUseLegacyLiveUrls(
    String serverUrl,
    String encodedUser,
    String encodedPass,
    String sampleStreamId,
  ) async {
    final cacheKey = '$serverUrl:$encodedUser';
    final cached = _legacyLiveUrlCache[cacheKey];
    if (cached != null) return cached;

    final liveStatus = await _probeStatusCode(
        '$serverUrl/live/$encodedUser/$encodedPass/$sampleStreamId.m3u8');
    if (liveStatus == null) {
      // Network failure — keep the standard form, but don't cache an
      // undetermined verdict; the next fetch re-probes.
      return false;
    }

    var useLegacy = false;
    if (liveStatus < 200 || liveStatus >= 300) {
      final legacyStatus = await _probeStatusCode(
          '$serverUrl/$encodedUser/$encodedPass/$sampleStreamId.m3u8');
      useLegacy =
          legacyStatus != null && legacyStatus >= 200 && legacyStatus < 300;
    }

    _legacyLiveUrlCache[cacheKey] = useLegacy;
    return useLegacy;
  }

  /// Fetch only the status code of a URL without downloading the body: some
  /// panels answer stream URLs with the live stream itself, which a plain
  /// http.get would buffer without bound.
  Future<int?> _probeStatusCode(String url) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      request.headers.addAll(_headers);
      final response =
          await client.send(request).timeout(const Duration(seconds: 10));
      // Cancel the body stream immediately; only the status matters.
      await response.stream.listen((_) {}).cancel();
      return response.statusCode;
    } catch (e) {
      debugPrint('XtreamCodesService: Probe failed for $url: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Clear cache for a specific server or all
  void clearCache([String? serverUrl]) {
    if (serverUrl != null) {
      _cache.removeWhere((key, _) => key.startsWith(serverUrl));
      _legacyLiveUrlCache.removeWhere((key, _) => key.startsWith(serverUrl));
    } else {
      _cache.clear();
      _legacyLiveUrlCache.clear();
    }
  }

  /// Drop expired entries, then the oldest beyond the cap.
  void _evictCache() {
    final now = DateTime.now();
    _cache.removeWhere((_, c) => now.difference(c.fetchedAt) >= _cacheDuration);
    while (_cache.length > _maxCachedResults) {
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
}

class _CachedResult {
  final IptvParseResult result;
  final DateTime fetchedAt;

  _CachedResult({required this.result, required this.fetchedAt});
}
