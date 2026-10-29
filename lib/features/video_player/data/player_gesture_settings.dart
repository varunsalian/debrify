import 'package:debrify/services/profiles/profile_preferences.dart';

/// Profile-owned player gesture preferences.
///
/// The gesture layer reads [swipeSeekCached] synchronously while a drag is in
/// flight, so the value is cached here rather than awaited per gesture. Each
/// new player kicks off [load] to refresh the cache from the active profile.
final class PlayerGestureSettings {
  const PlayerGestureSettings._();

  /// Swipe-to-seek on or off; profile-owned, defaults to on.
  static const swipeSeekKey = 'player_swipe_seek_v1';

  /// Last value read or written; true until [load] runs.
  static bool swipeSeekCached = true;

  /// Reads the key (default true), updates the cache and returns it.
  ///
  /// Never throws: with no profile yet, or any storage failure, it keeps and
  /// returns the cached value so gestures stay usable.
  static Future<bool> load() async {
    try {
      final prefs = await ProfilePreferences.instance();
      swipeSeekCached = prefs.getBool(swipeSeekKey) ?? true;
    } catch (_) {
      // No profile scope yet, or the read failed: keep the cached value.
    }
    return swipeSeekCached;
  }

  /// Writes the key and the cache. A failed write still updates the cache so
  /// the current session reflects the user's choice.
  static Future<void> setSwipeSeek(bool enabled) async {
    swipeSeekCached = enabled;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(swipeSeekKey, enabled);
    } catch (_) {
      // Nothing to persist into; the in-memory cache still holds.
    }
  }
}
