import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../profiles/profile_preferences.dart';

/// Profile-scoped torrent history persistence behind StorageService.
abstract final class TorrentSearchHistoryStore {
  static const String _torrentSearchHistoryKey = 'torrent_search_history_v1';
  static const String _torrentSearchHistoryEnabledKey =
      'torrent_search_history_enabled';

  /// Get torrent search history
  /// Returns list of maps containing torrent JSON + service + timestamp
  static Future<List<Map<String, dynamic>>> getTorrentSearchHistory() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_torrentSearchHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error loading torrent search history: $e');
      return [];
    }
  }

  /// Add torrent to search history with deduplication
  /// Deduplicates by infohash, keeps max 5 items (FIFO)
  static Future<void> addTorrentToHistory(
    Map<String, dynamic> torrentJson,
    String service,
  ) async {
    final prefs = await ProfilePreferences.instance();
    final history = await getTorrentSearchHistory();

    final infohash = torrentJson['infohash'] as String?;
    if (infohash == null || infohash.isEmpty) return;

    // Remove existing entry with same infohash (deduplicate)
    history.removeWhere((entry) {
      final entryTorrent = entry['torrent'] as Map<String, dynamic>?;
      return entryTorrent?['infohash'] == infohash;
    });

    // Add new entry at start
    history.insert(0, {
      'torrent': torrentJson,
      'service': service,
      'clickedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep only last 5
    if (history.length > 5) {
      history.removeRange(5, history.length);
    }

    await prefs.setString(_torrentSearchHistoryKey, jsonEncode(history));
  }

  /// Clear all search history
  static Future<void> clearTorrentSearchHistory() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_torrentSearchHistoryKey);
  }

  /// Get whether search history tracking is enabled
  static Future<bool> getTorrentSearchHistoryEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_torrentSearchHistoryEnabledKey) ?? true;
  }

  /// Set whether search history tracking is enabled
  static Future<void> setTorrentSearchHistoryEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_torrentSearchHistoryEnabledKey, enabled);
  }
}
