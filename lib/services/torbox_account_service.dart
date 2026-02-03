import 'package:flutter/foundation.dart';
import '../models/torbox_user.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';

class TorboxAccountService {
  static TorboxUser? _currentUser;
  static bool _isValidating = false;
  static int _validationToken = 0;

  /// Notifier for reactive UI updates when user state changes
  static final ValueNotifier<TorboxUser?> userNotifier = ValueNotifier(null);

  static TorboxUser? get currentUser => _currentUser;

  static bool get isValidating => _isValidating;

  // Internal setter that also notifies listeners
  static void _setCurrentUser(TorboxUser? user) {
    _currentUser = user;
    userNotifier.value = user;
  }

  static Future<bool> validateAndGetUserInfo(
    String apiKey, {
    bool persist = true,
  }) async {
    if (_isValidating) return false;

    _isValidating = true;
    final int token = ++_validationToken;
    try {
      debugPrint('TorboxAccountService: Validating API key…');
      final user = await TorboxService.getUserInfo(apiKey);
      if (_validationToken != token) {
        debugPrint(
          'TorboxAccountService: Validation result discarded (token mismatch).',
        );
        return false;
      }
      _setCurrentUser(user);
      if (persist) {
        await StorageService.saveTorboxApiKey(apiKey);
      }
      debugPrint(
        'TorboxAccountService: Validation successful for ${user.email}.',
      );
      return true;
    } catch (e) {
      debugPrint('TorboxAccountService: Validation failed - $e');
      _setCurrentUser(null);
      return false;
    } finally {
      _isValidating = false;
    }
  }

  static Future<bool> isApiKeyValid() async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return false;
    }

    return validateAndGetUserInfo(apiKey, persist: false);
  }

  static void clearUserInfo() {
    debugPrint('TorboxAccountService: Clearing cached user info.');
    _setCurrentUser(null);
    _validationToken++;
  }

  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _setCurrentUser(null);
      return false;
    }

    return validateAndGetUserInfo(apiKey, persist: false);
  }
}
