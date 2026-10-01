import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';

final class DiscoverStorage {
  const DiscoverStorage._();

  static const String _discoverLayoutKey = 'discover_layout';
  static const String _discoverDefaultSourceKey = 'discover_default_source';
  static const String _discoverLastSourceKey = 'discover_last_source';

  /// Special value for the Discover default-source setting. When selected,
  /// [getDiscoverLastSource] decides which source opens on the next visit.
  static const String discoverDefaultRememberLast = 'remember';

  static bool _isDiscoverSourceValue(String value) =>
      value == 'cw' ||
      value == 'trakt' ||
      value == 'simkl' ||
      value == 'tmdb' ||
      value == 'mdblist' ||
      value == 'jellyfin' ||
      value == 'emby' ||
      (value.startsWith('a:') && value.length > 2 && value.length <= 514);

  /// What Discover should show when opened. Unset defaults to remembering the
  /// last source, preserving the most useful behavior for existing installs.
  static Future<String> getDiscoverDefaultSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverDefaultSourceKey);
    return value == discoverDefaultRememberLast || (value != null && _isDiscoverSourceValue(value))
        ? value!
        : discoverDefaultRememberLast;
  }

  static Future<void> setDiscoverDefaultSource(String value) async {
    final normalized = value == discoverDefaultRememberLast || _isDiscoverSourceValue(value)
        ? value
        : discoverDefaultRememberLast;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverDefaultSourceKey, normalized);
  }

  /// The last source explicitly opened from Discover. A missing or malformed
  /// value safely falls back to Continue Watching.
  static Future<String> getDiscoverLastSource() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_discoverLastSourceKey);
    return value != null && _isDiscoverSourceValue(value) ? value : 'cw';
  }

  static Future<void> setDiscoverLastSource(
    String value, {
    bool Function()? canContinue,
  }) async {
    if (!_isDiscoverSourceValue(value)) return;
    if (canContinue == null) {
      final prefs = await ProfilePreferences.instance();
      if (prefs.getString(_discoverLastSourceKey) == value) return;
      await prefs.setString(_discoverLastSourceKey, value);
      return;
    }
    await ProfileRuntime.withoutCapturedScope(() async {
      if (!canContinue()) return;
      final prefs = await ProfilePreferences.instance();
      if (!canContinue()) return;
      await ProfilePreferences.synchronizeExternalMutation(() async {
        if (!canContinue() || prefs.getString(_discoverLastSourceKey) == value) {
          return;
        }
        await prefs.setString(_discoverLastSourceKey, value);
      }, marksMutation: false);
    });
  }

  /// TV Discover layout: 'stage' (the focused title full-bleed with one bottom
  /// shelf, the default) or 'grid' (the detail rail beside a poster wall). Its
  /// own key, deliberately NOT shared with [getTvHomeStyle]: Home's Canvas
  /// switches rails with UP/DOWN and Discover's Stage owns a filter line —
  /// neither layout has the other's axis, so one pref governing both would
  /// promise a symmetry they can't keep. Phone/desktop never read it.
  ///
  /// Unset reads as 'stage', so users who never opened the picker move to it.
  /// Everything else that holds a pre-load placeholder for this pref must
  /// agree, or the UI paints one layout and then swaps: Discover's warm-start
  /// layout memory, DiscoverLayoutPage, SettingsScreen.
  /// Synchronous mirror of `discoverLayout`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String discoverLayoutCached = 'stage';

  /// Scoped callers suppress a retired request's shared-cache publication.
  /// The normalized return value and unguarded callers keep their contract.
  static Future<String> getDiscoverLayout({
    bool Function()? canContinue,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final layout = prefs.getString(_discoverLayoutKey) == 'grid' ? 'grid' : 'stage';
    if (canContinue?.call() ?? true) discoverLayoutCached = layout;
    return layout;
  }

  /// Normalizes toward 'stage' on the same terms [getDiscoverLayout] does —
  /// an unrecognized value has to mean the default on BOTH sides, or writing
  /// one would silently pin the layout the reader treats as the exception.
  static Future<void> setDiscoverLayout(String layout) async {
    final normalized = layout == 'grid' ? 'grid' : 'stage';
    discoverLayoutCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_discoverLayoutKey, normalized);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    discoverLayoutCached = 'stage';
  }
}
