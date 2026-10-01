import 'package:debrify/services/profiles/profile_preferences.dart';

final class SkipSegmentsStorage {
  const SkipSegmentsStorage._();
  static const String _skipSegmentsEnabledKey = 'skip_segments_enabled';
  static const String _skipSegmentProviderKey = 'skip_segment_provider';

  /// Stable provider identifier persisted by the Playback settings page.
  /// Kept here rather than using a display label so future provider names can
  /// change without migrating preferences.
  static const String skipSegmentProviderAuto = 'auto';
  static const String skipSegmentProviderSkipDb = 'skipdb';
  static const String skipSegmentProviderIntroDb = 'introdb';
  static const String skipSegmentProviderTheIntroDb = 'theintrodb';
  static const Set<String> _supportedSkipSegmentProviders = <String>{
    skipSegmentProviderAuto,
    skipSegmentProviderSkipDb,
    skipSegmentProviderIntroDb,
    skipSegmentProviderTheIntroDb,
  };

  /// Whether the Debrify Player should request community timestamps and show
  /// manual skip buttons. Manual buttons are enabled by default; this setting
  /// never authorizes automatic seeking.
  static Future<bool> getSkipSegmentsEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_skipSegmentsEnabledKey) ?? true;
  }

  static Future<void> setSkipSegmentsEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_skipSegmentsEnabledKey, enabled);
  }

  /// Timestamp source used by the Debrify Player. Unknown stored values fall
  /// back safely so removing a provider cannot strand the feature.
  static Future<String> getSkipSegmentProvider() async {
    final prefs = await ProfilePreferences.instance();
    final provider = prefs.getString(_skipSegmentProviderKey);
    return _supportedSkipSegmentProviders.contains(provider) ? provider! : skipSegmentProviderAuto;
  }

  static Future<void> setSkipSegmentProvider(String provider) async {
    final prefs = await ProfilePreferences.instance();
    final supported = _supportedSkipSegmentProviders.contains(provider) ? provider : skipSegmentProviderAuto;
    await prefs.setString(_skipSegmentProviderKey, supported);
  }
}
