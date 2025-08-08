import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _defaultDownloadUriKey = 'default_download_saf_uri';
  
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

  // Default download folder (SAF URI)
  static Future<String?> getDefaultDownloadUri() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultDownloadUriKey);
  }

  static Future<void> saveDefaultDownloadUri(String uri) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultDownloadUriKey, uri);
  }

  static Future<void> clearDefaultDownloadUri() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_defaultDownloadUriKey);
  }
} 