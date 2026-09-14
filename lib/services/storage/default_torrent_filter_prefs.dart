import 'dart:convert';

import '../profiles/profile_preferences.dart';

/// Default torrent filter encodings behind the compatible StorageService APIs.
abstract final class DefaultTorrentFilterPrefs {
  static const String _defaultFilterQualitiesKey =
      'default_filter_qualities_v1';
  static const String _defaultFilterRipSourcesKey =
      'default_filter_rip_sources_v1';
  static const String _defaultFilterLanguagesKey =
      'default_filter_languages_v1';
  static const String _defaultFilterSizesKey = 'default_filter_sizes_v1';
  static const String _defaultFilterDynamicRangesKey =
      'default_filter_dynamic_ranges_v1';

  static Future<List<String>> getDefaultFilterQualities() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterQualitiesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterQualities(List<String> qualities) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterQualitiesKey, jsonEncode(qualities));
  }

  static Future<List<String>> getDefaultFilterRipSources() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterRipSourcesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterRipSources(
    List<String> ripSources,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterRipSourcesKey, jsonEncode(ripSources));
  }

  static Future<List<String>> getDefaultFilterLanguages() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterLanguagesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterLanguages(List<String> languages) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterLanguagesKey, jsonEncode(languages));
  }

  static Future<List<String>> getDefaultFilterSizes() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterSizesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterSizes(List<String> sizes) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterSizesKey, jsonEncode(sizes));
  }

  static Future<List<String>> getDefaultFilterDynamicRanges() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_defaultFilterDynamicRangesKey);
    if (json == null) return [];
    return List<String>.from(jsonDecode(json));
  }

  static Future<void> setDefaultFilterDynamicRanges(List<String> ranges) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_defaultFilterDynamicRangesKey, jsonEncode(ranges));
  }

  /// Remove only filters through the host's captured profile preferences.
  /// The host then removes the provider using that same instance.
  static Future<void> clearDefaults(ProfilePreferences prefs) async {
    await prefs.remove(_defaultFilterQualitiesKey);
    await prefs.remove(_defaultFilterRipSourcesKey);
    await prefs.remove(_defaultFilterLanguagesKey);
    await prefs.remove(_defaultFilterSizesKey);
    await prefs.remove(_defaultFilterDynamicRangesKey);
  }
}
