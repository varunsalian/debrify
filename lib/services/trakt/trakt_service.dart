import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage_service.dart';
import 'trakt_constants.dart';

/// Service for Trakt OAuth authentication and API calls.
class TraktService {
  static final TraktService _instance = TraktService._internal();
  factory TraktService() => _instance;
  TraktService._internal();

  static TraktService get instance => _instance;

  /// Common headers for all Trakt API requests.
  Map<String, String> _apiHeaders({String? accessToken}) => {
        'Content-Type': 'application/json',
        'trakt-api-version': kTraktApiVersion,
        'trakt-api-key': kTraktClientId,
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      };

  /// Check if the user is authenticated (has a non-expired access token).
  Future<bool> isAuthenticated() async {
    final token = await StorageService.getTraktAccessToken();
    if (token == null || token.isEmpty) return false;

    // Check if token is expired
    final expiryMs = await StorageService.getTraktTokenExpiry();
    if (expiryMs != null && DateTime.now().millisecondsSinceEpoch >= expiryMs) {
      // Try to refresh
      final refreshed = await refreshAccessToken();
      return refreshed;
    }

    return true;
  }

  /// Refresh the access token using the stored refresh token.
  Future<bool> refreshAccessToken() async {
    try {
      final refreshToken = await StorageService.getTraktRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await http.post(
        Uri.parse(kTraktTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh_token': refreshToken,
          'client_id': kTraktClientId,
          'client_secret': kTraktClientSecret,
          'grant_type': 'refresh_token',
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);
        return true;
      }

      debugPrint('Trakt: Token refresh failed (${response.statusCode})');
      return false;
    } catch (e) {
      debugPrint('Trakt: Token refresh error: $e');
      return false;
    }
  }

  /// Revoke the current token and clear stored auth data.
  Future<void> logout() async {
    try {
      final accessToken = await StorageService.getTraktAccessToken();
      if (accessToken != null) {
        await http.post(
          Uri.parse('$kTraktApiBaseUrl/oauth/revoke'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'token': accessToken,
            'client_id': kTraktClientId,
            'client_secret': kTraktClientSecret,
          }),
        );
      }
    } catch (e) {
      debugPrint('Trakt: Revoke token error: $e');
    }

    await StorageService.clearTraktAuth();
  }

  /// Get the stored username.
  Future<String?> getUsername() async {
    return StorageService.getTraktUsername();
  }

  /// Store tokens and expiry from a token response.
  Future<void> _storeTokens(Map<String, dynamic> data) async {
    await StorageService.setTraktAccessToken(data['access_token'] as String);
    await StorageService.setTraktRefreshToken(data['refresh_token'] as String);

    final expiresIn = data['expires_in'] as int?;
    if (expiresIn != null) {
      final expiryMs = DateTime.now()
          .add(Duration(seconds: expiresIn))
          .millisecondsSinceEpoch;
      await StorageService.setTraktTokenExpiry(expiryMs);
    }
  }

  // ============================================================================
  // Device Code Flow (for Android TV)
  // ============================================================================

  /// Request a device code for the device code OAuth flow.
  /// Returns the parsed JSON response on success, null on failure.
  Future<Map<String, dynamic>?> requestDeviceCode() async {
    try {
      final response = await http.post(
        Uri.parse(kTraktDeviceCodeUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': kTraktClientId}),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      debugPrint('Trakt: Device code request failed (${response.statusCode}): ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Trakt: Device code request error: $e');
      return null;
    }
  }

  /// Poll for a device token using the device code.
  /// Returns null on success (tokens stored), or an error string:
  /// "authorization_pending", "slow_down", "expired_token", "access_denied",
  /// "network_error" (transient — safe to retry), or "error" (fatal).
  Future<String?> pollDeviceToken(String deviceCode) async {
    try {
      final response = await http.post(
        Uri.parse(kTraktDeviceTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': deviceCode,
          'client_id': kTraktClientId,
          'client_secret': kTraktClientSecret,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);
        final accessToken = data['access_token'] as String;
        await _fetchAndStoreUsername(accessToken);
        return null; // Success
      }

      if (response.statusCode == 400) {
        if (response.body.isEmpty) return 'authorization_pending';
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['error'] as String? ?? 'error';
      }

      // Rate limited — treat as slow_down so polling backs off
      if (response.statusCode == 429) {
        debugPrint('Trakt: Device token poll rate limited (429)');
        return 'slow_down';
      }

      debugPrint('Trakt: Device token poll failed (${response.statusCode}): ${response.body}');
      return 'error';
    } catch (e) {
      // Network timeout, socket exception, etc. — transient, safe to retry
      debugPrint('Trakt: Device token poll network error: $e');
      return 'network_error';
    }
  }

  // ============================================================================
  // Scrobble Methods
  // ============================================================================

  /// Authenticated POST request with automatic token refresh on 401.
  Future<http.Response?> _authenticatedPost(
      String path, Map<String, dynamic> body) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http.post(
        Uri.parse('$kTraktApiBaseUrl$path'),
        headers: _apiHeaders(accessToken: accessToken),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 15));

      // If unauthorized, try refreshing the token once
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http.post(
          Uri.parse('$kTraktApiBaseUrl$path'),
          headers: _apiHeaders(accessToken: accessToken),
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (e) {
      debugPrint('Trakt: POST $path error: $e');
      return null;
    }
  }

  /// Scrobble: notify Trakt that playback has started.
  Future<bool> scrobbleStart(String imdbId, double progress,
      {int? season, int? episode}) async {
    return _scrobble('/scrobble/start', imdbId, progress,
        season: season, episode: episode);
  }

  /// Scrobble: notify Trakt that playback was paused.
  Future<bool> scrobblePause(String imdbId, double progress,
      {int? season, int? episode}) async {
    return _scrobble('/scrobble/pause', imdbId, progress,
        season: season, episode: episode);
  }

  /// Scrobble: notify Trakt that playback was stopped.
  Future<bool> scrobbleStop(String imdbId, double progress,
      {int? season, int? episode}) async {
    return _scrobble('/scrobble/stop', imdbId, progress,
        season: season, episode: episode);
  }

  Future<bool> _scrobble(String path, String imdbId, double progress,
      {int? season, int? episode}) async {
    // Treat 0 as null — Kotlin TV player sends 0 for movies instead of null
    if (season != null && season <= 0) season = null;
    if (episode != null && episode <= 0) episode = null;
    // Refuse to scrobble if only one of season/episode is set — would send
    // a movie body with a show IMDB ID, corrupting Trakt history.
    if ((season == null) != (episode == null)) {
      debugPrint(
          'Trakt: Skipping scrobble — incomplete episode data (season: $season, episode: $episode)');
      return false;
    }
    final Map<String, dynamic> body;
    if (season != null && episode != null) {
      body = {
        'show': {
          'ids': {'imdb': imdbId},
        },
        'episode': {
          'season': season,
          'number': episode,
        },
        'progress': progress,
      };
    } else {
      body = {
        'movie': {
          'ids': {'imdb': imdbId},
        },
        'progress': progress,
      };
    }
    final response = await _authenticatedPost(path, body);
    if (response == null) return false;
    if (response.statusCode >= 200 && response.statusCode < 300) {
      debugPrint('Trakt: Scrobble $path OK (progress: $progress)');
      return true;
    }
    debugPrint(
        'Trakt: Scrobble $path failed (${response.statusCode}): ${response.body}');
    return false;
  }

  // ============================================================================
  // Sync Action Methods (Watchlist, Collection, History, Ratings, Custom Lists)
  // ============================================================================

  /// Generic sync action helper for add/remove operations.
  /// [path] is the API path (e.g. '/sync/watchlist').
  /// [imdbId] is the IMDB ID (e.g. 'tt1234567').
  /// [type] is 'movie' or 'series' (mapped to 'movies'/'shows' API key).
  /// [extraItemFields] adds fields to the item object (e.g. {"rating": 8}).
  Future<bool> _syncAction(
    String path,
    String imdbId,
    String type, {
    Map<String, dynamic>? extraItemFields,
  }) async {
    final apiKey = type == 'series' ? 'shows' : 'movies';
    final item = <String, dynamic>{
      'ids': {'imdb': imdbId},
      if (extraItemFields != null) ...extraItemFields,
    };
    final body = {apiKey: [item]};
    final response = await _authenticatedPost(path, body);
    if (response == null) return false;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint(
          'Trakt: $path failed (${response.statusCode}): ${response.body}');
    }
    return ok;
  }

  Future<bool> addToWatchlist(String imdbId, String type) =>
      _syncAction('/sync/watchlist', imdbId, type);

  Future<bool> removeFromWatchlist(String imdbId, String type) =>
      _syncAction('/sync/watchlist/remove', imdbId, type);

  Future<bool> addToCollection(String imdbId, String type) =>
      _syncAction('/sync/collection', imdbId, type);

  Future<bool> removeFromCollection(String imdbId, String type) =>
      _syncAction('/sync/collection/remove', imdbId, type);

  Future<bool> addToHistory(String imdbId, String type) =>
      _syncAction('/sync/history', imdbId, type);

  Future<bool> removeFromHistory(String imdbId, String type) =>
      _syncAction('/sync/history/remove', imdbId, type);

  Future<bool> rateItem(String imdbId, String type, int rating) =>
      _syncAction('/sync/ratings', imdbId, type,
          extraItemFields: {'rating': rating});

  Future<bool> removeRating(String imdbId, String type) =>
      _syncAction('/sync/ratings/remove', imdbId, type);

  Future<bool> addToCustomList(
          String listId, String imdbId, String type) =>
      _syncAction('/users/me/lists/$listId/items', imdbId, type);

  Future<bool> removeFromCustomList(
          String listId, String imdbId, String type) =>
      _syncAction('/users/me/lists/$listId/items/remove', imdbId, type);

  /// Episode-level sync action helper.
  /// Body format: { "shows": [{ "ids": {"imdb": ...}, "seasons": [{ "number": N, "episodes": [{ "number": M, ...extraFields }] }] }] }
  Future<bool> _syncEpisodeAction(
    String path,
    String showImdbId,
    int season,
    int episode, {
    Map<String, dynamic>? extraEpisodeFields,
  }) async {
    final ep = <String, dynamic>{
      'number': episode,
      if (extraEpisodeFields != null) ...extraEpisodeFields,
    };
    final body = {
      'shows': [
        {
          'ids': {'imdb': showImdbId},
          'seasons': [
            {
              'number': season,
              'episodes': [ep],
            }
          ],
        }
      ],
    };
    final response = await _authenticatedPost(path, body);
    if (response == null) return false;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint(
          'Trakt: $path S${season}E$episode failed (${response.statusCode}): ${response.body}');
    }
    return ok;
  }

  Future<bool> markEpisodeWatched(
          String showImdbId, int season, int episode) =>
      _syncEpisodeAction('/sync/history', showImdbId, season, episode);

  Future<bool> markEpisodeUnwatched(
          String showImdbId, int season, int episode) =>
      _syncEpisodeAction('/sync/history/remove', showImdbId, season, episode);

  Future<bool> rateEpisode(
          String showImdbId, int season, int episode, int rating) =>
      _syncEpisodeAction('/sync/ratings', showImdbId, season, episode,
          extraEpisodeFields: {'rating': rating});

  // ============================================================================
  // List API Methods
  // ============================================================================

  /// Authenticated GET request with automatic token refresh on 401.
  Future<http.Response?> _authenticatedGet(String path) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http.get(
        Uri.parse('$kTraktApiBaseUrl$path'),
        headers: _apiHeaders(accessToken: accessToken),
      ).timeout(const Duration(seconds: 15));

      // If unauthorized, try refreshing the token once
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http.get(
          Uri.parse('$kTraktApiBaseUrl$path'),
          headers: _apiHeaders(accessToken: accessToken),
        ).timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (e) {
      debugPrint('Trakt: GET $path error: $e');
      return null;
    }
  }

  Future<http.Response?> _authenticatedDelete(String path) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http.delete(
        Uri.parse('$kTraktApiBaseUrl$path'),
        headers: _apiHeaders(accessToken: accessToken),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http.delete(
          Uri.parse('$kTraktApiBaseUrl$path'),
          headers: _apiHeaders(accessToken: accessToken),
        ).timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (e) {
      debugPrint('Trakt: DELETE $path error: $e');
      return null;
    }
  }

  /// Remove a playback entry by its ID.
  /// Returns true if successfully deleted (204 No Content).
  Future<bool> removePlaybackItem(int playbackId) async {
    final response = await _authenticatedDelete('/sync/playback/$playbackId');
    if (response == null || response.statusCode != 204) {
      debugPrint('Trakt: removePlaybackItem failed (${response?.statusCode})');
      return false;
    }
    return true;
  }

  /// Fetch a standard Trakt list (watchlist, collection, ratings, recommendations).
  /// [listType] is one of: watchlist, collection, ratings, recommendations.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchList(String listType, String contentType) async {
    final String path;
    if (listType == 'recommendations') {
      path = '/recommendations/$contentType?extended=full';
    } else if (listType == 'watched') {
      path = '/sync/watched/$contentType?extended=full';
    } else if (listType == 'history') {
      path = '/sync/history/$contentType?extended=full&limit=100';
    } else if (listType == 'trending' || listType == 'popular' || listType == 'anticipated') {
      path = '/$contentType/$listType?extended=full&limit=100';
    } else {
      path = '/sync/$listType/$contentType?extended=full';
    }

    final response = await _authenticatedGet(path);
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchList failed for $path (${response?.statusCode})');
      return [];
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchList parse error: $e');
      return [];
    }
  }

  /// Fetch the user's custom lists.
  Future<List<Map<String, dynamic>>> fetchCustomLists() async {
    final response = await _authenticatedGet('/users/me/lists');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchCustomLists failed (${response?.statusCode})');
      return [];
    }

    try {
      final list = jsonDecode(response.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Trakt: fetchCustomLists parse error: $e');
      return [];
    }
  }

  /// Fetch lists the authenticated user has liked on Trakt.
  Future<List<Map<String, dynamic>>> fetchLikedLists() async {
    final response = await _authenticatedGet('/users/me/likes/lists?limit=100');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchLikedLists failed (${response?.statusCode})');
      return [];
    }

    try {
      final list = jsonDecode(response.body) as List<dynamic>;
      // Each item wraps the list under a "list" key with the owner in "list.user"
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => e['list'] as Map<String, dynamic>?)
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      debugPrint('Trakt: fetchLikedLists parse error: $e');
      return [];
    }
  }

  /// Fetch items from a liked list owned by another user.
  /// [username] is the list owner's Trakt username.
  /// [listSlug] is the Trakt slug for the list.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchLikedListItems(String username, String listSlug, String contentType) async {
    final response = await _authenticatedGet('/users/$username/lists/$listSlug/items/$contentType?extended=full');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchLikedListItems failed (${response?.statusCode})');
      return [];
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchLikedListItems parse error: $e');
      return [];
    }
  }

  /// Fetch items from a specific custom list.
  /// [listId] is the Trakt slug for the list.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchCustomListItems(String listId, String contentType) async {
    final response = await _authenticatedGet('/users/me/lists/$listId/items/$contentType?extended=full');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchCustomListItems failed (${response?.statusCode})');
      return [];
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchCustomListItems parse error: $e');
      return [];
    }
  }

  /// Search Trakt for movies or shows by query.
  /// [query] is the search text, [type] is 'movie' or 'show'.
  /// Returns raw API results. Public endpoint — no auth required.
  Future<List<dynamic>> searchItems(String query, String type) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(query.trim());
    final url = '$kTraktApiBaseUrl/search/$type?query=$encoded&extended=full&limit=30';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _apiHeaders(),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('Trakt: search failed ($type, "$query") — ${response.statusCode}');
        return [];
      }
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: search error: $e');
      return [];
    }
  }

  /// Fetch all seasons with episodes for a show.
  /// [showId] can be an IMDB ID (e.g. 'tt1234567') or Trakt slug.
  /// This is a public endpoint — no auth token required.
  Future<List<Map<String, dynamic>>> fetchShowSeasons(String showId) async {
    final url = '$kTraktApiBaseUrl/shows/$showId/seasons?extended=episodes,full';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: _apiHeaders(),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint('Trakt: fetchShowSeasons failed for $showId (${response.statusCode})');
        return [];
      }

      final list = jsonDecode(response.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('Trakt: fetchShowSeasons error: $e');
      return [];
    }
  }

  /// Fetch the user's Trakt profile settings (username, etc.).
  Future<bool> _fetchAndStoreUsername(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('$kTraktApiBaseUrl/users/settings'),
        headers: _apiHeaders(accessToken: accessToken),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final user = data['user'] as Map<String, dynamic>?;
        final username = user?['username'] as String?;
        if (username != null) {
          await StorageService.setTraktUsername(username);
        }
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Trakt: Failed to fetch username: $e');
      return false;
    }
  }

  // ============================================================================
  // Playback / Continue Watching Methods
  // ============================================================================

  /// Fetch playback items (paused mid-watch) with full metadata.
  /// Returns raw items from /sync/playback for transformation.
  /// Each item has shape: { "progress": N, "movie": { ... } } or { "progress": N, "show": { ... } }
  Future<List<dynamic>> fetchPlaybackItems(String contentType) async {
    final response =
        await _authenticatedGet('/sync/playback/$contentType?extended=full');
    if (response == null || response.statusCode != 200) {
      debugPrint(
          'Trakt: fetchPlaybackItems failed (${response?.statusCode})');
      return [];
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchPlaybackItems parse error: $e');
      return [];
    }
  }

  /// Fetch recently watched shows that have a next episode available.
  /// Uses /users/me/history/episodes to find recently active shows,
  /// then checks each for a next_episode via /shows/{id}/progress/watched.
  /// Returns show items in playback-like format for merging with playback results.
  Future<List<Map<String, dynamic>>> fetchRecentShowsWithNextEpisode({
    Set<String> excludeImdbIds = const {},
    int historyLimit = 30,
  }) async {
    // Fetch recent episode history
    final response = await _authenticatedGet(
      '/users/me/history/episodes?limit=$historyLimit&extended=full',
    );
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchRecentHistory failed (${response?.statusCode})');
      return [];
    }

    List<dynamic> history;
    try {
      history = jsonDecode(response.body) as List<dynamic>;
    } catch (e) {
      debugPrint('Trakt: fetchRecentHistory parse error: $e');
      return [];
    }

    // Deduplicate to unique shows, keeping the first (most recent) occurrence
    final seenShows = <String, Map<String, dynamic>>{};
    for (final item in history) {
      if (item is! Map<String, dynamic>) continue;
      final show = item['show'] as Map<String, dynamic>?;
      if (show == null) continue;
      final ids = show['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      final traktId = ids?['trakt']?.toString();
      final showKey = imdbId ?? traktId;
      if (showKey == null) continue;
      if (excludeImdbIds.contains(imdbId)) continue;
      if (seenShows.containsKey(showKey)) continue;
      seenShows[showKey] = show;
    }

    if (seenShows.isEmpty) return [];

    debugPrint('Trakt: Checking ${seenShows.length} recent shows for next episode');

    // Check each show for a next episode (in parallel)
    final results = await Future.wait(
      seenShows.entries.map((entry) async {
        final show = entry.value;
        final traktId = show['ids']?['trakt']?.toString() ?? entry.key;
        final nextEp = await fetchNextEpisode(traktId);
        return nextEp != null
            ? {
                'show': show,
                'type': 'episode',
                'episode': {'season': nextEp.season, 'number': nextEp.episode},
              }
            : null;
      }),
    );

    final filtered = results.whereType<Map<String, dynamic>>().toList();
    debugPrint('Trakt: ${filtered.length} recent shows have next episodes');
    return filtered;
  }

  // ============================================================================
  // Watch Progress Methods
  // ============================================================================

  /// Fetch playback progress for movies paused mid-watch.
  /// Returns a map of IMDB ID → progress percentage (0-100).
  Future<Map<String, double>> fetchPlaybackProgress() async {
    final response = await _authenticatedGet('/sync/playback/movies');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchPlaybackProgress failed (${response?.statusCode})');
      return {};
    }

    try {
      final list = jsonDecode(response.body) as List<dynamic>;
      final result = <String, double>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final progress = item['progress'] as num?;
        final movie = item['movie'] as Map<String, dynamic>?;
        final ids = movie?['ids'] as Map<String, dynamic>?;
        final imdbId = ids?['imdb'] as String?;
        if (imdbId != null && progress != null) {
          result[imdbId] = progress.toDouble();
        }
      }
      return result;
    } catch (e) {
      debugPrint('Trakt: fetchPlaybackProgress parse error: $e');
      return {};
    }
  }

  /// Fetch all watched movies.
  /// Returns a map of IMDB ID → 100.0 (fully watched).
  Future<Map<String, double>> fetchWatchedMovies() async {
    final response = await _authenticatedGet('/sync/watched/movies');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchWatchedMovies failed (${response?.statusCode})');
      return {};
    }

    try {
      final list = jsonDecode(response.body) as List<dynamic>;
      final result = <String, double>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final movie = item['movie'] as Map<String, dynamic>?;
        final ids = movie?['ids'] as Map<String, dynamic>?;
        final imdbId = ids?['imdb'] as String?;
        if (imdbId != null) {
          result[imdbId] = 100.0;
        }
      }
      return result;
    } catch (e) {
      debugPrint('Trakt: fetchWatchedMovies parse error: $e');
      return {};
    }
  }

  /// Fetch watched episode keys for a specific show.
  /// Uses the per-show progress endpoint (much smaller than /sync/watched/shows).
  /// Returns a set of `"season-episode"` strings (e.g. `"1-5"`) for completed episodes.
  Future<Set<String>> fetchWatchedShowEpisodes(String showId) async {
    final response = await _authenticatedGet('/shows/$showId/progress/watched');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchWatchedShowEpisodes failed (${response?.statusCode})');
      return {};
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final result = <String>{};
      final seasons = data['seasons'] as List<dynamic>? ?? [];
      for (final season in seasons) {
        if (season is! Map<String, dynamic>) continue;
        final seasonNum = season['number'] as int?;
        if (seasonNum == null) continue;
        final episodes = season['episodes'] as List<dynamic>? ?? [];
        for (final ep in episodes) {
          if (ep is! Map<String, dynamic>) continue;
          final completed = ep['completed'] as bool? ?? false;
          final epNum = ep['number'] as int?;
          if (completed && epNum != null) {
            result.add('$seasonNum-$epNum');
          }
        }
      }
      return result;
    } catch (e) {
      debugPrint('Trakt: fetchWatchedShowEpisodes parse error: $e');
      return {};
    }
  }

  /// Fetch the next episode to watch for a show.
  /// Returns (season, episode) or null if show is complete / not started / error.
  Future<({int season, int episode})?> fetchNextEpisode(String showId) async {
    final response = await _authenticatedGet('/shows/$showId/progress/watched');
    if (response == null || response.statusCode != 200) return null;

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextEp = data['next_episode'] as Map<String, dynamic>?;
      if (nextEp == null) return null;

      final season = nextEp['season'] as int?;
      final number = nextEp['number'] as int?;
      if (season == null || number == null) return null;

      return (season: season, episode: number);
    } catch (e) {
      debugPrint('Trakt: fetchNextEpisode parse error: $e');
      return null;
    }
  }

  /// Fetch playback progress for episodes of a specific show.
  /// Returns a map of `"season-episode"` → progress percentage (0-100).
  Future<Map<String, double>> fetchEpisodePlaybackProgress(String showImdbId) async {
    final response = await _authenticatedGet('/sync/playback/episodes');
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchEpisodePlaybackProgress failed (${response?.statusCode})');
      return {};
    }

    try {
      final list = jsonDecode(response.body) as List<dynamic>;
      final result = <String, double>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        // Check if this episode belongs to the target show
        final show = item['show'] as Map<String, dynamic>?;
        final showIds = show?['ids'] as Map<String, dynamic>?;
        final imdbId = showIds?['imdb'] as String?;
        if (imdbId != showImdbId) continue;

        final progress = item['progress'] as num?;
        final episode = item['episode'] as Map<String, dynamic>?;
        final season = episode?['season'] as int?;
        final number = episode?['number'] as int?;
        if (season != null && number != null && progress != null) {
          result['$season-$number'] = progress.toDouble();
        }
      }
      return result;
    } catch (e) {
      debugPrint('Trakt: fetchEpisodePlaybackProgress parse error: $e');
      return {};
    }
  }
}
