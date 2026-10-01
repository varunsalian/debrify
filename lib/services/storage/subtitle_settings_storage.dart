import 'dart:convert';
import 'package:debrify/models/subtitle_source_priority.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class SubtitleSettingsStorage {
  const SubtitleSettingsStorage._();
  static const String _subtitleAutoSyncKey = 'subtitle_auto_sync_enabled';
  static const String _playerDefaultSubtitleLanguageKey = 'player_default_subtitle_language';
  static const String _playerDefaultAudioLanguageKey = 'player_default_audio_language';

  /// Whether native players silently align addon subtitles to the audio as
  /// playback runs. Android TV reads the same profile preference natively;
  /// MediaKit reads it in Dart (Android, macOS, Linux, tvOS — platforms whose
  /// bundled libmpv carries the analysis filters) and attaches its passive
  /// filter only while an addon subtitle is active. OFF by default on both
  /// engines — experimental opt-in. The default must stay in lock-step with
  /// the native read in AndroidTvTorrentPlayerActivity.isAutoSyncPrefEnabled.
  static Future<bool> getSubtitleAutoSyncEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_subtitleAutoSyncKey) ?? false;
  }

  static Future<void> setSubtitleAutoSyncEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_subtitleAutoSyncKey, enabled);
  }

  /// Automatically select only explicitly forced embedded subtitle tracks.
  static Future<bool> getSubtitleForcedOnly() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('subtitle_forced_only') ?? false;
  }

  static Future<void> setSubtitleForcedOnly(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('subtitle_forced_only', enabled);
  }

  /// Opt-in: automatically show subtitles only for a known audio language
  /// different from the profile's preferred audio language.
  static Future<bool> getSubtitleOnlyForeignAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('subtitle_only_foreign_audio') ?? false;
  }

  static Future<void> setSubtitleOnlyForeignAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('subtitle_only_foreign_audio', enabled);
  }

  /// Ordered, portable subtitle sources for automatic selection.
  static Future<List<String>> getSubtitleSourcePriority() async {
    final prefs = await ProfilePreferences.instance();
    return SubtitleSourcePriority.decode(
      prefs.getString(SubtitleSourcePriority.preferenceKey),
    );
  }

  static Future<void> setSubtitleSourcePriority(List<String> order) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      SubtitleSourcePriority.preferenceKey,
      jsonEncode(SubtitleSourcePriority.normalize(order)),
    );
  }

  /// Returns a language code, 'off', or null for no preference.
  static Future<String?> getDefaultSubtitleLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultSubtitleLanguageKey);
  }

  /// Set default subtitle language code
  /// Pass language code (e.g., 'en', 'es'), 'off' for disabled, or null to clear preference
  static Future<void> setDefaultSubtitleLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultSubtitleLanguageKey);
    } else {
      await prefs.setString(_playerDefaultSubtitleLanguageKey, languageCode);
    }
  }

  /// Get default audio language code
  /// Returns language code (e.g., 'en', 'es') or null for no preference
  static Future<String?> getDefaultAudioLanguage() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_playerDefaultAudioLanguageKey);
  }

  /// Set default audio language code
  /// Pass language code (e.g., 'en', 'es') or null to clear preference
  static Future<void> setDefaultAudioLanguage(String? languageCode) async {
    final prefs = await ProfilePreferences.instance();
    if (languageCode == null) {
      await prefs.remove(_playerDefaultAudioLanguageKey);
    } else {
      await prefs.setString(_playerDefaultAudioLanguageKey, languageCode);
    }
  }
}
