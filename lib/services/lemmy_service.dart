import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'youtube_service.dart';

/// Sort options for Lemmy listings
enum LemmySort { active, hot, new_, top, mostComments }

/// Time filter, applied to the "top" sort (maps to TopDay, TopWeek, ...)
enum LemmyTimeFilter { hour, day, week, month, year, all }

/// Information about a Lemmy video post.
///
/// Mirrors [RedditVideoPost] so the UI layer behaves identically. Lemmy posts
/// link out to external hosts (redgifs, imgur, streamable, direct mp4) just
/// like Reddit, and additionally expose [embedVideoUrl] for embedded players.
class LemmyVideoPost {
  final String id;
  final String title;

  /// Community handle, e.g. "videos@lemmy.world" (or just "videos" if local).
  final String community;
  final String author;

  /// Direct/embed video URL (mp4, m3u8, peertube embed, etc.).
  final String? directVideoUrl;

  /// Redgifs page URL — needs async resolution before playback.
  final String? redgifsUrl;

  /// YouTube video id — resolved to a stream via [YoutubeService] at playback.
  final String? youtubeId;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final bool isNsfw;

  /// Canonical post URL (ap_id) for reference.
  final String permalink;
  final int score;
  final int numComments;
  final DateTime createdUtc;

  const LemmyVideoPost({
    required this.id,
    required this.title,
    required this.community,
    required this.author,
    this.directVideoUrl,
    this.redgifsUrl,
    this.youtubeId,
    this.thumbnailUrl,
    this.durationSeconds,
    this.isNsfw = false,
    required this.permalink,
    required this.score,
    required this.numComments,
    required this.createdUtc,
  });

  /// Check if this is a Redgifs video (needs async fetch)
  bool get isRedgifs => redgifsUrl != null && redgifsUrl!.isNotEmpty;

  /// Check if this is a YouTube video (resolved on-device via youtube_explode)
  bool get isYouTube => youtubeId != null && youtubeId!.isNotEmpty;

  String? get playableUrl => directVideoUrl;

  bool get hasVideo =>
      (playableUrl != null && playableUrl!.isNotEmpty) || isRedgifs || isYouTube;

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

/// Result of a Lemmy listing request.
class LemmyListingResult {
  final List<LemmyVideoPost> posts;

  /// Next page number to fetch (as a string cursor), or null when exhausted.
  final String? after;

  const LemmyListingResult({
    required this.posts,
    this.after,
  });

  bool get hasMore => after != null && after!.isNotEmpty;
}

/// Service for browsing and playing videos from Lemmy (the federated
/// Reddit-style link aggregator).
///
/// Uses Lemmy's public REST API (v3), which requires no authentication for
/// read operations. Queries a single instance (default lemmy.world), which
/// federates content from across the network when [_listingType] is "All".
class LemmyService {
  static const String _userAgent = 'Debrify/1.0 (Flutter; Video Player)';
  static const String defaultInstance = 'https://lemmy.world';

  /// Federated listing — returns posts from the whole network the instance
  /// knows about, not just locally-created ones.
  static const String _listingType = 'All';

  static const int _minVideosPerFetch = 30;
  static const int _maxPagesPerFetch = 8;
  static const int _pageSize = 50;
  static const Duration _pageDelay = Duration(milliseconds: 300);
  static const Duration _httpTimeout = Duration(seconds: 15);
  static const Duration _rateLimitBackoff = Duration(seconds: 5);

  static const List<String> _videoExtensions = ['.mp4', '.webm', '.mov', '.m4v', '.m3u8'];
  static const List<String> _videoHostDomains = ['streamable.com', 'gfycat.com'];

  /// Instance base URL, overridable via settings. Defaults to lemmy.world.
  static String instanceBaseUrl = defaultInstance;

  static final _rng = Random();

  static Future<http.Response> _get(Uri uri) async {
    final response = await http
        .get(uri, headers: {'User-Agent': _userAgent})
        .timeout(_httpTimeout);

    if (response.statusCode == 429) {
      debugPrint('LemmyService: Rate limited, backing off ${_rateLimitBackoff.inSeconds}s');
      await Future.delayed(_rateLimitBackoff);
      return http
          .get(uri, headers: {'User-Agent': _userAgent})
          .timeout(_httpTimeout);
    }

    return response;
  }

  // ============== Public, auto-paginating entry points ==============

  /// Fetch videos from a community (or the whole federated feed when
  /// [community] is null), auto-paginating until we have enough results.
  static Future<LemmyListingResult> fetchCommunityVideos({
    String? community,
    LemmySort sort = LemmySort.hot,
    LemmyTimeFilter timeFilter = LemmyTimeFilter.day,
    bool allowNsfw = false,
    String? after,
    int minVideos = _minVideosPerFetch,
  }) async {
    return _fetchMultiplePages(
      minVideos: minVideos,
      initialAfter: after,
      fetcher: (page) => getCommunityVideos(
        community: community,
        sort: sort,
        timeFilter: timeFilter,
        page: page,
        allowNsfw: allowNsfw,
      ),
    );
  }

  /// Search for videos (optionally restricted to [community]), auto-paginating.
  static Future<LemmyListingResult> fetchSearchVideos({
    required String query,
    String? community,
    LemmySort sort = LemmySort.top,
    LemmyTimeFilter timeFilter = LemmyTimeFilter.all,
    bool allowNsfw = false,
    String? after,
    int minVideos = _minVideosPerFetch,
  }) async {
    return _fetchMultiplePages(
      minVideos: minVideos,
      initialAfter: after,
      fetcher: (page) => searchVideos(
        query: query,
        community: community,
        sort: sort,
        timeFilter: timeFilter,
        page: page,
        allowNsfw: allowNsfw,
      ),
    );
  }

  /// Generic multi-page fetcher that aggregates video posts across pages.
  static Future<LemmyListingResult> _fetchMultiplePages({
    required int minVideos,
    required Future<LemmyListingResult> Function(int page) fetcher,
    String? initialAfter,
  }) async {
    final allPosts = <LemmyVideoPost>[];
    final seenIds = <String>{};
    int page = int.tryParse(initialAfter ?? '') ?? 1;
    int pagesLoaded = 0;

    while (pagesLoaded < _maxPagesPerFetch) {
      if (pagesLoaded > 0) {
        await Future.delayed(_pageDelay);
      }

      LemmyListingResult result;
      try {
        result = await fetcher(page);
      } catch (e) {
        if (allPosts.isEmpty) rethrow;
        debugPrint('LemmyService: Page $page failed ($e), '
            'returning ${allPosts.length} videos collected so far');
        break;
      }

      for (final post in result.posts) {
        if (seenIds.add(post.id)) {
          allPosts.add(post);
        }
      }
      pagesLoaded++;
      final nextPage = page + 1;
      page = nextPage;

      debugPrint(
        'LemmyService: Page $pagesLoaded — got ${result.posts.length} videos '
        '(total ${allPosts.length}/$minVideos)',
      );

      if (allPosts.length >= minVideos || !result.hasMore) {
        return LemmyListingResult(
          posts: allPosts,
          after: result.hasMore ? nextPage.toString() : null,
        );
      }
    }

    return LemmyListingResult(posts: allPosts, after: page.toString());
  }

  // ============== Single-page API calls ==============

  /// Fetch a single page of community (or federated) video posts.
  static Future<LemmyListingResult> getCommunityVideos({
    String? community,
    LemmySort sort = LemmySort.hot,
    LemmyTimeFilter timeFilter = LemmyTimeFilter.day,
    int page = 1,
    bool allowNsfw = false,
  }) async {
    final queryParams = <String, String>{
      'type_': _listingType,
      'sort': _sortToApi(sort, timeFilter),
      'limit': _pageSize.toString(),
      'page': page.toString(),
    };

    final normalized = _normalizeCommunity(community);
    if (normalized != null) {
      queryParams['community_name'] = normalized;
    }

    final uri = Uri.parse('${_apiBase()}/post/list')
        .replace(queryParameters: queryParams);
    debugPrint('LemmyService: Fetching $uri');

    final response = await _get(uri);
    if (response.statusCode != 200) {
      debugPrint('LemmyService: HTTP ${response.statusCode}');
      throw Exception('Failed to fetch community (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    return _parsePostViews(data, allowNsfw: allowNsfw);
  }

  /// Search for video posts, optionally restricted to [community].
  static Future<LemmyListingResult> searchVideos({
    required String query,
    String? community,
    LemmySort sort = LemmySort.top,
    LemmyTimeFilter timeFilter = LemmyTimeFilter.all,
    int page = 1,
    bool allowNsfw = false,
  }) async {
    final queryParams = <String, String>{
      'q': query,
      'type_': 'Posts',
      'listing_type': _listingType,
      'sort': _sortToApi(sort, timeFilter),
      'limit': _pageSize.toString(),
      'page': page.toString(),
    };

    final normalized = _normalizeCommunity(community);
    if (normalized != null) {
      queryParams['community_name'] = normalized;
    }

    final uri = Uri.parse('${_apiBase()}/search')
        .replace(queryParameters: queryParams);
    debugPrint('LemmyService: Searching $uri');

    final response = await _get(uri);
    if (response.statusCode != 200) {
      debugPrint('LemmyService: HTTP ${response.statusCode}');
      throw Exception('Search failed (HTTP ${response.statusCode})');
    }

    final dynamic data = json.decode(response.body);
    return _parsePostViews(data, allowNsfw: allowNsfw);
  }

  /// Get a random video from a community by sampling a random page depth.
  static Future<LemmyVideoPost?> getRandomVideo({
    String? community,
    bool allowNsfw = false,
  }) async {
    final seenIds = <String>{};
    final candidates = <LemmyVideoPost>[];

    // Sample across a couple of different sort/depth strategies for variety.
    final strategies = <(LemmySort, LemmyTimeFilter, int)>[
      (LemmySort.new_, LemmyTimeFilter.all, 6),
      (LemmySort.top, LemmyTimeFilter.all, 4),
      (LemmySort.top, LemmyTimeFilter.year, 3),
      (LemmySort.hot, LemmyTimeFilter.all, 3),
    ];
    strategies.shuffle(_rng);

    for (int s = 0; s < 2 && s < strategies.length; s++) {
      try {
        final (sort, time, maxPage) = strategies[s];
        final page = 1 + _rng.nextInt(maxPage);

        if (s > 0) await Future.delayed(_pageDelay);
        final result = await getCommunityVideos(
          community: community,
          sort: sort,
          timeFilter: time,
          page: page,
          allowNsfw: allowNsfw,
        );

        debugPrint(
          'LemmyService: Random strategy ${sort.name}/${time.name} page $page '
          'got ${result.posts.length} videos',
        );

        for (final post in result.posts) {
          if (seenIds.add(post.id)) candidates.add(post);
        }
      } catch (e) {
        debugPrint('LemmyService: Random strategy $s failed: $e');
      }
    }

    if (candidates.isEmpty) return null;
    return candidates[_rng.nextInt(candidates.length)];
  }

  // ============== Parsing ==============

  /// Parse a Lemmy response containing a list of PostView objects.
  /// Works for both /post/list (`posts`) and /search (`posts`) responses.
  static LemmyListingResult _parsePostViews(dynamic data, {required bool allowNsfw}) {
    if (data is! Map || data['posts'] is! List) {
      return const LemmyListingResult(posts: []);
    }

    final rawPosts = data['posts'] as List;
    final posts = <LemmyVideoPost>[];

    for (final view in rawPosts) {
      if (view is! Map) continue;
      final videoPost = _parsePostView(view, allowNsfw: allowNsfw);
      if (videoPost != null && videoPost.hasVideo) {
        posts.add(videoPost);
      }
    }

    // If the page came back full, assume there is more to fetch.
    final hasMore = rawPosts.length >= _pageSize;
    return LemmyListingResult(posts: posts, after: hasMore ? 'more' : null);
  }

  /// Parse a single Lemmy PostView into a [LemmyVideoPost].
  static LemmyVideoPost? _parsePostView(Map<dynamic, dynamic> view, {required bool allowNsfw}) {
    final post = view['post'];
    if (post is! Map) return null;

    final isNsfw = post['nsfw'] == true;
    if (isNsfw && !allowNsfw) return null;

    final id = post['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final title = post['name']?.toString() ?? 'Untitled';
    final permalink = post['ap_id']?.toString() ?? '';

    final creator = view['creator'];
    final author = (creator is Map ? creator['name']?.toString() : null) ?? '[deleted]';

    final communityView = view['community'];
    final community = _communityHandle(communityView);

    final counts = view['counts'];
    final score = (counts is Map ? (counts['score'] as num?)?.toInt() : null) ?? 0;
    final numComments =
        (counts is Map ? (counts['comments'] as num?)?.toInt() : null) ?? 0;

    DateTime createdUtc;
    try {
      createdUtc = DateTime.parse(post['published']?.toString() ?? '').toUtc();
    } catch (_) {
      createdUtc = DateTime.fromMillisecondsSinceEpoch(0);
    }

    String? thumbnailUrl = post['thumbnail_url']?.toString();

    // Video extraction: prefer Lemmy's resolved embed, then inspect the link.
    String? directVideoUrl;
    String? redgifsUrl;
    String? youtubeId;

    final embed = post['embed_video_url']?.toString();
    if (embed != null && embed.isNotEmpty) {
      directVideoUrl = embed;
    }

    final url = post['url']?.toString() ?? '';
    if (url.isNotEmpty) {
      final lowerUrl = url.toLowerCase();
      if (url.contains('redgifs.com')) {
        redgifsUrl = url;
      } else if (YoutubeService.isYouTubeUrl(url)) {
        youtubeId = YoutubeService.extractYouTubeId(url);
      } else if (lowerUrl.contains('imgur.com') && lowerUrl.endsWith('.gifv')) {
        directVideoUrl ??= url.replaceAll('.gifv', '.mp4');
      } else if (_videoExtensions.any((ext) => lowerUrl.split('?').first.endsWith(ext))) {
        directVideoUrl ??= url;
      } else if (_videoHostDomains.any((d) => lowerUrl.contains(d))) {
        directVideoUrl ??= url;
      }
    }

    if (directVideoUrl == null && redgifsUrl == null && youtubeId == null) {
      return null;
    }

    // Lemmy often has no thumbnail for YouTube links — derive one from the id.
    if ((thumbnailUrl == null || thumbnailUrl.isEmpty) && youtubeId != null) {
      thumbnailUrl = YoutubeService.thumbnailForId(youtubeId);
    }

    return LemmyVideoPost(
      id: id,
      title: title,
      community: community,
      author: author,
      directVideoUrl: directVideoUrl,
      redgifsUrl: redgifsUrl,
      youtubeId: youtubeId,
      thumbnailUrl: thumbnailUrl,
      isNsfw: isNsfw,
      permalink: permalink,
      score: score,
      numComments: numComments,
      createdUtc: createdUtc,
    );
  }

  /// Build a "name@instance" handle from a community object.
  static String _communityHandle(dynamic community) {
    if (community is! Map) return '';
    final name = community['name']?.toString() ?? '';
    final actorId = community['actor_id']?.toString();
    if (actorId != null && actorId.isNotEmpty) {
      final host = Uri.tryParse(actorId)?.host;
      if (host != null && host.isNotEmpty) {
        return '$name@$host';
      }
    }
    return name;
  }

  // ============== Helpers ==============

  static String _apiBase() {
    var base = instanceBaseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (!base.startsWith('http')) base = 'https://$base';
    return '$base/api/v3';
  }

  /// Normalize a community handle for the API. Returns null for the "all" feed.
  static String? _normalizeCommunity(String? community) {
    if (community == null) return null;
    final trimmed = community.trim();
    if (trimmed.isEmpty) return null;
    return trimmed.startsWith('!') ? trimmed.substring(1) : trimmed;
  }

  /// Map our (sort, timeFilter) pair to Lemmy's single `sort` parameter.
  static String _sortToApi(LemmySort sort, LemmyTimeFilter timeFilter) {
    switch (sort) {
      case LemmySort.active:
        return 'Active';
      case LemmySort.hot:
        return 'Hot';
      case LemmySort.new_:
        return 'New';
      case LemmySort.mostComments:
        return 'MostComments';
      case LemmySort.top:
        switch (timeFilter) {
          case LemmyTimeFilter.hour:
            return 'TopHour';
          case LemmyTimeFilter.day:
            return 'TopDay';
          case LemmyTimeFilter.week:
            return 'TopWeek';
          case LemmyTimeFilter.month:
            return 'TopMonth';
          case LemmyTimeFilter.year:
            return 'TopYear';
          case LemmyTimeFilter.all:
            return 'TopAll';
        }
    }
  }

  /// Display name for a sort option.
  static String getSortDisplayName(LemmySort sort) {
    switch (sort) {
      case LemmySort.active:
        return 'Active';
      case LemmySort.hot:
        return 'Hot';
      case LemmySort.new_:
        return 'New';
      case LemmySort.top:
        return 'Top';
      case LemmySort.mostComments:
        return 'Most Comments';
    }
  }

  /// Display name for a time filter.
  static String getTimeFilterDisplayName(LemmyTimeFilter filter) {
    switch (filter) {
      case LemmyTimeFilter.hour:
        return 'Past Hour';
      case LemmyTimeFilter.day:
        return 'Today';
      case LemmyTimeFilter.week:
        return 'This Week';
      case LemmyTimeFilter.month:
        return 'This Month';
      case LemmyTimeFilter.year:
        return 'This Year';
      case LemmyTimeFilter.all:
        return 'All Time';
    }
  }

  /// Validate a community handle like "videos" or "videos@lemmy.world".
  static bool isValidCommunityName(String name) {
    final pattern = RegExp(r'^[a-zA-Z0-9_]{2,}(@[a-zA-Z0-9.\-]+)?$');
    return pattern.hasMatch(name.startsWith('!') ? name.substring(1) : name);
  }
}
