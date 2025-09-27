import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DropboxAuthService {
  static const String _storageKeyAccessToken = 'dropbox_access_token';
  static const String _storageKeyRefreshToken = 'dropbox_refresh_token';
  static const String _storageKeyAccountEmail = 'dropbox_account_email';
  static const String _storageKeyFolderPath = 'dropbox_folder_path';

  // Dropbox app key from Dropbox Console
  static const String _dropboxAppKey = '1hyex074pwd1y29';

  // Dropbox OAuth2 endpoints
  static const String _authorizationEndpoint = 'https://www.dropbox.com/oauth2/authorize';
  static const String _tokenEndpoint = 'https://api.dropboxapi.com/oauth2/token';

  // Required scopes for the app
  static const List<String> _scopes = [
    'account_info.read',
    'files.metadata.write',
    'files.content.write'
  ];

  /// Get the appropriate redirect URI based on the current platform
  static String get _redirectUri {
    if (kIsWeb) {
      return 'http://localhost:53682/callback';
    } else if (Platform.isAndroid) {
      return 'com.debrify.app:/oauth2redirect';
    } else if (Platform.isIOS) {
      return 'com.debrify.app:/oauth2redirect';
    } else {
      // Desktop (macOS, Windows, Linux) - use custom scheme
      return 'com.debrify.app:/oauth2redirect';
    }
  }

  /// Generate a cryptographically secure code verifier for PKCE
  static String _generateCodeVerifier() {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    return List.generate(128, (index) => charset[random.nextInt(charset.length)]).join();
  }

  /// Generate code challenge from code verifier using SHA256
  static String _generateCodeChallenge(String codeVerifier) {
    final bytes = utf8.encode(codeVerifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Check if user is currently connected to Dropbox
  static Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString(_storageKeyAccessToken);
    final refreshToken = prefs.getString(_storageKeyRefreshToken);
    return accessToken != null && refreshToken != null;
  }

  /// Get stored access token
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKeyAccessToken);
  }

  /// Get stored refresh token
  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKeyRefreshToken);
  }

  /// Get stored account email
  static Future<String?> getAccountEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKeyAccountEmail);
  }

  /// Get stored folder path
  static Future<String?> getFolderPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKeyFolderPath);
  }

  /// Start the OAuth2 flow with PKCE
  static Future<DropboxAuthResult> authenticate() async {
    try {
      final flutterAppAuth = FlutterAppAuth();

      // Generate PKCE parameters
      final codeVerifier = _generateCodeVerifier();
      final codeChallenge = _generateCodeChallenge(codeVerifier);

      // Prepare authorization request
      final authorizationRequest = AuthorizationTokenRequest(
        _dropboxAppKey,
        _redirectUri,
        issuer: 'https://www.dropbox.com',
        scopes: _scopes,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: _authorizationEndpoint,
          tokenEndpoint: _tokenEndpoint,
        ),
        additionalParameters: {
          'token_access_type': 'offline', // Request refresh token
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
        preferEphemeralSession: false,
      );

      // Perform authorization
      final authorizationTokenResponse = await flutterAppAuth.authorizeAndExchangeCode(
        authorizationRequest,
      );

      if (authorizationTokenResponse == null) {
        return DropboxAuthResult(
          success: false,
          error: 'Authorization was cancelled or failed',
        );
      }

      // Store tokens and basic info
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKeyAccessToken, authorizationTokenResponse.accessToken!);
      await prefs.setString(_storageKeyRefreshToken, authorizationTokenResponse.refreshToken!);

      // Extract email from ID token if available, or fetch from API later
      String? email;
      if (authorizationTokenResponse.idToken != null) {
        // Parse JWT token to extract email (simplified)
        try {
          final parts = authorizationTokenResponse.idToken!.split('.');
          if (parts.length == 3) {
            final payload = json.decode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
            email = payload['email'];
          }
        } catch (e) {
          // If parsing fails, we'll fetch email from API later
          debugPrint('Failed to parse ID token for email: $e');
        }
      }

      if (email != null) {
        await prefs.setString(_storageKeyAccountEmail, email);
      }

      return DropboxAuthResult(
        success: true,
        accessToken: authorizationTokenResponse.accessToken!,
        refreshToken: authorizationTokenResponse.refreshToken!,
        email: email,
      );

    } catch (e) {
      debugPrint('Dropbox authentication error: $e');
      return DropboxAuthResult(
        success: false,
        error: 'Authentication failed: $e',
      );
    }
  }

  /// Refresh the access token using the refresh token
  static Future<DropboxAuthResult> refreshAccessToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        return DropboxAuthResult(
          success: false,
          error: 'No refresh token available',
        );
      }

      final flutterAppAuth = FlutterAppAuth();
      
      final tokenRequest = TokenRequest(
        _dropboxAppKey,
        _redirectUri,
        refreshToken: refreshToken,
        serviceConfiguration: const AuthorizationServiceConfiguration(
          authorizationEndpoint: _authorizationEndpoint,
          tokenEndpoint: _tokenEndpoint,
        ),
      );

      final tokenResponse = await flutterAppAuth.token(tokenRequest);
      
      if (tokenResponse == null) {
        return DropboxAuthResult(
          success: false,
          error: 'Token refresh failed',
        );
      }

      // Update stored access token
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKeyAccessToken, tokenResponse.accessToken!);
      
      if (tokenResponse.refreshToken != null) {
        await prefs.setString(_storageKeyRefreshToken, tokenResponse.refreshToken!);
      }

      return DropboxAuthResult(
        success: true,
        accessToken: tokenResponse.accessToken!,
        refreshToken: tokenResponse.refreshToken ?? refreshToken,
      );

    } catch (e) {
      debugPrint('Dropbox token refresh error: $e');
      return DropboxAuthResult(
        success: false,
        error: 'Token refresh failed: $e',
      );
    }
  }

  /// Store account email and folder path
  static Future<void> storeAccountInfo(String email, String folderPath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKeyAccountEmail, email);
    await prefs.setString(_storageKeyFolderPath, folderPath);
  }

  /// Disconnect from Dropbox and clear all stored data
  static Future<void> disconnect() async {
    try {
      // Try to revoke the token first
      final accessToken = await getAccessToken();
      if (accessToken != null) {
        await _revokeToken(accessToken);
      }
    } catch (e) {
      debugPrint('Failed to revoke token: $e');
    }

    // Clear all stored data
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKeyAccessToken);
    await prefs.remove(_storageKeyRefreshToken);
    await prefs.remove(_storageKeyAccountEmail);
    await prefs.remove(_storageKeyFolderPath);
  }

  /// Revoke the access token via Dropbox API
  static Future<void> _revokeToken(String accessToken) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('https://api.dropboxapi.com/2/auth/token/revoke'));
      request.headers.set('Authorization', 'Bearer $accessToken');
      request.headers.set('Content-Type', 'application/json');
      
      final response = await request.close();
      if (response.statusCode != 200) {
        debugPrint('Token revocation failed with status: ${response.statusCode}');
      }
    } finally {
      client.close();
    }
  }
}

/// Result class for Dropbox authentication operations
class DropboxAuthResult {
  final bool success;
  final String? accessToken;
  final String? refreshToken;
  final String? email;
  final String? error;

  DropboxAuthResult({
    required this.success,
    this.accessToken,
    this.refreshToken,
    this.email,
    this.error,
  });
}
