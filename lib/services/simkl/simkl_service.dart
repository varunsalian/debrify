import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/profiles/profile_policy.dart';
import '../episode_tracker_snapshot_revision.dart';
import '../profiles/profile_async_authorization.dart';
import '../profiles/profile_runtime.dart';
import '../storage_service.dart';
import 'simkl_calendar_service.dart';
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

class _SimklPinAuthorization {
  final ProfileAsyncAuthorization authorization;
  final DateTime expiresAt;

  const _SimklPinAuthorization({
    required this.authorization,
    required this.expiresAt,
  });
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
  final Map<String, _SimklPinAuthorization> _pinAuthorizations = {};

  void _invalidateLibraryCache() {
    _libCacheData = null;
    _libCacheAt = null;
    _libCacheGeneration++;
  }

  // ── Paused-playback-sessions cache ──────────────────────────────────────────
  // The whole `/sync/playback/episodes` list is account-wide, and a single
  // detail open reads it 2-3 times (episode progress bars + the resume-label
  // loader + a Resume press). Cache the raw list briefly AND coalesce
  // concurrent readers so one detail open costs one fetch. Invalidated on any
  // scrobble write (which is exactly what changes these sessions), so the
  // post-playback refresh always re-fetches.
  List<dynamic>? _playbackCacheData;
  DateTime? _playbackCacheAt;
  Future<List<dynamic>?>? _playbackInFlight;
  // The generation the in-flight fetch was started at — a reader that arrives
  // after a scrobble write invalidated the cache must NOT join a fetch started
  // before it (that fetch carries pre-write, stale sessions); it starts fresh.
  int _playbackInFlightGeneration = -1;
  int _playbackCacheGeneration = 0;
  static const Duration _playbackTtl = Duration(seconds: 30);

  // Parallel cache for `/sync/playback/movies` — same shape/rules as the
  // episode cache above, sharing the one generation counter so a scrobble
  // write invalidates both at once.
  List<dynamic>? _moviePlaybackCacheData;
  DateTime? _moviePlaybackCacheAt;
  Future<List<dynamic>?>? _moviePlaybackInFlight;
  int _moviePlaybackInFlightGeneration = -1;

  void _invalidatePlaybackCache() {
    _playbackCacheData = null;
    _playbackCacheAt = null;
    _moviePlaybackCacheData = null;
    _moviePlaybackCacheAt = null;
    _playbackCacheGeneration++;
  }

  /// Clears every account-scoped process cache at a profile boundary.
  void resetProfileScope() {
    _invalidateLibraryCache();
    _invalidatePlaybackCache();
    _pinAuthorizations.clear();
    SimklCalendarService.instance.invalidate();
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

  /// The user's full library snapshot (`/sync/all-items/all/all`), where every
  /// item is tagged with its own `status` and `user_rating`. Backed by the same
  /// 45s cache the detail-page status lookups use, so callers that need the
  /// whole library (e.g. the Simkl calendar's intersection) share one fetch
  /// instead of issuing their own. Null when disconnected or the fetch failed
  /// (never a poisoned empty), so callers can distinguish "failed" from a
  /// genuinely empty library.
  Future<Map<String, dynamic>?> fetchLibrarySnapshotOrNull() =>
      _cachedLibAllAll();

  /// Completed movies and series in one minimal bulk response. This omits
  /// `extended=full`: poster badges need only IDs and title status.
  Future<({Set<String> movies, Set<String> series})?>
  fetchCompletedTitleIds() async {
    final token = await StorageService.getSimklAccessToken();
    // Disconnected is a successful empty snapshot, not a transient failure.
    // This lets consumers clear badges belonging to the previous account while
    // still preserving their last snapshot when an authenticated request fails.
    if (token == null || token.isEmpty) {
      return (movies: <String>{}, series: <String>{});
    }
    final data = await _getOrNull(
      _apiUri('/sync/all-items/all/completed'),
      headers: _apiHeaders(accessToken: token),
      label: 'fetchCompletedTitleIds',
    );
    if (data is! Map<String, dynamic>) return null;
    Set<String> idsFor(String bucket) {
      final result = <String>{};
      for (final raw in data[bucket] as List<dynamic>? ?? const []) {
        if (raw is! Map<String, dynamic>) continue;
        final content = (raw['movie'] ?? raw['show']) as Map<String, dynamic>?;
        final ids = content?['ids'] as Map<String, dynamic>?;
        final imdb = (ids?['imdb'] as String?)?.trim().toLowerCase();
        if (imdb != null && imdb.isNotEmpty) result.add(imdb);
      }
      return result;
    }

    return (movies: idsFor('movies'), series: idsFor('shows'));
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
    } catch (error) {
      debugPrint('Simkl: fetchTitleStatus failed (${error.runtimeType})');
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
    // account) never reads the previous user's watchlist/ratings — including
    // the derived calendar (mirrors TraktService clearing TraktCalendarService).
    _invalidateLibraryCache();
    SimklCalendarService.instance.invalidate();
    StorageService.movieFinishedRevision.value++;
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
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      final uri = Uri.parse(
        kSimklPinUrl,
      ).replace(queryParameters: {'client_id': kSimklClientId});
      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final userCode = data['user_code'] as String?;
        if (authorization != null && userCode != null && userCode.isNotEmpty) {
          _prunePinAuthorizations();
          final seconds = (data['expires_in'] as int? ?? 900).clamp(1, 1800);
          _pinAuthorizations[userCode] = _SimklPinAuthorization(
            authorization: authorization,
            expiresAt: DateTime.now().add(Duration(seconds: seconds)),
          );
        }
        return data;
      }

      debugPrint('Simkl: PIN request failed (${response.statusCode})');
      return null;
    } catch (error) {
      debugPrint('Simkl: PIN request error (${error.runtimeType})');
      return null;
    }
  }

  /// Poll for PIN authorization status.
  /// Returns null on success (token stored), or an error string:
  /// "authorization_pending", "slow_down", "network_error" (transient — safe
  /// to retry), or "error" (fatal).
  Future<String?> pollPin(String userCode) async {
    try {
      final attempt = _pinAuthorizations[userCode];
      if (ProfileRuntime.isInitialized &&
          ProfileRuntime.isProfileCommitted &&
          (attempt == null || attempt.expiresAt.isBefore(DateTime.now()))) {
        _pinAuthorizations.remove(userCode);
        return 'access_denied';
      }
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
          _pinAuthorizations.remove(userCode);
          Future<void> commit() async {
            await StorageService.setSimklAccessToken(accessToken);
            await _fetchAndStoreUsername(accessToken);
            StorageService.movieFinishedRevision.value++;
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

        final message = (data['message'] as String?)?.toLowerCase() ?? '';
        if (message.contains('slow down')) return 'slow_down';
        return 'authorization_pending';
      }

      debugPrint('Simkl: PIN poll failed (${response.statusCode})');
      return 'error';
    } catch (error) {
      // Network timeout, socket exception, etc. — transient, safe to retry
      debugPrint('Simkl: PIN poll network error (${error.runtimeType})');
      return 'network_error';
    }
  }

  void _prunePinAuthorizations() {
    final now = DateTime.now();
    _pinAuthorizations.removeWhere((_, value) => value.expiresAt.isBefore(now));
    while (_pinAuthorizations.length >= 8) {
      _pinAuthorizations.remove(_pinAuthorizations.keys.first);
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
      final name = (user?['name'] as String?) ?? (account?['name'] as String?);
      if (name != null && name.isNotEmpty) {
        await StorageService.setSimklUsername(name);
      }
    } catch (error) {
      debugPrint('Simkl: username lookup failed (${error.runtimeType})');
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
    } catch (error) {
      debugPrint('Simkl: $label error (${error.runtimeType})');
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

  /// The user's "watching" TV shows with Simkl's server-computed `next_to_watch`
  /// (via `next_watch_info=yes`) — powers the Continue Watching "up next"
  /// entries (the next episode of a show you're mid-way through but haven't
  /// paused). Deliberately no `extended=full`: the per-show next-watch fields +
  /// the show summary object are enough, and `full` would bloat the response
  /// with the whole watched-episode list. Returns the raw `shows` list (empty
  /// when the list is genuinely empty), or null on failure / when disconnected.
  Future<List<dynamic>?> fetchUpNextShowsOrNull() async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return null;
    final uri = _apiUri('/sync/all-items/shows/watching', {
      'next_watch_info': 'yes',
    });
    final data = await _getOrNull(
      uri,
      headers: _apiHeaders(accessToken: token),
      label: 'upNext shows',
    );
    if (data is! Map<String, dynamic>) return null;
    final shows = data['shows'];
    return shows is List ? shows : const [];
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
  /// add-to-list returns 201), JSON decode, catch-and-null. [body] may be a
  /// Map or a List (the `/sync/watched` endpoint takes a top-level array).
  Future<dynamic> _postOrNull(
    String path,
    Object body, {
    required String token,
    required String label,
    Map<String, String>? query,
  }) async {
    try {
      final uri = _apiUri(path, query);
      final response = await http
          .post(
            uri,
            headers: _apiHeaders(accessToken: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 201) {
        debugPrint('Simkl: $label failed (${response.statusCode})');
        return null;
      }
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    } catch (error) {
      debugPrint('Simkl: $label error (${error.runtimeType})');
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
    // Moving to or away from Completed changes the effective watched set.
    // We do not know the previous status here, so every successful move must
    // invalidate; unlike ratings, any list move can remove an existing tick.
    StorageService.movieFinishedRevision.value++;
    if (type == 'series') {
      EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
    }
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
          {
            'ids': {'imdb': imdbId},
          },
        ],
      },
      token: token,
      label: 'markWatched $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    StorageService.movieFinishedRevision.value++;
    if (type == 'series') {
      EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
    }
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
          {
            'ids': {'imdb': imdbId},
          },
        ],
      },
      token: token,
      label: 'markUnwatched $typeKey',
    );
    if (!_wasMatched(result, typeKey)) return false;
    _invalidateLibraryCache();
    StorageService.movieFinishedRevision.value++;
    if (type == 'series') {
      EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
    }
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
    EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', showImdbId);
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
    EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', showImdbId);
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

  // ============================================================================
  // Scrobbling (real-time playback)
  // ============================================================================

  /// Report playback started/resumed. [progress] is 0-100.
  Future<bool> scrobbleStart(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) {
    return _scrobble(
      '/scrobble/start',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  /// Report playback paused — Simkl saves the progress as a resumable
  /// playback session any signed-in device can fetch.
  Future<bool> scrobblePause(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) {
    return _scrobble(
      '/scrobble/pause',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  /// Finalize the playback session. Simkl decides server-side: ≥80% → mark
  /// watched, <80% → save as a paused playback.
  Future<bool> scrobbleStop(
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) {
    return _scrobble(
      '/scrobble/stop',
      imdbId,
      progress,
      season: season,
      episode: episode,
    );
  }

  /// Shared scrobble POST — mirrors TraktService._scrobble's guards: a
  /// non-positive season/episode is treated as absent, and a request with
  /// exactly ONE of them is refused (it would corrupt into a movie-shaped
  /// body carrying a show id).
  Future<bool> _scrobble(
    String path,
    String imdbId,
    double progress, {
    int? season,
    int? episode,
  }) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final s = (season != null && season <= 0) ? null : season;
    final e = (episode != null && episode <= 0) ? null : episode;
    if ((s == null) != (e == null)) {
      debugPrint('Simkl: scrobble refused — season/episode mismatch');
      return false;
    }
    final Map<String, dynamic> body = s != null
        ? {
            'show': {
              'ids': {'imdb': imdbId},
            },
            'episode': {'season': s, 'number': e},
            'progress': progress,
          }
        : {
            'movie': {
              'ids': {'imdb': imdbId},
            },
            'progress': progress,
          };
    final result = await _postOrNull(
      path,
      body,
      token: token,
      label: 'scrobble $path',
    );
    // Any scrobble write changes the account's paused sessions — drop the
    // read cache so a later resume/progress read reflects it.
    if (result != null) {
      _invalidatePlaybackCache();
      if (s != null && e != null) {
        EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
      }
    }
    return result != null;
  }

  // ============================================================================
  // Playback / watched reads (resume + episode progress bars)
  // ============================================================================

  /// Raw paused-playback sessions for episodes, or null on failure. Cached for
  /// [_playbackTtl] and coalesced across concurrent callers, so a detail open's
  /// several readers share a single fetch.
  Future<List<dynamic>?> _fetchEpisodePlaybackSessions() async {
    final at = _playbackCacheAt;
    if (at != null && DateTime.now().difference(at) < _playbackTtl) {
      return _playbackCacheData;
    }
    // Only join an in-flight fetch started at the current generation — a fetch
    // that predates a scrobble-write invalidation would hand back stale data.
    final inFlight = _playbackInFlight;
    if (inFlight != null &&
        _playbackInFlightGeneration == _playbackCacheGeneration) {
      return inFlight;
    }
    final future = _loadEpisodePlaybackSessions();
    _playbackInFlight = future;
    _playbackInFlightGeneration = _playbackCacheGeneration;
    try {
      return await future;
    } finally {
      // Don't clear a newer fetch that may have replaced this one mid-flight.
      if (identical(_playbackInFlight, future)) _playbackInFlight = null;
    }
  }

  Future<List<dynamic>?> _loadEpisodePlaybackSessions() async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return null;
    final generation = _playbackCacheGeneration;
    final data = await _getOrNull(
      _apiUri('/sync/playback/episodes'),
      headers: _apiHeaders(accessToken: token),
      label: 'playback episodes',
    );
    final list = data is List ? data : null;
    // Only cache an authoritative result that wasn't superseded by a scrobble
    // write while this fetch was in flight.
    if (list != null && generation == _playbackCacheGeneration) {
      _playbackCacheData = list;
      _playbackCacheAt = DateTime.now();
    }
    return list;
  }

  /// Coerce a decoded JSON value to a num without ever throwing — accepts a
  /// real number or a numeric string ("1"), else null. Used for every leaf
  /// numeric field of a playback session so a wrong-typed field degrades to
  /// "skip this session" instead of a CastError escaping the Play path.
  static num? _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }

  /// The show+episode+progress of one playback session, or null when the
  /// session is malformed / not for [showImdbId]. Central so both readers
  /// parse identically and neither can throw.
  ({int season, int episode, double? progress})? _parseEpisodeSession(
    dynamic raw,
    String showImdbId,
  ) {
    if (raw is! Map) return null;
    final show = raw['show'];
    if (show is! Map) return null;
    final ids = show['ids'];
    if (ids is! Map || ids['imdb'] != showImdbId) return null;
    final ep = raw['episode'];
    if (ep is! Map) return null;
    final season = _asNum(ep['season'])?.toInt();
    final number = _asNum(ep['number'])?.toInt();
    if (season == null || number == null) return null;
    return (
      season: season,
      episode: number,
      progress: _asNum(raw['progress'])?.toDouble(),
    );
  }

  /// In-progress (paused) episode percents for one show, keyed
  /// `'$season-$episode'` → 0-100. Empty map on failure — mirrors
  /// TraktService.fetchEpisodePlaybackProgress's contract. Throw-free: a
  /// malformed session is skipped, not fatal.
  Future<Map<String, double>> fetchEpisodePlaybackProgress(
    String showImdbId,
  ) async {
    final sessions = await _fetchEpisodePlaybackSessions();
    if (sessions == null) return {};
    final out = <String, double>{};
    for (final raw in sessions) {
      final parsed = _parseEpisodeSession(raw, showImdbId);
      final progress = parsed?.progress;
      if (parsed == null || progress == null) continue;
      out['${parsed.season}-${parsed.episode}'] = progress.clamp(0.0, 100.0);
    }
    return out;
  }

  /// The show's most recently paused episode (by `paused_at`) — the resume
  /// target for the detail page's Play button. Null when the show has no
  /// well-formed paused session (or on failure). Only well-formed sessions are
  /// selection candidates, so a malformed newest session never shadows a valid
  /// older one, and the whole path is throw-free.
  Future<({int season, int episode, double? progress})?>
  fetchShowPlaybackSelection(String showImdbId) async {
    final sessions = await _fetchEpisodePlaybackSessions();
    if (sessions == null) return null;
    ({int season, int episode, double? progress})? best;
    DateTime? bestAt;
    var haveBest = false;
    for (final raw in sessions) {
      final parsed = _parseEpisodeSession(raw, showImdbId);
      if (parsed == null) continue;
      final rawAt = (raw as Map)['paused_at'];
      final at = rawAt is String ? DateTime.tryParse(rawAt) : null;
      // A session without a parseable timestamp still beats no session.
      if (!haveBest || (at != null && (bestAt == null || at.isAfter(bestAt)))) {
        best = parsed;
        bestAt = at;
        haveBest = true;
      }
    }
    return best;
  }

  /// The next unwatched episode of a show, from Simkl's server-computed
  /// `next_to_watch` (watched-progress based, via `next_watch_info=yes`).
  /// Returns null when the show isn't in the 'watching' list, has nothing left
  /// (completed / `next_to_watch` null), or its `next_to_watch` is an anime-style
  /// absolute number (no season) rather than `SxxExx`. This is the series-resume
  /// FALLBACK used when a show has no paused playback session — so a series
  /// watched up to E3 on another device resumes at E4, not the default S01E01.
  Future<({int season, int episode})?> fetchNextToWatch(
    String showImdbId,
  ) async {
    final shows = await fetchUpNextShowsOrNull();
    if (shows == null) return null;
    for (final raw in shows) {
      if (raw is! Map) continue;
      final show = raw['show'];
      final ids = show is Map ? show['ids'] : null;
      if (ids is! Map || ids['imdb'] != showImdbId) continue;
      return parseSimklEpisodeCode(raw['next_to_watch']);
    }
    return null;
  }

  /// Parse a Simkl `SxxExx` episode code (e.g. `next_to_watch`'s `"S02E06"`)
  /// into season/episode. Returns null for anything that isn't `SxxExx` — a null
  /// value, or an anime-style absolute code (`"E148"`, no season) the app's IMDb
  /// S/E model can't place. Shared by the Continue Watching up-next builder and
  /// the series-resume fallback so they never disagree on the parse rule.
  static ({int season, int episode})? parseSimklEpisodeCode(dynamic value) {
    if (value is! String) return null;
    final m = RegExp(r'^[Ss](\d+)[Ee](\d+)$').firstMatch(value.trim());
    if (m == null) return null;
    final s = int.tryParse(m.group(1)!);
    final e = int.tryParse(m.group(2)!);
    if (s == null || e == null) return null;
    return (season: s, episode: e);
  }

  /// Raw paused-playback sessions for movies — parallel to
  /// [_fetchEpisodePlaybackSessions] (same cache/coalescing rules, shared
  /// generation counter).
  Future<List<dynamic>?> _fetchMoviePlaybackSessions() async {
    final at = _moviePlaybackCacheAt;
    if (at != null && DateTime.now().difference(at) < _playbackTtl) {
      return _moviePlaybackCacheData;
    }
    final inFlight = _moviePlaybackInFlight;
    if (inFlight != null &&
        _moviePlaybackInFlightGeneration == _playbackCacheGeneration) {
      return inFlight;
    }
    final future = _loadMoviePlaybackSessions();
    _moviePlaybackInFlight = future;
    _moviePlaybackInFlightGeneration = _playbackCacheGeneration;
    try {
      return await future;
    } finally {
      if (identical(_moviePlaybackInFlight, future)) {
        _moviePlaybackInFlight = null;
      }
    }
  }

  Future<List<dynamic>?> _loadMoviePlaybackSessions() async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return null;
    final generation = _playbackCacheGeneration;
    final data = await _getOrNull(
      _apiUri('/sync/playback/movies'),
      headers: _apiHeaders(accessToken: token),
      label: 'playback movies',
    );
    final list = data is List ? data : null;
    if (list != null && generation == _playbackCacheGeneration) {
      _moviePlaybackCacheData = list;
      _moviePlaybackCacheAt = DateTime.now();
    }
    return list;
  }

  /// The RAW account-wide paused-playback session lists (cached 30s, coalesced,
  /// invalidated on any scrobble write). Null on failure / when disconnected.
  /// The per-title resume lookups above filter these to one imdb id; the
  /// Continue Watching row needs the whole list (every paused title), so these
  /// public accessors expose it without a second network round-trip.
  Future<List<dynamic>?> fetchEpisodePlaybackSessions() =>
      _fetchEpisodePlaybackSessions();
  Future<List<dynamic>?> fetchMoviePlaybackSessions() =>
      _fetchMoviePlaybackSessions();

  /// Fire a `DELETE` and report success (any 2xx). Simkl's delete-playback
  /// returns an empty body, so only the status code matters.
  Future<bool> _deleteOk(
    String path, {
    required String token,
    required String label,
  }) async {
    try {
      final response = await http
          .delete(_apiUri(path), headers: _apiHeaders(accessToken: token))
          .timeout(const Duration(seconds: 15));
      // 204 = deleted. 404 = the session is already gone (stale cache / double
      // action) — the desired end state holds, so treat it as success too.
      if ((response.statusCode >= 200 && response.statusCode < 300) ||
          response.statusCode == 404) {
        return true;
      }
      debugPrint('Simkl: $label failed (${response.statusCode})');
      return false;
    } catch (error) {
      debugPrint('Simkl: $label error (${error.runtimeType})');
      return false;
    }
  }

  /// Remove a title from Continue Watching by clearing ALL its paused playback
  /// sessions — movie AND any episodes — via `DELETE /sync/playback/{id}` per
  /// matching session (each session in the `/sync/playback` list carries a
  /// 64-bit `id`). A watchlist-status change (Completed/Dropped) does NOT clear
  /// these on its own, so callers that want the title gone from the CW row call
  /// this too. Invalidates the playback cache so the row refetches without the
  /// removed sessions. Returns true when every matching session was deleted (or
  /// there was nothing to delete). Never throws.
  Future<bool> deletePlaybackForImdb(String imdbId) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    // Independent GETs — fetch concurrently. A null list means the fetch failed.
    final lists = await Future.wait([
      _fetchEpisodePlaybackSessions(),
      _fetchMoviePlaybackSessions(),
    ]);
    final episodes = lists[0];
    final movies = lists[1];
    final ids = <int>{};
    for (final raw in [...?episodes, ...?movies]) {
      if (raw is! Map) continue;
      final content = raw['show'] ?? raw['movie'];
      final cids = content is Map ? content['ids'] : null;
      if (cids is! Map || cids['imdb'] != imdbId) continue;
      final id = _asNum(raw['id'])?.toInt();
      if (id != null) ids.add(id);
    }
    // Nothing to delete: only an authoritative "success" if BOTH lists were
    // actually readable — a failed fetch (null) means we might have missed the
    // session, so don't report success (the caller would show a false toast).
    if (ids.isEmpty) return episodes != null && movies != null;
    var allOk = true;
    for (final id in ids) {
      final ok = await _deleteOk(
        '/sync/playback/$id',
        token: token,
        label: 'deletePlayback $id',
      );
      if (!ok) allOk = false;
    }
    _invalidatePlaybackCache();
    if (allOk) {
      EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
    }
    return allOk;
  }

  /// Clear the paused session for ONE specific episode of a show (matched by
  /// show imdb + season + episode number) via `DELETE /sync/playback/{id}` — so
  /// marking that episode watched also drops it from Continue Watching. A no-op
  /// (returns true without touching the cache) when there's no matching paused
  /// session, so the common "mark an unpaused episode watched" case is free.
  /// Only invalidates the playback cache when it actually deleted something.
  Future<bool> deletePlaybackForEpisode(
    String imdbId,
    int season,
    int episode,
  ) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return false;
    final episodes = await _fetchEpisodePlaybackSessions();
    final ids = <int>{};
    for (final raw in [...?episodes]) {
      if (raw is! Map) continue;
      final show = raw['show'];
      final sids = show is Map ? show['ids'] : null;
      if (sids is! Map || sids['imdb'] != imdbId) continue;
      final ep = raw['episode'];
      if (ep is! Map) continue;
      if (_asNum(ep['season'])?.toInt() != season) continue;
      if (_asNum(ep['number'])?.toInt() != episode) continue;
      final id = _asNum(raw['id'])?.toInt();
      if (id != null) ids.add(id);
    }
    // Nothing to delete — authoritative only if the fetch actually succeeded
    // (a null list is a failure we shouldn't report as success).
    if (ids.isEmpty) return episodes != null;
    var allOk = true;
    for (final id in ids) {
      final ok = await _deleteOk(
        '/sync/playback/$id',
        token: token,
        label: 'deletePlaybackEp $id',
      );
      if (!ok) allOk = false;
    }
    _invalidatePlaybackCache();
    if (allOk) {
      EpisodeTrackerSnapshotRevision.invalidateTitle('simkl', imdbId);
    }
    return allOk;
  }

  /// The paused progress percent (0-100) of a movie's Simkl playback session,
  /// or null when it has none (not paused / finished / not in playback / on
  /// failure). Throw-free defensive parsing like the episode readers.
  Future<double?> fetchMoviePlaybackProgress(String movieImdbId) async {
    final sessions = await _fetchMoviePlaybackSessions();
    if (sessions == null) return null;
    for (final raw in sessions) {
      if (raw is! Map) continue;
      final movie = raw['movie'];
      if (movie is! Map) continue;
      final ids = movie['ids'];
      if (ids is! Map || ids['imdb'] != movieImdbId) continue;
      final progress = _asNum(raw['progress'])?.toDouble();
      if (progress == null) continue;
      // Mirror Trakt's _visibleProgress: a boundary session (<=0 not started,
      // >=100 finished) is NOT a resumable position. Returning it would make
      // the detail button promise a "Resume" the player won't seek to (it only
      // seeks 0 < pct < 100), breaking label↔Play lock-step. Skip it (like the
      // episode reader scans every session) so a later in-progress session for
      // the same movie still wins; fall through to null if none is resumable.
      if (progress <= 0 || progress >= 100) continue;
      return progress;
    }
    return null;
  }

  /// Fully-watched episodes of a show as a `'$season-$episode'` key set, via
  /// `POST /sync/watched?extended=episodes`. Empty set on failure — mirrors
  /// TraktService.fetchWatchedShowEpisodes's contract.
  Future<Set<String>> fetchWatchedShowEpisodes(String showImdbId) async {
    final token = await StorageService.getSimklAccessToken();
    if (token == null || token.isEmpty) return {};
    final result = await _postOrNull(
      '/sync/watched',
      [
        {
          'ids': {'imdb': showImdbId},
        },
      ],
      token: token,
      label: 'fetchWatchedShowEpisodes',
      query: {'extended': 'episodes'},
    );
    if (result is! List || result.isEmpty) return {};
    final item = result.first;
    if (item is! Map<String, dynamic>) return {};
    final out = <String>{};
    final seasons = item['seasons'];
    if (seasons is! List) return out;
    for (final s in seasons) {
      if (s is! Map<String, dynamic>) continue;
      final seasonNum = (s['number'] as num?)?.toInt();
      final episodes = s['episodes'];
      if (seasonNum == null || episodes is! List) continue;
      for (final e in episodes) {
        if (e is! Map<String, dynamic>) continue;
        if (e['watched'] != true) continue;
        final epNum = (e['number'] as num?)?.toInt();
        if (epNum != null) out.add('$seasonNum-$epNum');
      }
    }
    return out;
  }
}
