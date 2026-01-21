import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

/// Sort options for Reddit listings
enum RedditSort { hot, new_, top, rising, relevance }

/// Time filter for top/controversial posts
enum RedditTimeFilter { hour, day, week, month, year, all }

/// Information about a Reddit video post
class RedditVideoPost {
  final String id;
  final String title;
  final String subreddit;
  final String author;
  final String? dashPlaylistUrl;
  final String? fallbackUrl;
  final String? redgifsUrl; // Redgifs page URL (needs async fetch for video)
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int? width;
  final int? height;
  final bool isNsfw;
  final String permalink;
  final int score;
  final int numComments;
  final DateTime createdUtc;

  const RedditVideoPost({
    required this.id,
    required this.title,
    required this.subreddit,
    required this.author,
    this.dashPlaylistUrl,
    this.fallbackUrl,
    this.redgifsUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.width,
    this.height,
    this.isNsfw = false,
    required this.permalink,
    required this.score,
    required this.numComments,
    required this.createdUtc,
  });

  /// Check if this is a Redgifs video (needs async fetch)
  bool get isRedgifs => redgifsUrl != null && redgifsUrl!.isNotEmpty;

  /// Get the best playable URL (DASH preferred, fallback to direct MP4)
  /// Note: For Redgifs posts, this returns null - use RedgifsService to fetch URL
  String? get playableUrl => dashPlaylistUrl ?? fallbackUrl;

  /// Check if this post has a playable video (including Redgifs)
  bool get hasVideo => (playableUrl != null && playableUrl!.isNotEmpty) || isRedgifs;

  /// Format score for display (e.g., 1.2k, 15.3k)
  String get formattedScore {
    if (score >= 1000000) {
      return '${(score / 1000000).toStringAsFixed(1)}M';
    } else if (score >= 1000) {
      return '${(score / 1000).toStringAsFixed(1)}k';
    }
    return score.toString();
  }
}

/// Result of a subreddit listing request
class RedditListingResult {
  final List<RedditVideoPost> posts;
  final String? after; // Pagination cursor
  final String? before;

  const RedditListingResult({
    required this.posts,
    this.after,
    this.before,
  });

  bool get hasMore => after != null && after!.isNotEmpty;
}

/// Service for interacting with Reddit to browse and play videos
class RedditService {
  static const String _userAgent = 'Debrify/1.0 (Flutter; Video Player)';
  static const String _baseUrl = 'https://www.reddit.com';
  static const String _oauthBaseUrl = 'https://oauth.reddit.com';

  // OAuth configuration
  static const String _clientId = 'YOUR_CLIENT_ID'; // TODO: Replace with actual client ID
  static const String _redirectUri = 'debrify://reddit/callback';
  static const String _scope = 'read';

  /// Get subreddit video posts with filters
  static Future<RedditListingResult> getSubredditVideos({
    required String subreddit,
    RedditSort sort = RedditSort.hot,
    RedditTimeFilter timeFilter = RedditTimeFilter.day,
    int limit = 100,
    String? after,
    bool allowNsfw = false,
  }) async {
    final sortStr = _sortToString(sort);
    final baseUrl = '$_baseUrl/r/$subreddit/$sortStr.json';

    final queryParams = <String, String>{
      'limit': limit.toString(),
      'raw_json': '1',
      if (allowNsfw) 'include_over_18': 'on',
    };

    if (after != null && after.isNotEmpty) {
      queryParams['after'] = after;
    }

    // Add time filter for top/controversial sorts
    if (sort == RedditSort.top) {
      queryParams['t'] = _timeFilterToString(timeFilter);
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    debugPrint('RedditService: Fetching $uri');

    final response = await http.get(
      uri,
      headers: {'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      debugPrint('RedditService: HTTP ${response.statusCode}');
      throw Exception('Failed to fetch subreddit (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    return _parseListingData(data);
  }

  /// Search for videos in a subreddit
  static Future<RedditListingResult> searchSubredditVideos({
    required String subreddit,
    required String query,
    RedditSort sort = RedditSort.hot,
    RedditTimeFilter timeFilter = RedditTimeFilter.all,
    int limit = 100,
    String? after,
    bool allowNsfw = false,
  }) async {
    final baseUrl = '$_baseUrl/r/$subreddit/search.json';

    final queryParams = <String, String>{
      'q': query,
      'restrict_sr': 'on',
      'sort': _sortToString(sort),
      't': _timeFilterToString(timeFilter),
      'limit': limit.toString(),
      'raw_json': '1',
      'type': 'link',
      if (allowNsfw) 'include_over_18': 'on',
    };

    if (after != null && after.isNotEmpty) {
      queryParams['after'] = after;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    debugPrint('RedditService: Searching $uri');

    final response = await http.get(
      uri,
      headers: {'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      debugPrint('RedditService: HTTP ${response.statusCode}');
      throw Exception('Search failed (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    return _parseListingData(data);
  }

  /// Search for videos across all of Reddit (global search)
  static Future<RedditListingResult> searchAllVideos({
    required String query,
    RedditSort sort = RedditSort.relevance,
    RedditTimeFilter timeFilter = RedditTimeFilter.all,
    int limit = 100,
    String? after,
    bool allowNsfw = false,
  }) async {
    final baseUrl = '$_baseUrl/search.json';

    final queryParams = <String, String>{
      'q': query,
      'sort': _sortToString(sort),
      't': _timeFilterToString(timeFilter),
      'limit': limit.toString(),
      'raw_json': '1',
      'type': 'link',
      if (allowNsfw) 'include_over_18': 'on',
    };

    if (after != null && after.isNotEmpty) {
      queryParams['after'] = after;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    debugPrint('RedditService: Global search $uri');

    final response = await http.get(
      uri,
      headers: {'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      debugPrint('RedditService: HTTP ${response.statusCode}');
      throw Exception('Search failed (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    return _parseListingData(data);
  }

  /// Get video info from a single post URL
  static Future<RedditVideoPost?> getVideoFromPostUrl(String postUrl) async {
    final jsonUrl = _convertToJsonUrl(postUrl);
    debugPrint('RedditService: Fetching post $jsonUrl');

    final response = await http.get(
      Uri.parse(jsonUrl),
      headers: {'User-Agent': _userAgent},
    );

    if (response.statusCode != 200) {
      debugPrint('RedditService: HTTP ${response.statusCode}');
      throw Exception('Failed to fetch post (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);

    // Reddit returns an array with [post_data, comments_data]
    if (data is! List || data.isEmpty) {
      return null;
    }

    final postListing = data[0];
    if (postListing is! Map || postListing['data'] == null) {
      return null;
    }

    final children = postListing['data']['children'];
    if (children is! List || children.isEmpty) {
      return null;
    }

    final post = children[0]['data'];
    if (post is! Map) {
      return null;
    }

    return _parsePostToVideoPost(post);
  }

  /// Convert various Reddit URL formats to JSON API URL
  static String _convertToJsonUrl(String url) {
    var cleanUrl = url.trim();

    // Handle redd.it short URLs
    final reddItMatch = RegExp(r'redd\.it/([a-zA-Z0-9]+)').firstMatch(cleanUrl);
    if (reddItMatch != null) {
      final postId = reddItMatch.group(1);
      return '$_baseUrl/comments/$postId.json';
    }

    // Remove any query parameters and trailing slashes
    cleanUrl = cleanUrl.split('?').first;
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }

    // Normalize to www.reddit.com
    cleanUrl = cleanUrl
        .replaceAll('old.reddit.com', 'www.reddit.com')
        .replaceAll('new.reddit.com', 'www.reddit.com')
        .replaceAll('://reddit.com', '://www.reddit.com');

    // Add .json extension
    if (!cleanUrl.endsWith('.json')) {
      cleanUrl = '$cleanUrl.json';
    }

    return cleanUrl;
  }

  /// Parse Reddit listing response
  static RedditListingResult _parseListingData(dynamic data) {
    if (data is! Map || data['data'] == null) {
      return const RedditListingResult(posts: []);
    }

    final listingData = data['data'];
    final children = listingData['children'] as List?;
    final after = listingData['after']?.toString();
    final before = listingData['before']?.toString();

    if (children == null || children.isEmpty) {
      return RedditListingResult(posts: [], after: after, before: before);
    }

    final posts = <RedditVideoPost>[];
    for (final child in children) {
      if (child is! Map || child['data'] == null) continue;

      final postData = child['data'];
      final videoPost = _parsePostToVideoPost(postData);

      // Only include posts with videos
      if (videoPost != null && videoPost.hasVideo) {
        posts.add(videoPost);
      }
    }

    return RedditListingResult(posts: posts, after: after, before: before);
  }

  /// Parse a single post data to RedditVideoPost
  static RedditVideoPost? _parsePostToVideoPost(Map<dynamic, dynamic> post) {
    final id = post['id']?.toString() ?? '';
    final title = post['title']?.toString() ?? 'Untitled';
    final subreddit = post['subreddit']?.toString() ?? '';
    final author = post['author']?.toString() ?? '[deleted]';
    final isNsfw = post['over_18'] == true;
    final permalink = post['permalink']?.toString() ?? '';
    final score = (post['score'] as num?)?.toInt() ?? 0;
    final numComments = (post['num_comments'] as num?)?.toInt() ?? 0;
    final createdUtc = DateTime.fromMillisecondsSinceEpoch(
      ((post['created_utc'] as num?)?.toInt() ?? 0) * 1000,
    );

    // Get thumbnail (prefer preview images)
    String? thumbnailUrl;
    final preview = post['preview'];
    if (preview is Map && preview['images'] is List) {
      final images = preview['images'] as List;
      if (images.isNotEmpty) {
        final firstImage = images[0];
        if (firstImage is Map) {
          // Try to get a medium resolution preview
          final resolutions = firstImage['resolutions'] as List?;
          if (resolutions != null && resolutions.length >= 2) {
            thumbnailUrl = _decodeHtmlEntities(
              resolutions[resolutions.length ~/ 2]['url']?.toString(),
            );
          }
          thumbnailUrl ??= _decodeHtmlEntities(
            firstImage['source']?['url']?.toString(),
          );
        }
      }
    }
    thumbnailUrl ??= post['thumbnail']?.toString();
    if (thumbnailUrl == 'self' || thumbnailUrl == 'default' || thumbnailUrl == 'nsfw') {
      thumbnailUrl = null;
    }

    // Extract video information
    String? dashUrl;
    String? fallbackUrl;
    int? duration;
    int? width;
    int? height;

    // Check for Reddit-hosted video (v.redd.it)
    final media = post['media'];
    if (media is Map && media['reddit_video'] != null) {
      final redditVideo = media['reddit_video'];
      dashUrl = redditVideo['dash_url']?.toString();
      fallbackUrl = redditVideo['fallback_url']?.toString();
      duration = (redditVideo['duration'] as num?)?.toInt();
      width = (redditVideo['width'] as num?)?.toInt();
      height = (redditVideo['height'] as num?)?.toInt();
    }

    // Check for crosspost with video
    if (dashUrl == null) {
      final crosspostParentList = post['crosspost_parent_list'];
      if (crosspostParentList is List && crosspostParentList.isNotEmpty) {
        final parentMedia = crosspostParentList[0]['media'];
        if (parentMedia is Map && parentMedia['reddit_video'] != null) {
          final redditVideo = parentMedia['reddit_video'];
          dashUrl = redditVideo['dash_url']?.toString();
          fallbackUrl = redditVideo['fallback_url']?.toString();
          duration = (redditVideo['duration'] as num?)?.toInt();
          width = (redditVideo['width'] as num?)?.toInt();
          height = (redditVideo['height'] as num?)?.toInt();
        }
      }
    }

    // Check secure_media as fallback
    if (dashUrl == null) {
      final secureMedia = post['secure_media'];
      if (secureMedia is Map && secureMedia['reddit_video'] != null) {
        final redditVideo = secureMedia['reddit_video'];
        dashUrl = redditVideo['dash_url']?.toString();
        fallbackUrl = redditVideo['fallback_url']?.toString();
        duration = (redditVideo['duration'] as num?)?.toInt();
        width = (redditVideo['width'] as num?)?.toInt();
        height = (redditVideo['height'] as num?)?.toInt();
      }
    }

    // Check for Redgifs URL
    String? redgifsUrl;
    if (dashUrl == null && fallbackUrl == null) {
      final postUrl = post['url']?.toString() ?? '';
      final domain = post['domain']?.toString() ?? '';
      if (domain.contains('redgifs.com') || postUrl.contains('redgifs.com')) {
        redgifsUrl = postUrl;
      }
    }

    // Skip posts without any video source
    if (dashUrl == null && fallbackUrl == null && redgifsUrl == null) {
      return null;
    }

    return RedditVideoPost(
      id: id,
      title: title,
      subreddit: subreddit,
      author: author,
      dashPlaylistUrl: dashUrl,
      fallbackUrl: fallbackUrl,
      redgifsUrl: redgifsUrl,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: duration,
      width: width,
      height: height,
      isNsfw: isNsfw,
      permalink: permalink,
      score: score,
      numComments: numComments,
      createdUtc: createdUtc,
    );
  }

  /// Decode HTML entities in URLs (Reddit encodes & as &amp;)
  static String? _decodeHtmlEntities(String? url) {
    if (url == null) return null;
    return url.replaceAll('&amp;', '&');
  }

  /// Convert sort enum to string
  static String _sortToString(RedditSort sort) {
    switch (sort) {
      case RedditSort.hot:
        return 'hot';
      case RedditSort.new_:
        return 'new';
      case RedditSort.top:
        return 'top';
      case RedditSort.rising:
        return 'rising';
      case RedditSort.relevance:
        return 'relevance';
    }
  }

  /// Convert time filter enum to string
  static String _timeFilterToString(RedditTimeFilter filter) {
    switch (filter) {
      case RedditTimeFilter.hour:
        return 'hour';
      case RedditTimeFilter.day:
        return 'day';
      case RedditTimeFilter.week:
        return 'week';
      case RedditTimeFilter.month:
        return 'month';
      case RedditTimeFilter.year:
        return 'year';
      case RedditTimeFilter.all:
        return 'all';
    }
  }

  /// Get display name for sort
  static String getSortDisplayName(RedditSort sort) {
    switch (sort) {
      case RedditSort.hot:
        return 'Hot';
      case RedditSort.new_:
        return 'New';
      case RedditSort.top:
        return 'Top';
      case RedditSort.rising:
        return 'Rising';
      case RedditSort.relevance:
        return 'Relevance';
    }
  }

  /// Get display name for time filter
  static String getTimeFilterDisplayName(RedditTimeFilter filter) {
    switch (filter) {
      case RedditTimeFilter.hour:
        return 'Past Hour';
      case RedditTimeFilter.day:
        return 'Today';
      case RedditTimeFilter.week:
        return 'This Week';
      case RedditTimeFilter.month:
        return 'This Month';
      case RedditTimeFilter.year:
        return 'This Year';
      case RedditTimeFilter.all:
        return 'All Time';
    }
  }

  /// Validate subreddit name
  static bool isValidSubredditName(String name) {
    // Subreddit names: 3-21 chars, alphanumeric + underscores
    final pattern = RegExp(r'^[a-zA-Z0-9_]{2,21}$');
    return pattern.hasMatch(name);
  }

  /// Validate if a URL is a Reddit post URL
  static bool isValidRedditUrl(String url) {
    final patterns = [
      RegExp(r'reddit\.com/r/[^/]+/comments/[a-zA-Z0-9]+'),
      RegExp(r'redd\.it/[a-zA-Z0-9]+'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  // ============== OAuth Support (for future use) ==============

  /// Generate OAuth authorization URL
  static String getOAuthUrl({required String state}) {
    final params = {
      'client_id': _clientId,
      'response_type': 'code',
      'state': state,
      'redirect_uri': _redirectUri,
      'duration': 'permanent',
      'scope': _scope,
    };
    return Uri.https('www.reddit.com', '/api/v1/authorize.compact', params).toString();
  }

  /// Check if user is authenticated
  static Future<bool> isAuthenticated() async {
    final token = await StorageService.getRedditAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Clear authentication
  static Future<void> logout() async {
    await StorageService.clearRedditAuth();
  }
}
