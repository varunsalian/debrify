import 'dart:math';
import 'package:flutter/material.dart';
import '../models/channel_hub.dart';
import '../models/movie_torrentio_stream.dart';
import '../services/debrid_service.dart';
import '../services/storage_service.dart';

class TVPlaybackService {
  /// Selects a random movie from a channel hub and plays it
  static Future<Map<String, dynamic>?> playRandomMovieFromHub(
    BuildContext context,
    ChannelHub hub,
  ) async {
    try {
      // Check if hub has movies
      if (hub.movies.isEmpty) {
        throw Exception('No movies available in this channel hub');
      }

      // Select a random movie
      final random = Random();
      final randomMovie = hub.movies[random.nextInt(hub.movies.length)];
      
      print('DEBUG: Selected random movie: ${randomMovie.name}');

      // Check if movie has Torrentio streams
      if (!randomMovie.hasTorrentioData || randomMovie.torrentioStreams.isEmpty) {
        throw Exception('No streaming data available for ${randomMovie.name}');
      }

      // Select a random torrent stream
      final randomStream = randomMovie.torrentioStreams[
        random.nextInt(randomMovie.torrentioStreams.length)
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
        hub.quality,
      );

      if (result != null) {
        return {
          'videoUrl': result['downloadLink'],
          'title': randomMovie.name,
          'subtitle': '${randomMovie.year ?? ''} • ${randomStream.title}',
          'movie': randomMovie,
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
} 