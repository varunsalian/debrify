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
  static const String _webUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36';

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

  /// Get captcha token from PikPak
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
      final captchaToken = await _getCaptchaToken(
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

      final headers = {
        'Content-Type': 'application/json',
        'User-Agent': _webUserAgent,
      };

      if (deviceId != null && deviceId.isNotEmpty) {
        headers['X-Device-ID'] = deviceId;
      }

      if (captchaToken != null && captchaToken.isNotEmpty) {
        headers['X-Captcha-Token'] = captchaToken;
      }

      headers['X-Client-ID'] = _webClientId;

      final response = await http.post(
        Uri.parse('$_authBaseUrl/v1/auth/token')
            .replace(queryParameters: {'client_id': _webClientId}),
        headers: headers,
        body: jsonEncode({
          'client_id': _webClientId,
          'client_secret': _webClientSecret,
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];

        // Save new tokens
        await StorageService.setPikPakAccessToken(_accessToken!);
        await StorageService.setPikPakRefreshToken(_refreshToken!);

        print('PikPak: Token refreshed successfully');
        return true;
      } else {
        print('PikPak: Token refresh failed: ${response.statusCode} - ${response.body}');

        try {
          final errorData = jsonDecode(response.body);
          final errorCode = errorData['error_code'];
          final errorType = errorData['error'] ?? '';
          final errorDesc = errorData['error_description'] ?? '';

          // Check for refresh token expired (invalid_grant) - requires full re-login
          if (errorType == 'invalid_grant' ||
              errorDesc.toString().toLowerCase().contains('refresh token') ||
              errorDesc.toString().toLowerCase().contains('expired')) {
            print('PikPak: Refresh token expired, clearing all auth data');
            await logout();
            return false;
          }

          // Check for captcha error (error code 4002)
          if (errorCode == 4002 || errorCode == '4002') {
            print('PikPak: Captcha token invalid, will need to re-login');
            await StorageService.clearPikPakCaptchaToken();
          }
        } catch (e) {
          // Ignore JSON parsing errors
        }

        return false;
      }
    } catch (e) {
      print('PikPak: Token refresh error: $e');
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
        final captchaToken = await _getCaptchaToken(
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

  /// Get file details by ID
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
        final captchaToken = await _getCaptchaToken(
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

  /// List files in a directory
  Future<List<Map<String, dynamic>>> listFiles({String? parentId, int limit = 100}) async {
    try {
      print('PikPak: Listing files (parent: ${parentId ?? "root"})');
      // IMPORTANT: Adding with_audit=true to get media links populated for each file
      final response = await _makeAuthenticatedRequest(
        'GET',
        '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true',
        null,
      );
      final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
      print('PikPak: Found ${files.length} files');
      return files;
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
        final captchaToken = await _getCaptchaToken(
          action: action,
          deviceId: deviceId,
          userId: userId,
        );

        await StorageService.setPikPakCaptchaToken(captchaToken);
        print('PikPak: Retrying with fresh captcha token');

        // Retry the request
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/files?parent_id=${parentId ?? ""}&thumbnail_size=SIZE_SMALL&limit=$limit&with_audit=true',
          null,
        );

        final files = List<Map<String, dynamic>>.from(response['files'] ?? []);
        print('PikPak: Found ${files.length} files (after retry)');
        return files;
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
              final files = await listFiles(parentId: fileId);
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
}
