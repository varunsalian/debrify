import 'package:debrify/models/engine_config/engine_config.dart';

/// Manages pagination state and logic for different pagination types.
///
/// Supports four pagination types:
/// - **none**: Single request, no pagination
/// - **cursor**: Cursor-based pagination (e.g., Torrents CSV)
/// - **page**: Page number based pagination (e.g., SolidTorrents)
/// - **offset**: Offset based pagination
class PaginationHandler {
  final PaginationConfig config;

  // Current state
  int _currentPage = 0;
  String? _currentCursor;
  int _totalResultsFetched = 0;
  bool _hasMore = true;

  PaginationHandler(this.config) {
    _initializeState();
  }

  /// Initialize state based on pagination type
  void _initializeState() {
    _currentPage = _startPage;
    _currentCursor = null;
    _totalResultsFetched = 0;
    _hasMore = _paginationType != 'none';
  }

  /// Get the normalized pagination type
  String get _paginationType {
    final type = config.type.toLowerCase();
    if (['cursor', 'page', 'offset', 'none'].contains(type)) {
      return type;
    }
    // Default to 'none' for unknown types
    return 'none';
  }

  /// Get the starting page number
  int get _startPage {
    return config.page?.startPage ?? 1;
  }

  /// Reset pagination state for a new search
  void reset() {
    _currentPage = _startPage;
    _currentCursor = null;
    _totalResultsFetched = 0;
    _hasMore = _paginationType != 'none';
  }

  /// Check if more pages should be fetched
  bool get hasMorePages {
    if (_paginationType == 'none') {
      return false;
    }
    return _hasMore;
  }

  /// Check if pagination is supported
  bool get supportsPagination {
    return _paginationType != 'none';
  }

  /// Get current page number (1-indexed for API by default)
  int get currentPageNumber => _currentPage;

  /// Get the current cursor value (for cursor-based pagination)
  String? get currentCursor => _currentCursor;

  /// Get total results fetched so far
  int get totalResultsFetched => _totalResultsFetched;

  /// Get max results limit based on settings.
  ///
  /// Priority:
  /// 1. Settings max results (user preference)
  /// 2. Config fixed results (for engines with no pagination)
  /// 3. Calculate from maxPages * resultsPerPage
  /// 4. Return null (no limit)
  int? getMaxResults(int? settingsMaxResults) {
    // User settings take priority
    if (settingsMaxResults != null && settingsMaxResults > 0) {
      return settingsMaxResults;
    }

    // For 'none' type, use fixed results
    if (_paginationType == 'none' && config.fixedResults != null) {
      return config.fixedResults;
    }

    // Calculate from maxPages and resultsPerPage
    if (config.maxPages != null && config.resultsPerPage != null) {
      return config.maxPages! * config.resultsPerPage!;
    }

    return null;
  }

  /// Build pagination params for URL
  Map<String, String> getPaginationParams() {
    switch (_paginationType) {
      case 'none':
        return {};

      case 'cursor':
        return _getCursorParams();

      case 'page':
        return _getPageParams();

      case 'offset':
        return _getOffsetParams();

      default:
        return {};
    }
  }

  /// Get cursor-based pagination parameters
  Map<String, String> _getCursorParams() {
    final cursorConfig = config.cursor;
    if (cursorConfig == null) {
      return {};
    }

    // Only add cursor param if we have a cursor value
    if (_currentCursor != null && _currentCursor!.isNotEmpty) {
      return {cursorConfig.paramName: _currentCursor!};
    }

    return {};
  }

  /// Get page-based pagination parameters
  Map<String, String> _getPageParams() {
    final pageConfig = config.page;
    if (pageConfig == null) {
      return {};
    }

    return {pageConfig.paramName: _currentPage.toString()};
  }

  /// Get offset-based pagination parameters
  Map<String, String> _getOffsetParams() {
    final resultsPerPage = config.resultsPerPage ?? 20;
    final offset = (_currentPage - _startPage) * resultsPerPage;

    return {'offset': offset.toString()};
  }

  /// Update state after receiving response.
  ///
  /// [responseData] - The raw response data from the API
  /// [resultsCount] - Number of results received in this response
  void updateFromResponse(dynamic responseData, int resultsCount) {
    _totalResultsFetched += resultsCount;

    switch (_paginationType) {
      case 'none':
        _hasMore = false;
        break;

      case 'cursor':
        _updateCursorState(responseData);
        break;

      case 'page':
        _updatePageState(responseData, resultsCount);
        break;

      case 'offset':
        _updateOffsetState(resultsCount);
        break;
    }
  }

  /// Update state for cursor-based pagination
  void _updateCursorState(dynamic responseData) {
    _currentCursor = extractCursor(responseData);
    _hasMore = _currentCursor != null && _currentCursor!.isNotEmpty;

    // Also check maxPages if configured
    if (_hasMore && config.maxPages != null) {
      _currentPage++;
      _hasMore = _currentPage <= config.maxPages!;
    }
  }

  /// Update state for page-based pagination
  void _updatePageState(dynamic responseData, int resultsCount) {
    _currentPage++;

    // Check hasMoreField in response if configured
    final hasMoreFromResponse = checkHasMore(responseData);

    // Check if we've hit maxPages
    final withinMaxPages =
        config.maxPages == null || _currentPage <= config.maxPages!;

    // Check if we got results (if no results, likely no more pages)
    final gotResults = resultsCount > 0;

    _hasMore = hasMoreFromResponse && withinMaxPages && gotResults;
  }

  /// Update state for offset-based pagination
  void _updateOffsetState(int resultsCount) {
    _currentPage++;

    // For offset-based, hasMore = results == resultsPerPage
    final resultsPerPage = config.resultsPerPage ?? 20;
    final fullPage = resultsCount >= resultsPerPage;

    // Check maxPages limit
    final withinMaxPages =
        config.maxPages == null || _currentPage <= config.maxPages!;

    _hasMore = fullPage && withinMaxPages;
  }

  /// Extract cursor from response for cursor-based pagination.
  ///
  /// Handles nested fields using dot notation (e.g., "data.next_cursor")
  String? extractCursor(dynamic responseData) {
    if (responseData == null) {
      return null;
    }

    final cursorConfig = config.cursor;
    if (cursorConfig == null || cursorConfig.responseField.isEmpty) {
      return null;
    }

    try {
      return _extractNestedValue(responseData, cursorConfig.responseField);
    } catch (_) {
      // Don't crash on missing response fields
      return null;
    }
  }

  /// Check hasNext field for page-based pagination.
  ///
  /// Returns true if:
  /// - No hasMoreField is configured (assume more pages exist)
  /// - The hasMoreField exists and is truthy
  bool checkHasMore(dynamic responseData) {
    final pageConfig = config.page;
    if (pageConfig == null || pageConfig.hasMoreField == null) {
      // If no hasMoreField configured, assume more pages exist
      return true;
    }

    if (responseData == null) {
      return false;
    }

    try {
      final value =
          _extractNestedValue(responseData, pageConfig.hasMoreField!);
      return _isTruthy(value);
    } catch (_) {
      // Don't crash on missing response fields
      return false;
    }
  }

  /// Extract a nested value from response data using dot notation.
  ///
  /// Example: "data.pagination.next" extracts responseData['data']['pagination']['next']
  String? _extractNestedValue(dynamic data, String fieldPath) {
    if (data == null || fieldPath.isEmpty) {
      return null;
    }

    final parts = fieldPath.split('.');
    dynamic current = data;

    for (final part in parts) {
      if (current is Map) {
        current = current[part];
      } else if (current is List && int.tryParse(part) != null) {
        final index = int.parse(part);
        if (index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }

      if (current == null) {
        return null;
      }
    }

    return current?.toString();
  }

  /// Check if a value is truthy
  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value > 0;
    if (value is String) {
      final lower = value.toLowerCase();
      return lower == 'true' || lower == '1' || lower == 'yes';
    }
    return true;
  }

  /// Calculate if we should fetch more based on max results.
  ///
  /// Returns true if:
  /// - hasMorePages is true
  /// - totalResultsFetched < maxResults (if maxResults is set)
  /// - currentPage < maxPages (if maxPages is set)
  bool shouldFetchMore(int? maxResults) {
    // Check if there are more pages available
    if (!hasMorePages) {
      return false;
    }

    // Check if we've hit the max results limit
    if (maxResults != null && _totalResultsFetched >= maxResults) {
      return false;
    }

    // Check if we've hit the max pages limit
    if (config.maxPages != null && _currentPage > config.maxPages!) {
      return false;
    }

    return true;
  }

  /// Get the number of results still needed to reach maxResults.
  ///
  /// Returns null if no limit is set.
  int? getRemainingResultsNeeded(int? maxResults) {
    if (maxResults == null) {
      return null;
    }

    final remaining = maxResults - _totalResultsFetched;
    return remaining > 0 ? remaining : 0;
  }

  /// Check if we're on the first page (no pagination params needed yet)
  bool get isFirstPage {
    if (_paginationType == 'cursor') {
      return _currentCursor == null;
    }
    return _currentPage == _startPage;
  }

  @override
  String toString() {
    return 'PaginationHandler('
        'type: $_paginationType, '
        'page: $_currentPage, '
        'cursor: $_currentCursor, '
        'fetched: $_totalResultsFetched, '
        'hasMore: $_hasMore)';
  }
}

/// Factory for creating pagination handlers
class PaginationHandlerFactory {
  /// Create a pagination handler from a config
  static PaginationHandler create(PaginationConfig config) {
    return PaginationHandler(config);
  }

  /// Create a pagination handler with default "none" config
  static PaginationHandler createDefault() {
    return PaginationHandler(const PaginationConfig(type: 'none'));
  }

  /// Create a pagination handler from a config map
  static PaginationHandler fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return createDefault();
    }
    return PaginationHandler(PaginationConfig.fromMap(map));
  }
}
