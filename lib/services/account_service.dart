import '../models/rd_user.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';

class AccountService {
  static RDUser? _currentUser;
  static bool _isValidating = false;

  // Get current user info (cached)
  static RDUser? get currentUser => _currentUser;

  // Check if currently validating
  static bool get isValidating => _isValidating;

  // Validate API key and get user info
  static Future<bool> validateAndGetUserInfo(String apiKey) async {
    if (_isValidating) return false;
    
    _isValidating = true;
    try {
      final user = await DebridService.getUserInfo(apiKey);
      _currentUser = user;
      return true;
    } catch (e) {
      _currentUser = null;
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
    _currentUser = null;
  }

  // Refresh user info
  static Future<bool> refreshUserInfo() async {
    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _currentUser = null;
      return false;
    }
    
    return await validateAndGetUserInfo(apiKey);
  }
} 