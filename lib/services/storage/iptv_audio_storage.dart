import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class IptvAudioStorage {
  const IptvAudioStorage._();

  static const String _iptvSeriesAudioLangKey = 'iptv_series_audio_lang';

  /// The audio LANGUAGE the user last chose for an IPTV series (keyed by the
  /// series' name). Language, not the mpv track ordinal — episodes are
  /// separate files whose track ordering differs, so an ordinal wouldn't
  /// carry. Null when the series has no remembered choice.
  static Future<String?> getIptvSeriesAudioLanguage(String seriesKey) async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map[seriesKey] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Remember the audio language for an IPTV series so later episodes (and
  /// future sessions) default to it.
  static Future<void> setIptvSeriesAudioLanguage(
    String seriesKey,
    String languageCode,
  ) async {
    if (seriesKey.isEmpty || languageCode.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    Map<String, dynamic> map = {};
    final raw = prefs.getString(_iptvSeriesAudioLangKey);
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    map[seriesKey] = languageCode;
    await prefs.setString(_iptvSeriesAudioLangKey, jsonEncode(map));
  }
}
