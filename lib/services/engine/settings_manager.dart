import 'package:shared_preferences/shared_preferences.dart';
import '../../models/engine_config/engine_config.dart';

/// Manages dynamic storage keys for engine settings.
///
/// Key generation patterns:
/// - Normal settings: engine_{engineId}_{settingId}
/// - TV settings: engine_tv_{engineId}_{context}_{settingId}
/// - Global TV: engine_tv_global_{settingId}
class SettingsManager {
  // Singleton pattern
  static final SettingsManager _instance = SettingsManager._internal();
  factory SettingsManager() => _instance;
  SettingsManager._internal();

  // ============================================================
  // Key Generation Methods
  // ============================================================

  /// Generate storage key for normal setting
  /// Pattern: engine_{engineId}_{settingId}
  String generateKey(String engineId, String settingId) {
    final normalizedEngineId = _normalizeId(engineId);
    final normalizedSettingId = _normalizeId(settingId);
    return 'engine_${normalizedEngineId}_$normalizedSettingId';
  }

  /// Generate storage key for TV mode setting
  /// Pattern: engine_tv_{engineId}_{context}_{settingId}
  /// Contexts: enabled, small_channel, large_channel, quick_play
  String generateTvKey(String engineId, String context, String settingId) {
    final normalizedEngineId = _normalizeId(engineId);
    final normalizedContext = _normalizeId(context);
    final normalizedSettingId = _normalizeId(settingId);
    return 'engine_tv_${normalizedEngineId}_${normalizedContext}_$normalizedSettingId';
  }

  /// Generate key for global TV setting
  /// Pattern: engine_tv_global_{settingId}
  String generateGlobalTvKey(String settingId) {
    final normalizedSettingId = _normalizeId(settingId);
    return 'engine_tv_global_$normalizedSettingId';
  }

  /// Normalize ID to be storage-safe (lowercase, underscores)
  String _normalizeId(String id) {
    return id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  }

  // ============================================================
  // Normal Engine Settings - Enabled
  // ============================================================

  /// Get the enabled state for an engine
  Future<bool> getEnabled(String engineId, bool defaultValue) async {
    final key = generateKey(engineId, 'enabled');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// Set the enabled state for an engine
  Future<void> setEnabled(String engineId, bool value) async {
    final key = generateKey(engineId, 'enabled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // ============================================================
  // Normal Engine Settings - Max Results
  // ============================================================

  /// Get the max results for an engine
  Future<int> getMaxResults(String engineId, int defaultValue) async {
    final key = generateKey(engineId, 'max_results');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set the max results for an engine
  Future<void> setMaxResults(String engineId, int value) async {
    final key = generateKey(engineId, 'max_results');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  // ============================================================
  // Generic Get/Set Methods
  // ============================================================

  /// Generic get value for any engine setting
  Future<T?> getValue<T>(
      String engineId, String settingId, T defaultValue) async {
    final key = generateKey(engineId, settingId);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (T == bool) {
        return (prefs.getBool(key) ?? defaultValue as bool) as T;
      } else if (T == int) {
        return (prefs.getInt(key) ?? defaultValue as int) as T;
      } else if (T == String) {
        return (prefs.getString(key) ?? defaultValue as String) as T;
      } else if (T == double) {
        return (prefs.getDouble(key) ?? defaultValue as double) as T;
      }
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Generic set value for any engine setting
  Future<void> setValue<T>(String engineId, String settingId, T value) async {
    final key = generateKey(engineId, settingId);
    final prefs = await SharedPreferences.getInstance();

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  // ============================================================
  // TV Mode Settings - Enabled
  // ============================================================

  /// Get TV mode enabled state for an engine
  Future<bool> getTvEnabled(String engineId, bool defaultValue) async {
    final key = generateTvKey(engineId, 'enabled', 'enabled');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// Set TV mode enabled state for an engine
  Future<void> setTvEnabled(String engineId, bool value) async {
    final key = generateTvKey(engineId, 'enabled', 'enabled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // ============================================================
  // TV Mode Settings - Small Channel Max
  // ============================================================

  /// Get TV small channel max results for an engine
  Future<int> getTvSmallChannelMax(String engineId, int defaultValue) async {
    final key = generateTvKey(engineId, 'small_channel', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set TV small channel max results for an engine
  Future<void> setTvSmallChannelMax(String engineId, int value) async {
    final key = generateTvKey(engineId, 'small_channel', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  // ============================================================
  // TV Mode Settings - Large Channel Max
  // ============================================================

  /// Get TV large channel max results for an engine
  Future<int> getTvLargeChannelMax(String engineId, int defaultValue) async {
    final key = generateTvKey(engineId, 'large_channel', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set TV large channel max results for an engine
  Future<void> setTvLargeChannelMax(String engineId, int value) async {
    final key = generateTvKey(engineId, 'large_channel', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  // ============================================================
  // TV Mode Settings - Quick Play Max
  // ============================================================

  /// Get TV quick play max results for an engine
  Future<int> getTvQuickPlayMax(String engineId, int defaultValue) async {
    final key = generateTvKey(engineId, 'quick_play', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set TV quick play max results for an engine
  Future<void> setTvQuickPlayMax(String engineId, int value) async {
    final key = generateTvKey(engineId, 'quick_play', 'max_results');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
  }

  // ============================================================
  // Global TV Settings - Keyword Threshold
  // ============================================================

  /// Get global keyword threshold for TV mode
  Future<int> getGlobalKeywordThreshold(int defaultValue) async {
    final key = generateGlobalTvKey('keyword_threshold');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set global keyword threshold for TV mode
  Future<void> setGlobalKeywordThreshold(int value) async {
    final key = generateGlobalTvKey('keyword_threshold');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value.clamp(1, 50));
  }

  // ============================================================
  // Global TV Settings - Batch Size
  // ============================================================

  /// Get global batch size for TV mode
  Future<int> getGlobalBatchSize(int defaultValue) async {
    final key = generateGlobalTvKey('batch_size');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set global batch size for TV mode
  Future<void> setGlobalBatchSize(int value) async {
    final key = generateGlobalTvKey('batch_size');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value.clamp(1, 10));
  }

  // ============================================================
  // Global TV Settings - Min Torrents Per Keyword
  // ============================================================

  /// Get global min torrents per keyword for TV mode
  Future<int> getGlobalMinTorrentsPerKeyword(int defaultValue) async {
    final key = generateGlobalTvKey('min_torrents_per_keyword');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set global min torrents per keyword for TV mode
  Future<void> setGlobalMinTorrentsPerKeyword(int value) async {
    final key = generateGlobalTvKey('min_torrents_per_keyword');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value.clamp(1, 50));
  }

  // ============================================================
  // Global TV Settings - Max Keywords (Quick Play)
  // ============================================================

  /// Get global max keywords for quick play TV mode
  Future<int> getGlobalMaxKeywords(int defaultValue) async {
    final key = generateGlobalTvKey('max_keywords');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key) ?? defaultValue;
  }

  /// Set global max keywords for quick play TV mode
  Future<void> setGlobalMaxKeywords(int value) async {
    final key = generateGlobalTvKey('max_keywords');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value.clamp(1, 20));
  }

  // ============================================================
  // Global TV Settings - Avoid NSFW
  // ============================================================

  /// Get global avoid NSFW setting for TV mode
  Future<bool> getGlobalAvoidNsfw(bool defaultValue) async {
    final key = generateGlobalTvKey('avoid_nsfw');
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key) ?? defaultValue;
  }

  /// Set global avoid NSFW setting for TV mode
  Future<void> setGlobalAvoidNsfw(bool value) async {
    final key = generateGlobalTvKey('avoid_nsfw');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  // ============================================================
  // Bulk Operations
  // ============================================================

  /// Get all settings for an engine based on its config
  Future<Map<String, dynamic>> getAllSettingsForEngine(
      String engineId, SettingsConfig config) async {
    final result = <String, dynamic>{};
    final prefs = await SharedPreferences.getInstance();

    for (final key in config.keys) {
      final setting = config.getSetting(key);
      if (setting == null) continue;

      final storageKey = generateKey(engineId, key);

      if (setting.isToggle) {
        result[key] = prefs.getBool(storageKey) ?? setting.defaultBool;
      } else if (setting.isDropdown || setting.isSlider) {
        result[key] = prefs.getInt(storageKey) ?? setting.defaultInt;
      } else {
        // Handle string or other types
        final stringValue = prefs.getString(storageKey);
        result[key] = stringValue ?? setting.defaultValue;
      }
    }

    return result;
  }

  /// Reset all settings for an engine to their default values
  Future<void> resetEngineToDefaults(
      String engineId, SettingsConfig config) async {
    final prefs = await SharedPreferences.getInstance();

    for (final key in config.keys) {
      final setting = config.getSetting(key);
      if (setting == null) continue;

      final storageKey = generateKey(engineId, key);

      if (setting.isToggle) {
        await prefs.setBool(storageKey, setting.defaultBool);
      } else if (setting.isDropdown || setting.isSlider) {
        await prefs.setInt(storageKey, setting.defaultInt);
      } else {
        // Handle string or other types
        final defaultValue = setting.defaultValue;
        if (defaultValue is String) {
          await prefs.setString(storageKey, defaultValue);
        } else if (defaultValue != null) {
          await prefs.setString(storageKey, defaultValue.toString());
        }
      }
    }
  }

  // ============================================================
  // Effective Max Results (Context-Aware)
  // ============================================================

  /// Get effective max results considering TV mode context
  ///
  /// When [isTvMode] is true, returns the appropriate limit based on [tvContext]:
  /// - 'small_channel': Returns small channel max
  /// - 'large_channel': Returns large channel max
  /// - 'quick_play': Returns quick play max
  /// - Otherwise: Returns normal max results
  Future<int> getEffectiveMaxResults(
    String engineId, {
    bool isTvMode = false,
    String? tvContext,
    int defaultValue = 50,
    int defaultTvSmall = 100,
    int defaultTvLarge = 25,
    int defaultTvQuickPlay = 500,
  }) async {
    if (!isTvMode || tvContext == null) {
      return await getMaxResults(engineId, defaultValue);
    }

    switch (tvContext.toLowerCase()) {
      case 'small_channel':
      case 'smallchannel':
        return await getTvSmallChannelMax(engineId, defaultTvSmall);
      case 'large_channel':
      case 'largechannel':
        return await getTvLargeChannelMax(engineId, defaultTvLarge);
      case 'quick_play':
      case 'quickplay':
        return await getTvQuickPlayMax(engineId, defaultTvQuickPlay);
      default:
        return await getMaxResults(engineId, defaultValue);
    }
  }

  // ============================================================
  // TV Mode Generic Get/Set
  // ============================================================

  /// Generic get value for TV mode setting
  Future<T?> getTvValue<T>(
      String engineId, String context, String settingId, T defaultValue) async {
    final key = generateTvKey(engineId, context, settingId);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (T == bool) {
        return (prefs.getBool(key) ?? defaultValue as bool) as T;
      } else if (T == int) {
        return (prefs.getInt(key) ?? defaultValue as int) as T;
      } else if (T == String) {
        return (prefs.getString(key) ?? defaultValue as String) as T;
      } else if (T == double) {
        return (prefs.getDouble(key) ?? defaultValue as double) as T;
      }
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Generic set value for TV mode setting
  Future<void> setTvValue<T>(
      String engineId, String context, String settingId, T value) async {
    final key = generateTvKey(engineId, context, settingId);
    final prefs = await SharedPreferences.getInstance();

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  /// Generic get value for global TV setting
  Future<T?> getGlobalTvValue<T>(String settingId, T defaultValue) async {
    final key = generateGlobalTvKey(settingId);
    final prefs = await SharedPreferences.getInstance();

    try {
      if (T == bool) {
        return (prefs.getBool(key) ?? defaultValue as bool) as T;
      } else if (T == int) {
        return (prefs.getInt(key) ?? defaultValue as int) as T;
      } else if (T == String) {
        return (prefs.getString(key) ?? defaultValue as String) as T;
      } else if (T == double) {
        return (prefs.getDouble(key) ?? defaultValue as double) as T;
      }
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }

  /// Generic set value for global TV setting
  Future<void> setGlobalTvValue<T>(String settingId, T value) async {
    final key = generateGlobalTvKey(settingId);
    final prefs = await SharedPreferences.getInstance();

    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is double) {
      await prefs.setDouble(key, value);
    }
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  /// Check if a setting exists in storage
  Future<bool> hasValue(String engineId, String settingId) async {
    final key = generateKey(engineId, settingId);
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(key);
  }

  /// Remove a specific setting
  Future<void> removeValue(String engineId, String settingId) async {
    final key = generateKey(engineId, settingId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Remove all settings for an engine
  Future<void> clearEngineSettings(String engineId) async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final prefix = 'engine_${_normalizeId(engineId)}_';

    for (final key in allKeys) {
      if (key.startsWith(prefix)) {
        await prefs.remove(key);
      }
    }
  }

  /// Remove all TV mode settings for an engine
  Future<void> clearEngineTvSettings(String engineId) async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();
    final prefix = 'engine_tv_${_normalizeId(engineId)}_';

    for (final key in allKeys) {
      if (key.startsWith(prefix)) {
        await prefs.remove(key);
      }
    }
  }
}
