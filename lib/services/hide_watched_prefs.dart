import 'package:flutter/foundation.dart' show visibleForTesting;

import 'profiles/profile_preferences.dart';

/// Synchronously cached "Hide watched titles" switch (Settings › Tracking).
///
/// Same shape as `DiscoverPrefs`: a static cache warmed in `main()` and again
/// on profile switch, because the filter that honours it runs inside list
/// construction and cannot await storage. Setters are cache-first so a flip is
/// visible on the very next build while the disk write is still in flight.
class HideWatchedPrefs {
  HideWatchedPrefs._();

  // Profile-scoped. Persisted, so never rename without a migration.
  static const String _key = 'hide_watched_titles';

  static bool _enabled = false;
  static bool _warmed = false;

  /// Whether watched movies and finished shows are hidden from catalog
  /// surfaces. Off until the user asks.
  static bool get enabled => _enabled;

  /// Load the switch into the cache. Repeat calls are no-ops until
  /// [resetProfileScope].
  static Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    try {
      final prefs = await ProfilePreferences.instance();
      _enabled = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Storage unavailable — stay off for this session.
    }
  }

  /// Re-read from storage, bypassing the cache (backup, settings page).
  static Future<bool> read() async {
    try {
      final prefs = await ProfilePreferences.instance();
      _enabled = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Keep the cached value.
    }
    return _enabled;
  }

  /// Cache-first: [enabled] reflects [value] before the write lands.
  static Future<void> setEnabled(bool value) async {
    _enabled = value;
    _warmed = true;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  /// Forget the current profile's value so the next [warmUp] reloads it.
  static void resetProfileScope() {
    _enabled = false;
    _warmed = false;
  }

  /// Tests only — stands in for an app restart.
  @visibleForTesting
  static void debugReset() => resetProfileScope();
}
