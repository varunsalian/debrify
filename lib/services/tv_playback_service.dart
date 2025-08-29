import 'dart:math';
import 'package:flutter/material.dart';
import '../models/channel_hub.dart';
import '../models/movie_torrentio_stream.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';
import '../services/channel_hub_service.dart';

class TVPlaybackService {
  /// Selects a movie from a channel hub based on watch count (lowest first) and plays it
  static Future<Map<String, dynamic>?> playRandomMovieFromHub(
    BuildContext context,
    ChannelHub hub,
  ) async {
    // Get fresh hub data to ensure we have the latest watch counts
    final freshHub = await ChannelHubService.getChannelHub(hub.id);
    if (freshHub == null) {
      throw Exception('Hub not found: ${hub.id}');
    }
    try {
      // Check if hub has movies
      if (freshHub.movies.isEmpty) {
        throw Exception('No movies available in this channel hub');
      }

      // Filter movies with Torrentio data
      final availableMovies = freshHub.movies.where((movie) => 
        movie.hasTorrentioData && movie.torrentioStreams.isNotEmpty
      ).toList();

      if (availableMovies.isEmpty) {
        throw Exception('No movies with streaming data available in this channel hub');
      }

      // Sort movies by watch count (lowest first)
      availableMovies.sort((a, b) => a.timesWatched.compareTo(b.timesWatched));
      
      // Get the minimum watch count
      final minWatchCount = availableMovies.first.timesWatched;
      
      // Filter movies with the minimum watch count
      final leastWatchedMovies = availableMovies.where((movie) => 
        movie.timesWatched == minWatchCount
      ).toList();
      
      // Select a random movie from the least watched ones
      final random = Random();
      final selectedMovie = leastWatchedMovies[random.nextInt(leastWatchedMovies.length)];
      
      print('DEBUG: Selected movie with lowest watch count: ${selectedMovie.name} (watched ${selectedMovie.timesWatched} times)');

      // Create quality buckets and get priority order
      final qualityBuckets = _createQualityBuckets(selectedMovie.torrentioStreams);
      final bucketPriority = _getBucketPriority(freshHub.quality);
      print('DEBUG: Hub quality setting: ${freshHub.quality}');
      print('DEBUG: Bucket priority: ${bucketPriority.join(' → ')}');

      // Get Real-Debrid API key
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Real-Debrid API key not configured');
      }

      // Try buckets in priority order
      Map<String, dynamic>? result;
      MovieTorrentioStream? selectedStream;
      
      for (final bucketName in bucketPriority) {
        final bucket = qualityBuckets[bucketName]!;
        print('DEBUG: Trying bucket: $bucketName (${bucket.length} streams)');
        
        if (bucket.isEmpty) {
          print('DEBUG: Bucket $bucketName is empty, skipping...');
          continue;
        }
        
        // Try each stream in the bucket until one works
        final bucketCopy = List<MovieTorrentioStream>.from(bucket);
        while (bucketCopy.isNotEmpty) {
          // Select a random stream from this bucket
          final randomIndex = random.nextInt(bucketCopy.length);
          final stream = bucketCopy[randomIndex];
          bucketCopy.removeAt(randomIndex); // Remove from bucket copy
          
          print('DEBUG: Trying stream from $bucketName bucket: ${stream.title}');
          print('DEBUG: Stream qualityDetails: ${stream.qualityDetails}');
          
          // Create magnet link from infoHash
          final magnetLink = 'magnet:?xt=urn:btih:${stream.infoHash}';
          print('DEBUG: Processing magnet link: $magnetLink');
          
          // Try to get download link from Real-Debrid
          result = await _getDownloadLinkFromDebrid(
            apiKey, 
            magnetLink, 
            stream,
            freshHub.quality,
          );
          
          if (result != null) {
            selectedStream = stream;
            print('DEBUG: Success with stream from $bucketName bucket!');
            break;
          } else {
            print('DEBUG: Failed with stream from $bucketName bucket, trying next...');
          }
        }
        
        if (result != null) {
          break; // Found a working stream, exit bucket loop
        } else {
          print('DEBUG: All streams in $bucketName bucket failed, trying next bucket...');
        }
      }
      
      if (result == null || selectedStream == null) {
        throw Exception('Failed to get download link from any stream in any bucket');
      }

      // Increment the watch count immediately after successful selection
      await incrementMovieWatchCount(freshHub.id, selectedMovie.id);
      
      return {
        'videoUrl': result['downloadLink'],
        'title': selectedMovie.name,
        'subtitle': '${selectedMovie.year ?? ''} • ${selectedStream!.title}',
        'movie': selectedMovie,
        'stream': selectedStream,
      };

    } catch (e) {
      print('DEBUG: Error in playRandomMovieFromHub: $e');
      rethrow;
    }
  }

  /// Create quality buckets and organize streams by quality
  static Map<String, List<MovieTorrentioStream>> _createQualityBuckets(
    List<MovieTorrentioStream> streams,
  ) {
    print('DEBUG: Creating quality buckets for ${streams.length} streams');
    
    final buckets = <String, List<MovieTorrentioStream>>{
      '720p': <MovieTorrentioStream>[],
      '1080p': <MovieTorrentioStream>[],
      '4k': <MovieTorrentioStream>[],
      'other': <MovieTorrentioStream>[],
    };
    
    for (final stream in streams) {
      final qualityDetails = stream.qualityDetails?.toLowerCase() ?? '';
      print('DEBUG: Categorizing stream: ${stream.title}');
      print('DEBUG: QualityDetails: $qualityDetails');
      
      bool categorized = false;
      
      // Check for 4k first (most specific)
      if (RegExp(r'4k|2160p|uhd', caseSensitive: false).hasMatch(qualityDetails)) {
        buckets['4k']!.add(stream);
        print('DEBUG: ✓ Added to 4k bucket');
        categorized = true;
      }
      // Check for 1080p
      else if (RegExp(r'1080p', caseSensitive: false).hasMatch(qualityDetails)) {
        buckets['1080p']!.add(stream);
        print('DEBUG: ✓ Added to 1080p bucket');
        categorized = true;
      }
      // Check for 720p
      else if (RegExp(r'720p', caseSensitive: false).hasMatch(qualityDetails)) {
        buckets['720p']!.add(stream);
        print('DEBUG: ✓ Added to 720p bucket');
        categorized = true;
      }
      
      // If not categorized, add to other bucket
      if (!categorized) {
        buckets['other']!.add(stream);
        print('DEBUG: ✓ Added to other bucket');
      }
    }
    
    print('DEBUG: Quality buckets created:');
    print('DEBUG: - 720p: ${buckets['720p']!.length} streams');
    print('DEBUG: - 1080p: ${buckets['1080p']!.length} streams');
    print('DEBUG: - 4k: ${buckets['4k']!.length} streams');
    print('DEBUG: - Other: ${buckets['other']!.length} streams');
    
    return buckets;
  }

  /// Get the priority order of buckets based on user preference
  static List<String> _getBucketPriority(String userQuality) {
    final quality = userQuality.toLowerCase();
    
    switch (quality) {
      case '720p':
        return ['720p', '1080p', '4k', 'other'];
      case '1080p':
        return ['1080p', '4k', '720p', 'other'];
      case '4k':
        return ['4k', '1080p', '720p', 'other'];
      default:
        return ['720p', '1080p', '4k', 'other'];
    }
  }

  /// Get download link from Real-Debrid with fallback strategies
  static Future<Map<String, dynamic>?> _getDownloadLinkFromDebrid(
    String apiKey,
    String magnetLink,
    MovieTorrentioStream stream,
    String quality,
  ) async {
    try {
      // Strategy 1: Try "All video" selection first
      print('DEBUG: Trying "All video" selection...');
      try {
        final result = await DebridService.addTorrentToDebrid(
          apiKey, 
          magnetLink, 
          tempFileSelection: 'video',
        );
        
        if (result['downloadLink'] != null) {
          print('DEBUG: Success with "All video" selection');
          return result;
        }
      } catch (e) {
        print('DEBUG: "All video" selection failed: $e');
      }

      // Strategy 2: Try "Largest file" selection (default)
      print('DEBUG: Trying "Largest file" selection...');
      try {
        final result = await DebridService.addTorrentToDebrid(
          apiKey, 
          magnetLink, 
          tempFileSelection: 'largest',
        );
        
        if (result['downloadLink'] != null) {
          print('DEBUG: Success with "Largest file" selection');
          return result;
        }
      } catch (e) {
        print('DEBUG: "Largest file" selection failed: $e');
      }

      return null;

    } catch (e) {
      print('DEBUG: All Real-Debrid strategies failed: $e');
      return null;
    }
  }

  /// Get a random timestamp for video playback
  static Duration getRandomTimestamp(Duration totalDuration) {
    if (totalDuration.inSeconds <= 60) {
      // If video is 1 minute or less, start from beginning
      return Duration.zero;
    }
    
    final random = Random();
    // Leave at least 1 minute at the end
    final maxJumpSeconds = totalDuration.inSeconds - 60;
    final randomSeconds = random.nextInt(maxJumpSeconds);
    
    return Duration(seconds: randomSeconds);
  }

  /// Increment the watch count for a movie in a channel hub
  static Future<void> incrementMovieWatchCount(String hubId, String movieId) async {
    try {
      // Get the current hub
      final hub = await ChannelHubService.getChannelHub(hubId);
      if (hub == null) {
        print('DEBUG: Hub not found: $hubId');
        return;
      }

      // Find the movie and increment its watch count
      final movieIndex = hub.movies.indexWhere((movie) => movie.id == movieId);
      if (movieIndex == -1) {
        print('DEBUG: Movie not found in hub: $movieId');
        return;
      }

      final movie = hub.movies[movieIndex];
      final updatedMovie = movie.copyWith(timesWatched: movie.timesWatched + 1);
      
      // Create updated hub with the modified movie
      final updatedMovies = List<MovieInfo>.from(hub.movies);
      updatedMovies[movieIndex] = updatedMovie;
      
      final updatedHub = ChannelHub(
        id: hub.id,
        name: hub.name,
        quality: hub.quality,
        series: hub.series,
        movies: updatedMovies,
        createdAt: hub.createdAt,
      );

      // Save the updated hub
      await ChannelHubService.updateChannelHub(updatedHub);
      
      print('DEBUG: Incremented watch count for movie ${movie.name} to ${updatedMovie.timesWatched}');
      
    } catch (e) {
      print('DEBUG: Error incrementing movie watch count: $e');
    }
  }
} 