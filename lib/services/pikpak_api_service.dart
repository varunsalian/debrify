import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/profiles/profile_policy.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/connection_resource_service.dart';
import 'storage_service.dart';

class PikPakApiService {
  static final PikPakApiService instance = PikPakApiService._internal();
  factory PikPakApiService() => instance;
  PikPakApiService._internal();

  /// Notifier for reactive UI updates when auth state changes
  final ValueNotifier<bool> authStateNotifier = ValueNotifier(false);

  // Web Platform Constants (more reliable than Android/iOS)
  static const String _webClientId = 'YUMx5nI8ZU8Ap8pm';
  static const String _webClientSecret = 'dbw2OtmVEeuUvIptb1Coygx';
  static const String _webClientVersion = '2.0.0';
  static const String _webPackageName = 'mypikpak.com';
  // User-Agent should match Firefox (as used by rclone) for best compatibility
  static const String _webUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0';

  // Mutex for captcha token refresh to prevent race conditions
  final Map<String, Completer<String>> _captchaRefreshInProgress = {};

  // Web Platform Algorithms for Captcha Sign (from rclone)
  static const List<String> _webAlgorithms = [
    'C9qPpZLN8ucRTaTiUMWYS9cQvWOE',
    '+r6CQVxjzJV6LCV',
    'F',
    'pFJRC',
    '9WXYIDGrwTCz2OiVlgZa90qpECPD6olt',
    '/750aCr4lm/Sly/c',
    'RB+DT/gZCrbV',
    '',
    'CyLsf7hdkIRxRm215hl',
    '7xHvLi2tOYP0Y92b',
    'ZGTXXxu8E/MIWaEDB+Sm/',
    '1UI3',
    'E7fP5Pfijd+7K+t6Tg/NhuLq0eEUVChpJSkrKxpO',
    'ihtqpG6FMt65+Xk+tWUH2',
    'NhXXU9rg4XXdzo7u5o',
  ];

  // API endpoints
  static const String _authBaseUrl = 'https://user.mypikpak.net';
  static const String _driveBaseUrl = 'https://api-drive.mypikpak.com';

  // Account material is deliberately never retained in this singleton:
  // concurrent profile operations always reload it from their captured store.

  // Circuit breaker for re-authentication to prevent hammering PikPak when rate-limited
  DateTime? _lastReAuthAttempt;
  static const Duration _reAuthCooldown = Duration(seconds: 60);

  /// Generate a random device ID (32 character hex string like rclone does)
  String _generateDeviceId() {
    final random =
        DateTime.now().millisecondsSinceEpoch.toString() +
        DateTime.now().microsecondsSinceEpoch.toString() +
        (DateTime.now().hashCode * 31).toString();
    final bytes = utf8.encode(random);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Calculate captcha sign using web platform algorithms
  String _getCaptchaSign(String deviceId, [String? timestamp]) {
    // Use provided timestamp or generate new one
    timestamp ??= DateTime.now().millisecondsSinceEpoch.toString();

    // Start with: ClientID + ClientVersion + PackageName + DeviceID + Timestamp
    String str =
        _webClientId +
        _webClientVersion +
        _webPackageName +
        deviceId +
        timestamp;

    // Iteratively hash with each algorithm
    for (String algorithm in _webAlgorithms) {
      final bytes = utf8.encode(str + algorithm);
      final digest = md5.convert(bytes);
      str = digest.toString();
    }

    return '1.$str';
  }

  /// Get captcha token from PikPak with synchronization to prevent race conditions
  /// When multiple requests fail with "Verification code is invalid" simultaneously,
  /// only one will actually fetch a new token, others will wait and use the same token.
  Future<String> _getCaptchaTokenSynchronized({
    required String action,
    required String deviceId,
    String? email,
    String? userId,
  }) async {
    // Create a unique key for this captcha request
    final requestKey = '$action:${userId ?? email ?? 'anonymous'}';

    // Check if a refresh is already in progress for this key
    final existingRefresh = _captchaRefreshInProgress[requestKey];
    if (existingRefresh != null) {
      debugPrint(
        'PikPak: Captcha refresh already in progress for $action, waiting...',
      );
      try {
        return await existingRefresh.future;
      } catch (e) {
        // If the existing refresh failed, we'll try ourselves
        debugPrint(
          'PikPak: Existing captcha refresh failed, attempting new request',
        );
      }
    }

    // Create a new completer for this refresh
    final completer = Completer<String>();
    _captchaRefreshInProgress[requestKey] = completer;

    try {
      final token = await _getCaptchaToken(
        action: action,
        deviceId: deviceId,
        email: email,
        userId: userId,
      );
      completer.complete(token);
      return token;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      // Remove the completer after a short delay to allow all waiting requests to get the result
      Future.delayed(const Duration(milliseconds: 100), () {
        _captchaRefreshInProgress.remove(requestKey);
      });
    }
  }

  /// Get captcha token from PikPak (internal implementation)
  Future<String> _getCaptchaToken({
    required String action,
    required String deviceId,
    String? email,
    String? userId,
  }) async {
    try {
      debugPrint('PikPak: Requesting captcha token for action: $action');

      // Generate timestamp once for both captcha sign and meta
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      // Calculate captcha sign with the same timestamp
      final captchaSign = _getCaptchaSign(deviceId, timestamp);

      // Build meta with all required fields
      final meta = <String, String>{
        'captcha_sign': captchaSign,
        'client_id': _webClientId,
        'client_version': _webClientVersion,
        'device_id': deviceId,
        'package_name': _webPackageName,
        'timestamp': timestamp,
      };

      // For login action, add email (using username field in rclone)
      if (action == 'POST:/v1/auth/signin' && email != null) {
        meta['username'] =
            email; // rclone uses 'username' not 'email' for login
      }
      // For all other actions (file operations), add user_id
      else if (userId != null) {
        meta['user_id'] = userId;
      }

      debugPrint('PikPak: Captcha request metadata prepared');

      final response = await http.post(
        Uri.parse(
          '$_authBaseUrl/v1/shield/captcha/init',
        ).replace(queryParameters: {'client_id': _webClientId}),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _webUserAgent,
          'X-Device-ID': deviceId,
          'X-Client-ID': _webClientId,
        },
        body: jsonEncode({
          'action': action,
          'captcha_token': '',
          'client_id': _webClientId,
          'device_id': deviceId,
          'meta': meta,
          'redirect_uri': 'xlaccsdk01://xbase.cloud/callback?state=harbor',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['captcha_token'] as String;
        debugPrint('PikPak: Captcha token obtained successfully');
        return token;
      } else {
        debugPrint(
          'PikPak: Failed to get captcha token: ${response.statusCode}',
        );
        // Try to parse error details
        try {
          final errorData = jsonDecode(response.body);
          final errorCode = errorData['error_code'];
          final errorType = errorData['error'] ?? 'unknown';
          debugPrint('PikPak: Error code: $errorCode, type: $errorType');
        } catch (e) {
          // Ignore parsing errors
        }

        throw Exception('Failed to get captcha token: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('PikPak: Captcha token error (${e.runtimeType})');
      rethrow;
    }
  }

  /// Login with email and password
  /// [notifyListeners] - If false, won't update authStateNotifier (used for internal re-auth)
  Future<bool> login(
    String email,
    String password, {
    bool notifyListeners = true,
  }) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      if (authorization == null) {
        return _loginScoped(email, password, notifyListeners: notifyListeners);
      }
      return await authorization.run(
        () => _loginScoped(
          email,
          password,
          notifyListeners: notifyListeners,
          authorization: authorization,
        ),
      );
    } on StateError {
      if (notifyListeners) authStateNotifier.value = false;
      return false;
    }
  }

  Future<bool> _loginScoped(
    String email,
    String password, {
    required bool notifyListeners,
    ProfileAsyncAuthorization? authorization,
  }) async {
    try {
      debugPrint('PikPak: Starting login');

      // 1. Generate or load device ID
      String? deviceId = await StorageService.getPikPakDeviceId();
      if (deviceId == null) {
        deviceId = _generateDeviceId();
        await StorageService.setPikPakDeviceId(deviceId);
        debugPrint('PikPak: Generated a new device ID');
      } else {
        debugPrint('PikPak: Using the stored device ID');
      }

      // 2. Get captcha token BEFORE login
      final action = 'POST:/v1/auth/signin';
      final captchaToken = await _getCaptchaTokenSynchronized(
        action: action,
        deviceId: deviceId,
        email: email,
      );

      // 3. Attempt login with captcha token
      final response = await http.post(
        Uri.parse(
          '$_authBaseUrl/v1/auth/signin',
        ).replace(queryParameters: {'client_id': _webClientId}),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': _webUserAgent,
          'X-Device-ID': deviceId,
          'X-Client-ID': _webClientId,
          'X-Captcha-Token': captchaToken,
        },
        body: jsonEncode({
          'captcha_token': captchaToken,
          'client_id': _webClientId,
          'client_secret': _webClientSecret,
          'username': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String?;
        final userId = data['sub'] as String?;
        if (accessToken == null || refreshToken == null) return false;

        Future<void> commit() async {
          await StorageService.setPikPakEmail(email);
          await StorageService.setPikPakPassword(password);
          await StorageService.setPikPakAccessToken(accessToken);
          await StorageService.setPikPakRefreshToken(refreshToken);
          await StorageService.setPikPakCaptchaToken(captchaToken);
          if (userId != null) {
            await StorageService.setPikPakUserId(userId);
          }
        }

        if (authorization == null) {
          await commit();
        } else {
          await authorization.run(commit);
        }

        debugPrint('PikPak: Login successful');
        if (notifyListeners &&
            (authorization == null || authorization.isCurrentlyActive)) {
          authStateNotifier.value = true;
        }
        return true;
      } else {
        try {
          final errorData = jsonDecode(response.body);
          debugPrint(
            'PikPak: Login failed: code=${errorData['error_code']} '
            'type=${errorData['error'] ?? 'unknown'}',
          );
        } catch (_) {
          debugPrint('PikPak: Login failed: status=${response.statusCode}');
        }
        if (notifyListeners &&
            (authorization == null || authorization.isCurrentlyActive)) {
          authStateNotifier.value = false;
        }
        return false;
      }
    } catch (e) {
      debugPrint('PikPak: Login error (${e.runtimeType})');
      if (notifyListeners &&
          (authorization == null || authorization.isCurrentlyActive)) {
        authStateNotifier.value = false;
      }
      return false;
    }
  }

  /// Refresh access token using refresh token
  ///
  /// PikPak has deprecated client_secret for token refresh operations.
  /// Sending client_secret triggers error_code 7: "permission_denied" with
  /// message "[Danger], Please Do Not Save Your client_secret in browser".
  ///
  /// The fix follows rclone's approach: use standard OAuth2 token refresh
  /// without client_secret, relying on device_id and captcha_token for auth.
  Future<bool> refreshAccessToken() async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      if (authorization == null) return _refreshAccessTokenScoped(null);
      return await authorization.run(
        () => _refreshAccessTokenScoped(authorization),
      );
    } on StateError {
      return false;
    }
  }

  Future<bool> _refreshAccessTokenScoped(
    ProfileAsyncAuthorization? authorization,
  ) async {
    try {
      // Always reload from the operation's captured scope. A token retained by
      // the singleton may belong to a profile that has since switched away.
      final refreshToken = await StorageService.getPikPakRefreshToken();
      if (refreshToken == null) {
        debugPrint('PikPak: No refresh token available');
        return false;
      }

      debugPrint('PikPak: Refreshing access token...');

      final deviceId = await StorageService.getPikPakDeviceId();
      final captchaToken = await StorageService.getPikPakCaptchaToken();

      // Try multiple refresh methods in order of preference
      // Method 1: Standard OAuth2 refresh without client_secret (rclone approach)
      // Method 2: Fallback with re-authentication using stored credentials

      final success = await _tryRefreshWithoutClientSecret(
        deviceId,
        captchaToken,
        refreshToken,
        authorization,
      );
      if (success) {
        return true;
      }

      // Method 2: Try re-authentication with stored credentials
      debugPrint(
        'PikPak: Standard refresh failed, attempting re-authentication...',
      );
      return await _tryReAuthenticate();
    } catch (e) {
      debugPrint('PikPak: Token refresh error (${e.runtimeType})');
      return false;
    }
  }

  /// Attempt token refresh without client_secret (standard OAuth2 flow)
  /// This is the primary method following rclone's implementation
  Future<bool> _tryRefreshWithoutClientSecret(
    String? deviceId,
    String? captchaToken,
    String refreshToken,
    ProfileAsyncAuthorization? authorization,
  ) async {
    // Try JSON format first (rclone approach), then form-urlencoded (standard OAuth2)
    if (await _tryRefreshJson(
      deviceId,
      captchaToken,
      refreshToken,
      authorization,
    )) {
      return true;
    }

    debugPrint('PikPak: JSON refresh failed, trying form-urlencoded format...');
    return await _tryRefreshFormUrlEncoded(
      deviceId,
      captchaToken,
      refreshToken,
      authorization,
    );
  }

  /// Try refresh with JSON body (rclone's approach)
  Future<bool> _tryRefreshJson(
    String? deviceId,
    String? captchaToken,
    String refreshToken,
    ProfileAsyncAuthorization? authorization,
  ) async {
    try {
      // Use the rclone endpoint (user.mypikpak.com) which doesn't require client_secret
      const refreshUrl = 'https://user.mypikpak.com/v1/auth/token';

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'User-Agent': _webUserAgent,
        'X-Client-ID': _webClientId,
        'X-Client-Version': _webClientVersion,
      };

      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-ID'] = deviceId;
      }

      if (captchaToken != null && captchaToken.isNotEmpty) {
        headers['X-Captcha-Token'] = captchaToken;
      }

      // OAuth2 refresh WITHOUT client_secret - key fix for the permission_denied error
      final response = await http.post(
        Uri.parse(
          refreshUrl,
        ).replace(queryParameters: {'client_id': _webClientId}),
        headers: headers,
        body: jsonEncode({
          'client_id': _webClientId,
          // NOTE: client_secret is intentionally NOT included
          // PikPak rejects requests with client_secret with error_code 7
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
        }),
      );

      debugPrint(
        'PikPak: JSON refresh response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        return await _handleSuccessfulRefresh(response.body, authorization);
      } else {
        _logRefreshError(response.body);
        return false;
      }
    } catch (e) {
      debugPrint('PikPak: Error during JSON refresh (${e.runtimeType})');
      return false;
    }
  }

  /// Try refresh with form-urlencoded body (standard OAuth2 format)
  Future<bool> _tryRefreshFormUrlEncoded(
    String? deviceId,
    String? captchaToken,
    String refreshToken,
    ProfileAsyncAuthorization? authorization,
  ) async {
    try {
      // Standard OAuth2 token endpoint
      const refreshUrl = 'https://user.mypikpak.com/v1/auth/token';

      final headers = <String, String>{
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': _webUserAgent,
        'X-Client-ID': _webClientId,
        'X-Client-Version': _webClientVersion,
      };

      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-ID'] = deviceId;
      }

      if (captchaToken != null && captchaToken.isNotEmpty) {
        headers['X-Captcha-Token'] = captchaToken;
      }

      // Standard OAuth2 form-urlencoded body (without client_secret)
      final body = {
        'client_id': _webClientId,
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      };

      final response = await http.post(
        Uri.parse(
          refreshUrl,
        ).replace(queryParameters: {'client_id': _webClientId}),
        headers: headers,
        body: body,
      );

      debugPrint(
        'PikPak: Form-urlencoded refresh response status: ${response.statusCode}',
      );

      if (response.statusCode == 200) {
        return await _handleSuccessfulRefresh(response.body, authorization);
      } else {
        _logRefreshError(response.body);
        return false;
      }
    } catch (e) {
      debugPrint(
        'PikPak: Error during form-urlencoded refresh (${e.runtimeType})',
      );
      return false;
    }
  }

  /// Handle successful token refresh response
  Future<bool> _handleSuccessfulRefresh(
    String responseBody,
    ProfileAsyncAuthorization? authorization,
  ) async {
    try {
      final data = jsonDecode(responseBody);
      final accessToken = data['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) return false;
      final refreshToken = data['refresh_token'] as String?;
      final userId = data['sub'] as String?;

      Future<void> commit() async {
        if (refreshToken != null) {
          await StorageService.setPikPakRefreshToken(refreshToken);
        }
        await StorageService.setPikPakAccessToken(accessToken);
        if (userId != null) {
          await StorageService.setPikPakUserId(userId);
        }
      }

      if (authorization == null) {
        await commit();
      } else {
        await authorization.run(commit);
      }

      debugPrint('PikPak: Token refreshed successfully');
      return true;
    } catch (e) {
      debugPrint('PikPak: Error parsing refresh response (${e.runtimeType})');
      return false;
    }
  }

  /// Log refresh error details
  void _logRefreshError(String responseBody) {
    try {
      final errorData = jsonDecode(responseBody);
      final errorCode = errorData['error_code'];
      final errorType = errorData['error'] ?? '';
      final errorDesc = errorData['error_description'] ?? '';
      debugPrint('PikPak: Refresh failed: code=$errorCode, type=$errorType');

      // If invalid_grant, the refresh token itself is expired
      if (errorType == 'invalid_grant' ||
          errorDesc.toString().toLowerCase().contains('refresh token') ||
          errorDesc.toString().toLowerCase().contains('invalid refresh')) {
        debugPrint('PikPak: Refresh token is invalid/expired');
      }

      // If permission_denied (error code 7), this indicates client_secret issue
      if (errorCode == 7 || errorCode == '7') {
        debugPrint(
          'PikPak: Permission denied - this should not happen without client_secret',
        );
      }

      // If captcha error, clear it
      if (errorCode == 4002 || errorCode == '4002') {
        debugPrint('PikPak: Captcha token invalid during refresh');
        StorageService.clearPikPakCaptchaToken();
      }
    } catch (e) {
      // Ignore JSON parsing errors
    }
  }

  /// Attempt to re-authenticate using stored credentials
  /// This is a fallback when token refresh fails
  Future<bool> _tryReAuthenticate() async {
    try {
      // Circuit breaker: Don't attempt re-auth if we tried recently
      // This prevents hammering PikPak when rate-limited
      if (_lastReAuthAttempt != null) {
        final elapsed = DateTime.now().difference(_lastReAuthAttempt!);
        if (elapsed < _reAuthCooldown) {
          debugPrint(
            'PikPak: Re-auth cooldown active (${_reAuthCooldown.inSeconds - elapsed.inSeconds}s remaining), skipping',
          );
          return false;
        }
      }

      final email = await StorageService.getPikPakEmail();
      final password = await StorageService.getPikPakPassword();

      if (email == null || password == null) {
        debugPrint('PikPak: No stored credentials for re-authentication');
        // Clear all auth data since we can't recover
        await logout();
        return false;
      }

      // Mark this attempt
      _lastReAuthAttempt = DateTime.now();

      debugPrint('PikPak: Re-authenticating with stored credentials...');
      // Don't notify listeners during internal re-auth to prevent infinite loops
      final success = await login(email, password, notifyListeners: false);

      if (success) {
        debugPrint('PikPak: Re-authentication successful');
        // Reset cooldown on success
        _lastReAuthAttempt = null;
        return true;
      } else {
        debugPrint('PikPak: Re-authentication failed');
        // Don't clear credentials yet - user might need to re-login manually
        return false;
      }
    } catch (e) {
      debugPrint('PikPak: Re-authentication error (${e.runtimeType})');
      return false;
    }
  }

  /// Ensure we have valid authentication tokens
  /// Always syncs from storage to ensure we have the latest tokens
  Future<void> _ensureAuthenticated() async {
    // Always load from storage to ensure we have the latest tokens
    // This handles cases where tokens were refreshed in a different session
    // or the in-memory token became stale
    final storedAccessToken = await StorageService.getPikPakAccessToken();
    final storedRefreshToken = await StorageService.getPikPakRefreshToken();

    if (storedAccessToken == null || storedRefreshToken == null) {
      throw Exception('Not authenticated. Please login first.');
    }
  }

  /// Decode a PikPak response body defensively. PikPak sits behind
  /// Cloudflare and can return HTML challenge/gateway pages (even with 2xx
  /// codes); throw a clean [Exception] instead of leaking a FormatException
  /// or TypeError to callers.
  Map<String, dynamic> _decodeJsonMap(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw Exception(
        'PikPak returned a non-JSON response (HTTP ${response.statusCode})',
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw Exception(
      'PikPak returned an unexpected response shape (HTTP ${response.statusCode})',
    );
  }

  /// Make an authenticated API request with automatic token refresh
  Future<Map<String, dynamic>> _makeAuthenticatedRequest(
    String method,
    String url,
    Map<String, dynamic>? body,
  ) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
    );
    if (authorization == null) {
      return _makeAuthenticatedRequestScoped(method, url, body);
    }
    return authorization.run(
      () => _makeAuthenticatedRequestScoped(method, url, body),
    );
  }

  Future<Map<String, dynamic>> _makeAuthenticatedRequestScoped(
    String method,
    String url,
    Map<String, dynamic>? body,
  ) async {
    await _ensureAuthenticated();

    var accessToken = (await StorageService.getPikPakAccessToken())!;
    final deviceId = await StorageService.getPikPakDeviceId();
    final captchaToken = await StorageService.getPikPakCaptchaToken();

    final headers = {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'User-Agent': _webUserAgent,
      'X-Client-ID': _webClientId,
    };

    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Device-ID'] = deviceId;
    }

    if (captchaToken != null && captchaToken.isNotEmpty) {
      headers['X-Captcha-Token'] = captchaToken;
    }

    http.Response response;

    if (method == 'POST') {
      response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else if (method == 'GET') {
      response = await http.get(Uri.parse(url), headers: headers);
    } else {
      throw Exception('Unsupported HTTP method: $method');
    }

    // Handle 401 - token expired
    if (response.statusCode == 401) {
      debugPrint('PikPak: Access token expired, refreshing...');
      if (await refreshAccessToken()) {
        // Retry the request with new token
        accessToken = (await StorageService.getPikPakAccessToken())!;
        headers['Authorization'] = 'Bearer $accessToken';

        // Also reload captcha token in case it was refreshed
        final updatedCaptchaToken =
            await StorageService.getPikPakCaptchaToken();
        if (updatedCaptchaToken != null && updatedCaptchaToken.isNotEmpty) {
          headers['X-Captcha-Token'] = updatedCaptchaToken;
        }

        if (method == 'POST') {
          response = await http.post(
            Uri.parse(url),
            headers: headers,
            body: body != null ? jsonEncode(body) : null,
          );
        } else if (method == 'GET') {
          response = await http.get(Uri.parse(url), headers: headers);
        }
      } else {
        throw Exception('Failed to refresh token. Please login again.');
      }
    }

    if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded. Please try again later.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decodeJsonMap(response);
    } else {
      final errorData = _decodeJsonMap(response);
      final errorCode = errorData['error_code'];
      final errorMessage =
          errorData['error_description'] ?? errorData['error'] ?? '';

      // Check for access token expired (error_code 16 or "unauthenticated")
      // PikPak returns this with non-401 status codes
      if (errorCode == 16 ||
          errorCode == '16' ||
          errorMessage.toString().toLowerCase().contains('access token') ||
          errorData['error'] == 'unauthenticated') {
        debugPrint(
          'PikPak: Access token expired (error_code: $errorCode), attempting refresh...',
        );

        if (await refreshAccessToken()) {
          debugPrint('PikPak: Token refreshed, retrying request...');
          // Retry the request with new token
          accessToken = (await StorageService.getPikPakAccessToken())!;
          headers['Authorization'] = 'Bearer $accessToken';

          // Also reload captcha token in case it was refreshed
          final updatedCaptchaToken =
              await StorageService.getPikPakCaptchaToken();
          if (updatedCaptchaToken != null && updatedCaptchaToken.isNotEmpty) {
            headers['X-Captcha-Token'] = updatedCaptchaToken;
          }

          if (method == 'POST') {
            response = await http.post(
              Uri.parse(url),
              headers: headers,
              body: body != null ? jsonEncode(body) : null,
            );
          } else if (method == 'GET') {
            response = await http.get(Uri.parse(url), headers: headers);
          }

          // Check if retry succeeded
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return _decodeJsonMap(response);
          } else {
            // If retry also failed, throw the new error
            final retryErrorData = _decodeJsonMap(response);
            throw Exception(
              retryErrorData['error_description'] ??
                  retryErrorData['error'] ??
                  'API request failed after token refresh',
            );
          }
        } else {
          // Refresh failed - clear tokens and require re-login
          debugPrint(
            'PikPak: Token refresh failed, clearing auth and requiring re-login',
          );
          await logout();
          throw Exception('Session expired. Please login again.');
        }
      }

      // Check for captcha error (error code 4002)
      if (errorCode == 4002 || errorCode == '4002') {
        debugPrint(
          'PikPak: Captcha token invalid (error 4002), clearing token',
        );
        await StorageService.clearPikPakCaptchaToken();
      }

      throw Exception(
        errorMessage.isNotEmpty ? errorMessage : 'API request failed',
      );
    }
  }

  /// Create a folder in PikPak
  /// Returns the created folder's metadata including its ID
  Future<Map<String, dynamic>> createFolder({
    required String folderName,
    String? parentFolderId,
  }) async {
    try {
      debugPrint('PikPak: Creating folder');

      // Try using existing captcha token first
      final response = await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files',
        {
          'kind': 'drive#folder',
          'parent_id': parentFolderId ?? '',
          'name': folderName,
        },
      );

      debugPrint('PikPak: Folder created successfully');
      return response;
    } catch (e) {
      // If we get verification error, try requesting a fresh captcha token
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          debugPrint(
            'PikPak: Warning: No user ID found, this might cause issues',
          );
        }

        final action = 'POST:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files',
          {
            'kind': 'drive#folder',
            'parent_id': parentFolderId ?? '',
            'name': folderName,
          },
        );

        debugPrint('PikPak: Folder created successfully after retry');
        return response;
      } else {
        debugPrint('PikPak: Failed to create folder (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Find or create a subfolder with caching
  /// First checks cache, then validates folder exists, searches for existing folder, or creates new one
  /// Returns the folder ID
  Future<String> findOrCreateSubfolder({
    required String folderName,
    String? parentFolderId,
    required Future<String?> Function() getCachedId,
    required Future<void> Function(String) setCachedId,
  }) async {
    try {
      // Step 1: Check cache
      final cachedId = await getCachedId();
      if (cachedId != null && cachedId.isNotEmpty) {
        debugPrint('PikPak: Found cached folder reference');

        // Step 2: Validate cached folder still exists
        try {
          final metadata = await getFileMetadata(cachedId);
          final name = metadata['name'] as String?;
          final kind = metadata['kind'] as String?;
          final parent = metadata['parent_id'] as String?;

          // Verify it's still the right folder
          if (name == folderName &&
              kind == 'drive#folder' &&
              parent == (parentFolderId ?? '')) {
            debugPrint('PikPak: Cached folder validated successfully');
            return cachedId;
          } else {
            debugPrint('PikPak: Cached folder metadata mismatch');
          }
        } catch (e) {
          debugPrint(
            'PikPak: Cached folder validation failed (${e.runtimeType})',
          );
        }
      }

      // Step 3: Search for existing folder in parent
      debugPrint('PikPak: Searching for existing folder');
      try {
        final result = await listFiles(parentId: parentFolderId, limit: 100);
        for (final file in result.files) {
          final name = file['name'] as String?;
          final kind = file['kind'] as String?;
          if (name == folderName && kind == 'drive#folder') {
            final folderId = file['id'] as String;
            debugPrint('PikPak: Found existing folder');
            // Cache the folder ID (don't fail if caching fails)
            try {
              await setCachedId(folderId);
            } catch (cacheError) {
              debugPrint(
                'PikPak: Failed to cache folder reference '
                '(${cacheError.runtimeType})',
              );
              // Continue anyway - we found the folder
            }
            return folderId;
          }
        }
      } catch (e) {
        debugPrint('PikPak: Error searching for folder (${e.runtimeType})');
      }

      // Step 4: Create new folder
      debugPrint('PikPak: Folder not found, creating it');
      final folderData = await createFolder(
        folderName: folderName,
        parentFolderId: parentFolderId,
      );

      // Extract folder ID from response (PikPak API can return it in different formats)
      String? folderId;
      if (folderData['file'] != null) {
        folderId = folderData['file']['id'];
      } else if (folderData['id'] != null) {
        folderId = folderData['id'];
      }

      if (folderId == null) {
        throw Exception(
          'Could not extract folder ID from createFolder response',
        );
      }

      // Cache the new folder ID (don't fail if caching fails)
      try {
        await setCachedId(folderId);
      } catch (cacheError) {
        debugPrint(
          'PikPak: Failed to cache folder reference (${cacheError.runtimeType})',
        );
        // Continue anyway - the folder was created successfully
      }

      return folderId;
    } catch (e) {
      debugPrint(
        'PikPak: Failed to find or create subfolder (${e.runtimeType})',
      );

      // Check if the error is because the parent folder (restricted folder) was deleted
      final errorMsg = e.toString().toLowerCase();
      if (errorMsg.contains('target folder no longer exists') ||
          errorMsg.contains('parent folder not found') ||
          errorMsg.contains('folder does not exist')) {
        debugPrint(
          'PikPak: Parent folder appears to be deleted, not falling back',
        );
        throw Exception('RESTRICTED_FOLDER_DELETED');
      }

      // Fall back to parent folder only for other types of errors
      debugPrint('PikPak: Falling back to parent folder');
      return parentFolderId ?? '';
    }
  }

  /// Add offline download (magnet link)
  Future<Map<String, dynamic>> addOfflineDownload(
    String magnetLink, {
    String? parentFolderId,
  }) async {
    try {
      debugPrint(
        'PikPak: Adding offline download to folder ${parentFolderId ?? "root"}...',
      );

      // Try using existing captcha token first (from login)
      final response = await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files',
        {
          'kind': 'drive#file',
          'name': '',
          'parent_id': parentFolderId ?? '',
          'upload_type': 'UPLOAD_TYPE_URL',
          'url': {'url': magnetLink},
          'folder_type': '',
        },
      );

      debugPrint('PikPak: Offline download added successfully');
      return response;
    } catch (e) {
      // If we get verification error, try requesting a fresh captcha token
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        // Get userId for file operations
        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          debugPrint(
            'PikPak: Warning: No user ID found, this might cause issues',
          );
        }

        final action = 'POST:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files',
          {
            'kind': 'drive#file',
            'name': '',
            'parent_id': parentFolderId ?? '',
            'upload_type': 'UPLOAD_TYPE_URL',
            'url': {'url': magnetLink},
            'folder_type': '',
          },
        );

        debugPrint('PikPak: Offline download added successfully');
        return response;
      } else {
        debugPrint('PikPak: Failed to add offline download (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Get task status by task ID
  /// Returns task details including progress (0-100) and phase
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    try {
      debugPrint('PikPak: Getting task status');
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/tasks/$taskId',
        null,
      );
      debugPrint(
        'PikPak: Task status retrieved - progress: ${response['progress']}, phase: ${response['phase']}',
      );
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint(
          'PikPak: Captcha token invalid for task status, requesting fresh token...',
        );

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        final action = 'GET:/drive/v1/tasks';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying task status with fresh captcha token');

        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/tasks/$taskId',
          null,
        );
        debugPrint(
          'PikPak: Task status retrieved (after retry) - progress: ${response['progress']}, phase: ${response['phase']}',
        );
        return response;
      } else {
        debugPrint('PikPak: Failed to get task status (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Move files to trash (recoverable)
  /// Returns true if successful
  Future<bool> batchTrashFiles(List<String> fileIds) async {
    if (fileIds.isEmpty) return true;

    try {
      debugPrint('PikPak: Moving ${fileIds.length} file(s) to trash...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchTrash',
        {'ids': fileIds},
      );

      debugPrint('PikPak: Files moved to trash successfully');
      return true;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        final action = 'POST:/drive/v1/files:batchTrash';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files:batchTrash',
          {'ids': fileIds},
        );

        debugPrint('PikPak: Files moved to trash successfully (after retry)');
        return true;
      } else {
        debugPrint('PikPak: Failed to move files to trash (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Permanently delete files (not recoverable)
  /// Returns true if successful
  Future<bool> batchDeleteFiles(List<String> fileIds) async {
    if (fileIds.isEmpty) return true;

    try {
      debugPrint('PikPak: Permanently deleting ${fileIds.length} file(s)...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchDelete',
        {'ids': fileIds},
      );

      debugPrint('PikPak: Files deleted permanently');
      return true;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        final action = 'POST:/drive/v1/files:batchDelete';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files:batchDelete',
          {'ids': fileIds},
        );

        debugPrint('PikPak: Files deleted permanently (after retry)');
        return true;
      } else {
        debugPrint('PikPak: Failed to delete files (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final accessToken = await StorageService.getPikPakAccessToken();
      final refreshToken = await StorageService.getPikPakRefreshToken();
      final isAuth = accessToken != null && refreshToken != null;
      authStateNotifier.value = isAuth;
      return isAuth;
    } on ResourceAuthorizationException {
      // The outgoing profile may be revoked between the two credential reads.
      return false;
    }
  }

  /// Drop account material retained in this process before another profile is
  /// allowed to warm. Persisted credentials remain in the scoped store.
  void resetProfileScope() {
    _lastReAuthAttempt = null;
    _captchaRefreshInProgress.clear();
    authStateNotifier.value = false;
  }

  /// Logout - clear all tokens
  Future<void> logout() async {
    await StorageService.clearPikPakAuth();
    authStateNotifier.value = false;
    debugPrint('PikPak: Logged out');
  }

  /// Get current email
  Future<String?> getEmail() => StorageService.getPikPakEmail();

  /// Test connection by trying to list files
  Future<bool> testConnection() async {
    try {
      await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files?parent_id=&thumbnail_size=SIZE_SMALL&limit=10',
        null,
      );
      debugPrint('PikPak: Connection test successful');
      return true;
    } catch (error) {
      debugPrint('PikPak: Connection test failed (${error.runtimeType})');
      return false;
    }
  }

  /// Check if the restricted folder still exists
  /// Returns true if folder exists or no restricted folder is set
  /// Returns false if restricted folder is set but doesn't exist (was deleted)
  Future<bool> verifyRestrictedFolderExists() async {
    try {
      final restrictedFolderId =
          await StorageService.getPikPakRestrictedFolderId();

      // If no restricted folder is set, return true (nothing to verify)
      if (restrictedFolderId == null || restrictedFolderId.isEmpty) {
        return true;
      }

      debugPrint('PikPak: Verifying restricted folder exists');

      // Try to get the folder metadata
      try {
        final metadata = await getFileMetadata(restrictedFolderId);
        final kind = metadata['kind'] as String?;

        // Verify it's actually a folder
        if (kind == 'drive#folder') {
          debugPrint('PikPak: Restricted folder verified - still exists');
          return true;
        } else {
          debugPrint(
            'PikPak: Restricted folder ID points to non-folder (kind: $kind)',
          );
          return false;
        }
      } catch (e) {
        debugPrint(
          'PikPak: Restricted folder verification failed (${e.runtimeType})',
        );
        // If we can't get metadata, the folder likely doesn't exist
        return false;
      }
    } catch (e) {
      debugPrint(
        'PikPak: Restricted folder verification error (${e.runtimeType})',
      );
      // On error, assume folder exists to avoid false positives
      return true;
    }
  }

  /// Get basic file metadata by ID (without resolving streaming URLs)
  /// This is faster than getFileDetails as it doesn't include usage=FETCH
  /// Use this when you only need file name, size, mime type, etc. for sorting/filtering
  Future<Map<String, dynamic>> getFileMetadata(String fileId) async {
    try {
      debugPrint('PikPak: Getting basic file metadata');
      // Get basic file info WITHOUT usage=FETCH (faster, no streaming URL resolution)
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files/$fileId',
        null,
      );
      debugPrint('PikPak: File metadata retrieved successfully');
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          debugPrint(
            'PikPak: Warning: No user ID found, this might cause issues',
          );
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/files/$fileId',
          null,
        );

        debugPrint(
          'PikPak: File metadata retrieved successfully (after retry)',
        );
        return response;
      } else {
        debugPrint('PikPak: Failed to get file metadata (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Get file details by ID (including streaming URLs - slower)
  Future<Map<String, dynamic>> getFileDetails(String fileId) async {
    try {
      debugPrint('PikPak: Getting file details');
      // CRITICAL FIX: Adding usage=FETCH parameter to populate download URLs
      // This is required to get web_content_link and medias populated in response
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files/$fileId?usage=FETCH&_magic=2021&thumbnail_size=SIZE_LARGE&with_audit=true',
        null,
      );
      debugPrint('PikPak: File details retrieved successfully');
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          debugPrint(
            'PikPak: Warning: No user ID found, this might cause issues',
          );
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/files/$fileId?usage=FETCH&_magic=2021&thumbnail_size=SIZE_LARGE&with_audit=true',
          null,
        );

        debugPrint('PikPak: File details retrieved successfully (after retry)');
        return response;
      } else {
        debugPrint('PikPak: Failed to get file details (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// List files in a directory with pagination support
  /// Returns a record containing the files list and optional next page token
  Future<({List<Map<String, dynamic>> files, String? nextPageToken})>
  listFiles({String? parentId, int limit = 50, String? pageToken}) async {
    try {
      debugPrint('PikPak: Listing files');
      // IMPORTANT: Adding with_audit=true to get media links populated for each file
      // Adding filters to exclude trashed files (deleted files go to trash first in PikPak)
      final filters = Uri.encodeComponent('{"trashed":{"eq":false}}');
      String url =
          '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true&filters=$filters';
      if (pageToken != null && pageToken.isNotEmpty) {
        url += '&page_token=$pageToken';
      }
      final response = await _makeAuthenticatedRequest('GET', url, null);
      final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
      final nextPageToken = response['next_page_token'] as String?;
      debugPrint('PikPak: Found ${files.length} files');
      return (files: files, nextPageToken: nextPageToken);
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        debugPrint('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          debugPrint(
            'PikPak: Warning: No user ID found, this might cause issues',
          );
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        debugPrint('PikPak: Retrying with fresh captcha token');

        // Retry the request with same filters
        final retryFilters = Uri.encodeComponent('{"trashed":{"eq":false}}');
        String retryUrl =
            '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true&filters=$retryFilters';
        if (pageToken != null && pageToken.isNotEmpty) {
          retryUrl += '&page_token=$pageToken';
        }
        final response = await _makeAuthenticatedRequest('GET', retryUrl, null);

        final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
        final nextPageToken = response['next_page_token'] as String?;
        debugPrint('PikPak: Found ${files.length} files after retry');
        return (files: files, nextPageToken: nextPageToken);
      } else {
        debugPrint('PikPak: Failed to list files (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Extract streaming URL from file metadata
  /// Prefers media links (better for video streaming) over web_content_link
  String? getStreamingUrl(Map<String, dynamic> fileData) {
    // Check medias array first (better for video streaming)
    final medias = fileData['medias'] as List?;
    if (medias != null && medias.isNotEmpty) {
      debugPrint('PikPak: Found ${medias.length} media entries');
      // Find default quality or original quality
      dynamic selectedMedia;

      try {
        selectedMedia = medias.firstWhere(
          (m) => m['is_default'] == true,
          orElse: () => medias.firstWhere(
            (m) => m['is_origin'] == true,
            orElse: () => medias[0],
          ),
        );
      } catch (e) {
        selectedMedia = medias[0];
      }

      final url = selectedMedia['link']?['url'];
      if (url != null && url.isNotEmpty) {
        debugPrint('PikPak: Using media link for streaming');
        return url;
      }
    }

    // Fallback to web_content_link
    final webLink = fileData['web_content_link'];
    if (webLink != null && webLink.isNotEmpty) {
      debugPrint('PikPak: Using web_content_link for streaming');
      return webLink;
    }

    debugPrint('PikPak: No streaming URL found in file data');
    return null;
  }

  /// Wait for download to complete with polling
  /// Returns file data when phase is PHASE_TYPE_COMPLETE
  /// Throws TimeoutException if download doesn't complete within timeout
  Future<Map<String, dynamic>> waitForDownloadComplete(
    String fileId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    Function(int)? onProgress,
  }) async {
    debugPrint('PikPak: Waiting for download to complete');
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(pollInterval);

      try {
        final fileData = await getFileDetails(fileId);
        final phase = fileData['phase'];
        final kind = fileData['kind'];

        debugPrint('PikPak: Download phase: $phase, kind: $kind');

        // Check if complete
        if (phase == 'PHASE_TYPE_COMPLETE') {
          debugPrint('PikPak: Download completed!');

          // DEBUG: Check if it's a folder (torrents often download as folders)
          if (kind == 'drive#folder') {
            debugPrint(
              'PikPak: Downloaded item is a folder, listing contents...',
            );
            try {
              final result = await listFiles(parentId: fileId);
              final files = result.files;
              debugPrint('PikPak: Found ${files.length} files in folder');

              // Find the first video file
              for (final file in files) {
                final mimeType = file['mime_type'] ?? '';
                if (mimeType.startsWith('video/')) {
                  debugPrint('PikPak: Found video file');
                  // CRITICAL FIX: Fetch full file details with download URLs
                  final videoFileId = file['id'];
                  final fullVideoData = await getFileDetails(videoFileId);
                  return fullVideoData;
                }
              }

              // If no video found, return first file with full details
              if (files.isNotEmpty) {
                debugPrint('PikPak: No video found, using first file');
                final firstFileId = files[0]['id'];
                final fullFileData = await getFileDetails(firstFileId);
                return fullFileData;
              }
            } catch (e) {
              debugPrint(
                'PikPak: Error listing folder contents (${e.runtimeType})',
              );
            }
          }

          return fileData;
        }

        // Check if failed
        if (phase == 'PHASE_TYPE_ERROR') {
          throw Exception('Download failed with error phase');
        }

        // Update progress if callback provided
        if (onProgress != null) {
          final progress = fileData['progress'];
          if (progress != null) {
            try {
              onProgress(
                progress is int ? progress : int.parse(progress.toString()),
              );
            } catch (e) {
              // Ignore progress parsing errors
            }
          }
        }
      } catch (e) {
        // File might not exist yet, continue polling
        debugPrint('PikPak: Polling error; will retry (${e.runtimeType})');
        continue;
      }
    }

    throw TimeoutException(
      'Download did not complete within ${timeout.inMinutes} minutes',
    );
  }

  /// Add magnet link and wait for it to be ready for streaming
  /// Returns file data with streaming URL when ready
  Future<Map<String, dynamic>> addAndWaitForReady(
    String magnetLink, {
    Function(int)? onProgress,
  }) async {
    debugPrint('PikPak: Adding magnet and waiting for ready state');

    // Step 1: Add offline download
    final addResponse = await addOfflineDownload(magnetLink);

    // Extract file ID from response
    String? fileId;

    // Try different response structures
    if (addResponse['file'] != null) {
      fileId = addResponse['file']['id'];
    } else if (addResponse['task'] != null) {
      fileId = addResponse['task']['file_id'];
    } else if (addResponse['id'] != null) {
      fileId = addResponse['id'];
    }

    if (fileId == null) {
      throw Exception('Could not extract file ID from add response');
    }

    // Step 2: Wait for download to complete
    final fileData = await waitForDownloadComplete(
      fileId,
      onProgress: onProgress,
    );

    // Step 3: Verify streaming URL is available
    final streamingUrl = getStreamingUrl(fileData);
    if (streamingUrl == null) {
      throw Exception('File completed but no streaming URL available');
    }

    debugPrint('PikPak: Ready for streaming');
    return fileData;
  }

  /// Recursively list all files in a folder and its subfolders
  /// Returns a flat list of all files found
  ///
  /// Parameters:
  /// - [folderId]: The root folder ID to scan
  /// - [limit]: Page size for listing (default 50)
  /// - [includePaths]: When true, adds '_fullPath' and '_displayName' fields to each file
  ///   preserving the folder structure in file names (e.g., "Season 1/Episode 1.mkv")
  ///   Default is false for backward compatibility with existing callers
  Future<List<Map<String, dynamic>>> listFilesRecursive({
    required String folderId,
    int limit = 50,
    bool includePaths = false,
  }) async {
    final allFiles = <Map<String, dynamic>>[];
    await _listFilesRecursiveHelper(
      folderId: folderId,
      limit: limit,
      allFiles: allFiles,
      includePaths: includePaths,
      currentPath: '', // Start with empty path at root
    );
    return allFiles;
  }

  /// Helper method for recursive folder traversal
  ///
  /// When [includePaths] is true:
  /// - Each file gets '_fullPath' field containing path from scan root (e.g., "Season 1/Episode 1.mkv")
  /// - Each file gets '_displayName' field containing just the filename without path
  /// - Original 'name' field is preserved unchanged
  Future<void> _listFilesRecursiveHelper({
    required String folderId,
    required int limit,
    required List<Map<String, dynamic>> allFiles,
    required bool includePaths,
    required String currentPath,
  }) async {
    String? nextPageToken;

    do {
      // List files in current folder
      final result = await listFiles(
        parentId: folderId,
        limit: limit,
        pageToken: nextPageToken,
      );

      // Process each file
      for (final file in result.files) {
        final kind = file['kind'] ?? '';
        final fileName = file['name'] as String? ?? 'Unknown';

        if (kind == 'drive#folder') {
          // Build path for subfolder
          final subfolderPath = includePaths
              ? (currentPath.isEmpty ? fileName : '$currentPath/$fileName')
              : '';

          // Recursively scan subfolder
          await _listFilesRecursiveHelper(
            folderId: file['id'],
            limit: limit,
            allFiles: allFiles,
            includePaths: includePaths,
            currentPath: subfolderPath,
          );
        } else {
          // Add file to results
          if (includePaths) {
            // Create a copy of the file with path information
            final fileWithPath = Map<String, dynamic>.from(file);

            // Build full path from root of scan
            final fullPath = currentPath.isEmpty
                ? fileName
                : '$currentPath/$fileName';

            // Add path metadata fields
            fileWithPath['_fullPath'] = fullPath;
            fileWithPath['_displayName'] = fileName; // Just the filename

            allFiles.add(fileWithPath);
          } else {
            // Original behavior - just add the file as-is
            allFiles.add(file);
          }
        }
      }

      nextPageToken = result.nextPageToken;
    } while (nextPageToken != null && nextPageToken.isNotEmpty);
  }

  // NOTE: Cold storage handling is done entirely in the video player with retry logic
  // Pre-validation was removed because:
  // 1. PikPak has two-stage activation (connection opens, then file becomes playable)
  // 2. Byte validation only detects stage 1, not stage 2
  // 3. Player retry logic is more reliable and provides better UX
  // 4. Hot files play instantly without validation overhead
}
