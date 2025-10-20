import 'package:flutter/foundation.dart';
import '../models/torbox_user.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';

class TorboxAccountService {
  static TorboxUser? _currentUser;
  static bool _isValidating = false;

  static TorboxUser? get currentUser => _currentUser;

  static bool get isValidating => _isValidating;

  static Future<bool> validateAndGetUserInfo(String apiKey) async {
    if (_isValidating) return false;

    _isValidating = true;
    try {
      debugPrint('TorboxAccountService: Validating API key…');
      final user = await TorboxService.getUserInfo(apiKey);
      _currentUser = user;
      await StorageService.saveTorboxApiKey(apiKey);
      debugPrint(
        'TorboxAccountService: Validation successful for ${user.email}.',
      );
      return true;
    } catch (e) {
      debugPrint('TorboxAccountService: Validation failed - $e');
      _currentUser = null;
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

    return validateAndGetUserInfo(apiKey);
  }

  static void clearUserInfo() {
    debugPrint('TorboxAccountService: Clearing cached user info.');
    _currentUser = null;
  }

  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getTorboxApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _currentUser = null;
      return false;
    }

    return validateAndGetUserInfo(apiKey);
  }
}
