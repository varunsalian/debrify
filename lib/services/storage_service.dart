import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  
  // API Key methods
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_apiKeyKey);
  }

  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
  }

  static Future<void> deleteApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_apiKeyKey);
  }

  // File Selection methods
  static Future<String> getFileSelection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_fileSelectionKey) ?? 'largest'; // Default to largest file
  }

  static Future<void> saveFileSelection(String selection) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fileSelectionKey, selection);
  }
} 