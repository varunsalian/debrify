import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/debrify_tv_cache.dart';

class DebrifyTvCacheService {
  static const String _prefsKey = 'debrify_tv_channel_cache_v1';
  static const int _schemaVersion = 1;
  static const int _maxEntries = 50;

  static Future<Map<String, DebrifyTvChannelCacheEntry>> loadAllEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return <String, DebrifyTvChannelCacheEntry>{};
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, DebrifyTvChannelCacheEntry>{};
      }

      final Map<String, DebrifyTvChannelCacheEntry> entries = {};
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) {
          return;
        }
        try {
          final entry = DebrifyTvChannelCacheEntry.fromJson(
            Map<String, dynamic>.from(value as Map),
          );
          if (entry.version == _schemaVersion) {
            entries[key] = entry;
          }
        } catch (_) {}
      });
      return entries;
    } catch (_) {
      return <String, DebrifyTvChannelCacheEntry>{};
    }
  }

  static Future<DebrifyTvChannelCacheEntry?> getEntry(String channelId) async {
    final all = await loadAllEntries();
    return all[channelId];
  }

  static Future<DebrifyTvChannelCacheEntry?> updateEntry(
    String channelId,
    DebrifyTvChannelCacheEntry? Function(
      DebrifyTvChannelCacheEntry? current,
    ) updater,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAllEntries();
    final next = updater(all[channelId]);

    if (next == null) {
      all.remove(channelId);
    } else {
      all[channelId] = next;
      _pruneOverflow(all);
    }

    await _persistAll(prefs, all);
    return next;
  }

  static Future<void> saveEntry(DebrifyTvChannelCacheEntry entry) async {
    await updateEntry(entry.channelId, (_) => entry);
  }

  static Future<void> removeEntry(String channelId) async {
    await updateEntry(channelId, (_) => null);
  }

  static Future<void> pruneExpired(Duration ttl) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadAllEntries();
    if (all.isEmpty) {
      return;
    }

    final threshold = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    final keysToRemove = all.entries
        .where((entry) => entry.value.fetchedAt > 0 && entry.value.fetchedAt < threshold)
        .map((entry) => entry.key)
        .toList();

    if (keysToRemove.isEmpty) {
      return;
    }

    for (final key in keysToRemove) {
      all.remove(key);
    }

    await _persistAll(prefs, all);
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static void _pruneOverflow(Map<String, DebrifyTvChannelCacheEntry> entries) {
    if (entries.length <= _maxEntries) {
      return;
    }
    final sorted = entries.entries.toList()
      ..sort(
        (a, b) => (a.value.fetchedAt).compareTo(b.value.fetchedAt),
      );
    final overflow = sorted.length - _maxEntries;
    for (int i = 0; i < overflow; i++) {
      entries.remove(sorted[i].key);
    }
  }

  static Future<void> _persistAll(
    SharedPreferences prefs,
    Map<String, DebrifyTvChannelCacheEntry> entries,
  ) async {
    final jsonMap = entries.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(jsonMap));
  }
}
