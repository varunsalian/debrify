import 'package:flutter/foundation.dart';

import '../../models/engine_config/engine_config.dart';
import '../../models/torrent.dart';
import '../search_engine.dart';
import 'engine_executor.dart';

/// High-level engine that implements SearchEngine interface using YAML configuration.
///
/// DynamicEngine wraps an EngineConfig and provides a standard SearchEngine
/// interface for executing searches against various torrent sources.
class DynamicEngine extends SearchEngine {
  /// The engine configuration loaded from YAML
  final EngineConfig config;

  /// The low-level executor for HTTP requests
  final EngineExecutor _executor = EngineExecutor();

  /// Default delay between paginated requests
  static const Duration _defaultPageDelay = Duration(milliseconds: 200);

  /// Create a DynamicEngine from an EngineConfig.
  DynamicEngine(this.config)
      : super(
          name: config.metadata.id,
          displayName: config.metadata.displayName,
          baseUrl: config.request.baseUrl ?? '',
        );

  // ============================================================
  // SearchEngine Interface Implementation
  // ============================================================

  /// Standard keyword search.
  @override
  Future<List<Torrent>> search(String query) async {
    if (!supportsKeywordSearch) {
      debugPrint(
          'DynamicEngine[$name]: Keyword search not supported');
      return [];
    }

    if (query.trim().isEmpty) {
      debugPrint('DynamicEngine[$name]: Empty query');
      return [];
    }

    try {
      return await _executor.execute(
        config: config,
        params: {'query': query.trim()},
        betweenPageRequests: _defaultPageDelay,
      );
    } catch (e) {
      debugPrint('DynamicEngine[$name]: Search error: $e');
      return [];
    }
  }

  /// Get the search URL for a query (for external browser opening).
  @override
  String getSearchUrl(String query) {
    final String encodedQuery = Uri.encodeComponent(query);

    // Try to get keyword URL from urls map
    final String? keywordUrl = config.request.urls?['keyword'];
    if (keywordUrl != null && keywordUrl.isNotEmpty) {
      // Replace {query} placeholder if present
      if (keywordUrl.contains('{query}')) {
        return keywordUrl.replaceAll('{query}', encodedQuery);
      }
      // Otherwise use query param from url_builder
      final String? queryParam = config.request.urlBuilder.queryParam;
      if (queryParam != null) {
        return '$keywordUrl?$queryParam=$encodedQuery';
      }
      return keywordUrl;
    }

    // Fall back to base URL
    final String base = config.request.baseUrl ?? '';
    final String? queryParam = config.request.urlBuilder.queryParam;
    if (queryParam != null) {
      return '$base?$queryParam=$encodedQuery';
    }
    return base;
  }

  // ============================================================
  // Extended Search Methods
  // ============================================================

  /// Search by IMDB ID.
  ///
  /// Returns empty list if IMDB search is not supported.
  Future<List<Torrent>> searchByImdb(String imdbId) async {
    if (!supportsImdbSearch) {
      debugPrint(
          'DynamicEngine[$name]: IMDB search not supported');
      return [];
    }

    if (imdbId.trim().isEmpty) {
      debugPrint('DynamicEngine[$name]: Empty IMDB ID');
      return [];
    }

    // Normalize IMDB ID (ensure it starts with 'tt')
    String normalizedId = imdbId.trim();
    if (!normalizedId.startsWith('tt')) {
      normalizedId = 'tt$normalizedId';
    }

    try {
      return await _executor.execute(
        config: config,
        params: {'imdbId': normalizedId},
        betweenPageRequests: _defaultPageDelay,
      );
    } catch (e) {
      debugPrint('DynamicEngine[$name]: IMDB search error: $e');
      return [];
    }
  }

  /// Search for series with season and episode.
  ///
  /// If season is not specified and series probing is configured,
  /// this will probe multiple seasons to find all available content.
  ///
  /// Returns empty list if series search is not supported.
  Future<List<Torrent>> searchSeries(
    String imdbId,
    int? season,
    int? episode,
  ) async {
    if (!supportsSeriesSearch) {
      debugPrint(
          'DynamicEngine[$name]: Series search not supported');
      return [];
    }

    if (imdbId.trim().isEmpty) {
      debugPrint('DynamicEngine[$name]: Empty IMDB ID for series');
      return [];
    }

    // Normalize IMDB ID
    String normalizedId = imdbId.trim();
    if (!normalizedId.startsWith('tt')) {
      normalizedId = 'tt$normalizedId';
    }

    try {
      // If season is specified, do a direct search
      if (season != null) {
        return await _searchSeriesDirect(normalizedId, season, episode);
      }

      // If no season specified, check if we should probe multiple seasons
      final SeriesConfig? seriesConfig = config.request.seriesConfig;
      if (seriesConfig != null && seriesConfig.maxSeasonProbes > 0) {
        return await _probeSeasons(normalizedId, seriesConfig, episode);
      }

      // No season probing configured, search without season
      return await _executor.execute(
        config: config,
        params: {
          'imdbId': normalizedId,
          if (episode != null) 'episode': episode,
        },
        betweenPageRequests: _defaultPageDelay,
      );
    } catch (e) {
      debugPrint('DynamicEngine[$name]: Series search error: $e');
      return [];
    }
  }

  /// Direct series search with specific season.
  Future<List<Torrent>> _searchSeriesDirect(
    String imdbId,
    int season,
    int? episode,
  ) async {
    return await _executor.execute(
      config: config,
      params: {
        'imdbId': imdbId,
        'season': season,
        if (episode != null) 'episode': episode,
      },
      betweenPageRequests: _defaultPageDelay,
    );
  }

  /// Probe multiple seasons to find all available content.
  ///
  /// This is useful for engines like Torrentio where season must be specified.
  /// The probing stops when a season returns 0 results.
  Future<List<Torrent>> _probeSeasons(
    String imdbId,
    SeriesConfig seriesConfig,
    int? episode,
  ) async {
    final List<Torrent> allResults = [];
    final int maxProbes = seriesConfig.maxSeasonProbes;
    final int defaultEpisode = seriesConfig.defaultEpisode;

    debugPrint(
        'DynamicEngine[$name]: Probing up to $maxProbes seasons');

    for (int seasonNum = 1; seasonNum <= maxProbes; seasonNum++) {
      try {
        final List<Torrent> seasonResults = await _executor.execute(
          config: config,
          params: {
            'imdbId': imdbId,
            'isSeries': true,
            'season': seasonNum,
            // Use provided episode or default to first episode
            'episode': episode ?? defaultEpisode,
          },
          betweenPageRequests: _defaultPageDelay,
        );

        if (seasonResults.isEmpty) {
          debugPrint(
              'DynamicEngine[$name]: Season $seasonNum returned 0 results, stopping probe');
          break;
        }

        debugPrint(
            'DynamicEngine[$name]: Season $seasonNum returned ${seasonResults.length} results');
        allResults.addAll(seasonResults);

        // Add a small delay between season probes
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint(
            'DynamicEngine[$name]: Error probing season $seasonNum: $e');
        // Continue to next season on error
      }
    }

    return allResults;
  }

  // ============================================================
  // Capabilities
  // ============================================================

  /// Check if keyword search is supported.
  bool get supportsKeywordSearch => config.metadata.capabilities.keywordSearch;

  /// Check if IMDB search is supported.
  bool get supportsImdbSearch => config.metadata.capabilities.imdbSearch;

  /// Check if series search is supported.
  bool get supportsSeriesSearch => config.metadata.capabilities.seriesSupport;

  // ============================================================
  // Display Information
  // ============================================================

  /// Get the engine icon identifier.
  String get icon => config.metadata.icon;

  /// Get the engine description.
  String? get description => config.metadata.description;

  /// Get the engine categories.
  List<String> get categories => config.metadata.categories;

  // ============================================================
  // Configuration Access
  // ============================================================

  /// Get the settings configuration for UI rendering.
  SettingsConfig get settingsConfig => config.settings;

  /// Get the TV mode configuration.
  TvModeConfig? get tvModeConfig => config.tvMode;

  /// Get the request configuration.
  RequestConfig get requestConfig => config.request;

  /// Get the response configuration.
  ResponseConfig get responseConfig => config.response;

  /// Get the pagination configuration.
  PaginationConfig get paginationConfig => config.pagination;

  /// Get the engine capabilities.
  EngineCapabilities get capabilities => config.metadata.capabilities;

  // ============================================================
  // Advanced Search Methods
  // ============================================================

  /// Execute a search with custom parameters.
  ///
  /// This allows more control over the search, including:
  /// - Custom max results
  /// - Custom delay between requests
  /// - Season probing for series without specific season
  Future<List<Torrent>> executeSearch({
    String? query,
    String? imdbId,
    bool? isSeries,
    int? season,
    int? episode,
    int? maxResults,
    Duration? betweenPageRequests,
  }) async {
    // Normalize IMDB ID if provided
    String? normalizedImdbId;
    if (imdbId != null && imdbId.isNotEmpty) {
      normalizedImdbId = imdbId.trim();
      if (!normalizedImdbId.startsWith('tt')) {
        normalizedImdbId = 'tt$normalizedImdbId';
      }
    }

    // Check if this is a series search that needs season probing
    // Conditions: has IMDB, no season specified, IS a series, supports series, has series_config
    if (normalizedImdbId != null &&
        season == null &&
        isSeries == true &&
        supportsSeriesSearch &&
        config.request.seriesConfig != null) {
      debugPrint('DynamicEngine[$name]: Using season probing for series search');
      return await _probeSeasons(
        normalizedImdbId,
        config.request.seriesConfig!,
        episode,
      );
    }

    // Build params for direct executor call
    final Map<String, dynamic> params = {};

    if (query != null && query.isNotEmpty) {
      params['query'] = query.trim();
    }
    if (normalizedImdbId != null) {
      params['imdbId'] = normalizedImdbId;
    }
    if (isSeries != null) {
      params['isSeries'] = isSeries;
    }
    if (season != null) {
      params['season'] = season;
    }
    if (episode != null) {
      params['episode'] = episode;
    }

    if (params.isEmpty) {
      debugPrint('DynamicEngine[$name]: No search parameters provided');
      return [];
    }

    try {
      return await _executor.execute(
        config: config,
        params: params,
        maxResults: maxResults,
        betweenPageRequests: betweenPageRequests ?? _defaultPageDelay,
      );
    } catch (e) {
      debugPrint('DynamicEngine[$name]: Execute search error: $e');
      return [];
    }
  }

  // ============================================================
  // Utility Methods
  // ============================================================

  @override
  String toString() {
    return 'DynamicEngine('
        'name: $name, '
        'displayName: $displayName, '
        'keyword: $supportsKeywordSearch, '
        'imdb: $supportsImdbSearch, '
        'series: $supportsSeriesSearch)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DynamicEngine && other.name == name;
  }

  @override
  int get hashCode => name.hashCode;
}
