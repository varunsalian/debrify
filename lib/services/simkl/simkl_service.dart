import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../storage_service.dart';
import 'simkl_constants.dart';

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
}
