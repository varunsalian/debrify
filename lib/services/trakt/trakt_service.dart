import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/profiles/profile_policy.dart';
import '../episode_tracker_snapshot_revision.dart';
import '../profiles/profile_async_authorization.dart';
import '../profiles/profile_runtime.dart';
import '../storage_service.dart';
import 'trakt_calendar_service.dart';
import 'trakt_constants.dart';

/// The user's Trakt relationship to a single title — used to render a
/// state-aware detail page (in watchlist / collection / watched / rating)
/// instead of a blind "add only" menu.
class TraktTitleStatus {
  final bool inWatchlist;
  final bool inCollection;

  /// Title-level watched. Non-null only for movies; series retain both bulk
  /// history actions in their menu regardless of completion.
  final bool? watched;

  /// True when every currently aired regular episode is in Trakt history.
  /// Kept separate from [watched] so partially watched series can still offer
  /// both "Mark Watched" and "Mark Unwatched" bulk actions.
  final bool? seriesFullyWatched;

  bool? get titleWatched => watched ?? seriesFullyWatched;

  /// The user's 1–10 Trakt rating, or null if unrated.
  final int? rating;

  const TraktTitleStatus({
    this.inWatchlist = false,
    this.inCollection = false,
    this.watched,
    this.seriesFullyWatched,
    this.rating,
  });

  /// Keep an authoritative watched answer when a later best-effort refresh
  /// can only say "unknown". The independent library fields still come from
  /// the fresh response.
  TraktTitleStatus preserveWatchedFrom(TraktTitleStatus? previous) {
    if (previous == null) return this;
    return TraktTitleStatus(
      inWatchlist: inWatchlist,
      inCollection: inCollection,
      watched: watched ?? previous.watched,
      seriesFullyWatched: seriesFullyWatched ?? previous.seriesFullyWatched,
      rating: rating,
    );
  }
}

class _TraktDeviceAuthorization {
  final ProfileAsyncAuthorization authorization;
  final DateTime expiresAt;

  const _TraktDeviceAuthorization({
    required this.authorization,
    required this.expiresAt,
  });
}

/// Service for Trakt OAuth authentication and API calls.
class TraktService {
  static final TraktService _instance = TraktService._internal();
  factory TraktService() => _instance;
  TraktService._internal();

  static TraktService get instance => _instance;

  // ── Library-status cache ────────────────────────────────────────────────────
  // Detail pages ask "is this title in my watchlist / collection / watched /
  // rated?" on open. The answers come from account-wide lists (per content
  // type), so cache each list briefly and serve every title lookup from it —
  // opening five detail pages costs one fetch, not five. Any sync mutation
  // (add/remove/rate via [_syncAction]) clears the cache so the next open is
  // fresh.
  final Map<String, ({DateTime at, Object data})> _libCache = {};
  static const Duration _libTtl = Duration(seconds: 45);
  int _libCacheGeneration = 0;
  final Map<String, _TraktDeviceAuthorization> _deviceAuthorizations = {};

  void _invalidateLibraryCache() {
    _libCache.clear();
    _libCacheGeneration++;
  }

  /// Clears every account-scoped process cache at a profile boundary.
  void resetProfileScope() {
    _invalidateLibraryCache();
    _deviceAuthorizations.clear();
    TraktCalendarService.instance.invalidate();
  }

  Future<T?> _cachedLib<T>(String key, Future<T?> Function() load) async {
    final hit = _libCache[key];
    if (hit != null && DateTime.now().difference(hit.at) < _libTtl) {
      return hit.data as T;
    }
    final generation = _libCacheGeneration;
    final data = await load();
    // Only cache authoritative results — never poison the cache with the empty
    // set a transient failure produces, which would otherwise flip every
    // affected title's badge/menu to "not in library" for the whole TTL.
    if (data != null && generation == _libCacheGeneration) {
      _libCache[key] = (at: DateTime.now(), data: data as Object);
    }
    return data;
  }

  /// Extract the set of IMDb ids from a standard Trakt list response (items
  /// wrap a `movie`/`show` container).
  Set<String> _extractListImdbIds(List<dynamic> items) {
    final out = <String>{};
    for (final it in items) {
      if (it is! Map<String, dynamic>) continue;
      final container = (it['movie'] ?? it['show']) as Map<String, dynamic>?;
      final imdb =
          (container?['ids'] as Map<String, dynamic>?)?['imdb'] as String?;
      if (imdb != null) out.add(imdb);
    }
    return out;
  }

  /// Extract IMDb id → rating from a `/sync/ratings` list response.
  Map<String, int> _extractRatings(List<dynamic> items) {
    final out = <String, int>{};
    for (final it in items) {
      if (it is! Map<String, dynamic>) continue;
      final container = (it['movie'] ?? it['show']) as Map<String, dynamic>?;
      final imdb =
          (container?['ids'] as Map<String, dynamic>?)?['imdb'] as String?;
      final rating = it['rating'] as int?;
      if (imdb != null && rating != null) out[imdb] = rating;
    }
    return out;
  }

  /// The user's relationship to a single title: whether it's in their
  /// watchlist / collection, whether it's watched (movies only — see
  /// [TraktTitleStatus.watched]), and their rating. Backed by the short-lived
  /// library cache, so repeated detail opens don't re-fetch.
  ///
  /// Returns **null** when the answer can't be trusted — disconnected, or any of
  /// the core lists (watchlist / collection / ratings) failed to load — so
  /// callers keep whatever they last showed instead of wrongly rendering the
  /// title as "not in library". A genuine "in none of them" is a non-null
  /// all-false status, distinct from this null.
  Future<TraktTitleStatus?> fetchTitleStatus(String imdbId, String type) async {
    if (!await isAuthenticated()) return null;
    final contentType = type == 'series' ? 'shows' : 'movies';
    try {
      // Kick all list fetches off together, then await — they run concurrently.
      // Each returns null (not []) on a transient failure so it isn't cached.
      final watchlistF = _cachedLib<Set<String>>(
        'watchlist:$contentType',
        () async {
          final l = await fetchListOrNull('watchlist', contentType);
          return l == null ? null : _extractListImdbIds(l);
        },
      );
      final collectionF = _cachedLib<Set<String>>(
        'collection:$contentType',
        () async {
          final l = await fetchListOrNull('collection', contentType);
          return l == null ? null : _extractListImdbIds(l);
        },
      );
      final ratingsF = _cachedLib<Map<String, int>>(
        'ratings:$contentType',
        () async {
          final l = await fetchListOrNull('ratings', contentType);
          return l == null ? null : _extractRatings(l);
        },
      );
      // Watched via failure-aware endpoints, so a transient failure returns
      // null (not cached, treated as "unknown watched") instead of poisoning
      // the cache with an empty set. Series need progress detail so fully
      // watched can be distinguished from merely started.
      final Future<bool?> watchedF;
      if (type == 'series') {
        final normalizedId = imdbId.trim().toLowerCase();
        watchedF = _cachedLib<bool>(
          'watched:show:$normalizedId',
          () => fetchShowFullyWatchedOrNull(normalizedId),
        );
      } else {
        watchedF = _cachedLib<Set<String>>('watched:movies', () async {
          final l = await fetchListOrNull('watched', 'movies');
          return l == null ? null : _extractListImdbIds(l);
        }).then((ids) => ids?.contains(imdbId.toLowerCase()));
      }

      final watchlist = await watchlistF;
      final collection = await collectionF;
      final ratings = await ratingsF;
      // A core list unavailable → signal unknown (null) rather than fabricate an
      // all-false status the UI would read as "not in library".
      if (watchlist == null || collection == null || ratings == null) {
        return null;
      }
      // Null (watched fetch failed) → watched unknown, not "unwatched".
      final titleWatched = await watchedF;

      return TraktTitleStatus(
        inWatchlist: watchlist.contains(imdbId),
        inCollection: collection.contains(imdbId),
        watched: type == 'series' ? null : titleWatched,
        seriesFullyWatched: type == 'series' ? titleWatched : null,
        rating: ratings[imdbId],
      );
    } catch (error) {
      debugPrint('Trakt: fetchTitleStatus failed (${error.runtimeType})');
      return null;
    }
  }

  /// Common headers for all Trakt API requests.
  Map<String, String> _apiHeaders({String? accessToken}) => {
    'Content-Type': 'application/json',
    'trakt-api-version': kTraktApiVersion,
    'trakt-api-key': kTraktClientId,
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  String _userListItemTypeSegment(String contentType) {
    switch (contentType) {
      case 'movies':
        return 'movie';
      case 'shows':
        return 'show';
      case 'seasons':
        return 'season';
      case 'episodes':
        return 'episode';
      default:
        return contentType;
    }
  }

  int _paginationPageCount(http.Response response) {
    final raw = response.headers['x-pagination-page-count'];
    return int.tryParse(raw ?? '') ?? 1;
  }

  String _withQuerySeparator(String path) => path.contains('?') ? '&' : '?';

  Future<List<dynamic>> _fetchPagedListItems({
    required String basePath,
    required String contentType,
    required String logLabel,
  }) async {
    final items = <dynamic>[];
    var page = 1;
    var pageCount = 1;

    do {
      final separator = _withQuerySeparator(basePath);
      final path = '$basePath${separator}page=$page&limit=100';
      debugPrint('Trakt: $logLabel request page $page');
      final response = await _authenticatedGet(path);
      if (response == null || response.statusCode != 200) {
        debugPrint('Trakt: $logLabel failed (${response?.statusCode})');
        return [];
      }

      try {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        items.addAll(decoded);
        pageCount = _paginationPageCount(response);
        debugPrint(
          'Trakt: $logLabel OK $contentType page=$page/$pageCount '
          'pageCount=${decoded.length} total=${items.length}',
        );
      } catch (error) {
        debugPrint('Trakt: $logLabel parse error (${error.runtimeType})');
        return [];
      }

      page += 1;
    } while (page <= pageCount);

    return items;
  }

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
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      if (authorization == null) return _refreshAccessTokenScoped();
      return await authorization.run(_refreshAccessTokenScoped);
    } on StateError {
      return false;
    }
  }

  Future<bool> _refreshAccessTokenScoped() async {
    try {
      final refreshToken = await StorageService.getTraktRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) return false;

      final response = await http
          .post(
            Uri.parse(kTraktTokenUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'refresh_token': refreshToken,
              'client_id': kTraktClientId,
              'client_secret': kTraktClientSecret,
              'grant_type': 'refresh_token',
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);
        return true;
      }

      debugPrint('Trakt: Token refresh failed (${response.statusCode})');
      return false;
    } catch (error) {
      debugPrint('Trakt: Token refresh error (${error.runtimeType})');
      return false;
    }
  }

  /// Revoke the current token and clear stored auth data.
  Future<void> logout() async {
    final accessToken = await StorageService.getTraktAccessToken();
    // Local disposition happens before the upstream side effect. A shared
    // owner fails closed here, while a borrower detaches without revoking the
    // account used by its owner and other grantees.
    final shouldRevokeRemote = await StorageService.clearTraktAuth();
    try {
      if (shouldRevokeRemote && accessToken != null) {
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
    } catch (error) {
      debugPrint('Trakt: Revoke token error (${error.runtimeType})');
    }
    TraktCalendarService.instance.invalidate();
    // Drop cached library state so a later sign-in (possibly a different
    // account) never reads the previous user's watchlist/collection/ratings.
    _invalidateLibraryCache();
    StorageService.movieFinishedRevision.value++;
  }

  /// Get the stored username.
  Future<String?> getUsername() async {
    return StorageService.getTraktUsername();
  }

  /// Store tokens and expiry from a token response.
  Future<void> _storeTokens(Map<String, dynamic> data) async {
    // A fresh token may belong to a different account (a sign-in without an
    // intervening logout, e.g. re-auth). Drop any cached library state so the
    // previous user's watchlist/collection/ratings can't be served. Harmless on
    // a same-account refresh — it just forces one re-fetch.
    _invalidateLibraryCache();
    await StorageService.setTraktAccessToken(data['access_token'] as String);
    await StorageService.setTraktRefreshToken(data['refresh_token'] as String);

    final expiresIn = data['expires_in'] as int?;
    if (expiresIn != null) {
      final expiryMs = DateTime.now()
          .add(Duration(seconds: expiresIn))
          .millisecondsSinceEpoch;
      await StorageService.setTraktTokenExpiry(expiryMs);
    }
    StorageService.movieFinishedRevision.value++;
  }

  // ============================================================================
  // Device Code Flow (for Android TV)
  // ============================================================================

  /// Request a device code for the device code OAuth flow.
  /// Returns the parsed JSON response on success, null on failure.
  Future<Map<String, dynamic>?> requestDeviceCode() async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      final response = await http.post(
        Uri.parse(kTraktDeviceCodeUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'client_id': kTraktClientId}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final deviceCode = data['device_code'] as String?;
        if (authorization != null &&
            deviceCode != null &&
            deviceCode.isNotEmpty) {
          _pruneDeviceAuthorizations();
          final seconds = (data['expires_in'] as int? ?? 600).clamp(1, 1800);
          _deviceAuthorizations[deviceCode] = _TraktDeviceAuthorization(
            authorization: authorization,
            expiresAt: DateTime.now().add(Duration(seconds: seconds)),
          );
        }
        return data;
      }

      debugPrint('Trakt: Device code request failed (${response.statusCode})');
      return null;
    } catch (error) {
      debugPrint('Trakt: Device code request error (${error.runtimeType})');
      return null;
    }
  }

  /// Poll for a device token using the device code.
  /// Returns null on success (tokens stored), or an error string:
  /// "authorization_pending", "slow_down", "expired_token", "access_denied",
  /// "network_error" (transient — safe to retry), or "error" (fatal).
  Future<String?> pollDeviceToken(String deviceCode) async {
    try {
      final attempt = _deviceAuthorizations[deviceCode];
      if (ProfileRuntime.isInitialized &&
          ProfileRuntime.isProfileCommitted &&
          (attempt == null || attempt.expiresAt.isBefore(DateTime.now()))) {
        _deviceAuthorizations.remove(deviceCode);
        return 'access_denied';
      }
      final response = await http
          .post(
            Uri.parse(kTraktDeviceTokenUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': deviceCode,
              'client_id': kTraktClientId,
              'client_secret': kTraktClientSecret,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _deviceAuthorizations.remove(deviceCode);
        Future<void> commit() async {
          await _storeTokens(data);
          final accessToken = data['access_token'] as String;
          await _fetchAndStoreUsername(accessToken);
        }

        try {
          if (attempt == null) {
            await commit();
          } else {
            await attempt.authorization.run(commit);
          }
        } on StateError {
          return 'access_denied';
        }
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

      debugPrint('Trakt: Device token poll failed (${response.statusCode})');
      return 'error';
    } catch (error) {
      // Network timeout, socket exception, etc. — transient, safe to retry
      debugPrint(
        'Trakt: Device token poll network error (${error.runtimeType})',
      );
      return 'network_error';
    }
  }

  void _pruneDeviceAuthorizations() {
    final now = DateTime.now();
    _deviceAuthorizations.removeWhere(
      (_, value) => value.expiresAt.isBefore(now),
    );
    while (_deviceAuthorizations.length >= 8) {
      _deviceAuthorizations.remove(_deviceAuthorizations.keys.first);
    }
  }

  // ============================================================================
  // Scrobble Methods
  // ============================================================================

  /// Authenticated POST request with automatic token refresh on 401.
  Future<http.Response?> _authenticatedPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http
          .post(
            Uri.parse('$kTraktApiBaseUrl$path'),
            headers: _apiHeaders(accessToken: accessToken),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      // If unauthorized, try refreshing the token once
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http
            .post(
              Uri.parse('$kTraktApiBaseUrl$path'),
              headers: _apiHeaders(accessToken: accessToken),
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (error) {
      debugPrint('Trakt: Authenticated POST error (${error.runtimeType})');
      return null;
    }
  }

  /// Scrobble: notify Trakt that playback has started.
  Future<bool> scrobbleStart(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    return _scrobble(
      '/scrobble/start',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  /// Scrobble: notify Trakt that playback was paused.
  Future<bool> scrobblePause(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    return _scrobble(
      '/scrobble/pause',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  /// Scrobble: notify Trakt that playback was stopped.
  Future<bool> scrobbleStop(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    return _scrobble(
      '/scrobble/stop',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  Future<bool> _scrobble(
    String path,
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    // Treat 0 as null — Kotlin TV player sends 0 for movies instead of null
    if (season != null && season <= 0) season = null;
    if (episode != null && episode <= 0) episode = null;
    // Refuse to scrobble if only one of season/episode is set — would send
    // a movie body with a show IMDB ID, corrupting Trakt history.
    if ((season == null) != (episode == null)) {
      debugPrint('Trakt: Skipping scrobble with incomplete episode data');
      return false;
    }
    final Map<String, dynamic> body;
    if (season != null && episode != null) {
      body = {
        'show': {
          'ids': {'imdb': imdbId},
        },
        'episode': {'season': season, 'number': episode},
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
      if (season != null && episode != null) {
        EpisodeTrackerSnapshotRevision.invalidateTitle('trakt', imdbId);
      }
      if (path == '/scrobble/stop' && progress > 80) {
        _invalidateLibraryCache();
        StorageService.movieFinishedRevision.value++;
      }
      debugPrint('Trakt: Scrobble completed');
      return true;
    }
    debugPrint('Trakt: Scrobble failed (${response.statusCode})');
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
    final body = {
      apiKey: [item],
    };
    final response = await _authenticatedPost(path, body);
    if (response == null) return false;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint('Trakt: Sync action failed (${response.statusCode})');
    } else {
      // A watchlist/collection/history/ratings change makes the cached lists
      // stale — drop them so the next title-status lookup reflects it.
      _invalidateLibraryCache();
      if (path == '/sync/history' || path == '/sync/history/remove') {
        if (type == 'series') {
          EpisodeTrackerSnapshotRevision.invalidateTitle('trakt', imdbId);
        }
        StorageService.movieFinishedRevision.value++;
      }
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

  Future<bool> rateItem(String imdbId, String type, int rating) => _syncAction(
    '/sync/ratings',
    imdbId,
    type,
    extraItemFields: {'rating': rating},
  );

  Future<bool> removeRating(String imdbId, String type) =>
      _syncAction('/sync/ratings/remove', imdbId, type);

  Future<bool> addToCustomList(String listId, String imdbId, String type) =>
      _syncAction('/users/me/lists/$listId/items', imdbId, type);

  Future<bool> removeFromCustomList(
    String listId,
    String imdbId,
    String type,
  ) => _syncAction('/users/me/lists/$listId/items/remove', imdbId, type);

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
            },
          ],
        },
      ],
    };
    final response = await _authenticatedPost(path, body);
    if (response == null) return false;
    final ok = response.statusCode >= 200 && response.statusCode < 300;
    if (!ok) {
      debugPrint('Trakt: Episode sync failed (${response.statusCode})');
    } else if (path == '/sync/history' || path == '/sync/history/remove') {
      _invalidateLibraryCache();
      EpisodeTrackerSnapshotRevision.invalidateTitle('trakt', showImdbId);
      StorageService.movieFinishedRevision.value++;
    }
    return ok;
  }

  Future<bool> markEpisodeWatched(String showImdbId, int season, int episode) =>
      _syncEpisodeAction('/sync/history', showImdbId, season, episode);

  Future<bool> markEpisodeUnwatched(
    String showImdbId,
    int season,
    int episode,
  ) => _syncEpisodeAction('/sync/history/remove', showImdbId, season, episode);

  Future<bool> rateEpisode(
    String showImdbId,
    int season,
    int episode,
    int rating,
  ) => _syncEpisodeAction(
    '/sync/ratings',
    showImdbId,
    season,
    episode,
    extraEpisodeFields: {'rating': rating},
  );

  // ============================================================================
  // List API Methods
  // ============================================================================

  /// Authenticated GET request with automatic token refresh on 401.
  /// GET a public Trakt endpoint that needs only the api-key header (no OAuth
  /// token) — e.g. the global trending/popular/anticipated lists. Returns null
  /// on any failure, like [_authenticatedGet].
  Future<http.Response?> _publicGet(String path) async {
    try {
      return await http
          .get(Uri.parse('$kTraktApiBaseUrl$path'), headers: _apiHeaders())
          .timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Trakt: Public GET error (${error.runtimeType})');
      return null;
    }
  }

  Future<http.Response?> _authenticatedGet(String path) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http
          .get(
            Uri.parse('$kTraktApiBaseUrl$path'),
            headers: _apiHeaders(accessToken: accessToken),
          )
          .timeout(const Duration(seconds: 15));

      // If unauthorized, try refreshing the token once
      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http
            .get(
              Uri.parse('$kTraktApiBaseUrl$path'),
              headers: _apiHeaders(accessToken: accessToken),
            )
            .timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (error) {
      debugPrint('Trakt: Authenticated GET error (${error.runtimeType})');
      return null;
    }
  }

  Future<http.Response?> _authenticatedDelete(String path) async {
    var accessToken = await StorageService.getTraktAccessToken();
    if (accessToken == null) return null;

    try {
      var response = await http
          .delete(
            Uri.parse('$kTraktApiBaseUrl$path'),
            headers: _apiHeaders(accessToken: accessToken),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 401) {
        final refreshed = await refreshAccessToken();
        if (!refreshed) return null;

        accessToken = await StorageService.getTraktAccessToken();
        if (accessToken == null) return null;

        response = await http
            .delete(
              Uri.parse('$kTraktApiBaseUrl$path'),
              headers: _apiHeaders(accessToken: accessToken),
            )
            .timeout(const Duration(seconds: 15));
      }

      return response;
    } catch (error) {
      debugPrint('Trakt: Authenticated DELETE error (${error.runtimeType})');
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
  ///
  /// Returns an empty list on any failure — callers that need to tell a genuine
  /// outage from a truly empty list should use [fetchListOrNull] instead.
  Future<List<dynamic>> fetchList(String listType, String contentType) async =>
      await fetchListOrNull(listType, contentType) ?? const [];

  /// Like [fetchList] but returns null on failure (no auth / non-200 / network /
  /// parse error) so callers can distinguish a fetch that failed from a list
  /// that is genuinely empty — the two are visually different states.
  Future<List<dynamic>?> fetchListOrNull(
    String listType,
    String contentType,
  ) async {
    final String path;
    // trending/popular/anticipated are public Trakt endpoints — no OAuth token
    // required — so serve them without auth to survive a missing/expired token.
    final bool isPublic =
        listType == 'trending' ||
        listType == 'popular' ||
        listType == 'anticipated';
    if (listType == 'recommendations') {
      path = '/recommendations/$contentType?extended=full';
    } else if (listType == 'watched') {
      path = '/sync/watched/$contentType?extended=full';
    } else if (listType == 'history') {
      path = '/sync/history/$contentType?extended=full&limit=100';
    } else if (isPublic) {
      path = '/$contentType/$listType?extended=full&limit=100';
    } else {
      path = '/sync/$listType/$contentType?extended=full';
    }

    final response = isPublic
        ? await _publicGet(path)
        : await _authenticatedGet(path);
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchList failed (${response?.statusCode})');
      return null;
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (error) {
      debugPrint('Trakt: fetchList parse error (${error.runtimeType})');
      return null;
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
    } catch (error) {
      debugPrint('Trakt: fetchCustomLists parse error (${error.runtimeType})');
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
    } catch (error) {
      debugPrint('Trakt: fetchLikedLists parse error (${error.runtimeType})');
      return [];
    }
  }

  /// Fetch items from a liked list owned by another user.
  /// [username] is the list owner's Trakt username.
  /// [listSlug] is the Trakt slug for the list.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchLikedListItems(
    String username,
    String listSlug,
    String contentType,
  ) async {
    final itemType = _userListItemTypeSegment(contentType);
    final path =
        '/users/$username/lists/$listSlug/items/$itemType?extended=full';
    return _fetchPagedListItems(
      basePath: path,
      contentType: contentType,
      logLabel: 'fetchLikedListItems owner=$username slug=$listSlug',
    );
  }

  Future<List<dynamic>> fetchLikedListItemsFromList(
    Map<String, dynamic> list,
    String contentType,
  ) async {
    final base = _likedListBasePath(list);
    if (base == null) return [];
    final itemType = _userListItemTypeSegment(contentType);
    return _fetchPagedListItems(
      basePath: '$base/items/$itemType?extended=full',
      contentType: contentType,
      logLabel: 'fetchLikedListItems $base',
    );
  }

  /// Resolve a liked list to its API base segment (without a trailing `/items`):
  /// the global `/lists/{traktId}` when the list carries a Trakt id, else
  /// `/users/{owner}/lists/{slug}`. Null when neither can be built. Shared by the
  /// paged and single-ordered liked-list fetchers so they can't drift.
  String? _likedListBasePath(Map<String, dynamic> list) {
    final traktId = list['ids']?['trakt']?.toString();
    if (traktId != null && traktId.isNotEmpty) return '/lists/$traktId';
    final slug = list['ids']?['slug'] as String? ?? '';
    final user = list['user'] as Map<String, dynamic>?;
    final owner =
        user?['ids']?['slug'] as String? ?? user?['username'] as String? ?? '';
    if (owner.isEmpty || slug.isEmpty) return null;
    return '/users/$owner/lists/$slug';
  }

  /// Fetch items from a specific custom list.
  /// [listId] is the Trakt slug for the list.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchCustomListItems(
    String listId,
    String contentType,
  ) async {
    final itemType = _userListItemTypeSegment(contentType);
    final path = '/users/me/lists/$listId/items/$itemType?extended=full';
    return _fetchPagedListItems(
      basePath: path,
      contentType: contentType,
      logLabel: 'fetchCustomListItems slug=$listId',
    );
  }

  /// Fetch a user list's movie + show items in one call, preserving the list's
  /// own cross-type order (rank / listed_at), and returning null on failure so
  /// callers can tell an outage from a genuinely empty list. Seasons/episodes/
  /// people are intentionally excluded — the See-All grid renders posters only.
  ///
  /// [basePath] is the list segment without the trailing `/items` — e.g.
  /// `/users/me/lists/{slug}` (own) or `/lists/{traktId}` / `/users/{owner}/
  /// lists/{slug}` (liked).
  Future<List<dynamic>?> _fetchListItemsOrderedOrNull(
    String basePath,
    String logLabel,
  ) async {
    final items = <dynamic>[];
    var page = 1;
    var pageCount = 1;
    do {
      final path =
          '$basePath/items/movie,show?extended=full&page=$page&limit=100';
      final response = await _authenticatedGet(path);
      if (response == null || response.statusCode != 200) {
        debugPrint('Trakt: $logLabel failed (${response?.statusCode})');
        // Fail hard only if nothing loaded; a later page failing keeps the pages
        // already fetched (partial success) rather than blanking the whole list.
        return items.isEmpty ? null : items;
      }
      try {
        final decoded = jsonDecode(response.body) as List<dynamic>;
        items.addAll(decoded);
        pageCount = _paginationPageCount(response);
      } catch (error) {
        debugPrint('Trakt: $logLabel parse error (${error.runtimeType})');
        return items.isEmpty ? null : items;
      }
      page += 1;
    } while (page <= pageCount);
    return items;
  }

  /// Own custom list items (movies + shows) in list order, null on failure.
  /// [listRef] is the list's slug (preferred) or Trakt id.
  Future<List<dynamic>?> fetchCustomListItemsOrderedOrNull(String listRef) {
    return _fetchListItemsOrderedOrNull(
      '/users/me/lists/$listRef',
      'customList $listRef',
    );
  }

  /// Liked list items (movies + shows) in list order, null on failure. Resolves
  /// the list's global-id path when possible, else the owner/slug path.
  Future<List<dynamic>?> fetchLikedListItemsOrderedOrNull(
    Map<String, dynamic> list,
  ) {
    final base = _likedListBasePath(list);
    if (base == null) return Future.value(null);
    return _fetchListItemsOrderedOrNull(base, 'likedList $base');
  }

  /// Search Trakt for movies or shows by query.
  /// [query] is the search text, [type] is 'movie' or 'show'.
  /// Returns raw API results. Public endpoint — no auth required.
  Future<List<dynamic>> searchItems(String query, String type) async {
    if (query.trim().isEmpty) return [];
    final encoded = Uri.encodeComponent(query.trim());
    final url =
        '$kTraktApiBaseUrl/search/$type?query=$encoded&extended=full&limit=30';
    try {
      final response = await http
          .get(Uri.parse(url), headers: _apiHeaders())
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint(
          'Trakt: search failed ($type, "$query") — ${response.statusCode}',
        );
        return [];
      }
      return jsonDecode(response.body) as List<dynamic>;
    } catch (error) {
      debugPrint('Trakt: search error (${error.runtimeType})');
      return [];
    }
  }

  /// Fetch all seasons with episodes for a show.
  /// [showId] can be an IMDB ID (e.g. 'tt1234567') or Trakt slug.
  /// This is a public endpoint — no auth token required.
  Future<List<Map<String, dynamic>>> fetchShowSeasons(String showId) async {
    final url =
        '$kTraktApiBaseUrl/shows/$showId/seasons?extended=episodes,full';
    try {
      final response = await http
          .get(Uri.parse(url), headers: _apiHeaders())
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
          'Trakt: fetchShowSeasons failed for $showId (${response.statusCode})',
        );
        return [];
      }

      final list = jsonDecode(response.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    } catch (error) {
      debugPrint('Trakt: fetchShowSeasons error (${error.runtimeType})');
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
    } catch (error) {
      debugPrint('Trakt: Failed to fetch username (${error.runtimeType})');
      return false;
    }
  }

  // ============================================================================
  // Playback / Continue Watching Methods
  // ============================================================================

  /// Fetch what the authenticated user is currently watching (live scrobble).
  /// Returns the raw JSON map on 200, null on 204 (nothing playing) or any error.
  Future<Map<String, dynamic>?> fetchNowWatching() async {
    final response = await _authenticatedGet('/users/me/watching');
    if (response == null) return null;
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) {
      debugPrint('Trakt: fetchNowWatching failed (${response.statusCode})');
      return null;
    }
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      debugPrint('Trakt: fetchNowWatching parse error (${error.runtimeType})');
      return null;
    }
  }

  /// Fetch playback items (paused mid-watch) with full metadata.
  /// Returns raw items from /sync/playback for transformation.
  /// Each item has shape: { "progress": N, "movie": { ... } } or { "progress": N, "show": { ... } }
  Future<List<dynamic>> fetchPlaybackItems(String contentType) async {
    final response = await _authenticatedGet(
      '/sync/playback/$contentType?extended=full',
    );
    if (response == null || response.statusCode != 200) {
      debugPrint('Trakt: fetchPlaybackItems failed (${response?.statusCode})');
      return [];
    }

    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (error) {
      debugPrint(
        'Trakt: fetchPlaybackItems parse error (${error.runtimeType})',
      );
      return [];
    }
  }

  /// Fetch upcoming episodes from the user's Trakt calendar for the given window.
  ///
  /// Wraps GET `/calendars/my/shows/{startDate}/{days}`. Returns raw JSON
  /// entries, or `[]` on error / when unauthenticated. Trakt caps `days` at
  /// 33 — callers must not exceed this.
  ///
  /// Note: intentionally NOT using `?extended=full` — Trakt's calendar
  /// endpoints routinely time out with that flag, and the basic response
  /// already includes the fields we need (show title, ids, episode
  /// season/number, first_aired).
  Future<List<dynamic>> fetchCalendarMyShows({
    required DateTime startDate,
    required int days,
  }) async {
    assert(days > 0 && days <= 33, 'Trakt caps calendar days at 33');
    final y = startDate.year.toString().padLeft(4, '0');
    final m = startDate.month.toString().padLeft(2, '0');
    final d = startDate.day.toString().padLeft(2, '0');
    final path = '/calendars/my/shows/$y-$m-$d/$days';

    final response = await _authenticatedGet(path);
    if (response == null || response.statusCode != 200) {
      debugPrint(
        'Trakt: fetchCalendarMyShows failed (${response?.statusCode})',
      );
      return [];
    }
    try {
      return jsonDecode(response.body) as List<dynamic>;
    } catch (error) {
      debugPrint(
        'Trakt: fetchCalendarMyShows parse error (${error.runtimeType})',
      );
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
    } catch (error) {
      debugPrint(
        'Trakt: fetchRecentHistory parse error (${error.runtimeType})',
      );
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

    debugPrint(
      'Trakt: Checking ${seenShows.length} recent shows for next episode',
    );

    // Check each show for a next episode (in parallel, with one retry on network failure)
    final results = await Future.wait(
      seenShows.entries.map((entry) async {
        final show = entry.value;
        final traktId = show['ids']?['trakt']?.toString() ?? entry.key;
        try {
          // First attempt: check if the API is reachable
          final response = await _authenticatedGet(
            '/shows/$traktId/progress/watched',
          );
          var nextEp = _parseNextEpisode(response);

          // Retry once on network/HTTP failure (null response or non-200),
          // but NOT when the show legitimately has no next episode (200 + null next_episode)
          if (nextEp == null &&
              (response == null || response.statusCode != 200)) {
            await Future.delayed(const Duration(milliseconds: 500));
            final retryResponse = await _authenticatedGet(
              '/shows/$traktId/progress/watched',
            );
            nextEp = _parseNextEpisode(retryResponse);
          }

          return nextEp != null
              ? {
                  'show': show,
                  'type': 'episode',
                  'episode': {
                    'season': nextEp.season,
                    'number': nextEp.episode,
                  },
                }
              : null;
        } catch (error) {
          debugPrint('Trakt: fetchNextEpisode error (${error.runtimeType})');
          return null;
        }
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
      debugPrint(
        'Trakt: fetchPlaybackProgress failed (${response?.statusCode})',
      );
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
    } catch (error) {
      debugPrint(
        'Trakt: fetchPlaybackProgress parse error (${error.runtimeType})',
      );
      return {};
    }
  }

  /// Fetch all watched movies.
  /// Returns a map of IMDB ID → 100.0 (fully watched).
  Future<Map<String, double>> fetchWatchedMovies() async =>
      await fetchWatchedMoviesOrNull() ?? {};

  /// Failure-aware watched movie bulk read for background badge refreshes.
  Future<Map<String, double>?> fetchWatchedMoviesOrNull() async {
    final list = await _fetchAllWatchedPages('movies', limit: 250);
    if (list == null) return null;
    try {
      return debugParseWatchedMovies(list);
    } catch (error) {
      debugPrint(
        'Trakt: fetchWatchedMovies parse error (${error.runtimeType})',
      );
      return null;
    }
  }

  /// Kept visible for a response-shape regression test. The normal watched
  /// response contains the IMDb mapping; `extended=min` deliberately does not.
  @visibleForTesting
  static Map<String, double> debugParseWatchedMovies(List<dynamic> list) {
    final result = <String, double>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final movie = item['movie'] as Map<String, dynamic>?;
      final ids = movie?['ids'] as Map<String, dynamic>?;
      final imdbId = (ids?['imdb'] as String?)?.trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) result[imdbId] = 100.0;
    }
    return result;
  }

  /// Fully watched series, calculated in bulk from Trakt's paged progress
  /// response. A show with only some watched episodes is deliberately absent.
  Future<Set<String>> fetchFullyWatchedShows() async {
    return await fetchFullyWatchedShowsOrNull() ?? {};
  }

  /// Failure-aware fully-watched series bulk read.
  Future<Set<String>?> fetchFullyWatchedShowsOrNull() async {
    final list = await _fetchAllWatchedPages(
      'shows',
      extended: 'progress',
      limit: 100,
    );
    if (list == null) return null;
    return debugParseFullyWatchedShows(list);
  }

  /// Failure-aware completion check for one series detail page. This avoids
  /// downloading the user's entire watched-show history merely to label one
  /// title's Trakt pill.
  Future<bool?> fetchShowFullyWatchedOrNull(String showId) async {
    final response = await _authenticatedGet(
      '/shows/$showId/progress/watched?hidden=false&specials=false&count_specials=false',
    );
    if (response == null || response.statusCode != 200) return null;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return debugParseShowFullyWatched(data);
    } catch (error) {
      debugPrint(
        'Trakt: fetch show watched progress parse error '
        '(${error.runtimeType})',
      );
      return null;
    }
  }

  @visibleForTesting
  static bool? debugParseShowFullyWatched(Map<String, dynamic> data) {
    final aired = (data['aired'] as num?)?.toInt();
    final completed = (data['completed'] as num?)?.toInt();
    if (aired == null || completed == null) return null;
    return aired > 0 && completed >= aired;
  }

  @visibleForTesting
  static Set<String> debugParseFullyWatchedShows(List<dynamic> list) {
    final result = <String>{};
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final show = item['show'] as Map<String, dynamic>?;
      final ids = show?['ids'] as Map<String, dynamic>?;
      final imdbId = ids?['imdb'] as String?;
      final aired = (show?['aired_episodes'] as num?)?.toInt() ?? 0;
      if (imdbId == null || imdbId.isEmpty || aired <= 0) continue;
      final watched = <String>{};
      final seasons = item['seasons'] as List<dynamic>? ?? const [];
      for (final rawSeason in seasons) {
        if (rawSeason is! Map<String, dynamic>) continue;
        final season = (rawSeason['number'] as num?)?.toInt();
        if (season == null || season <= 0) continue;
        final episodes = rawSeason['episodes'] as List<dynamic>? ?? const [];
        for (final rawEpisode in episodes) {
          if (rawEpisode is! Map<String, dynamic>) continue;
          final episode = (rawEpisode['number'] as num?)?.toInt();
          if (episode != null && episode > 0) watched.add('$season-$episode');
        }
      }
      if (watched.length >= aired) result.add(imdbId.toLowerCase());
    }
    return result;
  }

  Future<List<dynamic>?> _fetchAllWatchedPages(
    String type, {
    String? extended,
    required int limit,
  }) async {
    final all = <dynamic>[];
    for (var page = 1; ; page++) {
      final response = await _authenticatedGet(
        '/sync/watched/$type?page=$page&limit=$limit'
        '${extended == null ? '' : '&extended=$extended'}',
      );
      if (response == null || response.statusCode != 200) {
        debugPrint(
          'Trakt: fetch watched $type failed (${response?.statusCode})',
        );
        return null;
      }
      try {
        final items = jsonDecode(response.body) as List<dynamic>;
        all.addAll(items);
        final pageCount = int.tryParse(
          response.headers['x-pagination-page-count'] ?? '',
        );
        if (items.isEmpty || (pageCount != null && page >= pageCount)) break;
        if (pageCount == null && items.length < limit) break;
      } catch (error) {
        debugPrint(
          'Trakt: fetch watched $type parse error (${error.runtimeType})',
        );
        return null;
      }
    }
    return all;
  }

  /// Fetch watched episode keys for a specific show.
  /// Uses the per-show progress endpoint (much smaller than /sync/watched/shows).
  /// Returns a set of `"season-episode"` strings (e.g. `"1-5"`) for completed episodes.
  Future<Set<String>> fetchWatchedShowEpisodes(String showId) async {
    return await fetchWatchedShowEpisodesOrNull(showId) ?? <String>{};
  }

  /// Failure-aware variant of [fetchWatchedShowEpisodes].
  ///
  /// An empty set is authoritative (the show has no completed episodes), while
  /// `null` means transport, status, or payload validation failed. Snapshot
  /// callers use that distinction to retain their last complete value instead
  /// of replacing it with a false empty history during an outage.
  Future<Set<String>?> fetchWatchedShowEpisodesOrNull(String showId) async {
    final response = await _authenticatedGet('/shows/$showId/progress/watched');
    if (response == null || response.statusCode != 200) {
      debugPrint(
        'Trakt: fetchWatchedShowEpisodes failed (${response?.statusCode})',
      );
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      final result = debugParseWatchedShowEpisodes(decoded);
      if (result == null) {
        debugPrint('Trakt: fetchWatchedShowEpisodes incomplete payload');
      }
      return result;
    } catch (error) {
      debugPrint(
        'Trakt: fetchWatchedShowEpisodes parse error '
        '(${error.runtimeType})',
      );
      return null;
    }
  }

  /// Strict parser for the per-show watched-progress response.
  ///
  /// Skipping malformed seasons/episodes would turn a truncated response into
  /// apparently authoritative history. Return `null` instead so callers can
  /// retain their last-good snapshot.
  @visibleForTesting
  static Set<String>? debugParseWatchedShowEpisodes(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final seasons = decoded['seasons'];
    if (seasons is! List<dynamic>) return null;

    final result = <String>{};
    for (final rawSeason in seasons) {
      if (rawSeason is! Map<String, dynamic>) return null;
      final seasonValue = rawSeason['number'];
      final episodes = rawSeason['episodes'];
      if (seasonValue is! num || episodes is! List<dynamic>) return null;
      final season = seasonValue.toInt();
      if (seasonValue != season || season < 0) return null;

      for (final rawEpisode in episodes) {
        if (rawEpisode is! Map<String, dynamic>) return null;
        final episodeValue = rawEpisode['number'];
        final completed = rawEpisode['completed'];
        if (episodeValue is! num || completed is! bool) return null;
        final episode = episodeValue.toInt();
        if (episodeValue != episode || episode <= 0) return null;
        if (completed) result.add('$season-$episode');
      }
    }
    return result;
  }

  /// Fetch the next episode to watch for a show.
  /// Returns (season, episode) or null if show is complete / not started / error.
  Future<({int season, int episode})?> fetchNextEpisode(String showId) async {
    final response = await _authenticatedGet('/shows/$showId/progress/watched');
    return _parseNextEpisode(response);
  }

  /// Parse a next_episode from a watched-progress API response.
  ({int season, int episode})? _parseNextEpisode(http.Response? response) {
    if (response == null || response.statusCode != 200) return null;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final nextEp = data['next_episode'] as Map<String, dynamic>?;
      if (nextEp == null) return null;

      final season = nextEp['season'] as int?;
      final number = nextEp['number'] as int?;
      if (season == null || number == null) return null;

      return (season: season, episode: number);
    } catch (error) {
      debugPrint('Trakt: next episode parse error (${error.runtimeType})');
      return null;
    }
  }

  /// Fetch playback progress for episodes of a specific show.
  /// Returns a map of `"season-episode"` → progress percentage (0-100).
  Future<Map<String, double>> fetchEpisodePlaybackProgress(
    String showImdbId,
  ) async {
    return await fetchEpisodePlaybackProgressOrNull(showImdbId) ??
        <String, double>{};
  }

  /// Failure-aware, pagination-complete variant of
  /// [fetchEpisodePlaybackProgress].
  ///
  /// Trakt paginates `/sync/playback/episodes`; publishing only its first page
  /// can silently erase checkpoints for shows on later pages. Every page must
  /// load and validate before this returns an authoritative map.
  Future<Map<String, double>?> fetchEpisodePlaybackProgressOrNull(
    String showImdbId,
  ) async {
    // Trakt caps explicitly paginated endpoints at 250. Request the applied
    // maximum rather than 1000 so a missing pagination header plus 250 items
    // is correctly recognized as potentially truncated, not a short page.
    const limit = 250;
    final result = <String, double>{};
    var page = 1;

    while (true) {
      final response = await _authenticatedGet(
        '/sync/playback/episodes?page=$page&limit=$limit',
      );
      if (response == null || response.statusCode != 200) {
        debugPrint(
          'Trakt: fetchEpisodePlaybackProgress failed '
          'page=$page (${response?.statusCode})',
        );
        return null;
      }

      try {
        final decoded = jsonDecode(response.body);
        final parsed = debugParseEpisodePlaybackProgress(decoded, showImdbId);
        if (parsed == null) {
          debugPrint('Trakt: episode playback incomplete payload page=$page');
          return null;
        }
        result.addAll(parsed);

        final items = decoded as List<dynamic>;
        final rawPageCount = response.headers['x-pagination-page-count'];
        final pageCount = rawPageCount == null
            ? null
            : int.tryParse(rawPageCount);
        if (rawPageCount != null && pageCount == null) {
          debugPrint('Trakt: episode playback invalid pagination metadata');
          return null;
        }
        if (pageCount != null) {
          // Trakt may report zero pages for an authoritative empty collection.
          if (pageCount == 0 && page == 1 && items.isEmpty) break;
          if (pageCount < page) {
            debugPrint('Trakt: episode playback invalid pagination metadata');
            return null;
          }
          if (page >= pageCount) break;
        } else {
          // Trakt can cap the applied page size below the requested limit, so
          // a non-empty "short" page does not prove completion. Only an empty
          // first page is self-authenticating without pagination headers.
          if (page == 1 && items.isEmpty) break;
          debugPrint('Trakt: episode playback pagination metadata missing');
          return null;
        }
        page++;
      } catch (error) {
        debugPrint(
          'Trakt: episode playback parse error (${error.runtimeType})',
        );
        return null;
      }
    }
    return result;
  }

  /// Strictly parse one playback page, filtering it to [showImdbId].
  @visibleForTesting
  static Map<String, double>? debugParseEpisodePlaybackProgress(
    Object? decoded,
    String showImdbId,
  ) {
    if (decoded is! List<dynamic>) return null;
    final target = showImdbId.trim().toLowerCase();
    if (target.isEmpty) return null;

    final result = <String, double>{};
    for (final rawItem in decoded) {
      if (rawItem is! Map<String, dynamic>) return null;
      final show = rawItem['show'];
      if (show is! Map<String, dynamic>) return null;
      final ids = show['ids'];
      if (ids is! Map<String, dynamic>) return null;
      final imdb = ids['imdb'];
      // IMDb can legitimately be absent for an unrelated Trakt item. It
      // cannot identify the target show, so it contributes nothing.
      if (imdb is! String || imdb.trim().toLowerCase() != target) continue;

      final episode = rawItem['episode'];
      final progressValue = rawItem['progress'];
      if (episode is! Map<String, dynamic> || progressValue is! num) {
        return null;
      }
      final seasonValue = episode['season'];
      final episodeValue = episode['number'];
      if (seasonValue is! num || episodeValue is! num) return null;
      final season = seasonValue.toInt();
      final number = episodeValue.toInt();
      final progress = progressValue.toDouble();
      if (seasonValue != season ||
          episodeValue != number ||
          season < 0 ||
          number <= 0 ||
          !progress.isFinite) {
        return null;
      }
      result['$season-$number'] = progress;
    }
    return result;
  }
}
