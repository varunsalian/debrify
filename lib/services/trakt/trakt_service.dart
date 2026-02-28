import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../storage_service.dart';
import 'trakt_constants.dart';

/// Service for Trakt OAuth authentication and API calls.
class TraktService {
  static final TraktService _instance = TraktService._internal();
  factory TraktService() => _instance;
  TraktService._internal();

  static TraktService get instance => _instance;

  /// In-memory OAuth state nonce for CSRF protection.
  String? _pendingOAuthState;

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

  /// Open the Trakt authorization page in the user's browser.
  Future<void> launchAuth() async {
    // Generate a random state nonce for CSRF protection
    final random = Random.secure();
    _pendingOAuthState = base64Url.encode(
      List.generate(16, (_) => random.nextInt(256)),
    );

    final uri = Uri.parse(
      '$kTraktAuthUrl'
      '?client_id=$kTraktClientId'
      '&response_type=code'
      '&redirect_uri=${Uri.encodeComponent(kTraktRedirectUri)}'
      '&state=$_pendingOAuthState',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _pendingOAuthState = null;
      throw Exception('Could not launch Trakt authorization URL');
    }
  }

  /// Validate the OAuth state parameter. Returns true if valid.
  bool validateState(String? state) {
    if (_pendingOAuthState == null || state == null) return false;
    final valid = state == _pendingOAuthState;
    _pendingOAuthState = null; // Consume the nonce
    return valid;
  }

  /// Exchange an authorization code for access + refresh tokens.
  /// Called after the user approves the app and we receive the callback.
  Future<bool> exchangeCode(String code) async {
    try {
      final response = await http.post(
        Uri.parse(kTraktTokenUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'client_id': kTraktClientId,
          'client_secret': kTraktClientSecret,
          'redirect_uri': kTraktRedirectUri,
          'grant_type': 'authorization_code',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        await _storeTokens(data);

        // Fetch and store the username
        final accessToken = data['access_token'] as String;
        await _fetchAndStoreUsername(accessToken);

        return true;
      }

      debugPrint('Trakt: Token exchange failed (${response.statusCode}): ${response.body}');
      return false;
    } catch (e) {
      debugPrint('Trakt: Token exchange error: $e');
      return false;
    }
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
          'redirect_uri': kTraktRedirectUri,
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

  /// Fetch a standard Trakt list (watchlist, collection, ratings, recommendations).
  /// [listType] is one of: watchlist, collection, ratings, recommendations.
  /// [contentType] is one of: movies, shows.
  Future<List<dynamic>> fetchList(String listType, String contentType) async {
    final String path;
    if (listType == 'recommendations') {
      path = '/recommendations/$contentType?extended=full';
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
}
