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
}
