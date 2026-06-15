import 'package:flutter/foundation.dart';
import '../models/premiumize_user.dart';
import '../services/storage_service.dart';
import '../services/premiumize_service.dart';

class PremiumizeAccountService {
  static PremiumizeUser? _currentUser;
  static bool _isValidating = false;
  static int _validationToken = 0;

  /// Notifier for reactive UI updates when user state changes.
  static final ValueNotifier<PremiumizeUser?> userNotifier =
      ValueNotifier(null);

  static PremiumizeUser? get currentUser => _currentUser;

  static bool get isValidating => _isValidating;

  static void _setCurrentUser(PremiumizeUser? user) {
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
      debugPrint('PremiumizeAccountService: Validating API key…');
      final user = await PremiumizeService.getUserInfo(apiKey);
      if (_validationToken != token) {
        debugPrint(
          'PremiumizeAccountService: Validation result discarded (token mismatch).',
        );
        return false;
      }
      _setCurrentUser(user);
      if (persist) {
        await StorageService.savePremiumizeApiKey(apiKey);
      }
      debugPrint(
        'PremiumizeAccountService: Validation successful for customer ${user.customerId}.',
      );
      return true;
    } catch (e) {
      debugPrint('PremiumizeAccountService: Validation failed - $e');
      _setCurrentUser(null);
      return false;
    } finally {
      _isValidating = false;
    }
  }

  static Future<bool> isApiKeyValid() async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return false;
    }
    return validateAndGetUserInfo(apiKey, persist: false);
  }

  static void clearUserInfo() {
    debugPrint('PremiumizeAccountService: Clearing cached user info.');
    _setCurrentUser(null);
    _validationToken++;
  }

  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _setCurrentUser(null);
      return false;
    }
    return validateAndGetUserInfo(apiKey, persist: false);
  }
}
