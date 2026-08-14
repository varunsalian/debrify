import 'package:flutter/foundation.dart';
import '../models/torbox_user.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/connection_resource_service.dart';

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
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      debugPrint('TorboxAccountService: Validating API key…');
      final user = capability == null
          ? await TorboxService.getUserInfo(apiKey)
          : await capability.run(() => TorboxService.getUserInfo(apiKey));
      if (_validationToken != token) {
        debugPrint(
          'TorboxAccountService: Validation result discarded (token mismatch).',
        );
        return false;
      }
      if (capability != null && !capability.isCurrentlyActive) return false;
      Future<void> commit() async {
        if (persist) await StorageService.saveTorboxApiKey(apiKey);
        if (capability == null || capability.isCurrentlyActive) {
          _setCurrentUser(user);
        }
      }

      if (capability == null) {
        await commit();
      } else {
        await capability.runIfCurrent(commit);
      }
      debugPrint('TorboxAccountService: Validation successful.');
      return true;
    } catch (e) {
      debugPrint('TorboxAccountService: Validation failed.');
      return false;
    } finally {
      if (_validationToken == token) _isValidating = false;
    }
  }

  static Future<bool> isApiKeyValid() async {
    try {
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) return false;
      return validateAndGetUserInfo(apiKey, persist: false);
    } on ResourceAuthorizationException {
      return false;
    }
  }

  static void clearUserInfo() {
    debugPrint('TorboxAccountService: Clearing cached user info.');
    _setCurrentUser(null);
    _validationToken++;
    _isValidating = false;
  }

  static Future<bool> refreshUserInfo() async {
    try {
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _setCurrentUser(null);
        return false;
      }
      return validateAndGetUserInfo(apiKey, persist: false);
    } on ResourceAuthorizationException {
      return false;
    }
  }
}
