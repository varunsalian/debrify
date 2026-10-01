import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/detail_page_storage.dart';

final class ThemeStorage {
  const ThemeStorage._();

  // Shared within lib/services/storage/.
  static const String appThemeKey = 'app_theme';
  static const String _themeOverridesKey = 'theme_overrides';

  /// The app-wide theme (Appearance → App Theme). `'legacy'` is the sentinel
  /// meaning "render today's app exactly" and is the default; any other
  /// accepted value is a `DetailPageStorage.kDetailThemes` id applied app-wide.
  ///
  /// Unknown/removed ids normalize to `'legacy'` on BOTH sides — never to a
  /// random theme — so a value written by a newer build downgrades safely.
  ///
  /// Write-through contract (owned by `AppThemeController.select`): choosing a
  /// real app theme also mirrors the id into `DetailPageStorage.detailThemeKey`, and the mirror
  /// is written FIRST — a crash between the two writes must leave an
  /// older-build-consistent view, and old builds only read `detail_theme`.
  static String appThemeCached = 'legacy';

  static Future<String> getAppTheme() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(appThemeKey);
    appThemeCached = (value == 'legacy' || DetailPageStorage.kDetailThemes.contains(value)) ? value! : 'legacy';
    return appThemeCached;
  }

  static Future<void> setAppTheme(String value) async {
    final prefs = await ProfilePreferences.instance();
    final normalized = (value == 'legacy' || DetailPageStorage.kDetailThemes.contains(value)) ? value : 'legacy';
    await prefs.setString(appThemeKey, normalized);
    appThemeCached = normalized;
  }

  /// The user's per-token edits, as the raw JSON `ThemeOverrides` encodes.
  ///
  /// Kept as a string here rather than a parsed object so this layer stays free
  /// of the theme package — and because the only consumer that matters resolves
  /// it once, on the controller, and memoizes the result.
  ///
  /// Empty string means "no overrides", which is both the default and the fast
  /// path every theme resolution checks first.
  static String themeOverridesCached = '';

  static Future<String> getThemeOverrides() async {
    final prefs = await ProfilePreferences.instance();
    themeOverridesCached = prefs.getString(_themeOverridesKey) ?? '';
    return themeOverridesCached;
  }

  static Future<void> setThemeOverrides(String raw) async {
    final prefs = await ProfilePreferences.instance();
    // Publish the mirror BEFORE the await, like every other live-applied
    // preference here: the controller has already recomputed and notified off
    // this value, and a rebuild that raced the write must not read the old one.
    themeOverridesCached = raw;
    if (raw.isEmpty) {
      await prefs.remove(_themeOverridesKey);
    } else {
      await prefs.setString(_themeOverridesKey, raw);
    }
  }

  static const String _textBrightnessKey = 'text_brightness';
  static const Set<String> _textBrightnessValues = {'bright', 'soft', 'dim'};

  /// App-wide text brightness (Appearance → Text Brightness): 'bright' (pure
  /// white, the default and the app's historical look), 'soft', or 'dim'.
  /// Consumed as a [TextBrightness] preset by the root theme — see
  /// `services/text_brightness.dart` for the actual colors. The synchronous
  /// mirror for first-frame reads is TextBrightnessController's notifier,
  /// warmed in main() before runApp — no cached copy lives here.
  ///
  /// Normalizes toward 'bright' on BOTH sides — an unrecognized value has to
  /// mean the default for the reader and the writer alike, or writing one
  /// would silently pin a preset the reader treats as the exception.
  static Future<String> getTextBrightness() async {
    final prefs = await ProfilePreferences.instance();
    final value = prefs.getString(_textBrightnessKey);
    return _textBrightnessValues.contains(value) ? value! : 'bright';
  }

  static Future<void> setTextBrightness(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      _textBrightnessKey,
      _textBrightnessValues.contains(value) ? value : 'bright',
    );
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    appThemeCached = 'legacy';
    themeOverridesCached = '';
  }
}
