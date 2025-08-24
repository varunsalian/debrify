import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class TVMazeService {
  static const String _baseUrl = 'https://api.tvmaze.com';
  static final Map<String, dynamic> _cache = {};
  static final Map<String, int> _seriesIdCache = {};
  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 15);
  static bool _isAvailable = true;
  static DateTime? _lastAvailabilityCheck;

  /// Check if the service is available with caching
  static Future<bool> isAvailable() async {
    // Cache availability check for 5 minutes to avoid excessive checks
    if (_lastAvailabilityCheck != null && 
        DateTime.now().difference(_lastAvailabilityCheck!) < const Duration(minutes: 5)) {
      return _isAvailable;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/shows/1'), // Try to get a known show
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      
      _isAvailable = response.statusCode == 200;
      _lastAvailabilityCheck = DateTime.now();
      return _isAvailable;
    } catch (e) {
      print('TVMaze availability check failed: $e');
      _isAvailable = false;
      _lastAvailabilityCheck = DateTime.now();
      return false;
    }
  }

  /// Clean show name for search
  static String _cleanShowName(String showName) {
    // Remove trailing dots and clean the name
    String cleaned = showName.trim();
    
    print('Original show name: "$showName"');
    
    // Replace common separators with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[._-]'), ' ');
    
    // Remove multiple consecutive spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove trailing dots and clean again
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '').trim();
    
    print('Cleaned show name: "$cleaned"');
    
    return cleaned;
  }

  /// Try alternative search method
  static Future<Map<String, dynamic>?> _tryAlternativeSearch(String cleanName) async {
    try {
      // For now, return null - we'll rely on the API working properly
      // This method can be enhanced later with a proper fallback database if needed
      print('Alternative search not implemented for: $cleanName');
      return null;
    } catch (e) {
      print('Alternative search failed: $e');
      return null;
    }
  }

  /// Search for a TV show by name with retry logic and better error handling
  static Future<Map<String, dynamic>?> searchShow(String showName) async {
    final cleanName = _cleanShowName(showName);
    final cacheKey = 'search_$cleanName';
    
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    // Check availability first
    if (!await isAvailable()) {
      print('TVMaze not available, trying alternative search for: $cleanName');
      // Try alternative search method
      final alternativeResult = await _tryAlternativeSearch(cleanName);
      if (alternativeResult != null) {
        _cache[cacheKey] = alternativeResult;
        _seriesIdCache[cleanName.toLowerCase()] = alternativeResult['id'] as int;
        return alternativeResult;
      }
      // Cache the failure to prevent repeated API calls
      _cache[cacheKey] = null;
      return null;
    }

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        // Use proper URL encoding
        final encodedQuery = Uri.encodeComponent(cleanName);
        final url = '$_baseUrl/search/shows?q=$encodedQuery';
        
        print('TVMaze searching for: $cleanName (encoded: $encodedQuery)');
        
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Accept': 'application/json',
          },
        ).timeout(_timeout);

        print('TVMaze response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final List<dynamic> results = json.decode(response.body);
          print('TVMaze found ${results.length} results');
          
          if (results.isNotEmpty) {
            final show = results.first['show'] as Map<String, dynamic>;
            _cache[cacheKey] = show;
            _seriesIdCache[cleanName.toLowerCase()] = show['id'] as int;
            return show;
          } else {
            // Cache the failure to prevent repeated API calls
            print('TVMaze search returned no results for: $cleanName');
            _cache[cacheKey] = null;
            return null;
          }
        } else if (response.statusCode == 429) {
          // Rate limited, wait and retry
          print('TVMaze rate limited, waiting...');
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          print('TVMaze search failed with status: ${response.statusCode}');
          print('Response body: ${response.body}');
        }
      } catch (e) {
        print('TVMaze search error (attempt $attempt): $e');
        
        // Check if it's a network-related error
        if (e is SocketException || 
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection reset') ||
            e.toString().contains('Connection refused')) {
          // Mark as unavailable for network errors
          _isAvailable = false;
          _lastAvailabilityCheck = DateTime.now();
          break; // Don't retry network errors
        }
        
        if (attempt < _maxRetries) {
          // Wait before retrying
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
      }
    }
    
    // If all attempts failed, try alternative search
    print('TVMaze search failed for: $cleanName, trying alternative search');
    final alternativeResult = await _tryAlternativeSearch(cleanName);
    if (alternativeResult != null) {
      _cache[cacheKey] = alternativeResult;
      _seriesIdCache[cleanName.toLowerCase()] = alternativeResult['id'] as int;
      return alternativeResult;
    }
    
    // Cache the failure to prevent repeated API calls
    _cache[cacheKey] = null;
    return null;
  }

  /// Get episodes for a show by ID with retry logic
  static Future<List<Map<String, dynamic>>> getEpisodes(int showId) async {
    final cacheKey = 'episodes_$showId';
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached is List) {
        return List<Map<String, dynamic>>.from(cached);
      }
    }

    // Check availability first
    if (!await isAvailable()) {
      print('TVMaze not available, skipping episodes fetch for show ID: $showId');
      return [];
    }

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/shows/$showId/episodes'),
          headers: {
            'Accept': 'application/json',
          },
        ).timeout(_timeout);

        if (response.statusCode == 200) {
          final List<dynamic> episodes = json.decode(response.body);
          final List<Map<String, dynamic>> episodeList = episodes
              .map((episode) => episode as Map<String, dynamic>)
              .toList();
          _cache[cacheKey] = episodeList;
          return episodeList;
        } else if (response.statusCode == 429) {
          // Rate limited, wait and retry
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
          print('TVMaze episodes failed with status: ${response.statusCode}');
        }
      } catch (e) {
        print('TVMaze episodes error (attempt $attempt): $e');
        
        // Check if it's a network-related error
        if (e is SocketException || 
            e.toString().contains('HandshakeException') ||
            e.toString().contains('Connection reset') ||
            e.toString().contains('Connection refused')) {
          // Mark as unavailable for network errors
          _isAvailable = false;
          _lastAvailabilityCheck = DateTime.now();
          break; // Don't retry network errors
        }
        
        if (attempt < _maxRetries) {
          // Wait before retry
          await Future.delayed(Duration(seconds: attempt));
          continue;
        }
      }
    }

    print('TVMaze episodes failed for show ID: $showId after $_maxRetries attempts');
    return [];
  }

  /// Get episode information by season and episode number
  static Future<Map<String, dynamic>?> getEpisodeInfo(
    String showName,
    int season,
    int episode,
  ) async {
    final cleanName = _cleanShowName(showName);
    
    // First try to get show ID from cache
    int? showId = _seriesIdCache[cleanName.toLowerCase()];
    
    if (showId == null) {
      // Search for the show
      final show = await searchShow(cleanName);
      if (show != null) {
        showId = show['id'] as int;
      }
    }

    if (showId == null) return null;

    // Get all episodes
    final episodes = await getEpisodes(showId);
    
    // Find the specific episode
    for (final ep in episodes) {
      if (ep['season'] == season && ep['number'] == episode) {
        return ep;
      }
    }

    return null;
  }

  /// Get show information by name
  static Future<Map<String, dynamic>?> getShowInfo(String showName) async {
    return await searchShow(showName);
  }

  /// Force refresh availability status
  static Future<void> refreshAvailability() async {
    _lastAvailabilityCheck = null; // Reset cache
    await isAvailable(); // This will update the status
  }

  /// Get current availability status
  static bool get currentAvailability => _isAvailable;

  /// Clear cache
  static void clearCache() {
    _cache.clear();
    _seriesIdCache.clear();
    _lastAvailabilityCheck = null;
    print('TVMazeService cache cleared');
  }

  /// Clear cache for a specific series
  static void clearSeriesCache(String seriesTitle) {
    final cleanName = _cleanShowName(seriesTitle);
    final searchKey = 'search_$cleanName';
    final seriesIdKey = cleanName.toLowerCase();
    
    _cache.remove(searchKey);
    _seriesIdCache.remove(seriesIdKey);
    
    print('Cleared TVMaze cache for series: $seriesTitle');
  }
} 