import 'package:flutter/foundation.dart';
import '../models/rd_user.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';

class AccountService {
  static RDUser? _currentUser;
  static bool _isValidating = false;

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
    try {
      // Use fallback validation which tries primary then backup endpoint
      final result = await DebridService.validateApiKeyWithFallback(apiKey);

      if (result['success'] == true) {
        _setCurrentUser(result['user'] as RDUser);

        // Save API key to storage
        await StorageService.saveApiKey(apiKey);
        // Endpoint is already saved by validateApiKeyWithFallback

        return true;
      } else {
        _setCurrentUser(null);
        return false;
      }
    } catch (e) {
      _setCurrentUser(null);
      return false;
    } finally {
      _isValidating = false;
    }
  }

  // Check if API key exists and is valid
  static Future<bool> isApiKeyValid() async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return false;
    }
    
    return await validateAndGetUserInfo(apiKey);
  }

  // Clear cached user info
  static void clearUserInfo() {
    _setCurrentUser(null);
  }

  // Refresh user info
  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _setCurrentUser(null);
      return false;
    }
    
    return await validateAndGetUserInfo(apiKey);
  }
} 