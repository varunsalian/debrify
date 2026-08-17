import 'package:flutter/foundation.dart';

import '../models/engine_config/engine_config.dart';
import '../models/indexer_manager_config.dart';
import '../models/torrent.dart';
import '../models/profiles/profile_policy.dart';
import 'engine/engine_registry.dart';
import 'engine/dynamic_engine.dart';
import 'engine/settings_manager.dart';
import 'indexer_manager_service.dart';
import 'profiles/profile_async_authorization.dart';
import 'stremio_service.dart';

/// Streaming-search hook: fired once per source (engine / addon batch) that
/// returned results, AS it completes — long before the slowest engine's
/// timeout. Fires on the search's async context; UI callers must re-check
/// mounted/token guards inside. The awaited search result stays the
/// authoritative full set.
typedef SearchBatchCallback = void Function(String source, List<Torrent> batch);

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
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    await ensureInitialized();

    try {
      DynamicEngine? engine;

      if (engineId != null) {
        // Use specified engine
        engine = _registry.getEngine(engineId);
        if (engine == null) {
          final indexerConfig = await IndexerManagerService.getConfigForEngine(
            engineId,
          );
          if (indexerConfig != null) {
            final maxResults = await _settings.getMaxResults(
              engineId,
              indexerConfig.maxResults,
            );
            final results = await IndexerManagerService.searchKeyword(
              indexerConfig,
              query,
              maxResults: maxResults,
            );
            await capability?.runIfCurrent(() async {});
            return results;
          }
          debugPrint('TorrentService: Requested engine was not found');
          return [];
        }
      } else {
        // Use first keyword-capable engine
        final engines = await _getKeywordSearchEngines();
        if (engines.isEmpty) {
          debugPrint('TorrentService: No keyword search engines available');
          return [];
        }
        engine = engines.first;
      }

      // Get max results setting for this engine
      final defaultMax = engine.settingsConfig.maxResults?.defaultInt ?? 50;
      final maxResults = await _settings.getMaxResults(engine.name, defaultMax);

      final results = await engine.executeSearch(
        query: query,
        maxResults: maxResults,
      );
      await capability?.runIfCurrent(() async {});
      return results;
    } catch (_) {
      debugPrint('TorrentService: search failed');
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
  /// - 'torrents': `List<Torrent>` - deduplicated and sorted by seeders
  /// - 'engineCounts': `Map<String, int>` - count of results per engine
  /// - 'engineErrors': `Map<String, String>` - error messages per engine
  static Future<Map<String, dynamic>> searchAllEngines(
    String query, {
    Map<String, bool>? engineStates,
    String? imdbIdOverride,
    Map<String, int>? maxResultsOverrides,
    SearchBatchCallback? onBatch,
  }) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    await ensureInitialized();

    final Map<String, int> engineCounts = {};
    final Map<String, String> engineErrors = {};

    // Get all keyword search capable engines
    final allEngines = await _getKeywordSearchEngines();

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
      final isEnabled = await _isEngineSelected(engine, engineStates);

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
    final effectiveQuery = override != null && override.isNotEmpty
        ? override
        : query;

    // Search all selected engines in parallel
    final List<Future<List<Torrent>>> futures = [];

    for (final engine in selectedEngines) {
      final engineId = engine.name;

      // Get max results setting for this engine (check override first)
      final int maxResults;
      if (maxResultsOverrides != null &&
          maxResultsOverrides.containsKey(engineId)) {
        maxResults = maxResultsOverrides[engineId]!;
        debugPrint('TorrentService: Using per-engine result limit');
      } else {
        final maxResultsSetting = engine.settingsConfig.maxResults;
        final defaultMax = maxResultsSetting?.defaultInt ?? 50;
        maxResults = await _settings.getMaxResults(engineId, defaultMax);
        debugPrint('TorrentService: Loaded engine result limit');
      }

      futures.add(
        _executeKeywordSearch(engine, effectiveQuery, maxResults)
            .then((results) {
              engineCounts[engineId] = results.length;
              debugPrint('TorrentService: Engine search completed');
              // Isolated: a throwing consumer callback must never reject the
              // search future or be misrecorded as an engine failure.
              if (results.isNotEmpty) {
                try {
                  onBatch?.call(engineId, results);
                } catch (_) {
                  debugPrint('TorrentService: onBatch callback failed');
                }
              }
              return results;
            })
            .catchError((error, _) {
              engineCounts[engineId] = 0;
              engineErrors[engineId] = 'Search failed';
              debugPrint('TorrentService: engine search failed');
              return <Torrent>[];
            }),
      );
    }

    final allResults = await Future.wait(futures);

    // Deduplicate and sort
    final torrents = _deduplicateAndSort(allResults);
    await capability?.runIfCurrent(() async {});

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
  /// - [availableSeasons]: Known seasons from IMDbbot API for optimized probing
  ///
  /// Returns the same format as [searchAllEngines].
  static Future<Map<String, dynamic>> searchByImdb(
    String imdbId, {
    Map<String, bool>? engineStates,
    bool isMovie = true,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    Duration? timeout,
    SearchBatchCallback? onBatch,
  }) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    await ensureInitialized();

    final Map<String, int> engineCounts = {};
    final Map<String, String> engineErrors = {};

    // Get all IMDB search capable engines
    final allEngines = await _getImdbSearchEngines();

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
      final isEnabled = await _isEngineSelected(engine, engineStates);

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

      var future =
          _executeImdbSearch(
                engine,
                imdbId,
                isMovie: isMovie,
                season: season,
                episode: episode,
                availableSeasons: availableSeasons,
                maxResults: maxResults,
              )
              .then((results) {
                engineCounts[engineId] = results.length;
                debugPrint('TorrentService: IMDB engine search completed');
                // Isolated: see the keyword path — consumer exceptions must
                // never alter the awaited search result.
                if (results.isNotEmpty) {
                  try {
                    onBatch?.call(engineId, results);
                  } catch (_) {
                    debugPrint('TorrentService: onBatch callback failed');
                  }
                }
                return results;
              })
              .catchError((error, _) {
                engineCounts[engineId] = 0;
                engineErrors[engineId] = 'Search failed';
                debugPrint('TorrentService: IMDB engine search failed');
                return <Torrent>[];
              });
      if (timeout != null) {
        future = future.timeout(
          timeout,
          onTimeout: () {
            engineCounts[engineId] = 0;
            engineErrors[engineId] = 'Timeout after ${timeout.inSeconds}s';
            debugPrint('TorrentService: IMDB engine search timed out');
            return <Torrent>[];
          },
        );
      }
      futures.add(future);
    }

    final allResults = await Future.wait(futures);

    // Deduplicate and sort
    final torrents = _deduplicateAndSort(allResults);
    await capability?.runIfCurrent(() async {});

    return {
      'torrents': torrents,
      'engineCounts': engineCounts,
      'engineErrors': engineErrors,
    };
  }

  // ============================================================
  // Combined Search (Engines + Stremio Addons)
  // ============================================================

  /// Search by IMDB ID using both YAML engines and Stremio addons.
  ///
  /// This combines results from the traditional YAML-based engines and
  /// any configured Stremio addons for comprehensive torrent discovery.
  ///
  /// Parameters:
  /// - [imdbId]: The IMDB ID (e.g., 'tt1234567')
  /// - [engineStates]: Optional map of engine ID to enabled state
  /// - [isMovie]: True for movies, false for TV series
  /// - [season]: Season number for TV series (optional)
  /// - [episode]: Episode number for TV series (optional)
  /// - [includeStremio]: Whether to include Stremio addon results (default: true)
  /// - [availableSeasons]: Known seasons from IMDbbot API for optimized probing
  ///
  /// Returns the same format as [searchByImdb] with additional Stremio sources.
  static Future<Map<String, dynamic>> searchByImdbWithStremio(
    String imdbId, {
    Map<String, bool>? engineStates,
    bool isMovie = true,
    int? season,
    int? episode,
    bool includeStremio = true,
    List<int>? availableSeasons,
    String?
    contentType, // Optional explicit content type (for TV channels, etc.)
    Duration? stremioTimeout,
    Duration? engineTimeout,
    SearchBatchCallback? onBatch,
  }) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    // For non-IMDB content types (TV channels, etc.), skip traditional engine search
    final isNonImdbContent =
        contentType != null &&
        contentType != 'movie' &&
        contentType != 'series';

    // Start searches in parallel
    final List<Future<Map<String, dynamic>>> searchFutures = [];

    // Traditional engine search only for movie/series (IMDB content)
    if (!isNonImdbContent) {
      searchFutures.add(
        searchByImdb(
          imdbId,
          engineStates: engineStates,
          isMovie: isMovie,
          season: season,
          episode: episode,
          availableSeasons: availableSeasons,
          timeout: engineTimeout,
          onBatch: onBatch, // per-engine batches stream straight through
        ),
      );
    }

    // Add Stremio search if enabled
    if (includeStremio) {
      searchFutures.add(
        _searchStremioAddons(
          imdbId: imdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
          availableSeasons: availableSeasons,
          contentType: contentType,
          timeout: stremioTimeout,
        ).then((result) {
          // The addon side reports as one batch when it completes (it never
          // throws — errors come back as an empty result).
          final streams = result['torrents'] as List<Torrent>? ?? const [];
          if (streams.isNotEmpty) {
            try {
              onBatch?.call('stremio', streams);
            } catch (_) {
              debugPrint('TorrentService: onBatch callback failed');
            }
          }
          return result;
        }),
      );
    }

    final results = await Future.wait(searchFutures);

    // Combine results
    final Map<String, int> combinedCounts = {};
    final Map<String, String> combinedErrors = {};
    final List<List<Torrent>> allTorrentLists = [];

    for (final result in results) {
      final torrents = result['torrents'] as List<Torrent>? ?? [];
      final counts = result['engineCounts'] as Map<String, int>? ?? {};
      final errors =
          result['engineErrors'] as Map<String, String>? ??
          result['addonErrors'] as Map<String, String>? ??
          {};

      allTorrentLists.add(torrents);
      combinedCounts.addAll(counts);

      // Also add addon counts if present
      final addonCounts = result['addonCounts'] as Map<String, int>?;
      if (addonCounts != null) {
        combinedCounts.addAll(addonCounts);
      }

      combinedErrors.addAll(errors);
    }

    // Log pre-deduplication counts
    debugPrint('TorrentService: Pre-dedup counts: $combinedCounts');

    // Count total torrents before dedup
    int totalPreDedup = 0;
    for (final list in allTorrentLists) {
      totalPreDedup += list.length;
    }
    debugPrint('TorrentService: Total torrents before dedup: $totalPreDedup');

    // Deduplicate and sort all results together
    final torrents = _deduplicateAndSort(allTorrentLists);
    await capability?.runIfCurrent(() async {});

    debugPrint(
      'TorrentService: Total torrents after dedup: ${torrents.length}',
    );

    // Recalculate counts based on actual deduplicated results
    // This ensures filter counts match what's actually available
    final Map<String, int> actualCounts = {};
    for (final torrent in torrents) {
      final source = torrent.source;
      actualCounts[source] = (actualCounts[source] ?? 0) + 1;
    }

    debugPrint('TorrentService: Post-dedup counts by source: $actualCounts');

    // Log the difference
    for (final key in combinedCounts.keys) {
      final pre = combinedCounts[key] ?? 0;
      final post = actualCounts[key] ?? 0;
      if (pre != post) {
        debugPrint('TorrentService: $key: $pre -> $post (${post - pre})');
      }
    }

    debugPrint(
      'TorrentService: Combined search returned ${torrents.length} unique torrents '
      'from ${actualCounts.length} sources',
    );

    return {
      'torrents': torrents,
      'engineCounts': actualCounts,
      'engineErrors': combinedErrors,
    };
  }

  /// Search Stremio addons for streams
  /// Stremio-addon-only search (no torrent engines). Same result shape as
  /// [searchByImdb]. Used by quick-play as a fallback when the engine search
  /// returns nothing — addon streams include direct-URL links that play
  /// without any torrent at all.
  static Future<Map<String, dynamic>> searchStremioAddonsOnly({
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    String? contentType,
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    final result = await _searchStremioAddons(
      imdbId: imdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      availableSeasons: availableSeasons,
      contentType: contentType,
      timeout: timeout,
      preserveOrder: preserveOrder,
    );
    await capability?.runIfCurrent(() async {});
    return result;
  }

  static Future<Map<String, dynamic>> _searchStremioAddons({
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    String?
    contentType, // Optional explicit content type (for TV channels, etc.)
    Duration? timeout,
    bool preserveOrder = false,
  }) async {
    try {
      final stremioService = StremioService.instance;
      final hasAddons = await stremioService.hasEnabledAddons();

      if (!hasAddons) {
        return {
          'torrents': <Torrent>[],
          'addonCounts': <String, int>{},
          'addonErrors': <String, String>{},
        };
      }

      // Use explicit contentType if provided, otherwise infer from isMovie
      final type = contentType ?? (isMovie ? 'movie' : 'series');
      final result = await stremioService.searchStreams(
        type: type,
        imdbId: imdbId,
        season: season,
        episode: episode,
        availableSeasons: availableSeasons,
        timeout: timeout,
        preserveOrder: preserveOrder,
      );

      return {
        'torrents': result['torrents'] as List<Torrent>? ?? [],
        'addonCounts': result['addonCounts'] as Map<String, int>? ?? {},
        'addonErrors': result['addonErrors'] as Map<String, String>? ?? {},
      };
    } catch (_) {
      debugPrint('TorrentService: Stremio addon search failed');
      return {
        'torrents': <Torrent>[],
        'addonCounts': <String, int>{},
        'addonErrors': <String, String>{'Stremio': 'Search failed'},
      };
    }
  }

  /// Check if any Stremio addons are configured
  static Future<bool> hasStremioAddons() async {
    return StremioService.instance.hasEnabledAddons();
  }

  /// Get count of enabled Stremio addons
  static Future<int> getStremioAddonCount() async {
    return StremioService.instance.getEnabledAddonCount();
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
    return _getAllEngines();
  }

  /// Get engines that support keyword search.
  static Future<List<DynamicEngine>> getKeywordSearchEngines() async {
    await ensureInitialized();
    return _getKeywordSearchEngines();
  }

  /// Get engines that support IMDB search.
  static Future<List<DynamicEngine>> getImdbSearchEngines() async {
    await ensureInitialized();
    return _getImdbSearchEngines();
  }

  /// Get engines that support series/TV show search.
  static Future<List<DynamicEngine>> getSeriesSearchEngines() async {
    await ensureInitialized();
    final engines = _registry.getSeriesSearchEngines();
    return [...engines, ...await _getIndexerManagerEngines()];
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
    final engine = _registry.getEngine(engineId);
    if (engine != null) return engine;
    final config = await IndexerManagerService.getConfigForEngine(engineId);
    return config == null ? null : _dynamicEngineForIndexerManager(config);
  }

  // ============================================================
  // Engine Info Helpers
  // ============================================================

  /// Get list of all available engine IDs.
  static Future<List<String>> getAvailableEngineIds() async {
    await ensureInitialized();
    return (await _getAllEngines()).map((engine) => engine.name).toList();
  }

  /// Get list of all engine display names.
  static Future<List<String>> getAvailableEngineDisplayNames() async {
    await ensureInitialized();
    return (await _getAllEngines())
        .map((engine) => engine.displayName)
        .toList();
  }

  /// Get engines filtered by category.
  ///
  /// Categories might include: 'movies', 'tv', 'anime', 'general', etc.
  static Future<List<DynamicEngine>> getEnginesByCategory(
    String category,
  ) async {
    await ensureInitialized();
    final engines = _registry.getEnginesByCategory(category);
    if (category == 'general' || category == 'movies' || category == 'tv') {
      return [...engines, ...await _getIndexerManagerEngines()];
    }
    return engines;
  }

  // ============================================================
  // Settings Integration
  // ============================================================

  /// Check if an engine is enabled in settings.
  static Future<bool> isEngineEnabled(String engineId) async {
    await ensureInitialized();
    final engine = await getEngine(engineId);
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
    final engine = await getEngine(engineId);
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

  static Future<List<DynamicEngine>> _getAllEngines() async {
    return [..._registry.getAllEngines(), ...await _getIndexerManagerEngines()];
  }

  static Future<List<DynamicEngine>> _getKeywordSearchEngines() async {
    return [
      ..._registry.getKeywordSearchEngines(),
      ...await _getIndexerManagerEngines(),
    ];
  }

  static Future<List<DynamicEngine>> _getImdbSearchEngines() async {
    return [
      ..._registry.getImdbSearchEngines(),
      ...await _getIndexerManagerEngines(),
    ];
  }

  static Future<List<DynamicEngine>> _getIndexerManagerEngines() async {
    final configs = await IndexerManagerService.getConfigs();
    return configs.map(_dynamicEngineForIndexerManager).toList();
  }

  static DynamicEngine _dynamicEngineForIndexerManager(
    IndexerManagerConfig config,
  ) {
    return DynamicEngine(
      EngineConfig(
        metadata: EngineMetadata(
          id: config.engineId,
          displayName: config.displayName,
          description:
              'Direct ${config.type.label} search engine configured in Debrify.',
          icon: 'hub',
          categories: const ['general', 'movies', 'tv'],
          capabilities: const EngineCapabilities(
            keywordSearch: true,
            imdbSearch: true,
            seriesSupport: true,
          ),
        ),
        request: RequestConfig(
          baseUrl: config.normalizedBaseUrl,
          method: 'GET',
          timeoutSeconds: config.timeoutSeconds,
          urlBuilder: const UrlBuilder(type: 'custom', encode: true),
          params: const [],
        ),
        pagination: const PaginationConfig(type: 'none'),
        response: const ResponseConfig(
          format: 'custom',
          resultsPath: '',
          fieldMapping: {},
        ),
        settings: SettingsConfig(
          settings: {
            'enabled': SettingConfig(
              type: 'toggle',
              label: 'Enabled',
              defaultValue: config.enabled,
            ),
            'max_results': SettingConfig(
              type: 'dropdown',
              label: 'Max Results',
              defaultValue: config.maxResults,
              options: const [25, 50, 100, 200],
            ),
          },
        ),
      ),
    );
  }

  static Future<bool> _isEngineSelected(
    DynamicEngine engine,
    Map<String, bool>? engineStates,
  ) async {
    final engineId = engine.name;

    if (engineStates != null && engineStates.containsKey(engineId)) {
      return engineStates[engineId] ?? false;
    }

    if (engineStates != null &&
        IndexerManagerConfig.isIndexerManagerEngine(engineId)) {
      return false;
    }

    final defaultEnabled = engine.settingsConfig.enabled?.defaultBool ?? true;
    return _settings.getEnabled(engineId, defaultEnabled);
  }

  static Future<List<Torrent>> _executeKeywordSearch(
    DynamicEngine engine,
    String query,
    int maxResults,
  ) async {
    final config = await IndexerManagerService.getConfigForEngine(engine.name);
    if (config != null) {
      return IndexerManagerService.searchKeyword(
        config,
        query,
        maxResults: maxResults,
      );
    }

    return engine.executeSearch(query: query, maxResults: maxResults);
  }

  static Future<List<Torrent>> _executeImdbSearch(
    DynamicEngine engine,
    String imdbId, {
    required bool isMovie,
    int? season,
    int? episode,
    List<int>? availableSeasons,
    required int maxResults,
  }) async {
    final config = await IndexerManagerService.getConfigForEngine(engine.name);
    if (config != null) {
      return IndexerManagerService.searchByImdb(
        config,
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        maxResults: maxResults,
      );
    }

    return engine.executeSearch(
      imdbId: imdbId,
      isSeries: !isMovie,
      season: (!isMovie && engine.supportsSeriesSearch) ? season : null,
      episode: (!isMovie && engine.supportsSeriesSearch) ? episode : null,
      maxResults: maxResults,
      availableSeasons: (!isMovie && engine.supportsSeriesSearch)
          ? availableSeasons
          : null,
    );
  }

  /// Deduplicate torrent results by infohash and sort by seeders descending.
  /// Public form of the search-result merge (dedupe by infohash keeping the
  /// higher-seeded copy, sort seeders-desc) so streaming consumers can build
  /// PROVISIONAL result sets from accumulated [SearchBatchCallback] batches
  /// that match the awaited search's final merge exactly.
  static List<Torrent> mergeSearchResults(List<List<Torrent>> batches) =>
      _deduplicateAndSort(batches);

  /// Total order used for dedupe tie-breaks and sort tie-breaks, so the merge
  /// is deterministic and INDEPENDENT of batch arrival order — a streaming
  /// provisional merge and the awaited (nested) final merge can never pick
  /// different representatives or row orders for the same inputs.
  static int _mergeTieBreak(Torrent a, Torrent b) {
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    return a.source.compareTo(b.source);
  }

  static List<Torrent> _deduplicateAndSort(List<List<Torrent>> allResults) {
    final Map<String, Torrent> uniqueTorrents = {};

    for (final torrentList in allResults) {
      for (final torrent in torrentList) {
        // Keep the higher-seeded copy of a shared infohash; on equal seeders
        // pick deterministically (NOT first-seen — that would depend on which
        // engine happened to answer first).
        final existing = uniqueTorrents[torrent.infohash];
        if (existing == null ||
            torrent.seeders > existing.seeders ||
            (torrent.seeders == existing.seeders &&
                _mergeTieBreak(torrent, existing) < 0)) {
          uniqueTorrents[torrent.infohash] = torrent;
        }
      }
    }

    // Sort by seeders descending with a total-order tiebreak, so equal-seeder
    // runs (e.g. addon direct streams, all seeders == 0) can't reorder
    // arbitrarily between two merges of the same inputs.
    final deduplicatedResults = uniqueTorrents.values.toList();
    deduplicatedResults.sort((a, b) {
      final s = b.seeders.compareTo(a.seeders);
      if (s != 0) return s;
      final h = a.infohash.compareTo(b.infohash);
      if (h != 0) return h;
      return _mergeTieBreak(a, b);
    });

    debugPrint(
      'TorrentService: Deduplicated to ${deduplicatedResults.length} unique torrents',
    );

    return deduplicatedResults;
  }
}
