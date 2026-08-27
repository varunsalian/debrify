import 'package:flutter/foundation.dart';
import '../models/alldebrid_user.dart';
import 'storage_service.dart';
import 'alldebrid_service.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/connection_resource_service.dart';

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
      final capability = await ProfileAsyncAuthorization.capture(
        ProfileFeature.cloud,
      );
      debugPrint('AllDebridAccountService: Validating API key…');
      final user = capability == null
          ? await AllDebridService.getUserInfo(apiKey)
          : await capability.run(() => AllDebridService.getUserInfo(apiKey));
      if (_validationToken != token) {
        debugPrint(
          'AllDebridAccountService: Validation result discarded (token mismatch).',
        );
        return false;
      }
      if (capability != null && !capability.isCurrentlyActive) return false;
      Future<void> commit() async {
        if (persist) await StorageService.saveAllDebridApiKey(apiKey);
        if (capability == null || capability.isCurrentlyActive) {
          _setCurrentUser(user);
        }
      }

      if (capability == null) {
        await commit();
      } else {
        await capability.runIfCurrent(commit);
      }
      debugPrint('AllDebridAccountService: Validation successful.');
      return true;
    } catch (e) {
      debugPrint('AllDebridAccountService: Validation failed.');
      return false;
    } finally {
      if (_validationToken == token) _isValidating = false;
    }
  }

  static Future<bool> isApiKeyValid() async {
    try {
      final apiKey = await StorageService.getAllDebridApiKey();
      if (apiKey == null || apiKey.isEmpty) return false;
      return validateAndGetUserInfo(apiKey, persist: false);
    } on ResourceAuthorizationException {
      // A profile switch deliberately revokes a credential read in flight.
      return false;
    }
  }

  static void clearUserInfo() {
    debugPrint('AllDebridAccountService: Clearing cached user info.');
    _setCurrentUser(null);
    _validationToken++;
    _isValidating = false;
  }

  static Future<bool> refreshUserInfo() async {
    try {
      final apiKey = await StorageService.getAllDebridApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _setCurrentUser(null);
        return false;
      }
      return validateAndGetUserInfo(apiKey, persist: false);
    } on ResourceAuthorizationException {
      // Do not clear the newly active profile's process-global user state.
      return false;
    }
  }
}
