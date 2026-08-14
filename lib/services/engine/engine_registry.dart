import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import '../../models/engine_config/engine_config.dart';
import '../../models/engine_config/default_config.dart';
import '../profiles/profile_runtime.dart';
import '../profiles/profile_scope.dart';
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

  /// Pauses a completed load immediately before its scope/revision guard.
  /// Tests use this to prove an outgoing async load cannot publish late.
  @visibleForTesting
  static Future<void> Function()? debugBeforePublish;

  // Dependencies
  final ConfigLoader _configLoader = ConfigLoader();

  // Cached state
  DefaultConfig? _defaults;
  final Map<String, DynamicEngine> _engines = {};
  final Map<String, EngineConfig> _configs = {};
  final Lock _loadLock = Lock();
  bool _initialized = false;
  String? _loadedScopeKey;
  int _stateRevision = 0;

  /// Whether the registry has been initialized for the authoritative profile
  /// scope that is active now.
  ///
  /// A stale profile's map may exist for a few microtasks while a switch is
  /// publishing, but it is never observable through this registry.
  bool get isInitialized =>
      _initialized && _loadedScopeKey == _EngineRegistryScope.capture().key;

  /// Get the default configuration (null if not initialized)
  DefaultConfig? get defaults => isInitialized ? _defaults : null;

  /// Initialize the registry by loading all engine configurations.
  ///
  /// This method is idempotent - calling it multiple times will
  /// only load configurations once. Use [reload] to force a refresh.
  ///
  /// Errors during initialization are logged but not thrown,
  /// leaving the registry in an empty but usable state.
  Future<void> initialize() {
    final requestedScope = _EngineRegistryScope.capture();
    return _loadLock.synchronized(() async {
      if (!requestedScope.isCurrent) return;
      if (_initialized && _loadedScopeKey == requestedScope.key) {
        debugPrint('EngineRegistry: Already initialized');
        return;
      }
      await _loadScope(requestedScope);
    });
  }

  Future<void> _loadScope(_EngineRegistryScope requestedScope) async {
    final revision = ++_stateRevision;
    _clearState();
    // ConfigLoader is also process-global. Every registry load owns a fresh
    // config snapshot so it can never reuse the previous profile's list.
    _configLoader.clearCache();
    try {
      debugPrint('EngineRegistry: Initializing...');

      final loaded = await requestedScope.run(() async {
        final defaults = await _configLoader.getDefaults();
        final configs = await _configLoader.getEngines();
        return (defaults: defaults, configs: configs);
      });
      await debugBeforePublish?.call();

      // Profile publication and synchronous invalidation can both happen at
      // an await boundary. An old load is discarded rather than being allowed
      // to repopulate the singleton after the switch.
      if (revision != _stateRevision || !requestedScope.isCurrent) return;

      final engines = <String, DynamicEngine>{};
      final configsById = <String, EngineConfig>{};

      // Create DynamicEngine instances for each config
      for (final config in loaded.configs) {
        final id = config.metadata.id;
        if (id.isNotEmpty) {
          configsById[id] = config;
          engines[id] = DynamicEngine(config);
          debugPrint('EngineRegistry: Registered engine: $id');
        }
      }

      _defaults = loaded.defaults;
      _configs.addAll(configsById);
      _engines.addAll(engines);
      _loadedScopeKey = requestedScope.key;
      _initialized = true;
      debugPrint(
        'EngineRegistry: Initialized with ${_engines.length} engines',
      );
    } catch (e) {
      debugPrint('EngineRegistry: Initialization failed: $e');
      // Don't crash - leave in empty state
      if (revision == _stateRevision && requestedScope.isCurrent) {
        _loadedScopeKey = requestedScope.key;
        _initialized = true;
      }
    }
  }

  void _clearState() {
    _engines.clear();
    _configs.clear();
    _defaults = null;
    _initialized = false;
    _loadedScopeKey = null;
  }

  // ==================== Engine Access ====================

  /// Get all registered DynamicEngine instances.
  ///
  /// Returns an empty list if not initialized or no engines loaded.
  List<DynamicEngine> getAllEngines() {
    if (!isInitialized) {
      debugPrint('EngineRegistry: getAllEngines called before initialization');
      return [];
    }
    return _engines.values.toList();
  }

  /// Get all engine configurations as a map of ID to config.
  ///
  /// Returns an empty map if not initialized.
  Map<String, EngineConfig> getAllConfigs() {
    if (!isInitialized) {
      return {};
    }
    return Map.unmodifiable(_configs);
  }

  /// Get a specific engine by its ID.
  ///
  /// Returns null if not found or not initialized.
  DynamicEngine? getEngine(String id) {
    if (!isInitialized) {
      debugPrint('EngineRegistry: getEngine called before initialization');
      return null;
    }
    return _engines[id];
  }

  /// Get a specific engine configuration by ID.
  ///
  /// Returns null if not found or not initialized.
  EngineConfig? getConfig(String id) {
    if (!isInitialized) {
      return null;
    }
    return _configs[id];
  }

  // ==================== Capability-based Queries ====================

  /// Get all engines that support keyword search.
  ///
  /// Returns engines where metadata.capabilities.keywordSearch is true.
  List<DynamicEngine> getKeywordSearchEngines() {
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];

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
    if (!isInitialized) return [];
    return _engines.keys.toList();
  }

  /// Get list of all engine display names.
  ///
  /// Returns an empty list if not initialized.
  List<String> getDisplayNames() {
    if (!isInitialized) return [];

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
  Future<void> reload() {
    final requestedScope = _EngineRegistryScope.capture();
    debugPrint('EngineRegistry: Reloading configurations...');
    return _loadLock.synchronized(() async {
      if (!requestedScope.isCurrent) return;
      await _loadScope(requestedScope);
      debugPrint('EngineRegistry: Reload complete');
    });
  }

  /// Immediately makes the current registry snapshot inaccessible.
  ///
  /// Profile switching calls this before its first await. A load already in
  /// flight is invalidated by [_stateRevision] and cannot resurrect the
  /// outgoing profile's engines when it completes.
  void invalidateProfileScope() {
    _stateRevision++;
    _clearState();
    _configLoader.clearCache();
    debugPrint('EngineRegistry: Profile scope invalidated');
  }

  // ==================== Debug Helpers ====================

  /// Get a summary of the registry state for debugging.
  Map<String, dynamic> getDebugInfo() {
    final current = isInitialized;
    return {
      'initialized': current,
      'engine_count': current ? _engines.length : 0,
      'engine_ids': current ? _engines.keys.toList() : <String>[],
      'keyword_search_count': getKeywordSearchEngines().length,
      'imdb_search_count': getImdbSearchEngines().length,
      'series_search_count': getSeriesSearchEngines().length,
      'tv_mode_count': getTvModeEngines().length,
      'defaults_loaded': current && _defaults != null,
    };
  }
}

/// The process-global engine cache is bound to the authoritative runtime
/// scope, not to a captured async Zone. A search that began under profile A is
/// allowed to finish its own authorization check, but it cannot steer this
/// singleton back to A after profile B has been published.
class _EngineRegistryScope {
  const _EngineRegistryScope(this.key, this.scope);

  final String key;
  final ProfileScope? scope;

  static _EngineRegistryScope capture() {
    if (!ProfileRuntime.isInitialized) {
      return const _EngineRegistryScope('runtime:uninitialized', null);
    }
    if (ProfileRuntime.mode == ProfileRuntimeMode.legacyCompatibility) {
      return const _EngineRegistryScope('runtime:legacy', null);
    }
    final active = ProfileRuntime.scope.value;
    if (active == null) {
      return const _EngineRegistryScope('runtime:committed-unbound', null);
    }
    return _EngineRegistryScope(
      'profile:${active.profileId}:g:${active.dataGeneration}:e:${active.sessionEpoch}',
      active,
    );
  }

  bool get isCurrent => key == capture().key;

  Future<T> run<T>(Future<T> Function() body) {
    final captured = scope;
    return captured == null
        ? body()
        : ProfileRuntime.withCapturedScope(captured, body);
  }
}
