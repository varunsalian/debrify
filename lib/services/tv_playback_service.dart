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

      // Select a random torrent stream
      final randomStream = selectedMovie.torrentioStreams[
        random.nextInt(selectedMovie.torrentioStreams.length)
      ];
      
      print('DEBUG: Selected random stream: ${randomStream.title}');

      // Get Real-Debrid API key
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Real-Debrid API key not configured');
      }

      // Create magnet link from infoHash
      final magnetLink = 'magnet:?xt=urn:btih:${randomStream.infoHash}';
      
      print('DEBUG: Processing magnet link: $magnetLink');

      // Try to get download link from Real-Debrid
      final result = await _getDownloadLinkFromDebrid(
        apiKey, 
        magnetLink, 
        randomStream,
        freshHub.quality,
      );

      if (result != null) {
        // Increment the watch count immediately after successful selection
        await incrementMovieWatchCount(freshHub.id, selectedMovie.id);
        
        return {
          'videoUrl': result['downloadLink'],
          'title': selectedMovie.name,
          'subtitle': '${selectedMovie.year ?? ''} • ${randomStream.title}',
          'movie': selectedMovie,
          'stream': randomStream,
        };
      } else {
        throw Exception('Failed to get download link from Real-Debrid');
      }

    } catch (e) {
      print('DEBUG: Error in playRandomMovieFromHub: $e');
      rethrow;
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

      // Strategy 3: Try "All files" selection as last resort
      print('DEBUG: Trying "All files" selection...');
      try {
        final result = await DebridService.addTorrentToDebrid(
          apiKey, 
          magnetLink, 
          tempFileSelection: 'all',
        );
        
        if (result['downloadLink'] != null) {
          print('DEBUG: Success with "All files" selection');
          return result;
        }
      } catch (e) {
        print('DEBUG: "All files" selection failed: $e');
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