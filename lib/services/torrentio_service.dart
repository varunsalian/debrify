import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie_torrentio_stream.dart';
import '../models/channel_hub.dart';
import 'storage_service.dart';

class TorrentioService {
  static const String _baseUrl = 'https://torrentio.strem.fun';
  static const String _streamEndpoint = '/stream/movie';
  
  // Fetch streams for a specific movie by IMDB ID
  static Future<List<MovieTorrentioStream>> fetchMovieStreams(String imdbId, {
    String? quality,
    int? maxSize,
    int? minSize,
    String? providers,
    String? exclude,
    String? language,
    int? maxResults,
  }) async {
    try {
      // Build the URL without query parameters - just the basic endpoint with IMDB ID
      print('DEBUG: IMDB ID for Torrentio request: "$imdbId"');
      
      if (imdbId.isEmpty) {
        throw Exception('Empty IMDB ID provided for Torrentio request');
      }
      
      final uri = Uri.parse('$_baseUrl$_streamEndpoint/$imdbId.json');

      print('DEBUG: Fetching Torrentio streams from: ${uri.toString()}');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Debrify/1.0',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final streams = data['streams'] as List? ?? [];
        
        return streams.map((stream) => 
          MovieTorrentioStream.fromTorrentioResponse(stream, imdbId)
        ).toList();
      } else if (response.statusCode == 404) {
        print('DEBUG: No streams found for movie $imdbId');
        return [];
      } else {
        throw Exception('Failed to fetch streams: ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Error fetching Torrentio streams: $e');
      throw Exception('Network error while fetching streams: $e');
    }
  }

  // Save streams for a movie to storage (hub-specific)
  static Future<void> saveMovieStreams(String imdbId, List<MovieTorrentioStream> streams, {String? hubId}) async {
    try {
      final key = hubId != null ? 'torrentio_streams_${hubId}_$imdbId' : 'torrentio_streams_$imdbId';
      final data = streams.map((s) => s.toJson()).toList();
      await StorageService.saveString(key, json.encode(data));
      
      print('DEBUG: Saved ${streams.length} streams for movie $imdbId in hub $hubId');
    } catch (e) {
      print('DEBUG: Error saving streams: $e');
      throw Exception('Failed to save streams: $e');
    }
  }

  // Load streams for a movie from storage (hub-specific)
  static Future<List<MovieTorrentioStream>> loadMovieStreams(String imdbId, {String? hubId}) async {
    try {
      final key = hubId != null ? 'torrentio_streams_${hubId}_$imdbId' : 'torrentio_streams_$imdbId';
      final data = await StorageService.getString(key);
      
      if (data == null || data.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = json.decode(data);
      return jsonList.map((json) => MovieTorrentioStream.fromJson(json)).toList();
    } catch (e) {
      print('DEBUG: Error loading streams: $e');
      return [];
    }
  }

  // Check if streams are cached (hub-specific)
  static Future<bool> isStreamsCached(String imdbId, {String? hubId}) async {
    try {
      final key = hubId != null ? 'torrentio_streams_${hubId}_$imdbId' : 'torrentio_streams_$imdbId';
      final data = await StorageService.getString(key);
      return data != null && data.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // Get streams for a movie (always fetch fresh)
  static Future<List<MovieTorrentioStream>> getMovieStreams(String imdbId, {
    bool forceRefresh = false,
    String? hubId,
  }) async {
    try {
      // Always fetch fresh data, ignore cache
      print('DEBUG: Fetching fresh streams for movie $imdbId in hub $hubId (ignoring cache)');

      // Fetch fresh data
      print('DEBUG: Fetching fresh streams for movie $imdbId');
      final streams = await fetchMovieStreams(imdbId);

      // Save to cache
      if (streams.isNotEmpty) {
        await saveMovieStreams(imdbId, streams, hubId: hubId);
      }

      return streams;
    } catch (e) {
      print('DEBUG: Error getting streams: $e');
      // Fallback to cached data if available
      if (!forceRefresh) {
        return await loadMovieStreams(imdbId, hubId: hubId);
      }
      return [];
    }
  }



  // Update movie with Torrentio streams
  static Future<MovieInfo> updateMovieWithStreams(MovieInfo movie) async {
    try {
      final streams = await getMovieStreams(movie.id);
      
      return movie.copyWith(
        torrentioStreams: streams,
        hasTorrentioData: streams.isNotEmpty,
      );
    } catch (e) {
      print('DEBUG: Error updating movie with streams: $e');
      return movie;
    }
  }

  // Clear cache for a specific movie
  static Future<void> clearMovieCache(String imdbId, {String? hubId}) async {
    try {
      final key = hubId != null ? 'torrentio_streams_${hubId}_$imdbId' : 'torrentio_streams_$imdbId';
      await StorageService.remove(key);
      print('DEBUG: Cleared cache for movie $imdbId in hub $hubId');
    } catch (e) {
      print('DEBUG: Error clearing cache: $e');
    }
  }

  // Clear all Torrentio cache for a specific hub
  static Future<void> clearHubCache(String hubId) async {
    try {
      final keys = await StorageService.getAllKeys();
      final hubKeys = keys.where((key) => 
        key.startsWith('torrentio_streams_${hubId}_')
      ).toList();
      
      for (final key in hubKeys) {
        await StorageService.remove(key);
      }
      
      print('DEBUG: Cleared all Torrentio cache for hub $hubId');
    } catch (e) {
      print('DEBUG: Error clearing hub cache: $e');
    }
  }

  // Clear all Torrentio cache
  static Future<void> clearAllCache() async {
    try {
      final keys = await StorageService.getAllKeys();
      final torrentioKeys = keys.where((key) => 
        key.startsWith('torrentio_streams_')
      ).toList();
      
      for (final key in torrentioKeys) {
        await StorageService.remove(key);
      }
      
      print('DEBUG: Cleared all Torrentio cache');
    } catch (e) {
      print('DEBUG: Error clearing all cache: $e');
    }
  }
} 