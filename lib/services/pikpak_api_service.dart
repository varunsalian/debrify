import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

class PikPakApiService {
  static final PikPakApiService instance = PikPakApiService._internal();
  factory PikPakApiService() => instance;
  PikPakApiService._internal();

  // Web Platform Constants (more reliable than Android/iOS)
  static const String _webClientId = 'YUMx5nI8ZU8Ap8pm';
  static const String _webClientSecret = 'dbw2OtmVEeuUvIptb1Coygx';
  static const String _webClientVersion = '2.0.0';
  static const String _webPackageName = 'mypikpak.com';
  // User-Agent should match Firefox (as used by rclone) for best compatibility
  static const String _webUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0';

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

  // In-memory tokens
  String? _accessToken;
  String? _refreshToken;
  String? _email;
  String? _userId;

  /// Generate device ID from email and password (MD5 hash)
  String _generateDeviceId(String email, String password) {
    final bytes = utf8.encode(email + password);
    final digest = md5.convert(bytes);
    return digest.toString();
  }

  /// Calculate captcha sign using web platform algorithms
  String _getCaptchaSign(String deviceId, [String? timestamp]) {
    // Use provided timestamp or generate new one
    timestamp ??= DateTime.now().millisecondsSinceEpoch.toString();

    // Start with: ClientID + ClientVersion + PackageName + DeviceID + Timestamp
    String str = _webClientId + _webClientVersion + _webPackageName + deviceId + timestamp;

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
      print('PikPak: Captcha refresh already in progress for $action, waiting...');
      try {
        return await existingRefresh.future;
      } catch (e) {
        // If the existing refresh failed, we'll try ourselves
        print('PikPak: Existing captcha refresh failed, attempting new request');
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
      print('PikPak: Requesting captcha token for action: $action');

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
        meta['username'] = email;  // rclone uses 'username' not 'email' for login
      }
      // For all other actions (file operations), add user_id
      else if (userId != null) {
        meta['user_id'] = userId;
      }

      print('PikPak: Captcha meta fields - captcha_sign: ${captchaSign.substring(0, 10)}..., timestamp: $timestamp');

      final response = await http.post(
        Uri.parse('$_authBaseUrl/v1/shield/captcha/init')
            .replace(queryParameters: {'client_id': _webClientId}),
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
        print('PikPak: Captcha token obtained successfully');
        return token;
      } else {
        print('PikPak: Failed to get captcha token: ${response.statusCode}');
        print('PikPak: Response body: ${response.body}');

        // Try to parse error details
        try {
          final errorData = jsonDecode(response.body);
          final errorCode = errorData['error_code'];
          final errorDesc = errorData['error_description'] ?? errorData['error'] ?? 'Unknown error';
          print('PikPak: Error code: $errorCode, Description: $errorDesc');
        } catch (e) {
          // Ignore parsing errors
        }

        throw Exception('Failed to get captcha token: ${response.statusCode}');
      }
    } catch (e) {
      print('PikPak: Captcha token error: $e');
      rethrow;
    }
  }

  /// Login with email and password
  Future<bool> login(String email, String password) async {
    try {
      print('PikPak: Logging in as $email...');

      // 1. Generate or load device ID
      String? deviceId = await StorageService.getPikPakDeviceId();
      if (deviceId == null) {
        deviceId = _generateDeviceId(email, password);
        await StorageService.setPikPakDeviceId(deviceId);
        print('PikPak: Generated new device ID: $deviceId');
      } else {
        print('PikPak: Using existing device ID: $deviceId');
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
        Uri.parse('$_authBaseUrl/v1/auth/signin')
            .replace(queryParameters: {'client_id': _webClientId}),
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
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];
        _userId = data['sub'];
        _email = email;

        // Save everything
        await StorageService.setPikPakEmail(email);
        await StorageService.setPikPakPassword(password);
        await StorageService.setPikPakAccessToken(_accessToken!);
        await StorageService.setPikPakRefreshToken(_refreshToken!);
        await StorageService.setPikPakCaptchaToken(captchaToken);
        if (_userId != null) {
          await StorageService.setPikPakUserId(_userId!);
        }

        print('PikPak: Login successful');
        return true;
      } else {
        final errorData = jsonDecode(response.body);
        print('PikPak: Login failed: ${errorData['error_description'] ?? errorData['error'] ?? response.body}');
        return false;
      }
    } catch (e) {
      print('PikPak: Login error: $e');
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
      if (_refreshToken == null) {
        // Try to load from storage
        _refreshToken = await StorageService.getPikPakRefreshToken();
        if (_refreshToken == null) {
          print('PikPak: No refresh token available');
          return false;
        }
      }

      print('PikPak: Refreshing access token...');

      final deviceId = await StorageService.getPikPakDeviceId();
      final captchaToken = await StorageService.getPikPakCaptchaToken();

      // Try multiple refresh methods in order of preference
      // Method 1: Standard OAuth2 refresh without client_secret (rclone approach)
      // Method 2: Fallback with re-authentication using stored credentials

      final success = await _tryRefreshWithoutClientSecret(deviceId, captchaToken);
      if (success) {
        return true;
      }

      // Method 2: Try re-authentication with stored credentials
      print('PikPak: Standard refresh failed, attempting re-authentication...');
      return await _tryReAuthenticate();
    } catch (e) {
      print('PikPak: Token refresh error: $e');
      return false;
    }
  }

  /// Attempt token refresh without client_secret (standard OAuth2 flow)
  /// This is the primary method following rclone's implementation
  Future<bool> _tryRefreshWithoutClientSecret(String? deviceId, String? captchaToken) async {
    // Try JSON format first (rclone approach), then form-urlencoded (standard OAuth2)
    if (await _tryRefreshJson(deviceId, captchaToken)) {
      return true;
    }

    print('PikPak: JSON refresh failed, trying form-urlencoded format...');
    return await _tryRefreshFormUrlEncoded(deviceId, captchaToken);
  }

  /// Try refresh with JSON body (rclone's approach)
  Future<bool> _tryRefreshJson(String? deviceId, String? captchaToken) async {
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
        Uri.parse(refreshUrl).replace(queryParameters: {'client_id': _webClientId}),
        headers: headers,
        body: jsonEncode({
          'client_id': _webClientId,
          // NOTE: client_secret is intentionally NOT included
          // PikPak rejects requests with client_secret with error_code 7
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        }),
      );

      print('PikPak: JSON refresh response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return await _handleSuccessfulRefresh(response.body);
      } else {
        _logRefreshError(response.body);
        return false;
      }
    } catch (e) {
      print('PikPak: Error during JSON refresh: $e');
      return false;
    }
  }

  /// Try refresh with form-urlencoded body (standard OAuth2 format)
  Future<bool> _tryRefreshFormUrlEncoded(String? deviceId, String? captchaToken) async {
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
        'refresh_token': _refreshToken!,
      };

      final response = await http.post(
        Uri.parse(refreshUrl).replace(queryParameters: {'client_id': _webClientId}),
        headers: headers,
        body: body,
      );

      print('PikPak: Form-urlencoded refresh response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        return await _handleSuccessfulRefresh(response.body);
      } else {
        _logRefreshError(response.body);
        return false;
      }
    } catch (e) {
      print('PikPak: Error during form-urlencoded refresh: $e');
      return false;
    }
  }

  /// Handle successful token refresh response
  Future<bool> _handleSuccessfulRefresh(String responseBody) async {
    try {
      final data = jsonDecode(responseBody);
      _accessToken = data['access_token'];

      // Update refresh token if a new one is provided
      if (data['refresh_token'] != null) {
        _refreshToken = data['refresh_token'];
        await StorageService.setPikPakRefreshToken(_refreshToken!);
      }

      // Save new access token
      await StorageService.setPikPakAccessToken(_accessToken!);

      // Also update user ID if provided
      if (data['sub'] != null) {
        _userId = data['sub'];
        await StorageService.setPikPakUserId(_userId!);
      }

      print('PikPak: Token refreshed successfully');
      return true;
    } catch (e) {
      print('PikPak: Error parsing refresh response: $e');
      return false;
    }
  }

  /// Log refresh error details
  void _logRefreshError(String responseBody) {
    print('PikPak: Refresh failed: $responseBody');
    try {
      final errorData = jsonDecode(responseBody);
      final errorCode = errorData['error_code'];
      final errorType = errorData['error'] ?? '';
      final errorDesc = errorData['error_description'] ?? '';
      print('PikPak: Error code: $errorCode, type: $errorType, desc: $errorDesc');

      // If invalid_grant, the refresh token itself is expired
      if (errorType == 'invalid_grant' ||
          errorDesc.toString().toLowerCase().contains('refresh token') ||
          errorDesc.toString().toLowerCase().contains('invalid refresh')) {
        print('PikPak: Refresh token is invalid/expired');
      }

      // If permission_denied (error code 7), this indicates client_secret issue
      if (errorCode == 7 || errorCode == '7') {
        print('PikPak: Permission denied - this should not happen without client_secret');
      }

      // If captcha error, clear it
      if (errorCode == 4002 || errorCode == '4002') {
        print('PikPak: Captcha token invalid during refresh');
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
      final email = await StorageService.getPikPakEmail();
      final password = await StorageService.getPikPakPassword();

      if (email == null || password == null) {
        print('PikPak: No stored credentials for re-authentication');
        // Clear all auth data since we can't recover
        await logout();
        return false;
      }

      print('PikPak: Re-authenticating with stored credentials...');
      final success = await login(email, password);

      if (success) {
        print('PikPak: Re-authentication successful');
        return true;
      } else {
        print('PikPak: Re-authentication failed');
        // Don't clear credentials yet - user might need to re-login manually
        return false;
      }
    } catch (e) {
      print('PikPak: Re-authentication error: $e');
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
      // Clear in-memory tokens if storage is empty
      _accessToken = null;
      _refreshToken = null;
      throw Exception('Not authenticated. Please login first.');
    }

    // Update in-memory tokens from storage
    _accessToken = storedAccessToken;
    _refreshToken = storedRefreshToken;
    _email = await StorageService.getPikPakEmail();
    _userId = await StorageService.getPikPakUserId();
  }

  /// Make an authenticated API request with automatic token refresh
  Future<Map<String, dynamic>> _makeAuthenticatedRequest(
    String method,
    String url,
    Map<String, dynamic>? body,
  ) async {
    await _ensureAuthenticated();

    final deviceId = await StorageService.getPikPakDeviceId();
    final captchaToken = await StorageService.getPikPakCaptchaToken();

    final headers = {
      'Authorization': 'Bearer $_accessToken',
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
      response = await http.get(
        Uri.parse(url),
        headers: headers,
      );
    } else {
      throw Exception('Unsupported HTTP method: $method');
    }

    // Handle 401 - token expired
    if (response.statusCode == 401) {
      print('PikPak: Access token expired, refreshing...');
      if (await refreshAccessToken()) {
        // Retry the request with new token
        headers['Authorization'] = 'Bearer $_accessToken';

        // Also reload captcha token in case it was refreshed
        final updatedCaptchaToken = await StorageService.getPikPakCaptchaToken();
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
          response = await http.get(
            Uri.parse(url),
            headers: headers,
          );
        }
      } else {
        throw Exception('Failed to refresh token. Please login again.');
      }
    }

    if (response.statusCode == 429) {
      throw Exception('Rate limit exceeded. Please try again later.');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      final errorData = jsonDecode(response.body);
      final errorCode = errorData['error_code'];
      final errorMessage = errorData['error_description'] ?? errorData['error'] ?? '';

      // Check for access token expired (error_code 16 or "unauthenticated")
      // PikPak returns this with non-401 status codes
      if (errorCode == 16 || errorCode == '16' ||
          errorMessage.toString().toLowerCase().contains('access token') ||
          errorData['error'] == 'unauthenticated') {
        print('PikPak: Access token expired (error_code: $errorCode), attempting refresh...');

        if (await refreshAccessToken()) {
          print('PikPak: Token refreshed, retrying request...');
          // Retry the request with new token
          headers['Authorization'] = 'Bearer $_accessToken';

          // Also reload captcha token in case it was refreshed
          final updatedCaptchaToken = await StorageService.getPikPakCaptchaToken();
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
            response = await http.get(
              Uri.parse(url),
              headers: headers,
            );
          }

          // Check if retry succeeded
          if (response.statusCode >= 200 && response.statusCode < 300) {
            return jsonDecode(response.body);
          } else {
            // If retry also failed, throw the new error
            final retryErrorData = jsonDecode(response.body);
            throw Exception(retryErrorData['error_description'] ?? retryErrorData['error'] ?? 'API request failed after token refresh');
          }
        } else {
          // Refresh failed - clear tokens and require re-login
          print('PikPak: Token refresh failed, clearing auth and requiring re-login');
          await logout();
          throw Exception('Session expired. Please login again.');
        }
      }

      // Check for captcha error (error code 4002)
      if (errorCode == 4002 || errorCode == '4002') {
        print('PikPak: Captcha token invalid (error 4002), clearing token');
        await StorageService.clearPikPakCaptchaToken();
      }

      throw Exception(errorMessage.isNotEmpty ? errorMessage : 'API request failed');
    }
  }

  /// Add offline download (magnet link)
  Future<Map<String, dynamic>> addOfflineDownload(String magnetLink) async {
    try {
      print('PikPak: Adding offline download...');

      // Try using existing captcha token first (from login)
      final response = await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files',
        {
          'kind': 'drive#file',
          'name': '',
          'upload_type': 'UPLOAD_TYPE_URL',
          'url': {
            'url': magnetLink,
          },
          'folder_type': '',
        },
      );

      print('PikPak: Offline download added successfully');
      return response;
    } catch (e) {
      // If we get verification error, try requesting a fresh captcha token
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        // Get userId for file operations
        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          print('PikPak: Warning: No user ID found, this might cause issues');
        }

        final action = 'POST:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        print('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files',
          {
            'kind': 'drive#file',
            'name': '',
            'upload_type': 'UPLOAD_TYPE_URL',
            'url': {
              'url': magnetLink,
            },
            'folder_type': '',
          },
        );

        print('PikPak: Offline download added successfully');
        return response;
      } else {
        print('PikPak: Failed to add offline download: $e');
        rethrow;
      }
    }
  }

  /// Get task status by task ID
  /// Returns task details including progress (0-100) and phase
  Future<Map<String, dynamic>> getTaskStatus(String taskId) async {
    try {
      print('PikPak: Getting task status for $taskId');
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/tasks/$taskId',
        null,
      );
      print('PikPak: Task status retrieved - progress: ${response['progress']}, phase: ${response['phase']}');
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid for task status, requesting fresh token...');

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
        print('PikPak: Retrying task status with fresh captcha token');

        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/tasks/$taskId',
          null,
        );
        print('PikPak: Task status retrieved (after retry) - progress: ${response['progress']}, phase: ${response['phase']}');
        return response;
      } else {
        print('PikPak: Failed to get task status: $e');
        rethrow;
      }
    }
  }

  /// Move files to trash (recoverable)
  /// Returns true if successful
  Future<bool> batchTrashFiles(List<String> fileIds) async {
    if (fileIds.isEmpty) return true;

    try {
      print('PikPak: Moving ${fileIds.length} file(s) to trash...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchTrash',
        {'ids': fileIds},
      );

      print('PikPak: Files moved to trash successfully');
      return true;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

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
        print('PikPak: Retrying with fresh captcha token');

        await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files:batchTrash',
          {'ids': fileIds},
        );

        print('PikPak: Files moved to trash successfully (after retry)');
        return true;
      } else {
        print('PikPak: Failed to move files to trash: $e');
        rethrow;
      }
    }
  }

  /// Permanently delete files (not recoverable)
  /// Returns true if successful
  Future<bool> batchDeleteFiles(List<String> fileIds) async {
    if (fileIds.isEmpty) return true;

    try {
      print('PikPak: Permanently deleting ${fileIds.length} file(s)...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchDelete',
        {'ids': fileIds},
      );

      print('PikPak: Files deleted permanently');
      return true;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

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
        print('PikPak: Retrying with fresh captcha token');

        await _makeAuthenticatedRequest(
          'POST',
          '$_driveBaseUrl/drive/v1/files:batchDelete',
          {'ids': fileIds},
        );

        print('PikPak: Files deleted permanently (after retry)');
        return true;
      } else {
        print('PikPak: Failed to delete files: $e');
        rethrow;
      }
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final accessToken = await StorageService.getPikPakAccessToken();
    final refreshToken = await StorageService.getPikPakRefreshToken();
    return accessToken != null && refreshToken != null;
  }

  /// Logout - clear all tokens
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _email = null;
    _userId = null;
    await StorageService.clearPikPakAuth();
    print('PikPak: Logged out');
  }

  /// Get current email
  Future<String?> getEmail() async {
    if (_email != null) return _email;
    _email = await StorageService.getPikPakEmail();
    return _email;
  }

  /// Test connection by trying to list files
  Future<bool> testConnection() async {
    try {
      await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files?parent_id=&thumbnail_size=SIZE_SMALL&limit=10',
        null,
      );
      print('PikPak: Connection test successful');
      return true;
    } catch (e) {
      print('PikPak: Connection test failed: $e');
      return false;
    }
  }

  /// Get basic file metadata by ID (without resolving streaming URLs)
  /// This is faster than getFileDetails as it doesn't include usage=FETCH
  /// Use this when you only need file name, size, mime type, etc. for sorting/filtering
  Future<Map<String, dynamic>> getFileMetadata(String fileId) async {
    try {
      print('PikPak: Getting basic file metadata for $fileId');
      // Get basic file info WITHOUT usage=FETCH (faster, no streaming URL resolution)
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files/$fileId',
        null,
      );
      print('PikPak: File metadata retrieved successfully');
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          print('PikPak: Warning: No user ID found, this might cause issues');
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        print('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/files/$fileId',
          null,
        );

        print('PikPak: File metadata retrieved successfully (after retry)');
        return response;
      } else {
        print('PikPak: Failed to get file metadata: $e');
        rethrow;
      }
    }
  }

  /// Get file details by ID (including streaming URLs - slower)
  Future<Map<String, dynamic>> getFileDetails(String fileId) async {
    try {
      print('PikPak: Getting file details for $fileId');
      // CRITICAL FIX: Adding usage=FETCH parameter to populate download URLs
      // This is required to get web_content_link and medias populated in response
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files/$fileId?usage=FETCH&_magic=2021&thumbnail_size=SIZE_LARGE&with_audit=true',
        null,
      );
      print('PikPak: File details retrieved successfully');
      return response;
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          print('PikPak: Warning: No user ID found, this might cause issues');
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        print('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/files/$fileId?usage=FETCH&_magic=2021&thumbnail_size=SIZE_LARGE&with_audit=true',
          null,
        );

        print('PikPak: File details retrieved successfully (after retry)');
        return response;
      } else {
        print('PikPak: Failed to get file details: $e');
        rethrow;
      }
    }
  }

  /// List files in a directory with pagination support
  /// Returns a record containing the files list and optional next page token
  Future<({List<Map<String, dynamic>> files, String? nextPageToken})> listFiles({
    String? parentId,
    int limit = 50,
    String? pageToken,
  }) async {
    try {
      print('PikPak: Listing files (parent: ${parentId ?? "root"}, pageToken: ${pageToken ?? "none"})');
      // IMPORTANT: Adding with_audit=true to get media links populated for each file
      // Adding filters to exclude trashed files (deleted files go to trash first in PikPak)
      final filters = Uri.encodeComponent('{"trashed":{"eq":false}}');
      String url = '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true&filters=$filters';
      if (pageToken != null && pageToken.isNotEmpty) {
        url += '&page_token=$pageToken';
      }
      final response = await _makeAuthenticatedRequest('GET', url, null);
      final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
      final nextPageToken = response['next_page_token'] as String?;
      print('PikPak: Found ${files.length} files, nextPageToken: ${nextPageToken ?? "none"}');
      return (files: files, nextPageToken: nextPageToken);
    } catch (e) {
      // If captcha verification fails, get fresh token and retry
      if (e.toString().contains('Verification code is invalid')) {
        print('PikPak: Captcha token invalid, requesting fresh token...');

        final deviceId = await StorageService.getPikPakDeviceId();
        if (deviceId == null) {
          throw Exception('No device ID found. Please login first.');
        }

        final userId = await StorageService.getPikPakUserId();
        if (userId == null) {
          print('PikPak: Warning: No user ID found, this might cause issues');
        }

        final action = 'GET:/drive/v1/files';
        final captchaToken = await _getCaptchaTokenSynchronized(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        print('PikPak: Retrying with fresh captcha token');

        // Retry the request with same filters
        final retryFilters = Uri.encodeComponent('{"trashed":{"eq":false}}');
        String retryUrl = '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true&filters=$retryFilters';
        if (pageToken != null && pageToken.isNotEmpty) {
          retryUrl += '&page_token=$pageToken';
        }
        final response = await _makeAuthenticatedRequest('GET', retryUrl, null);

        final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
        final nextPageToken = response['next_page_token'] as String?;
        print('PikPak: Found ${files.length} files (after retry), nextPageToken: ${nextPageToken ?? "none"}');
        return (files: files, nextPageToken: nextPageToken);
      } else {
        print('PikPak: Failed to list files: $e');
        rethrow;
      }
    }
  }

  /// Extract streaming URL from file metadata
  /// Prefers media links (better for video streaming) over web_content_link
  String? getStreamingUrl(Map<String, dynamic> fileData) {
    // DEBUG: Print entire file data structure to understand what we're getting
    print('PikPak: File data keys: ${fileData.keys.toList()}');
    print('PikPak: File data JSON: ${jsonEncode(fileData)}');

    // DEBUG: Check specific fields
    print('PikPak: kind = ${fileData['kind']}');
    print('PikPak: medias = ${fileData['medias']}');
    print('PikPak: web_content_link = ${fileData['web_content_link']}');
    print('PikPak: links = ${fileData['links']}');

    // Check medias array first (better for video streaming)
    final medias = fileData['medias'] as List?;
    if (medias != null && medias.isNotEmpty) {
      print('PikPak: Found ${medias.length} media entries');
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
        print('PikPak: Using media link for streaming');
        return url;
      }
    }

    // Fallback to web_content_link
    final webLink = fileData['web_content_link'];
    if (webLink != null && webLink.isNotEmpty) {
      print('PikPak: Using web_content_link for streaming');
      return webLink;
    }

    print('PikPak: No streaming URL found in file data');
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
    print('PikPak: Waiting for download to complete (fileId: $fileId)');
    final startTime = DateTime.now();

    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(pollInterval);

      try {
        final fileData = await getFileDetails(fileId);
        final phase = fileData['phase'];
        final kind = fileData['kind'];

        print('PikPak: Download phase: $phase, kind: $kind');

        // Check if complete
        if (phase == 'PHASE_TYPE_COMPLETE') {
          print('PikPak: Download completed!');

          // DEBUG: Check if it's a folder (torrents often download as folders)
          if (kind == 'drive#folder') {
            print('PikPak: Downloaded item is a folder, listing contents...');
            try {
              final result = await listFiles(parentId: fileId);
              final files = result.files;
              print('PikPak: Found ${files.length} files in folder');

              // Find the first video file
              for (final file in files) {
                final mimeType = file['mime_type'] ?? '';
                print('PikPak: File: ${file['name']}, mime: $mimeType');
                if (mimeType.startsWith('video/')) {
                  print('PikPak: Found video file: ${file['name']}');
                  // CRITICAL FIX: Fetch full file details with download URLs
                  final videoFileId = file['id'];
                  final fullVideoData = await getFileDetails(videoFileId);
                  return fullVideoData;
                }
              }

              // If no video found, return first file with full details
              if (files.isNotEmpty) {
                print('PikPak: No video found, using first file: ${files[0]['name']}');
                final firstFileId = files[0]['id'];
                final fullFileData = await getFileDetails(firstFileId);
                return fullFileData;
              }
            } catch (e) {
              print('PikPak: Error listing folder contents: $e');
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
              onProgress(progress is int ? progress : int.parse(progress.toString()));
            } catch (e) {
              // Ignore progress parsing errors
            }
          }
        }
      } catch (e) {
        // File might not exist yet, continue polling
        print('PikPak: Polling error (will retry): $e');
        continue;
      }
    }

    throw TimeoutException('Download did not complete within ${timeout.inMinutes} minutes');
  }

  /// Add magnet link and wait for it to be ready for streaming
  /// Returns file data with streaming URL when ready
  Future<Map<String, dynamic>> addAndWaitForReady(
    String magnetLink, {
    Function(int)? onProgress,
  }) async {
    print('PikPak: Adding magnet and waiting for ready state');

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

    print('PikPak: File ID: $fileId');

    // Step 2: Wait for download to complete
    final fileData = await waitForDownloadComplete(fileId, onProgress: onProgress);

    // Step 3: Verify streaming URL is available
    final streamingUrl = getStreamingUrl(fileData);
    if (streamingUrl == null) {
      throw Exception('File completed but no streaming URL available');
    }

    print('PikPak: Ready for streaming! URL: ${streamingUrl.substring(0, 50)}...');
    return fileData;
  }

  /// Recursively list all files in a folder and its subfolders
  /// Returns a flat list of all files found
  Future<List<Map<String, dynamic>>> listFilesRecursive({
    required String folderId,
    int limit = 50,
  }) async {
    final allFiles = <Map<String, dynamic>>[];
    await _listFilesRecursiveHelper(
      folderId: folderId,
      limit: limit,
      allFiles: allFiles,
    );
    return allFiles;
  }

  /// Helper method for recursive folder traversal
  Future<void> _listFilesRecursiveHelper({
    required String folderId,
    required int limit,
    required List<Map<String, dynamic>> allFiles,
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

        if (kind == 'drive#folder') {
          // Recursively scan subfolder
          await _listFilesRecursiveHelper(
            folderId: file['id'],
            limit: limit,
            allFiles: allFiles,
          );
        } else {
          // Add file to results
          allFiles.add(file);
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
