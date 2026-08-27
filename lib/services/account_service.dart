import 'package:flutter/foundation.dart';
import '../models/rd_user.dart';
import 'debrid_service.dart';
import 'storage_service.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/connection_resource_service.dart';

class AccountService {
  static RDUser? _currentUser;
  static bool _isValidating = false;
  static int _validationToken = 0;

  /// Notifier for reactive UI updates when user state changes
  static final ValueNotifier<RDUser?> userNotifier = ValueNotifier(null);

  // Get current user info (cached)
  static RDUser? get currentUser => _currentUser;

  // Internal setter that also notifies listeners
  static void _setCurrentUser(RDUser? user) {
    _currentUser = user;
    userNotifier.value = user;
  }

  // Check if currently validating
  static bool get isValidating => _isValidating;

  // Validate API key and get user info (with automatic endpoint fallback)
  static Future<bool> validateAndGetUserInfo(String apiKey) async {
    if (_isValidating) return false;

    _isValidating = true;
    final token = ++_validationToken;
    try {
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      // Use fallback validation which tries primary then backup endpoint
      final result = capability == null
          ? await DebridService.validateApiKeyWithFallback(apiKey)
          : await capability.run(
              () => DebridService.validateApiKeyWithFallback(apiKey),
            );

      if (_validationToken != token) return false;
      if (result['success'] == true) {
        if (capability != null && !capability.isCurrentlyActive) return false;
        Future<void> commit() async {
          await StorageService.saveApiKey(apiKey);
          if (capability == null || capability.isCurrentlyActive) {
            _setCurrentUser(result['user'] as RDUser);
          }
        }

        if (capability == null) {
          await commit();
        } else {
          await capability.runIfCurrent(commit);
        }
        // Endpoint is already saved by validateApiKeyWithFallback

        return true;
      } else if (capability == null || capability.isCurrentlyActive) {
        _setCurrentUser(null);
        return false;
      }
      return false;
    } catch (e) {
      // A stale completion belongs to its initiating session and must not
      // clear the newly active profile's process-global account state.
      return false;
    } finally {
      if (_validationToken == token) _isValidating = false;
    }
  }

  // Check if API key exists and is valid
  static Future<bool> isApiKeyValid() async {
    try {
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) return false;
      return validateAndGetUserInfo(apiKey);
    } on ResourceAuthorizationException {
      return false;
    }
  }

  // Clear cached user info
  static void clearUserInfo() {
    _setCurrentUser(null);
    _validationToken++;
    _isValidating = false;
  }

  // Refresh user info
  static Future<bool> refreshUserInfo() async {
    try {
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _setCurrentUser(null);
        return false;
      }
      return validateAndGetUserInfo(apiKey);
    } on ResourceAuthorizationException {
      return false;
    }
  }
}
