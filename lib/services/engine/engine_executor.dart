import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/engine_config/engine_config.dart';
import '../../models/torrent.dart';
import 'response_parser.dart';
import 'field_mapper.dart';
import 'pagination_handler.dart';

/// Low-level executor that handles HTTP requests and response processing
/// based on YAML configuration.
class EngineExecutor {
  final ResponseParser _responseParser = const ResponseParser();
  final FieldMapper _fieldMapper = const FieldMapper();

  /// Execute a search and return torrents.
  ///
  /// [config] - The engine configuration
  /// [params] - Search parameters (query, imdbId, season, episode)
  /// [maxResults] - Maximum number of results to return
  /// [betweenPageRequests] - Delay between paginated requests
  Future<List<Torrent>> execute({
    required EngineConfig config,
    required Map<String, dynamic> params,
    int? maxResults,
    Duration? betweenPageRequests,
  }) async {
    final List<Torrent> allResults = [];

    try {
      // Initialize pagination handler with config directly
      final PaginationHandler paginationHandler =
          PaginationHandler(config.pagination);

      // Determine search type for response parsing
      final String searchType = _determineSearchType(params);

      // Get effective max results
      final int? effectiveMaxResults =
          paginationHandler.getMaxResults(maxResults);

      // Pagination loop
      bool shouldContinue = true;
      int pageNumber = 0;

      while (shouldContinue) {
        pageNumber++;

        // Get pagination params for this request
        final Map<String, String> paginationParams =
            paginationHandler.getPaginationParams();

        // Build the URL
        final String url =
            buildUrl(config.request, params, paginationParams);

        debugPrint('EngineExecutor: Fetching page $pageNumber from: $url');

        try {
          // Make the HTTP request
          final http.Response response =
              await makeRequest(url, config.request);

          if (response.statusCode != 200) {
            debugPrint(
                'EngineExecutor: HTTP ${response.statusCode} for $url');
            debugPrint(
                'EngineExecutor: Response body preview: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
            // Continue to next page on failure, but may break if critical
            if (pageNumber == 1) {
              // First page failed, return empty
              return [];
            }
            break;
          }

          // Parse and unwrap response (handles Jina wrapping)
          dynamic responseJson;
          dynamic unwrappedJson;
          try {
            responseJson = json.decode(response.body);
            // Unwrap Jina response if needed - extract inner JSON from data.content
            unwrappedJson = _unwrapJinaIfNeeded(responseJson, config.response.format);
          } catch (e) {
            debugPrint('EngineExecutor: Error parsing response JSON: $e');
            responseJson = null;
            unwrappedJson = null;
          }

          // Parse response to get raw results (pass unwrapped JSON)
          final List<Map<String, dynamic>> rawResults = _responseParser.parseJson(
            unwrappedJson,
            config.response,
            searchType: searchType,
          );

          if (rawResults.isEmpty) {
            debugPrint('EngineExecutor: No results on page $pageNumber');
            break;
          }

          // Map raw results to Torrent objects
          final List<Torrent> pageTorrents = [];
          for (final rawResult in rawResults) {
            try {
              final Torrent torrent = _fieldMapper.mapToTorrent(
                rawResult,
                config.response,
                config.metadata.id,
                searchType: searchType,
              );
              // Only add if infohash is valid
              if (torrent.infohash.isNotEmpty) {
                pageTorrents.add(torrent);
              }
            } catch (e) {
              debugPrint('EngineExecutor: Error mapping torrent: $e');
              // Continue with other results
            }
          }

          allResults.addAll(pageTorrents);
          debugPrint(
              'EngineExecutor: Got ${pageTorrents.length} torrents from page $pageNumber (total: ${allResults.length})');

          // Update pagination state with UNWRAPPED JSON (so pagination fields can be found)
          paginationHandler.updateFromResponse(unwrappedJson, rawResults.length);

          // Check if we should continue
          shouldContinue = paginationHandler.shouldFetchMore(effectiveMaxResults);

          // Check if we've reached max results
          if (effectiveMaxResults != null &&
              allResults.length >= effectiveMaxResults) {
            debugPrint(
                'EngineExecutor: Reached max results ($effectiveMaxResults)');
            shouldContinue = false;
          }

          // Add delay between page requests if configured
          if (shouldContinue && betweenPageRequests != null) {
            await Future.delayed(betweenPageRequests);
          }
        } catch (e) {
          debugPrint('EngineExecutor: Error fetching page $pageNumber: $e');
          // Return partial results on error
          if (allResults.isNotEmpty) {
            break;
          }
          rethrow;
        }
      }

      // Trim to max results if needed
      if (effectiveMaxResults != null &&
          allResults.length > effectiveMaxResults) {
        return allResults.sublist(0, effectiveMaxResults);
      }

      return allResults;
    } catch (e) {
      debugPrint('EngineExecutor: Execute error: $e');
      // Return partial results or empty list
      return allResults.isNotEmpty ? allResults : [];
    }
  }

  /// Build URL from config and params.
  ///
  /// [config] - Request configuration
  /// [params] - Search parameters
  /// [paginationParams] - Pagination parameters
  String buildUrl(
    RequestConfig config,
    Map<String, dynamic> params,
    Map<String, String> paginationParams,
  ) {
    // Get the base URL for this request type
    String baseUrl = getBaseUrl(config, params);

    // Replace path parameters
    baseUrl = replacePathParams(baseUrl, params);

    // Build query parameters based on url_builder type
    if (config.urlBuilder.type == 'query_params') {
      final Map<String, String> queryParams =
          buildQueryParams(config, params);

      // Add pagination params
      queryParams.addAll(paginationParams);

      // Build URL with query string
      if (queryParams.isNotEmpty) {
        final Uri uri = Uri.parse(baseUrl);
        final Uri finalUri = uri.replace(
          queryParameters: {
            ...uri.queryParameters,
            ...queryParams,
          },
        );
        return finalUri.toString();
      }
    } else if (config.urlBuilder.type == 'path') {
      // For path-based URLs, append query to the path
      final String? query = params['query'] as String?;
      if (query != null && query.isNotEmpty) {
        final String encodedQuery = config.urlBuilder.encode
            ? Uri.encodeComponent(query)
            : query;
        // Append to path
        if (!baseUrl.endsWith('/')) {
          baseUrl += '/';
        }
        baseUrl += encodedQuery;
      }

      // Add pagination as query params even for path-based URLs
      if (paginationParams.isNotEmpty) {
        final Uri uri = Uri.parse(baseUrl);
        final Uri finalUri = uri.replace(
          queryParameters: {
            ...uri.queryParameters,
            ...paginationParams,
          },
        );
        return finalUri.toString();
      }
    }

    return baseUrl;
  }

  /// Determine which base URL to use based on params.
  ///
  /// Priority:
  /// 1. Series URL (if season/episode provided and series URL exists)
  /// 2. IMDB URL (if imdbId provided and imdb URL exists)
  /// 3. Keyword URL (if query provided and keyword URL exists)
  /// 4. Default base URL
  String getBaseUrl(RequestConfig config, Map<String, dynamic> params) {
    final String? imdbId = params['imdbId'] as String?;
    final int? season = params['season'] as int?;
    final int? episode = params['episode'] as int?;
    final String? query = params['query'] as String?;

    final Map<String, String>? urls = config.urls;

    // Check for series URL
    if (urls != null &&
        imdbId != null &&
        imdbId.isNotEmpty &&
        (season != null || episode != null)) {
      if (urls.containsKey('series') && urls['series']!.isNotEmpty) {
        return urls['series']!;
      }
      // Fall through to imdb URL
    }

    // Check for IMDB URL
    if (urls != null && imdbId != null && imdbId.isNotEmpty) {
      if (urls.containsKey('imdb') && urls['imdb']!.isNotEmpty) {
        return urls['imdb']!;
      }
    }

    // Check for keyword URL
    if (urls != null && query != null && query.isNotEmpty) {
      if (urls.containsKey('keyword') && urls['keyword']!.isNotEmpty) {
        return urls['keyword']!;
      }
    }

    // Default to base URL
    return config.baseUrl ?? '';
  }

  /// Build query parameters from config and params.
  Map<String, String> buildQueryParams(
    RequestConfig config,
    Map<String, dynamic> params,
  ) {
    final Map<String, String> queryParams = {};

    // Determine request type for applies_to filtering
    final String requestType = _determineSearchType(params);

    // Process each configured parameter
    for (final RequestParam param in config.params) {
      // Check if this param applies to current request type
      if (param.appliesTo != null && param.appliesTo != requestType) {
        continue;
      }

      String? value;

      if (param.value != null) {
        // Static value
        value = param.value;
      } else if (param.source != null) {
        // Dynamic value from params
        final dynamic sourceValue = params[param.source];
        if (sourceValue != null) {
          value = sourceValue.toString();
        }
      }

      // Add to query params if we have a value or it's required
      if (value != null && value.isNotEmpty) {
        // Don't manually encode - Uri.replace() handles encoding automatically
        // Manual encoding would cause double-encoding (%20 -> %2520)
        queryParams[param.name] = value;
      } else if (param.required) {
        debugPrint(
            'EngineExecutor: Required param "${param.name}" has no value');
      }
    }

    // Handle the main query param from url_builder
    // Use getQueryParamForType to support per-search-type param names
    final String? queryParamName = config.urlBuilder.getQueryParamForType(requestType);
    if (queryParamName != null) {
      final String? query = params['query'] as String?;
      final String? imdbId = params['imdbId'] as String?;

      // Determine which value to use based on request type
      String? valueToUse;
      if (requestType == 'imdb' || requestType == 'series') {
        valueToUse = imdbId;
      } else {
        valueToUse = query;
      }

      if (valueToUse != null && valueToUse.isNotEmpty) {
        // Don't encode here - Uri.replace() will encode automatically
        // Manual encoding would cause double-encoding (%20 -> %2520)
        queryParams[queryParamName] = valueToUse;
      }
    }

    return queryParams;
  }

  /// Replace path parameters like {imdb_id}, {season}, {episode}.
  String replacePathParams(String url, Map<String, dynamic> params) {
    String result = url;

    // Standard path parameter mappings
    final Map<String, String> paramMappings = {
      'imdb_id': 'imdbId',
      'imdbId': 'imdbId',
      'query': 'query',
      'season': 'season',
      'episode': 'episode',
      's': 'season',
      'e': 'episode',
    };

    // Replace all {param} patterns
    final RegExp paramPattern = RegExp(r'\{([^}]+)\}');
    result = result.replaceAllMapped(paramPattern, (match) {
      final String paramName = match.group(1)!;
      final String mappedParam = paramMappings[paramName] ?? paramName;
      final dynamic value = params[mappedParam];

      if (value != null) {
        return value.toString();
      }

      debugPrint(
          'EngineExecutor: Path param "$paramName" not found in params');
      return match.group(0)!; // Keep original if not found
    });

    return result;
  }

  /// Make HTTP request.
  Future<http.Response> makeRequest(String url, RequestConfig config) async {
    final Duration timeout = Duration(
      seconds: config.timeoutSeconds ?? 30,
    );

    try {
      final Uri uri = Uri.parse(url);

      if (config.method.toUpperCase() == 'GET') {
        return await http.get(
          uri,
          headers: _getDefaultHeaders(),
        ).timeout(timeout);
      } else if (config.method.toUpperCase() == 'POST') {
        return await http.post(
          uri,
          headers: _getDefaultHeaders(),
        ).timeout(timeout);
      } else {
        throw UnsupportedError('Unsupported HTTP method: ${config.method}');
      }
    } catch (e) {
      debugPrint('EngineExecutor: HTTP request error: $e');
      rethrow;
    }
  }

  /// Get default HTTP headers.
  Map<String, String> _getDefaultHeaders() {
    return {
      'Accept': 'application/json',
      'User-Agent': 'Debrify/1.0',
    };
  }

  /// Determine search type based on params.
  String _determineSearchType(Map<String, dynamic> params) {
    final String? imdbId = params['imdbId'] as String?;
    final int? season = params['season'] as int?;
    final int? episode = params['episode'] as int?;

    if (imdbId != null && imdbId.isNotEmpty) {
      if (season != null || episode != null) {
        return 'series';
      }
      return 'imdb';
    }
    return 'keyword';
  }

  /// Unwrap Jina-wrapped response if needed.
  ///
  /// Jina.ai returns: {"code":200, "data": {"content": "{...actual JSON...}"}, ...}
  /// This extracts the actual JSON from data.content.
  ///
  /// Returns the unwrapped JSON, or the original if not Jina-wrapped.
  dynamic _unwrapJinaIfNeeded(dynamic responseJson, String format) {
    if (format != 'jina_wrapped') {
      return responseJson;
    }

    if (responseJson is! Map<String, dynamic>) {
      return responseJson;
    }

    try {
      final data = responseJson['data'];
      if (data is Map<String, dynamic> && data['content'] is String) {
        final contentStr = data['content'] as String;
        debugPrint('EngineExecutor: Unwrapping Jina response (content length: ${contentStr.length})');
        final unwrapped = json.decode(contentStr);
        return unwrapped;
      }
    } catch (e) {
      debugPrint('EngineExecutor: Error unwrapping Jina response: $e');
    }

    // Fallback to original if unwrapping fails
    return responseJson;
  }
}
