import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/movie_parser.dart';

/// Result of movie metadata lookup
class MovieMetadata {
  final String imdbId;
  final String title;
  final int? year;
  final String? poster;

  const MovieMetadata({
    required this.imdbId,
    required this.title,
    this.year,
    this.poster,
  });

  @override
  String toString() => 'MovieMetadata: $title ($year) - $imdbId';
}

/// Service for fetching movie metadata from Cinemeta
///
/// Uses the same caching pattern as TVMazeService:
/// - In-memory cache for fast access
/// - Persistent cache for cross-session storage
class MovieMetadataService {
  static const String _cinemetaBaseUrl = 'https://v3-cinemeta.strem.io';
  static const Duration _timeout = Duration(seconds: 15);
  static const int _maxRetries = 3;

  // In-memory cache (same pattern as TVMazeService)
  static final Map<String, MovieMetadata?> _cache = {};

  // Track availability
  static bool _isAvailable = true;
  static DateTime? _lastAvailabilityCheck;

  /// Look up movie metadata by title and year
  ///
  /// Returns MovieMetadata with IMDB ID if found, null otherwise.
  /// Uses caching to avoid repeated API calls.
  static Future<MovieMetadata?> lookupMovie(String title, int? year) async {
    if (title.isEmpty) return null;

    // Create cache key from title and year
    final cacheKey = _createCacheKey(title, year);

    // Check in-memory cache first
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached != null) {
        debugPrint('🎯 MovieMetadata: Cache HIT for "$title" ($year)');
      }
      return cached;
    }

    debugPrint('❌ MovieMetadata: Cache MISS for "$title" ($year), calling Cinemeta...');

    // Check availability (with 5 minute cache)
    if (!await _checkAvailability()) {
      debugPrint('MovieMetadata: Cinemeta unavailable');
      return null;
    }

    // Search Cinemeta
    final result = await _searchCinemeta(title, year);

    // Cache the result (even if null to prevent repeated failed lookups)
    _cache[cacheKey] = result;

    if (result != null) {
      debugPrint('✅ MovieMetadata: Found "${result.title}" (${result.year}) → ${result.imdbId}');
    } else {
      debugPrint('⚠️ MovieMetadata: No match found for "$title" ($year)');
    }

    return result;
  }

  /// Look up movie metadata from a filename
  ///
  /// Parses the filename to extract title and year, then looks up metadata.
  /// Returns null if filename doesn't have a year pattern (per user requirement).
  static Future<MovieMetadata?> lookupFromFilename(String filename) async {
    final movieInfo = MovieParser.parseFilename(filename);

    // Only proceed if filename has year pattern
    if (!movieInfo.hasYear || movieInfo.title == null) {
      debugPrint('MovieMetadata: Skipping "$filename" - no year pattern or title');
      return null;
    }

    return lookupMovie(movieInfo.title!, movieInfo.year);
  }

  /// Search Cinemeta for movie
  static Future<MovieMetadata?> _searchCinemeta(String title, int? year) async {
    // Clean title for search
    final searchQuery = MovieParser.cleanForSearch(title);
    final encodedQuery = Uri.encodeComponent(searchQuery);

    // Cinemeta search URL
    final url = '$_cinemetaBaseUrl/catalog/movie/top/search=$encodedQuery.json';

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {'Accept': 'application/json'},
        ).timeout(_timeout);

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final metas = data['metas'] as List<dynamic>?;

          if (metas == null || metas.isEmpty) {
            return null;
          }

          // Find best match
          return _findBestMatch(metas, title, year);
        } else if (response.statusCode == 429) {
          // Rate limited, wait and retry
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          debugPrint('MovieMetadata: Cinemeta returned ${response.statusCode}');
          return null;
        }
      } catch (e) {
        if (e is SocketException ||
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection reset')) {
          _isAvailable = false;
          _lastAvailabilityCheck = DateTime.now();
          break;
        }

        if (attempt < _maxRetries) {
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }

        debugPrint('MovieMetadata: Error searching Cinemeta: $e');
      }
    }

    return null;
  }

  /// Find the best matching movie from search results
  static MovieMetadata? _findBestMatch(
    List<dynamic> metas,
    String searchTitle,
    int? searchYear,
  ) {
    final normalizedSearchTitle = _normalizeTitle(searchTitle);

    MovieMetadata? bestMatch;
    int bestScore = 0;

    for (final meta in metas) {
      if (meta is! Map<String, dynamic>) continue;

      final id = meta['id'] as String?;
      final name = meta['name'] as String?;
      final yearStr = meta['year'] as String?;
      final releaseInfo = meta['releaseInfo'] as String?;
      final poster = meta['poster'] as String?;

      // Must have IMDB ID
      if (id == null || !id.startsWith('tt')) continue;
      if (name == null) continue;

      // Parse year from various fields
      int? metaYear;
      if (yearStr != null) {
        metaYear = int.tryParse(yearStr);
      }
      if (metaYear == null && releaseInfo != null) {
        // releaseInfo might be "2024" or "2024-"
        final yearMatch = RegExp(r'^\d{4}').firstMatch(releaseInfo);
        if (yearMatch != null) {
          metaYear = int.tryParse(yearMatch.group(0)!);
        }
      }

      // Calculate match score
      int score = 0;

      // Title match
      final normalizedMetaTitle = _normalizeTitle(name);
      if (normalizedMetaTitle == normalizedSearchTitle) {
        score += 100; // Exact match
      } else if (normalizedMetaTitle.contains(normalizedSearchTitle) ||
          normalizedSearchTitle.contains(normalizedMetaTitle)) {
        score += 50; // Partial match
      } else {
        continue; // Skip if titles don't match at all
      }

      // Year match
      if (searchYear != null && metaYear != null) {
        if (metaYear == searchYear) {
          score += 50; // Exact year match
        } else if ((metaYear - searchYear).abs() == 1) {
          score += 20; // Off by one year (common for late-year releases)
        }
      }

      if (score > bestScore) {
        bestScore = score;
        bestMatch = MovieMetadata(
          imdbId: id,
          title: name,
          year: metaYear,
          poster: poster,
        );
      }
    }

    return bestMatch;
  }

  /// Normalize title for comparison
  static String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Create cache key
  static String _createCacheKey(String title, int? year) {
    final normalizedTitle = _normalizeTitle(title);
    return year != null ? '${normalizedTitle}_$year' : normalizedTitle;
  }

  /// Check if service is available
  static Future<bool> _checkAvailability() async {
    // Cache availability check for 5 minutes
    if (_lastAvailabilityCheck != null &&
        DateTime.now().difference(_lastAvailabilityCheck!) < const Duration(minutes: 5)) {
      return _isAvailable;
    }

    try {
      final response = await http.get(
        Uri.parse('$_cinemetaBaseUrl/manifest.json'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      _isAvailable = response.statusCode == 200;
      _lastAvailabilityCheck = DateTime.now();
      return _isAvailable;
    } catch (e) {
      _isAvailable = false;
      _lastAvailabilityCheck = DateTime.now();
      return false;
    }
  }

  /// Clear cache
  static void clearCache() {
    _cache.clear();
    _lastAvailabilityCheck = null;
  }

  /// Get current availability status
  static bool get isAvailable => _isAvailable;
}
