import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'storage_service.dart';

/// Represents a media item for Trakt scrobbling
class TraktMediaItem {
  final String title;
  final String? imdbId;
  final int? tmdbId;
  final int? traktId;
  final String type; // 'movie' or 'episode'
  final int? season;
  final int? episode;

  TraktMediaItem({
    required this.title,
    this.imdbId,
    this.tmdbId,
    this.traktId,
    required this.type,
    this.season,
    this.episode,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    
    if (type == 'movie') {
      data['movie'] = {
        'title': title,
        'ids': {
          if (imdbId != null) 'imdb': imdbId,
          if (tmdbId != null) 'tmdb': tmdbId,
          if (traktId != null) 'trakt': traktId,
        }
      };
    } else {
      data['episode'] = {
        'ids': {
          if (imdbId != null) 'imdb': imdbId,
          if (tmdbId != null) 'tmdb': tmdbId,
          if (traktId != null) 'trakt': traktId,
        }
      };
      // For episodes, if we don't have direct IDs, we might need show info
      if (imdbId == null && tmdbId == null && traktId == null) {
         data['show'] = { 'title': title };
         data['episode'] = {
           'season': season,
           'number': episode,
         };
      }
    }
    return data;
  }
}

class TraktService {
  static const String _baseUrl = 'https://api.trakt.tv';
  
  static const String _clientId = String.fromEnvironment('TRAKT_CLIENT_ID');
  static const String _clientSecret = String.fromEnvironment('TRAKT_CLIENT_SECRET');
  static const String _redirectUri = 'debrify://trakt-auth';

  static bool get hasCredentials => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  static String getAuthUrl() {
    return 'https://trakt.tv/oauth/authorize?response_type=code&client_id=$_clientId&redirect_uri=$_redirectUri';
  }

  /// Device Authentication: Step 1 - Generate codes
  static Future<Map<String, dynamic>?> generateDeviceCode() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/device/code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'client_id': _clientId,
        }),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return null;
    } catch (e) {
      debugPrint('TraktService: Generate device code error: $e');
      return null;
    }
  }

  /// Device Authentication: Step 2 - Poll for token
  /// Returns 'success', 'pending', or 'expired'/'error'
  static Future<Map<String, dynamic>> pollForDeviceToken(String deviceCode) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/device/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': deviceCode,
          'client_id': _clientId,
          'client_secret': _clientSecret,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data);
        await fetchUserSettings();
        return {'status': 'success'};
      } else if (response.statusCode == 400) {
        // Pending or slow_down
        return {'status': 'pending'};
      } else if (response.statusCode == 404) {
        return {'status': 'not_found'};
      } else if (response.statusCode == 409) {
        return {'status': 'already_used'};
      } else if (response.statusCode == 410) {
        return {'status': 'expired'};
      } else if (response.statusCode == 418) {
        return {'status': 'denied'};
      } else if (response.statusCode == 429) {
        return {'status': 'slow_down'};
      }
      
      return {'status': 'error'};
    } catch (e) {
      debugPrint('TraktService: Poll device token error: $e');
      return {'status': 'error'};
    }
  }

  /// Exchange authorization code for access token
  static Future<bool> authenticate(String code) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'redirect_uri': _redirectUri,
          'grant_type': 'authorization_code',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data);
        await fetchUserSettings();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TraktService: Authentication error: $e');
      return false;
    }
  }

  /// Refresh the access token
  static Future<bool> refreshAccessToken() async {
    final refreshToken = await StorageService.getTraktRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/oauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh_token': refreshToken,
          'client_id': _clientId,
          'client_secret': _clientSecret,
          'redirect_uri': _redirectUri,
          'grant_type': 'refresh_token',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveTokens(data);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TraktService: Token refresh error: $e');
      return false;
    }
  }

  static Future<void> _saveTokens(Map<String, dynamic> data) async {
    await StorageService.setTraktAccessToken(data['access_token']);
    await StorageService.setTraktRefreshToken(data['refresh_token']);
    final expiresIn = data['expires_in'] as int;
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    await StorageService.setTraktExpiresAt(expiresAt);
  }

  static Future<bool> fetchUserSettings() async {
    final token = await _getValidToken();
    if (token == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/users/settings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'trakt-api-version': '2',
          'trakt-api-key': _clientId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final username = data['user']['username'];
        await StorageService.setTraktUsername(username);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('TraktService: Fetch settings error: $e');
      return false;
    }
  }

  static Future<String?> _getValidToken() async {
    final expiresAt = await StorageService.getTraktExpiresAt();
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      final refreshed = await refreshAccessToken();
      if (!refreshed) return null;
    }
    return await StorageService.getTraktAccessToken();
  }

  /// Scrobble: Start watching
  static Future<bool> startScrobble(TraktMediaItem item, double progress) async {
    return _sendScrobble('start', item, progress);
  }

  /// Scrobble: Pause watching
  static Future<bool> pauseScrobble(TraktMediaItem item, double progress) async {
    return _sendScrobble('pause', item, progress);
  }

  /// Scrobble: Stop watching
  static Future<bool> stopScrobble(TraktMediaItem item, double progress) async {
    return _sendScrobble('stop', item, progress);
  }

  static Future<bool> _sendScrobble(String action, TraktMediaItem item, double progress) async {
    final enabled = await StorageService.getTraktEnabled();
    if (!enabled) return false;

    final token = await _getValidToken();
    if (token == null) return false;

    try {
      final body = item.toJson();
      final packageInfo = await PackageInfo.fromPlatform();
      body['progress'] = progress;
      body['app_version'] = packageInfo.version;
      body['app_date'] = DateTime.now().toIso8601String().split('T')[0];

      final response = await http.post(
        Uri.parse('$_baseUrl/scrobble/$action'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          'trakt-api-version': '2',
          'trakt-api-key': _clientId,
        },
        body: jsonEncode(body),
      );

      return response.statusCode == 201;
    } catch (e) {
      debugPrint('TraktService: Scrobble $action error: $e');
      return false;
    }
  }

  static Future<void> logout() async {
    await StorageService.clearTraktAuth();
  }
}
