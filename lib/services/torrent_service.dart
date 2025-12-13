import 'package:flutter/foundation.dart';

import '../models/torrent.dart';
import 'engine/engine_registry.dart';
import 'engine/dynamic_engine.dart';
import 'engine/settings_manager.dart';

/// Service for searching torrents across multiple dynamic engines.
///
/// This service provides a unified interface for searching torrents
/// using the YAML-based engine registry system. It handles:
/// - Engine initialization
/// - Parallel searching across multiple engines
/// - Result deduplication by infohash
/// - Sorting by seeders
/// - Error handling per engine
///
/// Usage:
/// ```dart
/// // Keyword search
/// final results = await TorrentService.searchAllEngines('movie name');
///
/// // IMDB search
/// final results = await TorrentService.searchByImdb('tt1234567');
///
/// // Series search
/// final results = await TorrentService.searchByImdb(
///   'tt1234567',
///   isMovie: false,
///   season: 1,
///   episode: 5,
/// );
/// ```
class TorrentService {
  static final EngineRegistry _registry = EngineRegistry.instance;
  static final SettingsManager _settings = SettingsManager();

  // ============================================================
  // Initialization
  // ============================================================

  /// Ensure the engine registry is initialized.
  ///
  /// This method is idempotent and safe to call multiple times.
  /// If initialization fails, the registry will be in an empty but
  /// usable state (all queries return empty results).
  static Future<void> ensureInitialized() async {
    if (!_registry.isInitialized) {
      await _registry.initialize();
    }
  }

  // ============================================================
  // Single Engine Search
  // ============================================================

  /// Search using a single engine.
  ///
  /// If [engineId] is provided, that specific engine is used.
  /// Otherwise, the first available keyword-capable engine is used.
  ///
  /// Returns empty list if:
  /// - No engines are available
  /// - The specified engine doesn't exist
  /// - The engine doesn't support keyword search
  /// - The search fails
  static Future<List<Torrent>> searchTorrents(
    String query, {
    String? engineId,
  }) async {
    await ensureInitialized();

    try {
      DynamicEngine? engine;

      if (engineId != null) {
        // Use specified engine
        engine = _registry.getEngine(engineId);
        if (engine == null) {
          debugPrint('TorrentService: Engine not found: $engineId');
          return [];
        }
      } else {
        // Use first keyword-capable engine
        final engines = _registry.getKeywordSearchEngines();
        if (engines.isEmpty) {
          debugPrint('TorrentService: No keyword search engines available');
          return [];
        }
        engine = engines.first;
      }

      // Get max results setting for this engine
      final defaultMax = engine.settingsConfig.maxResults?.defaultInt ?? 50;
      final maxResults = await _settings.getMaxResults(engine.name, defaultMax);

      return await engine.executeSearch(query: query, maxResults: maxResults);
    } catch (e) {
      debugPrint('TorrentService: searchTorrents error: $e');
      return [];
    }
  }

  // ============================================================
  // Multi-Engine Keyword Search
  // ============================================================

  /// Search all enabled engines using keyword search.
  ///
  /// This is the main search method used by the UI for keyword-based searches.
  ///
  /// Parameters:
  /// - [query]: The search query string
  /// - [engineStates]: Optional map of engine ID to enabled state. If provided,
  ///   only engines with true state are searched. If null, uses stored settings.
  /// - [imdbIdOverride]: If provided, uses this instead of the query string
  ///   (for backward compatibility with existing UI code)
  /// - [maxResultsOverrides]: Optional map of engine ID to max results.
  ///   If provided for an engine, uses this instead of stored settings.
  ///
  /// Returns a map with:
  /// - 'torrents': List<Torrent> - deduplicated and sorted by seeders
  /// - 'engineCounts': Map<String, int> - count of results per engine
  /// - 'engineErrors': Map<String, String> - error messages per engine
  static Future<Map<String, dynamic>> searchAllEngines(
    String query, {
    Map<String, bool>? engineStates,
    String? imdbIdOverride,
    Map<String, int>? maxResultsOverrides,
  }) async {
    await ensureInitialized();

    final Map<String, int> engineCounts = {};
    final Map<String, String> engineErrors = {};

    // Get all keyword search capable engines
    final allEngines = _registry.getKeywordSearchEngines();

    if (allEngines.isEmpty) {
      debugPrint('TorrentService: No keyword search engines available');
      return {
        'torrents': <Torrent>[],
        'engineCounts': engineCounts,
        'engineErrors': engineErrors,
      };
    }

    // Filter engines based on enabled state
    final List<DynamicEngine> selectedEngines = [];

    for (final engine in allEngines) {
      final engineId = engine.name;
      bool isEnabled;

      if (engineStates != null && engineStates.containsKey(engineId)) {
        // Use provided state
        isEnabled = engineStates[engineId] ?? false;
      } else {
        // Check stored settings, default to config default
        final defaultEnabled =
            engine.settingsConfig.enabled?.defaultBool ?? true;
        isEnabled = await _settings.getEnabled(engineId, defaultEnabled);
      }

      if (isEnabled) {
        selectedEngines.add(engine);
      }
    }

    // If no engines selected, return empty results
    if (selectedEngines.isEmpty) {
      debugPrint('TorrentService: No engines enabled for search');
      return {
        'torrents': <Torrent>[],
        'engineCounts': engineCounts,
        'engineErrors': engineErrors,
      };
    }

    // Determine effective query
    final override = imdbIdOverride?.trim();
    final effectiveQuery =
        override != null && override.isNotEmpty ? override : query;

    // Search all selected engines in parallel
    final List<Future<List<Torrent>>> futures = [];

    for (final engine in selectedEngines) {
      final engineId = engine.name;

      // Get max results setting for this engine (check override first)
      final int maxResults;
      if (maxResultsOverrides != null && maxResultsOverrides.containsKey(engineId)) {
        maxResults = maxResultsOverrides[engineId]!;
        debugPrint('TorrentService: $engineId - using override maxResults: $maxResults');
      } else {
        final maxResultsSetting = engine.settingsConfig.maxResults;
        final defaultMax = maxResultsSetting?.defaultInt ?? 50;
        maxResults = await _settings.getMaxResults(engineId, defaultMax);
        debugPrint('TorrentService: $engineId - settingExists: ${maxResultsSetting != null}, '
            'yamlDefault: ${maxResultsSetting?.defaultValue}, defaultInt: $defaultMax, '
            'finalMax: $maxResults');
      }

      futures.add(
        engine.executeSearch(
          query: effectiveQuery,
          maxResults: maxResults,
        ).then((results) {
          engineCounts[engineId] = results.length;
          debugPrint(
              'TorrentService: $engineId returned ${results.length} results (max: $maxResults)');
          return results;
        }).catchError((error, _) {
          engineCounts[engineId] = 0;
          engineErrors[engineId] = error.toString();
          debugPrint('TorrentService: $engineId error: $error');
          return <Torrent>[];
        }),
      );
    }

    final allResults = await Future.wait(futures);

    // Deduplicate and sort
    final torrents = _deduplicateAndSort(allResults);

    return {
      'torrents': torrents,
      'engineCounts': engineCounts,
      'engineErrors': engineErrors,
    };
  }

  // ============================================================
  // IMDB Search
  // ============================================================

  /// Search by IMDB ID.
  ///
  /// This is used for advanced search where the user selects a specific
  /// movie or TV show from TMDB/IMDB.
  ///
  /// Parameters:
  /// - [imdbId]: The IMDB ID (e.g., 'tt1234567')
  /// - [engineStates]: Optional map of engine ID to enabled state
  /// - [isMovie]: True for movies, false for TV series
  /// - [season]: Season number for TV series (optional)
  /// - [episode]: Episode number for TV series (optional)
  ///
  /// Returns the same format as [searchAllEngines].
  static Future<Map<String, dynamic>> searchByImdb(
    String imdbId, {
    Map<String, bool>? engineStates,
    bool isMovie = true,
    int? season,
    int? episode,
  }) async {
    await ensureInitialized();

    final Map<String, int> engineCounts = {};
    final Map<String, String> engineErrors = {};

    // Get all IMDB search capable engines
    final allEngines = _registry.getImdbSearchEngines();

    if (allEngines.isEmpty) {
      debugPrint('TorrentService: No IMDB search engines available');
      return {
        'torrents': <Torrent>[],
        'engineCounts': engineCounts,
        'engineErrors': engineErrors,
      };
    }

    // Filter engines based on enabled state
    final List<DynamicEngine> selectedEngines = [];

    for (final engine in allEngines) {
      final engineId = engine.name;
      bool isEnabled;

      if (engineStates != null && engineStates.containsKey(engineId)) {
        isEnabled = engineStates[engineId] ?? false;
      } else {
        final defaultEnabled =
            engine.settingsConfig.enabled?.defaultBool ?? true;
        isEnabled = await _settings.getEnabled(engineId, defaultEnabled);
      }

      if (isEnabled) {
        selectedEngines.add(engine);
      }
    }

    if (selectedEngines.isEmpty) {
      debugPrint('TorrentService: No engines enabled for IMDB search');
      return {
        'torrents': <Torrent>[],
        'engineCounts': engineCounts,
        'engineErrors': engineErrors,
      };
    }

    // Search all selected engines in parallel
    final List<Future<List<Torrent>>> futures = [];

    for (final engine in selectedEngines) {
      final engineId = engine.name;

      // Get max results setting for this engine
      final defaultMax = engine.settingsConfig.maxResults?.defaultInt ?? 50;
      final maxResults = await _settings.getMaxResults(engineId, defaultMax);

      // Use executeSearch which supports maxResults
      futures.add(
        engine.executeSearch(
          imdbId: imdbId,
          isSeries: !isMovie,
          season: (!isMovie && engine.supportsSeriesSearch) ? season : null,
          episode: (!isMovie && engine.supportsSeriesSearch) ? episode : null,
          maxResults: maxResults,
        ).then((results) {
          engineCounts[engineId] = results.length;
          debugPrint(
              'TorrentService: $engineId (IMDB) returned ${results.length} results (max: $maxResults)');
          return results;
        }).catchError((error, _) {
          engineCounts[engineId] = 0;
          engineErrors[engineId] = error.toString();
          debugPrint('TorrentService: $engineId (IMDB) error: $error');
          return <Torrent>[];
        }),
      );
    }

    final allResults = await Future.wait(futures);

    // Deduplicate and sort
    final torrents = _deduplicateAndSort(allResults);

    return {
      'torrents': torrents,
      'engineCounts': engineCounts,
      'engineErrors': engineErrors,
    };
  }

  // ============================================================
  // Engine Access Methods
  // ============================================================

  /// Get all available engines.
  ///
  /// Returns an empty list if the registry is not initialized or
  /// contains no engines.
  static Future<List<DynamicEngine>> getAvailableEngines() async {
    await ensureInitialized();
    return _registry.getAllEngines();
  }

  /// Get engines that support keyword search.
  static Future<List<DynamicEngine>> getKeywordSearchEngines() async {
    await ensureInitialized();
    return _registry.getKeywordSearchEngines();
  }

  /// Get engines that support IMDB search.
  static Future<List<DynamicEngine>> getImdbSearchEngines() async {
    await ensureInitialized();
    return _registry.getImdbSearchEngines();
  }

  /// Get engines that support series/TV show search.
  static Future<List<DynamicEngine>> getSeriesSearchEngines() async {
    await ensureInitialized();
    return _registry.getSeriesSearchEngines();
  }

  /// Get engines configured for TV mode.
  static Future<List<DynamicEngine>> getTvModeEngines() async {
    await ensureInitialized();
    return _registry.getTvModeEngines();
  }

  /// Get a specific engine by ID.
  ///
  /// Returns null if the engine doesn't exist.
  static Future<DynamicEngine?> getEngine(String engineId) async {
    await ensureInitialized();
    return _registry.getEngine(engineId);
  }

  // ============================================================
  // Engine Info Helpers
  // ============================================================

  /// Get list of all available engine IDs.
  static Future<List<String>> getAvailableEngineIds() async {
    await ensureInitialized();
    return _registry.getEngineIds();
  }

  /// Get list of all engine display names.
  static Future<List<String>> getAvailableEngineDisplayNames() async {
    await ensureInitialized();
    return _registry.getDisplayNames();
  }

  /// Get engines filtered by category.
  ///
  /// Categories might include: 'movies', 'tv', 'anime', 'general', etc.
  static Future<List<DynamicEngine>> getEnginesByCategory(
      String category) async {
    await ensureInitialized();
    return _registry.getEnginesByCategory(category);
  }

  // ============================================================
  // Settings Integration
  // ============================================================

  /// Check if an engine is enabled in settings.
  static Future<bool> isEngineEnabled(String engineId) async {
    await ensureInitialized();
    final engine = _registry.getEngine(engineId);
    if (engine == null) return false;

    final defaultEnabled = engine.settingsConfig.enabled?.defaultBool ?? true;
    return _settings.getEnabled(engineId, defaultEnabled);
  }

  /// Set engine enabled state in settings.
  static Future<void> setEngineEnabled(String engineId, bool enabled) async {
    await _settings.setEnabled(engineId, enabled);
  }

  /// Get the max results setting for an engine.
  static Future<int> getEngineMaxResults(String engineId) async {
    await ensureInitialized();
    final engine = _registry.getEngine(engineId);
    if (engine == null) return 50;

    final defaultMax = engine.settingsConfig.maxResults?.defaultInt ?? 50;
    return _settings.getMaxResults(engineId, defaultMax);
  }

  // ============================================================
  // Registry Management
  // ============================================================

  /// Force reload all engine configurations.
  ///
  /// Useful for development hot-reload or when YAML files are updated.
  static Future<void> reloadEngines() async {
    await _registry.reload();
  }

  /// Get debug information about the registry state.
  static Future<Map<String, dynamic>> getDebugInfo() async {
    await ensureInitialized();
    return _registry.getDebugInfo();
  }

  // ============================================================
  // Private Helpers
  // ============================================================

  /// Deduplicate torrent results by infohash and sort by seeders descending.
  static List<Torrent> _deduplicateAndSort(List<List<Torrent>> allResults) {
    final Map<String, Torrent> uniqueTorrents = {};

    for (final torrentList in allResults) {
      for (final torrent in torrentList) {
        // Only add if we haven't seen this infohash
        // or if this one has more seeders
        final existing = uniqueTorrents[torrent.infohash];
        if (existing == null || torrent.seeders > existing.seeders) {
          uniqueTorrents[torrent.infohash] = torrent;
        }
      }
    }

    // Convert to list and sort by seeders descending
    final deduplicatedResults = uniqueTorrents.values.toList();
    deduplicatedResults.sort((a, b) => b.seeders.compareTo(a.seeders));

    debugPrint(
        'TorrentService: Deduplicated to ${deduplicatedResults.length} unique torrents');

    return deduplicatedResults;
  }
}
