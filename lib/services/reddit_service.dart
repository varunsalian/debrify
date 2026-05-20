import 'dart:convert';
import 'dart:math';
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
  final String? redgifsUrl;
  final String? directVideoUrl;
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
    this.directVideoUrl,
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

  String? get playableUrl => dashPlaylistUrl ?? fallbackUrl ?? directVideoUrl;

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

  static const int _minVideosPerFetch = 30;
  static const int _maxPagesPerFetch = 8;
  static const Duration _pageDelay = Duration(milliseconds: 350);
  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _rateLimitBackoff = Duration(seconds: 5);

  static const List<String> _videoExtensions = [
    '.mp4', '.webm', '.mov', '.m4v',
  ];
  static const List<String> _videoHostDomains = [
    'streamable.com',
    'gfycat.com',
  ];

  static Future<http.Response> _get(Uri uri) async {
    final response = await http.get(
      uri,
      headers: {'User-Agent': _userAgent},
    ).timeout(_httpTimeout);

    if (response.statusCode == 429) {
      debugPrint('RedditService: Rate limited, backing off ${_rateLimitBackoff.inSeconds}s');
      await Future.delayed(_rateLimitBackoff);
      return http.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(_httpTimeout);
    }

    return response;
  }

  /// Fetch videos from a subreddit, auto-paginating until we have enough results.
  static Future<RedditListingResult> fetchSubredditVideos({
    required String subreddit,
    RedditSort sort = RedditSort.hot,
    RedditTimeFilter timeFilter = RedditTimeFilter.day,
    bool allowNsfw = false,
    String? after,
    int minVideos = _minVideosPerFetch,
  }) async {
    return _fetchMultiplePages(
      minVideos: minVideos,
      initialAfter: after,
      fetcher: (cursor) => getSubredditVideos(
        subreddit: subreddit,
        sort: sort,
        timeFilter: timeFilter,
        after: cursor,
        allowNsfw: allowNsfw,
      ),
    );
  }

  /// Search for videos in a subreddit, auto-paginating until we have enough results.
  static Future<RedditListingResult> fetchSubredditSearchVideos({
    required String subreddit,
    required String query,
    RedditSort sort = RedditSort.hot,
    RedditTimeFilter timeFilter = RedditTimeFilter.all,
    bool allowNsfw = false,
    String? after,
    int minVideos = _minVideosPerFetch,
  }) async {
    return _fetchMultiplePages(
      minVideos: minVideos,
      initialAfter: after,
      fetcher: (cursor) => searchSubredditVideos(
        subreddit: subreddit,
        query: query,
        sort: sort,
        timeFilter: timeFilter,
        after: cursor,
        allowNsfw: allowNsfw,
      ),
    );
  }

  /// Search for videos across all of Reddit, auto-paginating until we have enough results.
  static Future<RedditListingResult> fetchGlobalSearchVideos({
    required String query,
    RedditSort sort = RedditSort.relevance,
    RedditTimeFilter timeFilter = RedditTimeFilter.all,
    bool allowNsfw = false,
    String? after,
    int minVideos = _minVideosPerFetch,
  }) async {
    return _fetchMultiplePages(
      minVideos: minVideos,
      initialAfter: after,
      fetcher: (cursor) => searchAllVideos(
        query: query,
        sort: sort,
        timeFilter: timeFilter,
        after: cursor,
        allowNsfw: allowNsfw,
      ),
    );
  }

  /// Generic multi-page fetcher that aggregates video posts across pages.
  static Future<RedditListingResult> _fetchMultiplePages({
    required int minVideos,
    required Future<RedditListingResult> Function(String? cursor) fetcher,
    String? initialAfter,
  }) async {
    final allPosts = <RedditVideoPost>[];
    final seenIds = <String>{};
    String? cursor = initialAfter;
    int pagesLoaded = 0;

    while (pagesLoaded < _maxPagesPerFetch) {
      if (pagesLoaded > 0) {
        await Future.delayed(_pageDelay);
      }

      RedditListingResult result;
      try {
        result = await fetcher(cursor);
      } catch (e) {
        if (allPosts.isEmpty) rethrow;
        debugPrint('RedditService: Page ${pagesLoaded + 1} failed ($e), '
            'returning ${allPosts.length} videos collected so far');
        break;
      }

      for (final post in result.posts) {
        if (seenIds.add(post.id)) {
          allPosts.add(post);
        }
      }
      cursor = result.after;
      pagesLoaded++;

      debugPrint(
        'RedditService: Page $pagesLoaded — got ${result.posts.length} videos '
        '(total ${allPosts.length}/$minVideos)',
      );

      if (allPosts.length >= minVideos || !result.hasMore) {
        return RedditListingResult(
          posts: allPosts,
          after: cursor,
          before: null,
        );
      }
    }

    return RedditListingResult(
      posts: allPosts,
      after: cursor,
      before: null,
    );
  }

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
      'include_over_18': 'on',
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

    final response = await _get(uri);

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
      'q': _buildVideoSearchQuery(query),
      'restrict_sr': 'on',
      'sort': _sortToString(sort),
      't': _timeFilterToString(timeFilter),
      'limit': limit.toString(),
      'raw_json': '1',
      'type': 'link',
      // Always include NSFW for subreddit search — Reddit's search silently
      // drops all results from NSFW subs without this flag, even with restrict_sr.
      'include_over_18': 'on',
    };

    if (after != null && after.isNotEmpty) {
      queryParams['after'] = after;
    }

    final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
    debugPrint('RedditService: Searching $uri');

    final response = await _get(uri);

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
      'q': _buildVideoSearchQuery(query),
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

    final response = await _get(uri);

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

    final response = await _get(Uri.parse(jsonUrl));

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

  static const int _randomMaxAttempts = 15;
  static final _rng = Random();

  /// Get a random video from a subreddit using Reddit's /random endpoint.
  /// Falls back to fetching diverse pages and picking randomly if /random
  /// doesn't yield a video after several attempts.
  static Future<RedditVideoPost?> getRandomVideo({
    required String subreddit,
    bool allowNsfw = false,
  }) async {
    // Phase 1: Try Reddit's /random endpoint for true randomness
    final seenIds = <String>{};
    int nonPostResponses = 0;
    for (int i = 0; i < _randomMaxAttempts; i++) {
      try {
        if (i > 0) await Future.delayed(_pageDelay);

        final uri = Uri.parse('$_baseUrl/r/$subreddit/random.json')
            .replace(queryParameters: {'raw_json': '1', 'include_over_18': 'on'});
        final response = await _get(uri);

        if (response.statusCode != 200) {
          nonPostResponses++;
          if (nonPostResponses >= 3) break;
          continue;
        }

        final dynamic data = json.decode(response.body);

        // /random returns [post_listing, comments_listing].
        // If the subreddit disables /random, Reddit returns a listing Map
        // instead of a List — detect this and bail to fallback early.
        if (data is! List || data.isEmpty) {
          nonPostResponses++;
          if (nonPostResponses >= 3) {
            debugPrint('RedditService: /random appears unsupported for r/$subreddit');
            break;
          }
          continue;
        }

        nonPostResponses = 0;

        final postListing = data[0];
        if (postListing is! Map || postListing['data'] == null) continue;

        final children = postListing['data']['children'];
        if (children is! List || children.isEmpty) continue;

        final postData = children[0]['data'];
        if (postData is! Map) continue;

        final id = postData['id']?.toString() ?? '';
        if (!seenIds.add(id)) continue;

        if (!allowNsfw && postData['over_18'] == true) continue;

        final post = _parsePostToVideoPost(postData);
        if (post != null && post.hasVideo) {
          debugPrint('RedditService: Random video found on attempt ${i + 1}');
          return post;
        }
      } catch (e) {
        debugPrint('RedditService: Random attempt ${i + 1} failed: $e');
        nonPostResponses++;
        if (nonPostResponses >= 3) break;
      }
    }

    // Phase 2: Fallback — sample from random depths across different sort views.
    // "new" is chronological, so random depth ≈ random time period.
    // "top" with different time filters covers different popularity strata.
    debugPrint('RedditService: /random exhausted, falling back to deep page sampling');
    final fallbackPosts = <RedditVideoPost>[];

    // (sort, timeFilter, maxPagesToSkip)
    final strategies = <(RedditSort, RedditTimeFilter, int)>[
      (RedditSort.new_, RedditTimeFilter.all, 8),
      (RedditSort.top, RedditTimeFilter.all, 5),
      (RedditSort.top, RedditTimeFilter.year, 3),
      (RedditSort.hot, RedditTimeFilter.all, 3),
      (RedditSort.top, RedditTimeFilter.month, 2),
    ];
    strategies.shuffle(_rng);

    for (int s = 0; s < 2 && s < strategies.length; s++) {
      try {
        final (sort, time, maxSkip) = strategies[s];
        final skipPages = _rng.nextInt(maxSkip + 1);

        // Skip phase: paginate with tiny limit to reach a random depth fast
        String? cursor;
        bool exhausted = false;
        for (int p = 0; p < skipPages; p++) {
          await Future.delayed(const Duration(milliseconds: 150));
          final skipResult = await getSubredditVideos(
            subreddit: subreddit,
            sort: sort,
            timeFilter: time,
            limit: 3,
            after: cursor,
            allowNsfw: allowNsfw,
          );
          cursor = skipResult.after;
          if (!skipResult.hasMore) {
            exhausted = true;
            break;
          }
        }

        // If we exhausted all content during skip, start over from the top
        if (exhausted) cursor = null;

        // Harvest phase: fetch a full page at the target depth
        await Future.delayed(_pageDelay);
        final result = await getSubredditVideos(
          subreddit: subreddit,
          sort: sort,
          timeFilter: time,
          limit: 100,
          after: cursor,
          allowNsfw: allowNsfw,
        );

        debugPrint(
          'RedditService: Fallback strategy ${sort.name}/${ time.name} '
          'skipped $skipPages pages, got ${result.posts.length} videos',
        );

        for (final post in result.posts) {
          if (seenIds.add(post.id)) {
            fallbackPosts.add(post);
          }
        }
      } catch (e) {
        debugPrint('RedditService: Fallback strategy $s failed: $e');
      }
    }

    if (fallbackPosts.isEmpty) return null;

    final pick = fallbackPosts[_rng.nextInt(fallbackPosts.length)];
    debugPrint('RedditService: Random fallback picked from ${fallbackPosts.length} videos');
    return pick;
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

    // Check for external video sources when no reddit-hosted video found
    String? redgifsUrl;
    String? directVideoUrl;
    if (dashUrl == null && fallbackUrl == null) {
      final postUrl = post['url']?.toString() ?? '';
      final domain = post['domain']?.toString() ?? '';
      final lowerUrl = postUrl.toLowerCase();

      if (domain.contains('redgifs.com') || postUrl.contains('redgifs.com')) {
        redgifsUrl = postUrl;
      } else if (lowerUrl.contains('imgur.com') && lowerUrl.endsWith('.gifv')) {
        directVideoUrl = postUrl.replaceAll('.gifv', '.mp4');
      } else if (_videoExtensions.any((ext) => lowerUrl.endsWith(ext))) {
        directVideoUrl = postUrl;
      } else if (_videoHostDomains.any((d) => domain.contains(d))) {
        directVideoUrl = postUrl;
      }
    }

    if (dashUrl == null && fallbackUrl == null && redgifsUrl == null && directVideoUrl == null) {
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
      directVideoUrl: directVideoUrl,
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

  static String _buildVideoSearchQuery(String query) {
    if (query.contains('is_video:') || query.contains('site:') || query.contains('url:')) {
      return query;
    }
    return '$query self:no';
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
