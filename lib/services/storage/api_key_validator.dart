import 'package:debrify/services/debrid_service.dart';

class ApiKeyValidator {
  static bool isValidFormat(String apiKey) {
    // Real Debrid API keys are typically 40 characters
    return apiKey.length == 40 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(apiKey);
  }

  static Future<bool> validateApiKey(String apiKey) async {
    if (!isValidFormat(apiKey)) return false;

    try {
      await DebridService.getUserInfo(apiKey);
      return true; // If we get here, the API key is valid
    } catch (e) {
      return false;
    }
  }
}
