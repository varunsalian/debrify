import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/torrent_provider_storage.dart';
import 'package:flutter/foundation.dart';

final class TorrentSearchStorage {
  const TorrentSearchStorage._();

  // Default Torrent Filter Settings
  static const String _defaultFilterQualitiesKey = 'default_filter_qualities_v1';
  static const String _defaultFilterRipSourcesKey = 'default_filter_rip_sources_v1';
  static const String _defaultFilterLanguagesKey = 'default_filter_languages_v1';
  static const String _defaultFilterSizesKey = 'default_filter_sizes_v1';
  static const String _defaultFilterDynamicRangesKey = 'default_filter_dynamic_ranges_v1';

  /// Show the new Stremio-styled Addons hub (single list + source/type filters,
  /// purple Discover theme, 1-click marketplace) instead of the classic two-tab
  /// Addons screen. On by default; can be turned off per-device via
  /// [setStremioAddonHubEnabled].
  static Future<bool> getStremioAddonHubEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('stremio_addon_hub_enabled') ?? true;
  }

  static Future<void> setStremioAddonHubEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('stremio_addon_hub_enabled', enabled);
  }

  /// Clear filter settings (qualities, rip sources, languages)
  static Future<void> clearAllFilterSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_defaultFilterQualitiesKey);
    await prefs.remove(_defaultFilterRipSourcesKey);
    await prefs.remove(_defaultFilterLanguagesKey);
    await prefs.remove(_defaultFilterSizesKey);
    await prefs.remove(_defaultFilterDynamicRangesKey);
    await prefs.remove(TorrentProviderStorage.defaultTorrentProviderKey);
  }

  static Future<bool> getShowAddonLogos() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('sources_show_addon_logos') ?? true;
  }

  static Future<void> setShowAddonLogos(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('sources_show_addon_logos', value);
  }

  static Future<bool> getUseAddonTextFormatting() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('sources_use_addon_text') ?? true;
  }

  static Future<void> setUseAddonTextFormatting(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('sources_use_addon_text', value);
  }

  // Default Torrent Filter Settings
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

  static const String _catalogSearchDisabledAddonsKey = 'catalog_search_disabled_addons_v1';

  /// Get the set of addon IDs the user has DISABLED for catalog search on the
  /// Search tab (empty = every searchable addon is queried).
  static Future<Set<String>> getCatalogSearchDisabledAddons() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_catalogSearchDisabledAddonsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading catalog search disabled addons: $e');
      return {};
    }
  }

  /// Save the set of addon IDs disabled for catalog search.
  static Future<void> setCatalogSearchDisabledAddons(
    Set<String> disabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_catalogSearchDisabledAddonsKey);
    } else {
      await prefs.setString(
        _catalogSearchDisabledAddonsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }
}
