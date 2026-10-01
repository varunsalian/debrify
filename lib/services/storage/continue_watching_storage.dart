import 'dart:convert';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/utils/json_isolate.dart';

final class ContinueWatchingStorage {
  const ContinueWatchingStorage._();
  // Shared within lib/services/storage/.
  static const String continueWatchingKey = 'continue_watching_v1';

  // ── Continue Watching (recently watched items for home screen) ──────────

  /// Get all continue watching items, sorted by most recent first.
  static Future<List<Map<String, dynamic>>> getContinueWatchingItems() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(continueWatchingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)).toList();
      for (final item in items) {
        final id = item['imdbId'];
        final type = item['contentType'];
        if (id is String && type is String) {
          item['imdbId'] = MediaIdentity.progressId(id, type);
        }
      }
      items.sort(
        (a, b) => ((b['updatedAt'] as int?) ?? 0).compareTo(
          (a['updatedAt'] as int?) ?? 0,
        ),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Add or update a continue watching entry.
  /// Deduplicates by IMDB ID — updates existing entry if found.
  static Future<void> saveContinueWatchingItem({
    required String imdbId,
    required String title,
    required String contentType,
    String? posterUrl,
    String? addonId,
    String? year,
  }) async {
    imdbId = MediaIdentity.progressId(imdbId, contentType);
    // Server-owned titles reopen through Discover, not catalog lookup.
    if (imdbId.startsWith('medialibrary:')) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(continueWatchingKey);
    List<Map<String, dynamic>> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = await decodeJsonAsync(raw);
        items = list.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    // Remove existing entry with same IMDB ID
    // Preserve the original predicate punctuation during this verbatim split.
    // dart format off
    items.removeWhere((e) => MediaIdentity.progressId(
      e['imdbId'] as String? ?? '', e['contentType'] as String? ?? '',
    ) == imdbId);
    // dart format on

    // Add at front
    items.insert(0, {
      'imdbId': imdbId,
      'title': title,
      'contentType': contentType,
      'posterUrl': posterUrl,
      'addonId': addonId,
      'year': year,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep max 50 items
    if (items.length > 50) items = items.sublist(0, 50);

    await saveContinueWatchingItems(items, tombstoneRemovals: false);
  }

  /// Remove a continue watching entry by IMDB ID.
  static Future<void> removeContinueWatchingItem(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(continueWatchingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)).toList();
      final before = items.length;
      items.removeWhere(
        (e) =>
            MediaIdentity.progressId(
              (e['imdbId'] as String? ?? '').trim().toLowerCase(),
              e['contentType'] as String? ?? '',
            ) ==
            normalized,
      );
      if (items.length == before) return;
      await saveContinueWatchingItems(items);
    } catch (_) {}
  }

  /// Clear all continue watching items.
  static Future<void> clearContinueWatching({
    bool recordSyncDeletions = true,
  }) async {
    await saveContinueWatchingItems(
      const <Map<String, dynamic>>[],
      tombstoneRemovals: recordSyncDeletions,
    );
  }

  // Shared within lib/services/storage/.
  static Future<void> saveContinueWatchingItems(
    List<Map<String, dynamic>> items, {
    bool tombstoneRemovals = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (tombstoneRemovals) {
      final previous = await getContinueWatchingItems();
      final retained = <String>{
        for (final item in items)
          if ((item['imdbId']?.toString().trim().toLowerCase() ?? '').isNotEmpty)
            item['imdbId'].toString().trim().toLowerCase(),
      };
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(
              (item) => item['imdbId']?.toString().trim().toLowerCase() ?? '',
            )
            .where((id) => id.isNotEmpty && !retained.contains(id))
            .map(WebDavSyncRecordKey.continueWatching),
      );
    }
    await prefs.setString(continueWatchingKey, jsonEncode(items));
  }
}
