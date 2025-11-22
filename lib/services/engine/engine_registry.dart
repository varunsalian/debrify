import 'package:flutter/foundation.dart';

import '../../models/engine_config/engine_config.dart';
import '../../models/engine_config/default_config.dart';
import 'config_loader.dart';
import 'dynamic_engine.dart';

/// Singleton registry that manages all loaded search engines.
///
/// This registry provides:
/// - Lazy initialization of engines from YAML configs
/// - Cached access to DynamicEngine instances
/// - Filtered queries by capability (keyword search, IMDB, series, TV mode)
/// - Hot-reload support for development
///
/// Usage:
/// ```dart
/// final registry = EngineRegistry.instance;
/// await registry.initialize();
///
/// // Get all engines
/// final engines = registry.getAllEngines();
///
/// // Get engines by capability
/// final keywordEngines = registry.getKeywordSearchEngines();
/// final imdbEngines = registry.getImdbSearchEngines();
/// ```
class EngineRegistry {
  // Singleton pattern
  static final EngineRegistry _instance = EngineRegistry._internal();

  /// Factory constructor returns singleton instance
  factory EngineRegistry() => _instance;

  /// Private internal constructor
  EngineRegistry._internal();

  /// Static accessor for singleton instance
  static EngineRegistry get instance => _instance;

  // Dependencies
  final ConfigLoader _configLoader = ConfigLoader();

  // Cached state
  DefaultConfig? _defaults;
  final Map<String, DynamicEngine> _engines = {};
  final Map<String, EngineConfig> _configs = {};
  bool _initialized = false;

  /// Whether the registry has been initialized
  bool get isInitialized => _initialized;

  /// Get the default configuration (null if not initialized)
  DefaultConfig? get defaults => _defaults;

  /// Initialize the registry by loading all engine configurations.
  ///
  /// This method is idempotent - calling it multiple times will
  /// only load configurations once. Use [reload] to force a refresh.
  ///
  /// Errors during initialization are logged but not thrown,
  /// leaving the registry in an empty but usable state.
  Future<void> initialize() async {
    if (_initialized) {
      debugPrint('EngineRegistry: Already initialized');
      return;
    }

    try {
      debugPrint('EngineRegistry: Initializing...');

      // Load defaults first
      _defaults = await _configLoader.getDefaults();

      // Load all engine configs
      final configs = await _configLoader.getEngines();

      // Create DynamicEngine instances for each config
      for (final config in configs) {
        final id = config.metadata.id;
        if (id.isNotEmpty) {
          _configs[id] = config;
          _engines[id] = DynamicEngine(config);
          debugPrint('EngineRegistry: Registered engine: $id');
        }
      }

      _initialized = true;
      debugPrint(
        'EngineRegistry: Initialized with ${_engines.length} engines',
      );
    } catch (e) {
      debugPrint('EngineRegistry: Initialization failed: $e');
      // Don't crash - leave in empty state
      _initialized = true;
    }
  }

  // ==================== Engine Access ====================

  /// Get all registered DynamicEngine instances.
  ///
  /// Returns an empty list if not initialized or no engines loaded.
  List<DynamicEngine> getAllEngines() {
    if (!_initialized) {
      debugPrint('EngineRegistry: getAllEngines called before initialization');
      return [];
    }
    return _engines.values.toList();
  }

  /// Get all engine configurations as a map of ID to config.
  ///
  /// Returns an empty map if not initialized.
  Map<String, EngineConfig> getAllConfigs() {
    if (!_initialized) {
      return {};
    }
    return Map.unmodifiable(_configs);
  }

  /// Get a specific engine by its ID.
  ///
  /// Returns null if not found or not initialized.
  DynamicEngine? getEngine(String id) {
    if (!_initialized) {
      debugPrint('EngineRegistry: getEngine called before initialization');
      return null;
    }
    return _engines[id];
  }

  /// Get a specific engine configuration by ID.
  ///
  /// Returns null if not found or not initialized.
  EngineConfig? getConfig(String id) {
    if (!_initialized) {
      return null;
    }
    return _configs[id];
  }

  // ==================== Capability-based Queries ====================

  /// Get all engines that support keyword search.
  ///
  /// Returns engines where metadata.capabilities.keywordSearch is true.
  List<DynamicEngine> getKeywordSearchEngines() {
    if (!_initialized) return [];

    return _engines.entries
        .where((entry) {
          final config = _configs[entry.key];
          return config?.metadata.capabilities.keywordSearch ?? false;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// Get all engines that support IMDB search.
  ///
  /// Returns engines where metadata.capabilities.imdbSearch is true.
  List<DynamicEngine> getImdbSearchEngines() {
    if (!_initialized) return [];

    return _engines.entries
        .where((entry) {
          final config = _configs[entry.key];
          return config?.metadata.capabilities.imdbSearch ?? false;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// Get all engines that support series/TV show search.
  ///
  /// Returns engines where metadata.capabilities.seriesSupport is true.
  List<DynamicEngine> getSeriesSearchEngines() {
    if (!_initialized) return [];

    return _engines.entries
        .where((entry) {
          final config = _configs[entry.key];
          return config?.metadata.capabilities.seriesSupport ?? false;
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// Get all engines that have TV mode configuration.
  ///
  /// Returns engines where tvMode config is defined (not null).
  List<DynamicEngine> getTvModeEngines() {
    if (!_initialized) return [];

    return _engines.entries
        .where((entry) {
          final config = _configs[entry.key];
          return config?.tvMode != null;
        })
        .map((entry) => entry.value)
        .toList();
  }

  // ==================== Filtering Helpers ====================

  /// Get engines by category.
  ///
  /// Returns engines where metadata.categories contains the specified category.
  /// Category matching is case-insensitive.
  List<DynamicEngine> getEnginesByCategory(String category) {
    if (!_initialized) return [];

    final lowerCategory = category.toLowerCase();
    return _engines.entries
        .where((entry) {
          final config = _configs[entry.key];
          final categories = config?.metadata.categories ?? [];
          return categories.any((c) => c.toLowerCase() == lowerCategory);
        })
        .map((entry) => entry.value)
        .toList();
  }

  /// Get engines with a specific capability.
  ///
  /// Supported capability strings:
  /// - 'keyword_search' or 'keyword'
  /// - 'imdb_search' or 'imdb'
  /// - 'series_support' or 'series'
  /// - 'tv_mode' or 'tv'
  ///
  /// Returns an empty list for unknown capabilities.
  List<DynamicEngine> getEnginesWithCapability(String capability) {
    if (!_initialized) return [];

    switch (capability.toLowerCase()) {
      case 'keyword_search':
      case 'keyword':
        return getKeywordSearchEngines();
      case 'imdb_search':
      case 'imdb':
        return getImdbSearchEngines();
      case 'series_support':
      case 'series':
        return getSeriesSearchEngines();
      case 'tv_mode':
      case 'tv':
        return getTvModeEngines();
      default:
        debugPrint('EngineRegistry: Unknown capability: $capability');
        return [];
    }
  }

  // ==================== Engine Info ====================

  /// Get list of all registered engine IDs.
  ///
  /// Returns an empty list if not initialized.
  List<String> getEngineIds() {
    if (!_initialized) return [];
    return _engines.keys.toList();
  }

  /// Get list of all engine display names.
  ///
  /// Returns an empty list if not initialized.
  List<String> getDisplayNames() {
    if (!_initialized) return [];

    return _configs.values
        .map((config) => config.metadata.displayName)
        .where((name) => name.isNotEmpty)
        .toList();
  }

  // ==================== Reload Support ====================

  /// Force reload all configurations.
  ///
  /// Clears all cached engines and configs, then reloads from YAML files.
  /// Useful for hot-reloading during development.
  Future<void> reload() async {
    debugPrint('EngineRegistry: Reloading configurations...');

    // Clear existing state
    _engines.clear();
    _configs.clear();
    _defaults = null;
    _initialized = false;

    // Clear config loader cache
    _configLoader.clearCache();

    // Re-initialize
    await initialize();

    debugPrint('EngineRegistry: Reload complete');
  }

  // ==================== Debug Helpers ====================

  /// Get a summary of the registry state for debugging.
  Map<String, dynamic> getDebugInfo() {
    return {
      'initialized': _initialized,
      'engine_count': _engines.length,
      'engine_ids': _engines.keys.toList(),
      'keyword_search_count': getKeywordSearchEngines().length,
      'imdb_search_count': getImdbSearchEngines().length,
      'series_search_count': getSeriesSearchEngines().length,
      'tv_mode_count': getTvModeEngines().length,
      'defaults_loaded': _defaults != null,
    };
  }
}
