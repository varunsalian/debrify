import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/http/gateway.dart';
import '../models/client_identity.dart';
import 'repository.dart';
import 'session.dart';
import '../models/file.dart';
import '../models/task.dart';
import 'api.dart';
import 'storage_session.dart';
import '../../../models/profiles/profile_policy.dart';
import '../../../services/profiles/profile_async_authorization.dart';
import '../../../services/profiles/connection_resource_service.dart';
import '../../../services/storage_service.dart';

/// The two body encodings PikPak accepts on its token endpoint.
enum _RefreshEncoding { json, form }

class PikPakApiService implements PikPakRepository {
  /// The transport, injected. No default and no static fallback: ServiceGraph
  /// builds it, which is what stops each adopting service from constructing
  /// its own with its own idea of a timeout.
  final HttpGateway _http;

  PikPakApiService({
    required HttpGateway http,
    required PikPakAuthSink publishAuth,
    PikPakClientIdentity identity = webIdentity,
  }) : _http = http,
       _publishAuth = publishAuth,
       _identity = identity;

  /// Written to, not owned. The ValueNotifier widgets listen to lives in
  /// composition; this service only announces the change.
  final PikPakAuthSink _publishAuth;

  /// How this app identifies itself to PikPak. Injected so there is exactly
  /// one of it — these headers used to be rebuilt by hand on five paths and
  /// had drifted apart.
  final PikPakClientIdentity _identity;

  /// The web client PikPak expects to be talking to. Kept as the default so
  /// composition names it in one place.
  static const webIdentity = PikPakClientIdentity(
    userAgent:
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) '
        'Gecko/20100101 Firefox/129.0',
    clientId: 'YUMx5nI8ZU8Ap8pm',
    clientSecret: 'dbw2OtmVEeuUvIptb1Coygx',
    clientVersion: '2.0.0',
    packageName: 'mypikpak.com',
    captchaSalts: [
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
    ],
  );

  // Mutex for captcha token refresh to prevent race conditions
  final Map<String, Completer<String>> _captchaRefreshInProgress = {};

  // Web Platform Algorithms for Captcha Sign (from rclone)

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

      // Signin identifies by username (as rclone does); every other action
      // identifies by user id.
      final isSignin = action == 'POST:/v1/auth/signin';
      final meta = _identity.captchaMeta(
        deviceId: deviceId,
        username: isSignin ? email : null,
        userId: isSignin ? null : userId,
      );

      final response = await _http.post(
        Uri.parse(
          '$_authBaseUrl/v1/shield/captcha/init',
        ).replace(queryParameters: {'client_id': _identity.clientId}),
        headers: {
          'Content-Type': 'application/json',
          ..._identity.headers(deviceId: deviceId),
        },
        body: jsonEncode({
          'action': action,
          'captcha_token': '',
          'client_id': _identity.clientId,
          'device_id': deviceId,
          'meta': meta,
          'redirect_uri': 'xlaccsdk01://xbase.cloud/callback?state=harbor',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data is Map ? data['captcha_token'] : null;
        if (token is! String || token.isEmpty) {
          throw PikPakUnexpectedResponse(
            'PikPak returned no captcha token.',
            statusCode: response.statusCode,
          );
        }
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
  Future<bool> login(String email, String password) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      if (authorization == null) {
        return await _loginScoped(email, password);
      }
      return await authorization.run(
        () => _loginScoped(email, password, authorization: authorization),
      );
    } on StateError {
      _publishAuth(false);
      return false;
    }
  }

  Future<bool> _loginScoped(
    String email,
    String password, {
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
      final response = await _http.post(
        Uri.parse(
          '$_authBaseUrl/v1/auth/signin',
        ).replace(queryParameters: {'client_id': _identity.clientId}),
        headers: {
          'Content-Type': 'application/json',
          ..._identity.headers(deviceId: deviceId, captchaToken: captchaToken),
        },
        body: jsonEncode({
          'captcha_token': captchaToken,
          'client_id': _identity.clientId,
          'client_secret': _identity.clientSecret,
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
        if (authorization == null || authorization.isCurrentlyActive) {
          _publishAuth(true);
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
        if (authorization == null || authorization.isCurrentlyActive) {
          _publishAuth(false);
        }
        return false;
      }
    } catch (e) {
      debugPrint('PikPak: Login error (${e.runtimeType})');
      if (authorization == null || authorization.isCurrentlyActive) {
        _publishAuth(false);
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
      if (authorization == null) return await _refreshAccessTokenScoped(null);
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
    if (await _tryRefresh(
      _RefreshEncoding.json,
      deviceId,
      captchaToken,
      refreshToken,
      authorization,
    )) {
      return true;
    }

    debugPrint('PikPak: JSON refresh failed, trying form-urlencoded format...');
    return await _tryRefresh(
      _RefreshEncoding.form,
      deviceId,
      captchaToken,
      refreshToken,
      authorization,
    );
  }

  /// Try refresh with JSON body (rclone's approach)
  /// One refresh, in whichever body encoding the caller wants to try.
  ///
  /// The two shapes were separate methods that differed only in Content-Type
  /// and how the same three fields were encoded; everything else — endpoint,
  /// query, success handling, error logging — was written twice.
  Future<bool> _tryRefresh(
    _RefreshEncoding encoding,
    String? deviceId,
    String? captchaToken,
    String refreshToken,
    ProfileAsyncAuthorization? authorization,
  ) async {
    // The rclone endpoint, which does not require client_secret.
    const refreshUrl = 'https://user.mypikpak.com/v1/auth/token';
    final isJson = encoding == _RefreshEncoding.json;

    // client_secret is deliberately absent: PikPak answers error_code 7 when
    // it is present, which is what the permission_denied reports were.
    final fields = {
      'client_id': _identity.clientId,
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
    };

    try {
      final response = await _http.post(
        Uri.parse(
          refreshUrl,
        ).replace(queryParameters: {'client_id': _identity.clientId}),
        headers: {
          'Content-Type': isJson
              ? 'application/json'
              : 'application/x-www-form-urlencoded',
          ..._identity.headers(deviceId: deviceId, captchaToken: captchaToken),
        },
        body: isJson ? jsonEncode(fields) : fields,
      );

      debugPrint(
        'PikPak: ${encoding.name} refresh response status: '
        '${response.statusCode}',
      );

      if (response.statusCode == 200) {
        return await _handleSuccessfulRefresh(response.body, authorization);
      }
      _logRefreshError(response.body);
      return false;
    } catch (e) {
      debugPrint('PikPak: ${encoding.name} refresh error (${e.runtimeType})');
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
      final success = await login(email, password);

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

  /// Run [attempt], and if PikPak rejects it for a stale captcha, fetch a
  /// fresh one for [action] and run it once more.
  ///
  /// This dance was written out eight times — createFolder, addOfflineDownload,
  /// getTaskStatus, both batch deletes, getFileMetadata, getFileDetails and the
  /// listing — each spelling the request twice, and they had already drifted in
  /// which of them logged what.
  Future<T> _retryWithFreshCaptcha<T>(
    String action,
    Future<T> Function() attempt,
  ) async {
    try {
      return await attempt();
    } catch (e) {
      if (!_isStaleCaptcha(e)) rethrow;
      debugPrint('PikPak: Captcha rejected for $action, refreshing');
      await _refreshCaptchaToken(action);
      return attempt();
    }
  }

  /// PikPak rejects a stale captcha with error_code 4002.
  ///
  /// Read off [PikPakRequestFailed] where there is one — every drive call goes
  /// through [PikPakApi] and gets the typed failure. The auth calls (captcha
  /// init, signin, both refresh shapes) still go straight to the gateway and
  /// throw a plain exception carrying only PikPak's sentence, so that spelling
  /// stays as a fallback until they move behind the client too.
  bool _isStaleCaptcha(Object e) {
    if (e is PikPakRequestFailed) return e.code == 4002 || e.code == '4002';
    return e.toString().contains('Verification code is invalid');
  }

  Future<void> _refreshCaptchaToken(String action) async {
    final deviceId = await StorageService.getPikPakDeviceId();
    if (deviceId == null) {
      throw Exception('No device ID found. Please login first.');
    }
    final userId = await StorageService.getPikPakUserId();
    if (userId == null) {
      debugPrint('PikPak: no user ID stored; captcha may be refused');
    }
    await StorageService.setPikPakCaptchaToken(
      await _getCaptchaTokenSynchronized(
        action: action,
        deviceId: deviceId,
        userId: userId,
      ),
    );
  }

  /// Everything that touches the cloud runs under the active profile's scope,
  /// so a switch mid-flight cannot write one profile's data into another's.
  Future<T> _inCloudScope<T>(Future<T> Function() body) async {
    final authorization = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
    );
    return authorization == null ? body() : authorization.run(body);
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

  /// Make an authenticated API request with automatic token refresh
  Future<Map<String, dynamic>> _makeAuthenticatedRequest(
    String method,
    String url,
    Map<String, dynamic>? body,
  ) async {
    return _inCloudScope(
      () => _makeAuthenticatedRequestScoped(method, url, body),
    );
  }

  Future<Map<String, dynamic>> _makeAuthenticatedRequestScoped(
    String method,
    String url,
    Map<String, dynamic>? body,
  ) async {
    await _ensureAuthenticated();
    return _api.send(
      method == 'GET' ? HttpMethod.get : HttpMethod.post,
      Uri.parse(url),
      body: body,
    );
  }

  /// Headers, the one refresh-and-retry, PikPak's error payload and the
  /// timeout all live in [PikPakApi] now. This used to spell the same request
  /// out three times and time none of them out.
  late final PikPakApi _api = PikPakApi(
    http: _http,
    session: StoragePikPakSession(onRefresh: refreshAccessToken),
    identity: _identity,
  );

  /// Create a folder in PikPak
  /// Returns the created folder's metadata including its ID
  Future<PikPakFile> createFolder({
    required String folderName,
    String? parentFolderId,
  }) => _retryWithFreshCaptcha('POST:/drive/v1/files', () async {
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
    return PikPakFile.fromJson(response);
  });

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

          // Verify it's still the right folder
          if (metadata.name == folderName &&
              metadata.isFolder &&
              metadata.parentId == (parentFolderId ?? '')) {
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
          if (file.name == folderName && file.isFolder) {
            final folderId = file.id;
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

      // PikPakFile.fromJson already unwraps the `file` envelope PikPak
      // sometimes puts a created folder inside.
      final folderId = folderData.id.isEmpty ? null : folderData.id;

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
  Future<PikPakTask> addOfflineDownload(
    String magnetLink, {
    String? parentFolderId,
  }) => _retryWithFreshCaptcha('POST:/drive/v1/files', () async {
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
    return PikPakTask.fromJson(response);
  });

  /// Get task status by task ID
  /// Returns task details including progress (0-100) and phase
  Future<PikPakTask> getTaskStatus(String taskId) =>
      _retryWithFreshCaptcha('GET:/drive/v1/tasks', () async {
        debugPrint('PikPak: Getting task status');
        final response = await _makeAuthenticatedRequest(
          'GET',
          '$_driveBaseUrl/drive/v1/tasks/$taskId',
          null,
        );
        final task = PikPakTask.fromJson(response);
        debugPrint(
          'PikPak: Task status retrieved - progress: ${task.progress}, '
          'phase: ${task.phase.name}',
        );
        return task;
      });

  /// Move files to trash (recoverable)
  /// Returns true if successful
  Future<bool> batchTrashFiles(List<String> fileIds) {
    if (fileIds.isEmpty) return Future.value(true);
    return _retryWithFreshCaptcha('POST:/drive/v1/files:batchTrash', () async {
      debugPrint('PikPak: Moving ${fileIds.length} file(s) to trash...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchTrash',
        {'ids': fileIds},
      );

      debugPrint('PikPak: Files moved to trash successfully');
      return true;
    });
  }

  /// Permanently delete files (not recoverable)
  /// Returns true if successful
  Future<bool> batchDeleteFiles(List<String> fileIds) {
    if (fileIds.isEmpty) return Future.value(true);
    return _retryWithFreshCaptcha('POST:/drive/v1/files:batchDelete', () async {
      debugPrint('PikPak: Permanently deleting ${fileIds.length} file(s)...');

      await _makeAuthenticatedRequest(
        'POST',
        '$_driveBaseUrl/drive/v1/files:batchDelete',
        {'ids': fileIds},
      );

      debugPrint('PikPak: Files deleted permanently');
      return true;
    });
  }

  /// Whether credentials are present. A query, not a publication: it used to
  /// publish on its way out, so any observer that reacted by
  /// asking this re-triggered itself. That loop is what
  /// `login(notifyListeners: false)` existed to break.
  Future<bool> isAuthenticated() async {
    try {
      final accessToken = await StorageService.getPikPakAccessToken();
      final refreshToken = await StorageService.getPikPakRefreshToken();
      return accessToken != null && refreshToken != null;
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
    _publishAuth(false);
  }

  /// Logout - clear all tokens
  Future<void> logout() async {
    await StorageService.clearPikPakAuth();
    _publishAuth(false);
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

        // Verify it's actually a folder
        if (metadata.isFolder) {
          debugPrint('PikPak: Restricted folder verified - still exists');
          return true;
        } else {
          debugPrint(
            'PikPak: Restricted folder ID points to non-folder '
            '(kind: ${metadata.kind.name})',
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
  Future<PikPakFile> getFileMetadata(
    String fileId,
  ) => _retryWithFreshCaptcha('GET:/drive/v1/files', () async {
    debugPrint('PikPak: Getting basic file metadata');
    // Get basic file info WITHOUT usage=FETCH (faster, no streaming URL resolution)
    final response = await _makeAuthenticatedRequest(
      'GET',
      '$_driveBaseUrl/drive/v1/files/$fileId',
      null,
    );
    debugPrint('PikPak: File metadata retrieved successfully');
    return PikPakFile.fromJson(response);
  });

  /// Get file details by ID (including streaming URLs - slower)
  Future<PikPakFile> getFileDetails(
    String fileId,
  ) => _retryWithFreshCaptcha('GET:/drive/v1/files', () async {
    debugPrint('PikPak: Getting file details');
    // CRITICAL FIX: Adding usage=FETCH parameter to populate download URLs
    // This is required to get web_content_link and medias populated in response
    final response = await _makeAuthenticatedRequest(
      'GET',
      '$_driveBaseUrl/drive/v1/files/$fileId?usage=FETCH&_magic=2021&thumbnail_size=SIZE_LARGE&with_audit=true',
      null,
    );
    debugPrint('PikPak: File details retrieved successfully');
    return PikPakFile.fromJson(response);
  });

  /// List files in a directory with pagination support
  /// Returns a record containing the files list and optional next page token
  Future<({List<PikPakFile> files, String? nextPageToken})> listFiles({
    String? parentId,
    int limit = 50,
    String? pageToken,
  }) async {
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
      final files = PikPakFile.listFromJson(response);
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

        final files = PikPakFile.listFromJson(response);
        final nextPageToken = response['next_page_token'] as String?;
        debugPrint('PikPak: Found ${files.length} files after retry');
        return (files: files, nextPageToken: nextPageToken);
      } else {
        debugPrint('PikPak: Failed to list files (${e.runtimeType})');
        rethrow;
      }
    }
  }

  /// Wait for download to complete with polling
  /// Returns file data when phase is PHASE_TYPE_COMPLETE
  /// Throws TimeoutException if download doesn't complete within timeout
  Future<PikPakFile> waitForDownloadComplete(
    String fileId, {
    Duration pollInterval = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 5),
    Function(int)? onProgress,
  }) async {
    debugPrint('PikPak: Waiting for download to complete');
    final startTime = DateTime.now();

    String? failure;

    while (DateTime.now().difference(startTime) < timeout) {
      await Future.delayed(pollInterval);

      try {
        final fileData = await getFileDetails(fileId);

        debugPrint(
          'PikPak: Download phase: ${fileData.phase.name}, '
          'kind: ${fileData.kind.name}',
        );

        // Check if complete
        if (fileData.isReady) {
          debugPrint('PikPak: Download completed!');

          // Torrents often download as folders.
          if (fileData.isFolder) {
            debugPrint(
              'PikPak: Downloaded item is a folder, listing contents...',
            );
            try {
              final result = await listFiles(parentId: fileId);
              final files = result.files;
              debugPrint('PikPak: Found ${files.length} files in folder');

              // Find the first video file. The listing entry has no download
              // URLs, so re-fetch the one we pick with full details.
              for (final file in files) {
                if (file.isVideo) {
                  debugPrint('PikPak: Found video file');
                  return await getFileDetails(file.id);
                }
              }

              if (files.isNotEmpty) {
                debugPrint('PikPak: No video found, using first file');
                return await getFileDetails(files.first.id);
              }
            } catch (e) {
              debugPrint(
                'PikPak: Error listing folder contents (${e.runtimeType})',
              );
            }
          }

          return fileData;
        }

        if (fileData.hasFailed) {
          failure = 'PikPak reported the download failed';
          break;
        }

        onProgress?.call(fileData.progress);
      } catch (e) {
        // File might not exist yet, continue polling
        debugPrint('PikPak: Polling error; will retry (${e.runtimeType})');
        continue;
      }
    }

    if (failure != null) throw Exception(failure);

    throw TimeoutException(
      'Download did not complete within ${timeout.inMinutes} minutes',
    );
  }

  /// Add magnet link and wait for it to be ready for streaming
  /// Returns file data with streaming URL when ready
  Future<PikPakFile> addAndWaitForReady(
    String magnetLink, {
    Function(int)? onProgress,
  }) async {
    debugPrint('PikPak: Adding magnet and waiting for ready state');

    // Step 1: Add offline download
    final addResponse = await addOfflineDownload(magnetLink);

    // PikPakTask.fromJson already unwraps the `task` envelope and reads
    // file_id, which is the drive entry the download is filling in.
    final fileId = addResponse.fileId.isNotEmpty
        ? addResponse.fileId
        : addResponse.id;

    if (fileId.isEmpty) {
      throw Exception('Could not extract file ID from add response');
    }

    // Step 2: Wait for download to complete
    final fileData = await waitForDownloadComplete(
      fileId,
      onProgress: onProgress,
    );

    // Step 3: Verify streaming URL is available
    if (fileData.streamingUrl == null) {
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
  /// - [includePaths]: When true each file carries [PikPakFile.fullPath], the
  ///   path from the scan root (e.g. "Season 1/Episode 1.mkv"). Default false.
  Future<List<PikPakFile>> listFilesRecursive({
    required String folderId,
    int limit = 50,
    bool includePaths = false,
  }) async {
    final allFiles = <PikPakFile>[];
    await _listFilesRecursiveHelper(
      folderId: folderId,
      limit: limit,
      allFiles: allFiles,
      includePaths: includePaths,
      currentPath: '', // Start with empty path at root
    );
    return allFiles;
  }

  /// Helper method for recursive folder traversal.
  ///
  /// When [includePaths] is true each file carries [PikPakFile.fullPath] — the
  /// path from the scan root, e.g. `Season 1/Episode 1.mkv`. [PikPakFile.name]
  /// stays the bare filename either way.
  Future<void> _listFilesRecursiveHelper({
    required String folderId,
    required int limit,
    required List<PikPakFile> allFiles,
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
        final fileName = file.name.isEmpty ? 'Unknown' : file.name;
        final path = currentPath.isEmpty ? fileName : '$currentPath/$fileName';

        if (file.isFolder) {
          await _listFilesRecursiveHelper(
            folderId: file.id,
            limit: limit,
            allFiles: allFiles,
            includePaths: includePaths,
            currentPath: includePaths ? path : '',
          );
        } else {
          allFiles.add(includePaths ? file.at(path) : file);
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
