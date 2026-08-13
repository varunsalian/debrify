import 'package:flutter/foundation.dart';

import '../../models/engine_config/engine_config.dart';
import '../../models/torrent.dart';
import '../../models/profiles/profile_policy.dart';
import '../profiles/profile_async_authorization.dart';
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
  Future<List<Torrent>> search(String query) =>
      _guardSearch(() => _search(query));

  Future<List<Torrent>> _search(String query) async {
    if (!supportsKeywordSearch) {
      debugPrint('DynamicEngine: Keyword search not supported');
      return [];
    }

    if (query.trim().isEmpty) {
      debugPrint('DynamicEngine: Empty query');
      return [];
    }

    try {
      return await _executor.execute(
        config: config,
        params: {'query': query.trim()},
        betweenPageRequests: _defaultPageDelay,
      );
    } catch (_) {
      debugPrint('DynamicEngine: Search failed');
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
  Future<List<Torrent>> searchByImdb(String imdbId) =>
      _guardSearch(() => _searchByImdb(imdbId));

  Future<List<Torrent>> _searchByImdb(String imdbId) async {
    if (!supportsImdbSearch) {
      debugPrint('DynamicEngine: IMDB search not supported');
      return [];
    }

    if (imdbId.trim().isEmpty) {
      debugPrint('DynamicEngine: Empty IMDB ID');
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
    } catch (_) {
      debugPrint('DynamicEngine: IMDB search failed');
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
  ) => _guardSearch(() => _searchSeries(imdbId, season, episode));

  Future<List<Torrent>> _searchSeries(
    String imdbId,
    int? season,
    int? episode,
  ) async {
    if (!supportsSeriesSearch) {
      debugPrint('DynamicEngine: Series search not supported');
      return [];
    }

    if (imdbId.trim().isEmpty) {
      debugPrint('DynamicEngine: Empty IMDB ID for series');
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
    } catch (_) {
      debugPrint('DynamicEngine: Series search failed');
      return [];
    }
  }

  /// Direct series search with specific season.
  Future<List<Torrent>> _searchSeriesDirect(
    String imdbId,
    int season,
    int? episode,
  ) async {
    // Get default episode from series config, fallback to 1
    final int defaultEpisode = config.request.seriesConfig?.defaultEpisode ?? 1;

    return await _executor.execute(
      config: config,
      params: {
        'imdbId': imdbId,
        'season': season,
        'episode': episode ?? defaultEpisode,
      },
      betweenPageRequests: _defaultPageDelay,
    );
  }

  /// Probe multiple seasons to find all available content.
  ///
  /// This is useful for engines where season must be specified.
  ///
  /// If [availableSeasons] is provided (from IMDbbot API), uses those seasons
  /// (capped at 10). Otherwise falls back to probing 1 to maxSeasonProbes.
  ///
  /// Probes all seasons IN PARALLEL for faster results.
  Future<List<Torrent>> _probeSeasons(
    String imdbId,
    SeriesConfig seriesConfig,
    int? episode, {
    List<int>? availableSeasons,
  }) async {
    final int defaultEpisode = seriesConfig.defaultEpisode;
    const int maxSeasonsToProbeCap =
        10; // Cap at 10 seasons like StremioService

    // Use available seasons if provided and non-empty, otherwise fallback to 1..maxProbes
    final bool hasSeasonData =
        availableSeasons != null && availableSeasons.isNotEmpty;
    List<int> seasonsToProbe = hasSeasonData
        ? availableSeasons
        : List.generate(seriesConfig.maxSeasonProbes, (i) => i + 1);

    // Cap at 10 seasons to avoid excessive requests
    if (seasonsToProbe.length > maxSeasonsToProbeCap) {
      debugPrint('DynamicEngine: Capping season probes');
      seasonsToProbe = seasonsToProbe.take(maxSeasonsToProbeCap).toList();
    }

    debugPrint('DynamicEngine: Probing seasons in parallel');

    // Probe all seasons in parallel for faster results
    final List<Future<List<Torrent>>> futures = seasonsToProbe.map((
      seasonNum,
    ) async {
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

        debugPrint('DynamicEngine: Season probe completed');
        return seasonResults;
      } catch (_) {
        debugPrint('DynamicEngine: Season probe failed');
        return <Torrent>[];
      }
    }).toList();

    // Wait for all parallel requests to complete
    final List<List<Torrent>> results = await Future.wait(futures);

    // Flatten results
    final List<Torrent> allResults = results.expand((list) => list).toList();
    debugPrint('DynamicEngine: Parallel probe completed');

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
  /// - [availableSeasons]: Known seasons from IMDbbot API for optimized probing
  Future<List<Torrent>> executeSearch({
    String? query,
    String? imdbId,
    bool? isSeries,
    int? season,
    int? episode,
    int? maxResults,
    Duration? betweenPageRequests,
    List<int>? availableSeasons,
  }) => _guardSearch(
    () => _executeSearch(
      query: query,
      imdbId: imdbId,
      isSeries: isSeries,
      season: season,
      episode: episode,
      maxResults: maxResults,
      betweenPageRequests: betweenPageRequests,
      availableSeasons: availableSeasons,
    ),
  );

  Future<List<Torrent>> _executeSearch({
    String? query,
    String? imdbId,
    bool? isSeries,
    int? season,
    int? episode,
    int? maxResults,
    Duration? betweenPageRequests,
    List<int>? availableSeasons,
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
      debugPrint('DynamicEngine: Using season probing for series search');
      return await _probeSeasons(
        normalizedImdbId,
        config.request.seriesConfig!,
        episode,
        availableSeasons: availableSeasons,
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
    // For series searches with season, ensure episode is set when required.
    if (episode != null) {
      params['episode'] = episode;
    } else if (isSeries == true && season != null) {
      // Use default episode from series config, or fallback to 1
      final int defaultEpisode =
          config.request.seriesConfig?.defaultEpisode ?? 1;
      params['episode'] = defaultEpisode;
    }

    if (params.isEmpty) {
      debugPrint('DynamicEngine: No search parameters provided');
      return [];
    }

    try {
      return await _executor.execute(
        config: config,
        params: params,
        maxResults: maxResults,
        betweenPageRequests: betweenPageRequests ?? _defaultPageDelay,
      );
    } catch (_) {
      debugPrint('DynamicEngine: Execute search failed');
      return [];
    }
  }

  Future<List<Torrent>> _guardSearch(
    Future<List<Torrent>> Function() operation,
  ) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.torrentSearch,
    );
    final results = capability == null
        ? await operation()
        : await capability.runIfCurrent(operation);
    if (capability != null) {
      await capability.runIfCurrent(() async {});
    }
    return results;
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
