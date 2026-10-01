import 'package:debrify/services/profiles/profile_preferences.dart';

final class DeviceStorage {
  const DeviceStorage._();
  static const String _batteryOptStatusKey = 'battery_opt_status_v1';
  static const String _supportRemoteConfigCacheKey =
      'support_remote_config_cache_v1';
  static const String _dismissedDonationCampaignIdsKey =
      'dismissed_donation_campaign_ids_v1';
  static const String _updateAutoCheckEnabledKey = 'update_auto_check_enabled';
  static const String _updateIncludeAlphaEnabledKey =
      'update_include_alpha_enabled';
  static const String _updateIgnoredVersionKey = 'update_ignored_version';

  // Battery optimization status
  static Future<String> getBatteryOptimizationStatus() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_batteryOptStatusKey) ?? 'unknown';
  }

  static Future<void> setBatteryOptimizationStatus(String status) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_batteryOptStatusKey, status);
  }

  // Download settings - Fixed to 1 parallel download
  static Future<int> getMaxParallelDownloads() async {
    return 1; // Always return 1 for single download at a time
  }

  static Future<void> setMaxParallelDownloads(int value) async {
    // No-op: parallel downloads are fixed to 1
  }

  // ── Custom download location (Android SAF tree) ─────────────────────────
  static const String _downloadTreeUriKey = 'download_tree_uri_v1';
  static const String _downloadTreeNameKey = 'download_tree_display_name_v1';

  /// The persisted SAF tree URI for the user-chosen download folder, or null
  /// when downloads go to the default location (Downloads/Debrify).
  static Future<String?> getDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeUriKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<String?> getDownloadTreeDisplayName() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadTreeNameKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadTreeUri(
    String treeUri,
    String displayName,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadTreeUriKey, treeUri);
    await prefs.setString(_downloadTreeNameKey, displayName);
  }

  static Future<void> clearDownloadTreeUri() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadTreeUriKey);
    await prefs.remove(_downloadTreeNameKey);
  }

  // ── Custom download location (desktop: plain filesystem path) ───────────
  // Windows/Linux only. macOS is deliberately excluded: the app is sandboxed
  // with a read-only user-selected-files entitlement, so a picked folder
  // needs security-scoped bookmarks to survive relaunch — separate feature.
  static const String _downloadDirPathKey = 'download_dir_path_v1';

  /// The persisted absolute directory for the user-chosen download folder on
  /// desktop, or null when downloads go to the platform default.
  static Future<String?> getDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    final v = prefs.getString(_downloadDirPathKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  static Future<void> setDownloadDirPath(String dirPath) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_downloadDirPathKey, dirPath);
  }

  static Future<void> clearDownloadDirPath() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_downloadDirPathKey);
  }

  static Future<String?> getSupportRemoteConfigCache() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getString(_supportRemoteConfigCacheKey);
  }

  static Future<void> setSupportRemoteConfigCache(String json) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setString(_supportRemoteConfigCacheKey, json);
  }

  static Future<List<String>> getDismissedDonationCampaignIds() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
  }

  static Future<void> dismissDonationCampaign(String campaignId) async {
    final prefs = await DevicePreferences.instance();
    final ids =
        prefs.getStringList(_dismissedDonationCampaignIdsKey) ?? <String>[];
    if (ids.contains(campaignId)) return;
    ids.add(campaignId);
    await prefs.setStringList(_dismissedDonationCampaignIdsKey, ids);
  }

  static Future<bool> getUpdateAutoCheckEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_updateAutoCheckEnabledKey) ?? true;
  }

  static Future<void> setUpdateAutoCheckEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_updateAutoCheckEnabledKey, enabled);
  }

  static Future<bool> getUpdateIncludeAlphaEnabled() async {
    final prefs = await DevicePreferences.instance();
    return prefs.getBool(_updateIncludeAlphaEnabledKey) ?? false;
  }

  static Future<void> setUpdateIncludeAlphaEnabled(bool enabled) async {
    final prefs = await DevicePreferences.instance();
    await prefs.setBool(_updateIncludeAlphaEnabledKey, enabled);
  }

  static Future<String?> getIgnoredUpdateVersion() async {
    final prefs = await DevicePreferences.instance();
    final value = prefs.getString(_updateIgnoredVersionKey);
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static Future<void> setIgnoredUpdateVersion(String? version) async {
    final prefs = await DevicePreferences.instance();
    if (version == null || version.trim().isEmpty) {
      await prefs.remove(_updateIgnoredVersionKey);
    } else {
      await prefs.setString(_updateIgnoredVersionKey, version);
    }
  }
}
