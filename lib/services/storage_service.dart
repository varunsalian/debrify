import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class StorageService {
  static const String _apiKeyKey = 'real_debrid_api_key';
  static const String _fileSelectionKey = 'real_debrid_file_selection';
  static const String _postTorrentActionKey = 'post_torrent_action';
  static const String _batteryOptStatusKey = 'battery_opt_status_v1'; // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  
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

  // Post-torrent action methods
  static Future<String> getPostTorrentAction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_postTorrentActionKey) ?? 'copy'; // Default to copy to clipboard
  }

  static Future<void> savePostTorrentAction(String action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postTorrentActionKey, action);
  }



  // Battery optimization status
  static Future<String> getBatteryOptimizationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_batteryOptStatusKey) ?? 'unknown';
  }

  static Future<void> setBatteryOptimizationStatus(String status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_batteryOptStatusKey, status);
  }

  // Video resume map helpers
  static Future<Map<String, dynamic>> _getVideoResumeMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_videoResumeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveVideoResumeMap(Map<String, dynamic> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_videoResumeKey, jsonEncode(map));
  }

  static Future<Map<String, dynamic>?> getVideoResume(String key) async {
    final map = await _getVideoResumeMap();
    final entry = map[key];
    if (entry is Map<String, dynamic>) return entry;
    return null;
  }

  static Future<void> upsertVideoResume(String key, Map<String, dynamic> entry) async {
    final map = await _getVideoResumeMap();
    map[key] = entry;
    await _saveVideoResumeMap(map);
  }
} 