import 'dart:convert';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/tvos_recovery_limits.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';

final class WatchlistStorage {
  const WatchlistStorage._();
  static const String _myWatchlistKey = TvOsRecoveryLimits.myWatchlistPreferenceKey;

  // ========================================================================
  // My Watchlist (movies + series)
  // ========================================================================

  /// Stable identity for Debrify's local movie/series watchlist. Prefer IMDb
  /// so the same title coming from two addons is one entry; fall back to the
  /// source addon + its content id for titles that do not expose IMDb metadata.
  /// Addon ids are part of that fallback because content ids are addon-local.
  static bool supportsMyWatchlistItem(StremioMeta item) {
    final type = item.type.trim().toLowerCase();
    return type == 'movie' || type == 'series';
  }

  /// Returns the identity-bearing item used by both watchlist reads and
  /// writes. A stored source is authoritative for non-IMDb ids; [fallback]
  /// only fills in a source for a newly opened source-less item.
  static StremioMeta withMyWatchlistSource(
    StremioMeta item,
    StremioAddon fallback,
  ) => item.sourceAddon == null ? item.withSourceAddon(fallback) : item;

  static String myWatchlistItemKey(StremioMeta item) {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final type = item.type.trim().toLowerCase();
    final imdbId = item.effectiveImdbId?.trim();
    if (imdbId != null && imdbId.isNotEmpty) return '$type:$imdbId';

    final sourceId = item.sourceAddon?.id.trim();
    final namespace = (sourceId == null || sourceId.isEmpty) ? 'unknown' : sourceId;
    return '$type:addon:${Uri.encodeComponent(namespace)}:'
        '${Uri.encodeComponent(item.id)}';
  }

  /// tvOS durability ceiling for the encoded watchlist. The recovery envelope
  /// silently skips any single value over its per-value limit, which would
  /// resurrect the wipe-on-restart bug; the 16KiB margin covers the
  /// JSON-escaping inflation the value picks up inside the envelope.
  static const int myWatchlistTvOsCapBytes = TvOsRecoveryLimits.envelopeValueBytes - 16 * 1024;

  /// Test seam: `PlatformUtil.isTvOS` is a `static final` and cannot be
  /// overridden, so tests drive the cap through this instead.
  @visibleForTesting
  static bool? debugMyWatchlistTvOsCapOverride;

  static bool get _myWatchlistCapEnforced => debugMyWatchlistTvOsCapOverride ?? PlatformUtil.isTvOS;

  static int _myWatchlistAddedAt(Map<String, dynamic> row) {
    final raw = row['addedAt'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw) ?? 0;
    return 0;
  }

  /// Recomputes keys from stored metadata so rows written by the original
  /// un-namespaced fallback scheme migrate in memory immediately. The next
  /// mutation persists the canonical key.
  static void _canonicalizeMyWatchlistRowKey(Map<String, dynamic> row) {
    final raw = row['item'];
    if (raw is! Map) return;
    try {
      final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
      if (supportsMyWatchlistItem(item)) {
        row['key'] = myWatchlistItemKey(item);
      }
    } catch (_) {
      // The item loader below will ignore the malformed row.
    }
  }

  static Future<List<Map<String, dynamic>>> _readMyWatchlistRows() async {
    final prefs = await ProfilePreferences.instance();
    final encoded = prefs.getString(_myWatchlistKey);
    if (encoded == null) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final rows = [
        for (final row in decoded)
          if (row is Map) Map<String, dynamic>.from(row),
      ];
      for (final row in rows) {
        _canonicalizeMyWatchlistRowKey(row);
      }
      return rows;
    } catch (e) {
      debugPrint('Error reading My Watchlist: $e');
      return <Map<String, dynamic>>[];
    }
  }

  /// Saved titles, newest first. Corrupt individual rows are ignored so one
  /// bad addon payload cannot make the whole shelf disappear.
  static Future<List<StremioMeta>> getMyWatchlistItems() async {
    final rows = await _readMyWatchlistRows();
    rows.sort(
      (a, b) => _myWatchlistAddedAt(b).compareTo(_myWatchlistAddedAt(a)),
    );
    final items = <StremioMeta>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.id.isEmpty || !supportsMyWatchlistItem(item)) {
          continue;
        }
        items.add(item);
      } catch (_) {
        // Skip only the malformed row.
      }
    }
    return items;
  }

  static Future<bool> isInMyWatchlist(StremioMeta item) async {
    if (!supportsMyWatchlistItem(item)) return false;
    final key = myWatchlistItemKey(item);
    final rows = await _readMyWatchlistRows();
    return rows.any((row) => row['key'] == key);
  }

  /// Adds, refreshes, or removes a title. Adding stores the full presentation
  /// metadata needed by Home, not just an id, so My Watchlist paints instantly
  /// offline and can route back through the source addon when it is installed.
  static Future<void> setMyWatchlistItem(StremioMeta item, bool saved) async {
    if (!supportsMyWatchlistItem(item)) {
      throw ArgumentError.value(
        item.type,
        'item.type',
        'My Watchlist supports only movies and series',
      );
    }
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final key = myWatchlistItemKey(item);
    final existing = rows.where((row) => row['key'] == key).firstOrNull;
    rows.removeWhere((row) => row['key'] == key);
    if (saved) {
      rows.insert(0, {
        'key': key,
        'addedAt': existing == null ? DateTime.now().millisecondsSinceEpoch : _myWatchlistAddedAt(existing),
        'item': item.toJson(),
      });
    }
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      var encoded = jsonEncode(rows);
      if (_myWatchlistCapEnforced) {
        // Oldest rows go first. The scan starts past index 0 because the row
        // just written sits there — a re-save keeps its original addedAt, so
        // an oldest-by-timestamp scan could otherwise evict exactly it.
        while (rows.length > 1 && utf8.encode(encoded).length > myWatchlistTvOsCapBytes) {
          var oldest = 1;
          for (var i = 2; i < rows.length; i++) {
            if (_myWatchlistAddedAt(rows[i]) < _myWatchlistAddedAt(rows[oldest])) {
              oldest = i;
            }
          }
          rows.removeAt(oldest);
          encoded = jsonEncode(rows);
        }
      }
      await prefs.setString(_myWatchlistKey, encoded);
    }
  }

  /// Removes a saved movie/series once actual playback is about to launch.
  /// IMDb is authoritative. Older/addon-local items without IMDb metadata use
  /// a conservative title/source fallback and are removed only when unique.
  static Future<bool> removeMyWatchlistItemForPlayback({
    String? imdbId,
    required String contentType,
    required String title,
    String? addonId,
  }) async {
    final type = contentType.trim().toLowerCase();
    if (type != 'movie' && type != 'series') return false;
    final normalizedImdb = imdbId?.trim().toLowerCase();
    final normalizedTitle = title.trim().toLowerCase();
    final normalizedAddon = addonId?.trim().toLowerCase();
    final prefs = await ProfilePreferences.instance();
    final rows = await _readMyWatchlistRows();
    final matches = <Map<String, dynamic>>[];
    for (final row in rows) {
      final raw = row['item'];
      if (raw is! Map) continue;
      try {
        final item = StremioMeta.fromJson(Map<String, dynamic>.from(raw));
        if (item.type.trim().toLowerCase() != type) continue;
        final itemImdb = item.effectiveImdbId?.trim().toLowerCase();
        if (normalizedImdb != null && normalizedImdb.isNotEmpty) {
          if (itemImdb == normalizedImdb) matches.add(row);
          continue;
        }
        if (itemImdb != null && itemImdb.isNotEmpty) continue;
        if (normalizedTitle.isEmpty || item.name.trim().toLowerCase() != normalizedTitle) {
          continue;
        }
        final itemAddon = item.sourceAddon?.id.trim().toLowerCase();
        if (normalizedAddon != null && normalizedAddon.isNotEmpty && itemAddon != normalizedAddon) {
          continue;
        }
        matches.add(row);
      } catch (_) {
        // Malformed rows are ignored rather than making playback fail.
      }
    }
    if (matches.length != 1) return false;
    rows.remove(matches.single);
    if (rows.isEmpty) {
      await prefs.remove(_myWatchlistKey);
    } else {
      await prefs.setString(_myWatchlistKey, jsonEncode(rows));
    }
    return true;
  }

  static Future<void> clearMyWatchlist() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_myWatchlistKey);
  }
}
