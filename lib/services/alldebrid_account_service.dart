import 'package:flutter/foundation.dart';
import '../models/alldebrid_user.dart';
import '../services/storage_service.dart';
import '../services/alldebrid_service.dart';

class AllDebridAccountService {
  static AllDebridUser? _currentUser;
  static bool _isValidating = false;
  static int _validationToken = 0;

  /// Notifier for reactive UI updates when user state changes.
  static final ValueNotifier<AllDebridUser?> userNotifier = ValueNotifier(null);

  static AllDebridUser? get currentUser => _currentUser;

  static bool get isValidating => _isValidating;

  static void _setCurrentUser(AllDebridUser? user) {
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
      debugPrint('AllDebridAccountService: Validating API key…');
      final user = await AllDebridService.getUserInfo(apiKey);
      if (_validationToken != token) {
        debugPrint(
          'AllDebridAccountService: Validation result discarded (token mismatch).',
        );
        return false;
      }
      _setCurrentUser(user);
      if (persist) {
        await StorageService.saveAllDebridApiKey(apiKey);
      }
      debugPrint(
        'AllDebridAccountService: Validation successful for ${user.username}.',
      );
      return true;
    } catch (e) {
      debugPrint('AllDebridAccountService: Validation failed - $e');
      _setCurrentUser(null);
      return false;
    } finally {
      _isValidating = false;
    }
  }

  static Future<bool> isApiKeyValid() async {
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return false;
    }
    return validateAndGetUserInfo(apiKey, persist: false);
  }

  static void clearUserInfo() {
    debugPrint('AllDebridAccountService: Clearing cached user info.');
    _setCurrentUser(null);
    _validationToken++;
  }

  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _setCurrentUser(null);
      return false;
    }
    return validateAndGetUserInfo(apiKey, persist: false);
  }
}
