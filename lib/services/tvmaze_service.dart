import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'tvmaze_cache_service.dart';

class TVMazeService {
  static const String _baseUrl = 'https://api.tvmaze.com';
  static final Map<String, dynamic> _cache = {};
  static final Map<String, int> _seriesIdCache = {};
  static const int _maxRetries = 3;
  static const Duration _timeout = Duration(seconds: 15);
  static bool _isAvailable = true;
  static DateTime? _lastAvailabilityCheck;
  static bool _cacheInitialized = false;

  /// Initialize the service and cleanup expired cache
  static Future<void> initialize() async {
    if (_cacheInitialized) return;

    try {
      await TVMazeCacheService.cleanupExpired();
      _cacheInitialized = true;
    } catch (e) {
      // Silently fail - cache is optional
    }
  }

  /// Check if the service is available with caching
  static Future<bool> isAvailable() async {
    // Ensure cache is initialized
    await initialize();

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
      _isAvailable = false;
      _lastAvailabilityCheck = DateTime.now();
      return false;
    }
  }

  /// Clean show name for search
  static String _cleanShowName(String showName) {
    // Remove trailing dots and clean the name
    String cleaned = showName.trim();

    // Replace common separators with spaces
    cleaned = cleaned.replaceAll(RegExp(r'[._-]'), ' ');
    
    // Remove multiple consecutive spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    
    // Remove trailing dots and clean again
    cleaned = cleaned.replaceAll(RegExp(r'\.+$'), '').trim();
    
    // Remove year patterns like (2023), (2023), 2023
    cleaned = cleaned.replaceAll(RegExp(r'\((\d{4})\)'), ''); // (2023)
    cleaned = cleaned.replaceAll(RegExp(r'\s+(\d{4})\s+'), ' '); // 2023 with spaces
    cleaned = cleaned.replaceAll(RegExp(r'^\d{4}\s+'), ''); // 2023 at start
    cleaned = cleaned.replaceAll(RegExp(r'\s+\d{4}$'), ''); // 2023 at end
    
    // Remove quality indicators
    cleaned = cleaned.replaceAll(RegExp(r'\b(1080p|720p|480p|2160p|4K|HDRip|BRRip|WEBRip|BluRay|HDTV|DVDRip)\b', caseSensitive: false), '');
    
    // Remove audio codecs
    cleaned = cleaned.replaceAll(RegExp(r'\b(AAC|AC3|DTS|FLAC|MP3|OGG)\b', caseSensitive: false), '');
    
    // Remove video codecs
    cleaned = cleaned.replaceAll(RegExp(r'\b(H\.264|H\.265|HEVC|AVC|XVID|DIVX)\b', caseSensitive: false), '');
    
    // Remove release group patterns (usually at the end with -GROUP)
    cleaned = cleaned.replaceAll(RegExp(r'-[A-Za-z0-9]+$'), '');
    
    // Remove season/episode patterns that might be in the title
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ss](\d{1,2})[Ee](\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(\d{1,2})[xX](\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b(\d{1,2})\.(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ss]eason\s*(\d{1,2})\s*[Ee]pisode\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee]pisode\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee]p\s*(\d{1,2})\b'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\b[Ee](\d{1,2})\b'), '');
    
    // Remove common torrent metadata
    cleaned = cleaned.replaceAll(RegExp(r'\b(REPACK|PROPER|INTERNAL|EXTENDED|DIRFIX|NFOFIX|SUBFIX)\b', caseSensitive: false), '');
    
    // Remove file extensions that might have been missed
    cleaned = cleaned.replaceAll(RegExp(r'\.[a-zA-Z0-9]{3,4}$'), '');
    
    // Clean up any remaining multiple spaces and trim
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return cleaned;
  }

  /// Generate multiple search variations for better matching
  static List<String> _generateSearchVariations(String cleanName) {
    final variations = <String>[];
    
    // Add the original cleaned name
    variations.add(cleanName);
    
    // Split by common words that might be part of the title
    final words = cleanName.split(' ').where((word) => word.isNotEmpty).toList();
    
    if (words.length > 1) {
      // Try without the last word (might be a descriptor)
      final withoutLast = words.take(words.length - 1).join(' ');
      if (withoutLast.isNotEmpty) {
        variations.add(withoutLast);
      }
      
      // Try without the first word (might be "The", "A", etc.)
      if (words.length > 2) {
        final withoutFirst = words.skip(1).join(' ');
        variations.add(withoutFirst);
      }
    }
    
    // Remove common prefixes/suffixes
    final withoutThe = cleanName.replaceAll(RegExp(r'^[Tt]he\s+'), '');
    if (withoutThe != cleanName && withoutThe.isNotEmpty) {
      variations.add(withoutThe);
    }
    
    // Remove common suffixes
    final withoutSuffixes = cleanName.replaceAll(RegExp(r'\s+(Series|Show|TV|Television)$', caseSensitive: false), '');
    if (withoutSuffixes != cleanName && withoutSuffixes.isNotEmpty) {
      variations.add(withoutSuffixes);
    }
    
    // Remove duplicates and empty strings
    return variations.where((v) => v.isNotEmpty).toSet().toList();
  }

  /// Try alternative search method
  static Future<Map<String, dynamic>?> _tryAlternativeSearch(String cleanName) async {
    try {
      // For now, return null - we'll rely on the API working properly
      // This method can be enhanced later with a proper fallback database if needed
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Search for a TV show by name with retry logic and better error handling
  static Future<Map<String, dynamic>?> searchShow(String showName) async {
    final cleanName = _cleanShowName(showName);
    final cacheKey = 'search_$cleanName';

    // Check in-memory cache first
    if (_cache.containsKey(cacheKey)) {
      print('🎯 TVMaze: Memory cache HIT for "$cleanName"');
      return _cache[cacheKey];
    }

    // Check persistent cache
    final persistedData = await TVMazeCacheService.get(cacheKey);
    if (persistedData != null) {
      print('💾 TVMaze: Persistent cache HIT for "$cleanName"');
      // Store in memory cache for faster access
      _cache[cacheKey] = persistedData;
      if (persistedData['id'] != null) {
        _seriesIdCache[cleanName.toLowerCase()] = persistedData['id'] as int;
      }
      return persistedData;
    }

    print('❌ TVMaze: Cache MISS for "$cleanName", calling API...');

    // Check availability first
    if (!await isAvailable()) {
      // Try alternative search method
      final alternativeResult = await _tryAlternativeSearch(cleanName);
      if (alternativeResult != null) {
        _cache[cacheKey] = alternativeResult;
        _seriesIdCache[cleanName.toLowerCase()] = alternativeResult['id'] as int;
        // Save to persistent cache
        await TVMazeCacheService.set(cacheKey, alternativeResult);
        return alternativeResult;
      }
      // Cache the failure to prevent repeated API calls
      _cache[cacheKey] = null;
      return null;
    }

    // Try multiple search strategies
    final searchVariations = _generateSearchVariations(cleanName);
    
    for (final searchTerm in searchVariations) {
      for (int attempt = 1; attempt <= _maxRetries; attempt++) {
        try {
          // Use proper URL encoding
          final encodedQuery = Uri.encodeComponent(searchTerm);
          final url = '$_baseUrl/search/shows?q=$encodedQuery';

          final response = await http.get(
            Uri.parse(url),
            headers: {
              'Accept': 'application/json',
            },
          ).timeout(_timeout);


          if (response.statusCode == 200) {
            final List<dynamic> results = json.decode(response.body);
            if (results.isNotEmpty) {
              final show = results.first['show'] as Map<String, dynamic>;
              _cache[cacheKey] = show;
              _seriesIdCache[cleanName.toLowerCase()] = show['id'] as int;
              // Save to persistent cache
              await TVMazeCacheService.set(cacheKey, show);
              print('✅ TVMaze: API success for "$cleanName" → cached (expires in 30 days)');
              return show;
            }
          } else if (response.statusCode == 429) {
            // Rate limited, wait and retry
            await Future.delayed(Duration(seconds: attempt * 2));
            continue;
          }
        } catch (e) {
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
      
      // If we get here, this search variation failed, try the next one
    }
    
    // If all attempts failed, try alternative search
    final alternativeResult = await _tryAlternativeSearch(cleanName);
    if (alternativeResult != null) {
      _cache[cacheKey] = alternativeResult;
      _seriesIdCache[cleanName.toLowerCase()] = alternativeResult['id'] as int;
      // Save to persistent cache
      await TVMazeCacheService.set(cacheKey, alternativeResult);
      return alternativeResult;
    }

    // Cache the failure to prevent repeated API calls
    _cache[cacheKey] = null;
    return null;
  }

  /// Get episodes for a show by ID with retry logic
  static Future<List<Map<String, dynamic>>> getEpisodes(int showId) async {
    final cacheKey = 'episodes_$showId';

    // Check in-memory cache first
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached is List) {
        print('🎯 TVMaze: Memory cache HIT for episodes (showId: $showId)');
        return List<Map<String, dynamic>>.from(cached);
      }
    }

    // Check persistent cache
    final persistedData = await TVMazeCacheService.getList(cacheKey);
    if (persistedData != null) {
      print('💾 TVMaze: Persistent cache HIT for episodes (showId: $showId, count: ${persistedData.length})');
      // Store in memory cache for faster access
      _cache[cacheKey] = persistedData;
      return persistedData;
    }

    print('❌ TVMaze: Cache MISS for episodes (showId: $showId), calling API...');

    // Check availability first
    if (!await isAvailable()) {
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
          // Save to persistent cache
          await TVMazeCacheService.setList(cacheKey, episodeList);
          print('✅ TVMaze: API success for episodes (showId: $showId, count: ${episodeList.length}) → cached (expires in 30 days)');
          return episodeList;
        } else if (response.statusCode == 429) {
          // Rate limited, wait and retry
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        } else {
        }
      } catch (e) {
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
      } else {
      }
    }

    if (showId == null) {
      return null;
    }

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
    final result = await searchShow(showName);
    return result;
  }

  /// Force refresh availability status
  static Future<void> refreshAvailability() async {
    _lastAvailabilityCheck = null; // Reset cache
    await isAvailable(); // This will update the status
  }

  /// Get current availability status
  static bool get currentAvailability => _isAvailable;

  /// Clear cache
  static Future<void> clearCache() async {
    _cache.clear();
    _seriesIdCache.clear();
    _lastAvailabilityCheck = null;
    // Clear persistent cache too
    await TVMazeCacheService.clearAll();
  }

  /// Clear cache for a specific series
  static Future<void> clearSeriesCache(String seriesTitle) async {
    final cleanName = _cleanShowName(seriesTitle);
    final searchKey = 'search_$cleanName';
    final seriesIdKey = cleanName.toLowerCase();

    _cache.remove(searchKey);
    _seriesIdCache.remove(seriesIdKey);

    // Clear persistent cache too
    await TVMazeCacheService.clearSeriesCache(seriesTitle);
  }

  /// Clear all cached data for a specific show ID
  /// This includes both in-memory and persistent cache entries
  static Future<void> clearShowCache(int showId) async {
    // Clear in-memory cache
    _cache.remove('show_$showId');
    _cache.remove('episodes_$showId');

    // Clear persistent cache
    await TVMazeCacheService.clearShowCache(showId);

    debugPrint('🧹 TVMazeService: Cleared cache for show ID $showId');
  }

  /// Search for shows by query (public method for manual search)
  /// Returns a list of shows matching the search query
  static Future<List<Map<String, dynamic>>> searchShows(String query) async {
    // Check availability first
    if (!await isAvailable()) {
      return [];
    }

    try {
      // Use proper URL encoding
      final encodedQuery = Uri.encodeComponent(query);
      final url = '$_baseUrl/search/shows?q=$encodedQuery';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final List<dynamic> results = json.decode(response.body);
        // Extract the show objects from the search results
        final shows = results.map((result) {
          final show = result['show'] as Map<String, dynamic>;
          // Add score for relevance
          if (result['score'] != null) {
            show['_searchScore'] = result['score'];
          }
          return show;
        }).toList();

        print('✅ TVMaze: Found ${shows.length} shows for query "$query"');
        return shows;
      } else if (response.statusCode == 429) {
        // Rate limited
        print('⚠️ TVMaze: Rate limited while searching for "$query"');
        return [];
      } else {
        print('❌ TVMaze: Search failed with status ${response.statusCode} for "$query"');
        return [];
      }
    } catch (e) {
      print('❌ TVMaze: Error searching for "$query": $e');
      return [];
    }
  }

  /// Get show details by ID
  static Future<Map<String, dynamic>?> getShowById(int showId) async {
    final cacheKey = 'show_$showId';

    // Check in-memory cache first
    if (_cache.containsKey(cacheKey)) {
      print('🎯 TVMaze: Memory cache HIT for show ID $showId');
      return _cache[cacheKey];
    }

    // Check persistent cache
    final persistedData = await TVMazeCacheService.get(cacheKey);
    if (persistedData != null) {
      print('💾 TVMaze: Persistent cache HIT for show ID $showId');
      // Store in memory cache for faster access
      _cache[cacheKey] = persistedData;
      return persistedData;
    }

    print('❌ TVMaze: Cache MISS for show ID $showId, calling API...');

    // Check availability first
    if (!await isAvailable()) {
      return null;
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/shows/$showId'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      if (response.statusCode == 200) {
        final show = json.decode(response.body) as Map<String, dynamic>;
        _cache[cacheKey] = show;
        // Save to persistent cache
        await TVMazeCacheService.set(cacheKey, show);
        print('✅ TVMaze: API success for show ID $showId → cached');
        return show;
      } else {
        print('❌ TVMaze: Failed to fetch show ID $showId - status ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ TVMaze: Error fetching show ID $showId: $e');
      return null;
    }
  }
}
