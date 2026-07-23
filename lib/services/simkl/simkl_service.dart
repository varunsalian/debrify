import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage_service.dart';
import 'simkl_constants.dart';

/// The user's Simkl relationship to a single title — mirrors
/// [TraktTitleStatus] but simpler: Simkl's watchlist model is one exclusive
/// status per item (not four independent Trakt-style flags: watchlist,
/// collection, watched, rating), so this is one nullable status string plus
/// a rating.
class SimklTitleStatus {
  /// One of `plantowatch`/`watching`/`hold`/`completed`/`dropped`, or null if
  /// the item isn't in any Simkl list.
  final String? currentStatus;

  /// The user's 1–10 Simkl rating, or null if unrated.
  final int? rating;

  const SimklTitleStatus({this.currentStatus, this.rating});
}

/// Service for Simkl OAuth (PIN flow) authentication.
///
/// Deliberately separate from [TraktService] rather than sharing an
/// interface — Trakt and Simkl run fully in parallel (both can scrobble/sync
/// at once), and keeping them independent means nothing here can regress
/// Trakt's already-working auth/scrobble flow.
///
/// Simkl's PIN-issued tokens don't expire and have no refresh token (per
/// Simkl's docs they're valid ~5 years, until the user revokes the app), so
/// unlike Trakt there's no refreshAccessToken()/expiry bookkeeping here.
class SimklService {
  static final SimklService _instance = SimklService._internal();
  factory SimklService() => _instance;
  SimklService._internal();

  static SimklService get instance => _instance;

  // ── Library-status cache ────────────────────────────────────────────────────
  // A single `/sync/all-items/all/all` call already tags every item with its
  // own status+rating, so unlike Trakt (which fetches watchlist/collection/
  // ratings separately) one cached fetch covers every detail-page lookup.
  // Internal duplicate of Trakt's own caching helper, not shared — see the
  // class doc on why Trakt and Simkl stay fully independent. Only one value
  // is ever cached (the whole library snapshot), so this is two plain fields
  // rather than a keyed map.
  Map<String, dynamic>? _libCacheData;
  DateTime? _libCacheAt;
  static const Duration _libTtl = Duration(seconds: 45);

  // Bumped on every invalidation (logout, or a successful write) so a fetch
  // already in flight when a write lands can't clobber the fresher cache
  // entry with its own stale, pre-write result.
  int _libCacheGeneration = 0;

  void _invalidateLibraryCache() {
    _libCacheData = null;
    _libCacheAt = null;
    _libCacheGeneration++;
  }

  Future<Map<String, dynamic>?> _cachedLibAllAll() async {
    final at = _libCacheAt;
    if (at != null && DateTime.now().difference(at) < _libTtl) {
      return _libCacheData;
    }
    final generation = _libCacheGeneration;
    final data = await fetchAllItemsOrNull('all', 'all');
    // Only cache authoritative results, and only if no write invalidated the
    // cache while this fetch was in flight — a transient failure or a
    // superseded fetch shouldn't poison/clobber the cache.
    if (data != null && generation == _libCacheGeneration) {
      _libCacheData = data;
      _libCacheAt = DateTime.now();
    }
    return data;
  }

  /// The user's relationship to a single title: which watchlist status (if
  /// any) it's in, and their rating. Backed by one cached `all/all` library
  /// fetch, scanned across all three content-type buckets (an anime title
  /// may live under `anime` rather than `movies`/`shows`).
  ///
  /// Returns null when the answer can't be trusted (disconnected, or the
  /// library fetch failed) so callers keep whatever they last showed instead
  /// of wrongly rendering "no status". A genuine "not in any list" is a
  /// non-null status with a null [SimklTitleStatus.currentStatus].
  Future<SimklTitleStatus?> fetchTitleStatus(String imdbId) async {
    if (!await isAuthenticated()) return null;
    try {
      final data = await _cachedLibAllAll();
      if (data == null) return null;
      for (final bucketKey in const ['movies', 'shows', 'anime']) {
        final items = (data[bucketKey] as List<dynamic>?) ?? const [];
        for (final raw in items) {
          if (raw is! Map<String, dynamic>) continue;
          final content =
              (raw['show'] ?? raw['movie']) as Map<String, dynamic>?;
          final ids = content?['ids'] as Map<String, dynamic>?;
          if (ids?['imdb'] == imdbId) {
            // Ratings are documented 1-10 — treat a 0 (if Simkl ever sends
            // one for "unrated" instead of omitting the field) the same as
            // absent, rather than showing a bogus "0/10".
            final ratingNum = (raw['user_rating'] as num?)?.toInt();
            return SimklTitleStatus(
              currentStatus: raw['status'] as String?,
              rating: (ratingNum != null && ratingNum > 0) ? ratingNum : null,
            );
          }
        }
      }
      return const SimklTitleStatus(); // Not in any list — genuine, cacheable.
    } catch (e) {
      debugPrint('Simkl: fetchTitleStatus failed: $e');
      return null;
    }
  }

  /// Internal `movie`/`series` → Simkl's plural type key.
  String _typeKey(String type) => type == 'series' ? 'shows' : 'movies';

  /// True when a write's [result] (from [_postOrNull]) is a successful,
  /// well-formed response AND Simkl's `not_found[typeKey]` list is empty —
  /// i.e. the item (show/movie) was actually matched server-side, not just
  /// that the HTTP call itself succeeded. Shared by every write method below
  /// so none of them can silently report success on an unmatched id.
  ///
  /// Defensively typed rather than chained casts, so an unexpected
  /// `not_found` shape (if Simkl's response ever differs from the documented
  /// one) can't throw — it's treated as "nothing reported not-found" rather
  /// than crashing the caller.
  ///
  /// Only catches a show/movie-level mismatch. For the episode-scoped writes
  /// (markEpisodeWatched/Unwatched, rateEpisode) this can't detect an
  /// unrecognized season/episode number within an otherwise-matched show —
  /// Simkl's `not_found` isn't documented to report at that granularity, so
  /// an episode-level false-success is a known limitation, not something
  /// this check can close.
  bool _wasMatched(dynamic result, String typeKey) {
    if (result is! Map) return false;
    final notFoundBlock = result['not_found'];
    if (notFoundBlock is! Map) return true;
    final notFound = notFoundBlock[typeKey];
    return notFound is! List || notFound.isEmpty;
  }

  /// Common headers for authenticated Simkl API requests.
  Map<String, String> _apiHeaders({String? accessToken}) => {
    'Content-Type': 'application/json',
    'simkl-api-key': kSimklClientId,
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };

  /// Check if the user is authenticated (has a stored access token).
  /// Simkl tokens don't expire, so unlike Trakt there's no refresh check.
  Future<bool> isAuthenticated() async {
    final token = await StorageService.getSimklAccessToken();
    return token != null && token.isNotEmpty;
  }

  /// Revoke local auth state. Simkl has no documented revoke endpoint for
  /// PIN-issued tokens, so this only clears local storage.
  Future<void> logout() async {
    await StorageService.clearSimklAuth();
    // Drop cached library state so a later sign-in (possibly a different
    // account) never reads the previous user's watchlist/ratings.
    _invalidateLibraryCache();
  }

  /// Get the stored username, if known.
  Future<String?> getUsername() async {
    return StorageService.getSimklUsername();
  }

  // ============================================================================
  // PIN Flow
  // ============================================================================

  /// Request a PIN for the device-code-style OAuth flow.
  /// Returns the parsed JSON response on success, null on failure.
  Future<Map<String, dynamic>?> requestPin() async {
    try {
      final uri = Uri.parse(
        kSimklPinUrl,
      ).replace(queryParameters: {'client_id': kSimklClientId});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      debugPrint(
        'Simkl: PIN request failed (${response.statusCode}): ${response.body}',
      );
      return null;
    } catch (e) {
      debugPrint('Simkl: PIN request error: $e');
      return null;
    }
  }

  /// Poll for PIN authorization status.
  /// Returns null on success (token stored), or an error string:
  /// "authorization_pending", "slow_down", "network_error" (transient — safe
  /// to retry), or "error" (fatal).
  Future<String?> pollPin(String userCode) async {
    try {
      final uri = Uri.parse(
        simklPinPollUrl(userCode),
      ).replace(queryParameters: {'client_id': kSimklClientId});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final result = data['result'] as String?;

        if (result == 'OK') {
          final accessToken = data['access_token'] as String?;
          if (accessToken == null || accessToken.isEmpty) return 'error';
          await StorageService.setSimklAccessToken(accessToken);
          await _fetchAndStoreUsername(accessToken);
          return null; // Success
        }

        final message = (data['message'] as String?)?.toLowerCase() ?? '';
        if (message.contains('slow down')) return 'slow_down';
        return 'authorization_pending';
      }

      debugPrint(
        'Simkl: PIN poll failed (${response.statusCode}): ${response.body}',
      );
      return 'error';
    } catch (e) {
      // Network timeout, socket exception, etc. — transient, safe to retry
      debugPrint('Simkl: PIN poll network error: $e');
      return 'network_error';
    }
  }

  /// Best-effort username lookup after a successful PIN exchange. Simkl's
  /// exact response shape for the display name isn't nailed down from docs
  /// alone, so this tries the field paths seen in third-party clients and
  /// simply leaves the username unset (not fatal — the settings page falls
  /// back to "Logged in") if none match.
  Future<void> _fetchAndStoreUsername(String accessToken) async {
    try {
      final response = await http.get(
        Uri.parse('$kSimklApiBaseUrl/users/settings'),
        headers: _apiHeaders(accessToken: accessToken),
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;
      final account = data['account'] as Map<String, dynamic>?;
      final name =
          (user?['name'] as String?) ?? (account?['name'] as String?);
      if (name != null && name.isNotEmpty) {
        await StorageService.setSimklUsername(name);
      }
    } catch (e) {
      debugPrint('Simkl: username lookup failed: $e');
    }
  }

  // ============================================================================
  // Discover / list-browsing fetches
  // ============================================================================

  /// client_id/app-name/app-version — documented as required query params on
  /// every Simkl request beyond the PIN flow.
  Map<String, String> _requiredParams() => {
    'client_id': kSimklClientId,
    'app-name': kSimklAppName,
    'app-version': kSimklAppVersion,
  };

  Uri _apiUri(String path, [Map<String, String>? extra]) => Uri.parse(
    '$kSimklApiBaseUrl$path',
  ).replace(queryParameters: {..._requiredParams(), ...?extra});

  /// Shared GET scaffold for every fetch below: timeout, status check, JSON
  /// decode, catch-and-null. Returns the decoded body (object or list) or
  /// null on any failure.
  Future<dynamic> _getOrNull(
    Uri uri, {
    required Map<String, String> headers,
    required String label,
  }) async {
    try {
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('Simkl: $label failed (${response.statusCode})');
        return null;
      }
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Simkl: $label error: $e');
      return null;
    }
  }

  /// Fetch the user's library items for one type+status bucket via
  /// `GET /sync/all-items/{type}/{status}`. [type] is
  /// `movies`/`shows`/`anime`/`all` (Simkl's own combined value, returning
  /// all three buckets in one response); [status] is
  /// `plantowatch`/`watching`/`hold`/`completed`/`dropped`. Returns null when
  /// not authenticated or on any failure, so callers can tell "nothing to
  /// show yet" from "the bucket is genuinely empty".
  Future<Map<String, dynamic>?> fetchAllItemsOrNull(
    String type,
    String status,
  ) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return null;
    final uri = _apiUri('/sync/all-items/$type/$status', {'extended': 'full'});
    final data = await _getOrNull(
      uri,
      headers: _apiHeaders(accessToken: token),
      label: 'fetchAllItems $type/$status',
    );
    return data is Map<String, dynamic> ? data : null;
  }

  /// Fetch the user's rated items for one content type via
  /// `GET /sync/ratings/{type}/{rating}`. Sends the explicit 1–10 comma list
  /// (documented to work) rather than an unconfirmed range shorthand.
  Future<Map<String, dynamic>?> fetchRatingsOrNull(String type) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return null;
    final uri = _apiUri('/sync/ratings/$type/1,2,3,4,5,6,7,8,9,10', {
      'extended': 'full',
    });
    final data = await _getOrNull(
      uri,
      headers: _apiHeaders(accessToken: token),
      label: 'fetchRatings $type',
    );
    return data is Map<String, dynamic> ? data : null;
  }

  /// Public (no-auth) GET against any Simkl API or CDN URL — used for
  /// trending/best/genre/premiere endpoints, none of which need a token.
  /// [url] may be a full URL (the CDN trending file) or built via
  /// `'$kSimklApiBaseUrl/tv/best/all'`-style paths. Returns the decoded JSON
  /// body (object or list) or null on failure.
  Future<dynamic> fetchPublicOrNull(String url) async {
    final parsed = Uri.parse(url);
    final uri = parsed.replace(
      queryParameters: {...parsed.queryParameters, ..._requiredParams()},
    );
    return _getOrNull(
      uri,
      headers: {'User-Agent': 'Debrify'},
      label: 'public fetch $url',
    );
  }

  // ============================================================================
  // Write actions (watchlist / history / ratings)
  // ============================================================================

  /// Shared POST scaffold: timeout, status check (200 or 201 — Simkl's
  /// add-to-list returns 201), JSON decode, catch-and-null.
  Future<dynamic> _postOrNull(
    String path,
    Map<String, dynamic> body, {
    required String token,
    required String label,
  }) async {
    try {
      final uri = _apiUri(path);
      final response = await http
          .post(
            uri,
            headers: _apiHeaders(accessToken: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint(
          'Simkl: $label failed (${response.statusCode}): ${response.body}',
        );
        return null;
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    } catch (e) {
      debugPrint('Simkl: $label error: $e');
      return null;
    }
  }

  /// Move a title into a watchlist status (`plantowatch`/`watching`/`hold`/
  /// `completed`/`dropped`) via `POST /sync/add-to-list`. Simkl has no
  /// "remove from list" endpoint — moving is the only operation; there's no
  /// way to fully delist an item back to "no status".
  Future<bool> addToList(String imdbId, String type, String status) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final typeKey = _typeKey(type);
    final result = await _postOrNull(
      '/sync/add-to-list',
      {
        typeKey: [
          {
            'to': status,
            'ids': {'imdb': imdbId},
          },
        ],
      },
      token: token,
      label: 'addToList $typeKey→$status',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Rate a title 1–10 via `POST /sync/ratings`.
  Future<bool> rateItem(String imdbId, String type, int rating) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final typeKey = _typeKey(type);
    final result = await _postOrNull(
      '/sync/ratings',
      {
        typeKey: [
          {
            'rating': rating,
            'ids': {'imdb': imdbId},
          },
        ],
      },
      token: token,
      label: 'rateItem $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Clear a title's rating via `POST /sync/ratings/remove`.
  Future<bool> removeRating(String imdbId, String type) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final typeKey = _typeKey(type);
    final result = await _postOrNull(
      '/sync/ratings/remove',
      {
        typeKey: [
          {
            'ids': {'imdb': imdbId},
          },
        ],
      },
      token: token,
      label: 'removeRating $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Mark a whole title (movie, or every aired episode of a show) watched via
  /// `POST /sync/history`.
  Future<bool> markWatched(String imdbId, String type) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final typeKey = _typeKey(type);
    final result = await _postOrNull(
      '/sync/history',
      {
        typeKey: [
          {'ids': {'imdb': imdbId}},
        ],
      },
      token: token,
      label: 'markWatched $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Unmark a whole title via `POST /sync/history/remove`.
  Future<bool> markUnwatched(String imdbId, String type) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final typeKey = _typeKey(type);
    final result = await _postOrNull(
      '/sync/history/remove',
      {
        typeKey: [
          {'ids': {'imdb': imdbId}},
        ],
      },
      token: token,
      label: 'markUnwatched $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Mark a single episode watched via `POST /sync/history` with the nested
  /// `seasons[].episodes[]` shape.
  Future<bool> markEpisodeWatched(
    String showImdbId,
    int season,
    int episode,
  ) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final result = await _postOrNull(
      '/sync/history',
      {
        'shows': [_episodeRef(showImdbId, season, episode)],
      },
      token: token,
      label: 'markEpisodeWatched',
    );
    if (!_wasMatched(result, 'shows')) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Unmark a single episode via `POST /sync/history/remove`.
  Future<bool> markEpisodeUnwatched(
    String showImdbId,
    int season,
    int episode,
  ) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final result = await _postOrNull(
      '/sync/history/remove',
      {
        'shows': [_episodeRef(showImdbId, season, episode)],
      },
      token: token,
      label: 'markEpisodeUnwatched',
    );
    if (!_wasMatched(result, 'shows')) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Rate a single episode 1–10 via `POST /sync/ratings`. The nested
  /// `seasons[].episodes[].rating` shape mirrors history's episode nesting —
  /// not separately confirmed from docs, flagged for a live-test check.
  Future<bool> rateEpisode(
    String showImdbId,
    int season,
    int episode,
    int rating,
  ) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final result = await _postOrNull(
      '/sync/ratings',
      {
        'shows': [
          {
            'ids': {'imdb': showImdbId},
            'seasons': [
              {
                'number': season,
                'episodes': [
                  {'number': episode, 'rating': rating},
                ],
              },
            ],
          },
        ],
      },
      token: token,
      label: 'rateEpisode',
    );
    if (!_wasMatched(result, 'shows')) return false;
    _invalidateLibraryCache();
    return true;
  }

  /// Builds the `{ids, seasons: [{number, episodes: [{number}]}]}` show
  /// reference shared by every episode-scoped write above.
  Map<String, dynamic> _episodeRef(String showImdbId, int season, int episode) {
    return {
      'ids': {'imdb': showImdbId},
      'seasons': [
        {
          'number': season,
          'episodes': [
            {'number': episode},
          ],
        },
      ],
    };
  }
}
