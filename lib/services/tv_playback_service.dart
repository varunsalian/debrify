import 'dart:math';
import '../models/tv_channel.dart';
import '../models/tv_channel_torrent.dart';
import '../utils/file_utils.dart';
import 'debrid_service.dart';
import 'storage_service.dart';
import 'tv_service.dart';

class TVPlaybackService {
  static const int _maxRetryAttempts = 5;

  /// Attempts to play a random torrent from the channel
  static Future<Map<String, dynamic>?> playRandomTorrentFromChannel(
    TVChannel channel,
    List<TVChannelTorrent> torrents,
  ) async {
    print('🎬 [TVPlayback] Starting playback for channel: ${channel.name}');
    print('🎬 [TVPlayback] Available torrents: ${torrents.length}');
    
    if (torrents.isEmpty) {
      print('🎬 [TVPlayback] No torrents available for channel: ${channel.name}');
      throw Exception('No torrents available for this channel');
    }

    final apiKey = await StorageService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      print('🎬 [TVPlayback] No API key found');
      throw Exception('Real Debrid API key not configured');
    }
    print('🎬 [TVPlayback] API key found: ${apiKey.substring(0, 8)}...');

    // Shuffle torrents to get random order
    final shuffledTorrents = List<TVChannelTorrent>.from(torrents);
    shuffledTorrents.shuffle(Random());
    print('🎬 [TVPlayback] Shuffled ${shuffledTorrents.length} torrents for random selection');

    // Try each torrent until one works
    for (int attempt = 0; attempt < _maxRetryAttempts && attempt < shuffledTorrents.length; attempt++) {
      final torrent = shuffledTorrents[attempt];
      print('🎬 [TVPlayback] Attempt ${attempt + 1}: Trying torrent "${torrent.name}"');
      print('🎬 [TVPlayback] Torrent magnet: ${torrent.magnet.substring(0, 50)}...');
      
      try {
        final result = await attemptTorrentPlayback(torrent, apiKey);
        if (result != null) {
          print('🎬 [TVPlayback] Successfully found playable content on attempt ${attempt + 1}');
          // Record successful play
          await _recordSuccessfulPlay(channel, torrent);
          return result;
        }
        print('🎬 [TVPlayback] Attempt ${attempt + 1} failed - no playable content');
      } catch (e) {
        print('🎬 [TVPlayback] Attempt ${attempt + 1} failed with error: $e');
        // Record failed attempt
        await _recordFailedPlay(channel, torrent);
        continue; // Try next torrent
      }
    }

    print('🎬 [TVPlayback] All attempts failed - no playable content found');
    throw Exception('No playable content found after $_maxRetryAttempts attempts');
  }

  /// Attempts to play a specific torrent using Real Debrid
  static Future<Map<String, dynamic>?> attemptTorrentPlayback(
    TVChannelTorrent torrent,
    String apiKey,
  ) async {
    print('🎬 [TVPlayback] Attempting playback for torrent: ${torrent.name}');
    
    try {
      // First attempt: Try with "all videos" selection
      print('🎬 [TVPlayback] First attempt: Trying "all videos" selection');
      try {
        final result = await DebridService.addTorrentToDebrid(
          apiKey,
          torrent.magnet,
          tempFileSelection: 'video',
        );
        
        print('🎬 [TVPlayback] "All videos" result: ${result != null ? 'SUCCESS' : 'NULL'}');
        if (result != null) {
          print('🎬 [TVPlayback] Download link: ${result['downloadLink']}');
          print('🎬 [TVPlayback] Files count: ${result['files']?.length ?? 0}');
        }
        
        // Verify we got a video file
        if (_isPlayableVideoResult(result)) {
          print('🎬 [TVPlayback] "All videos" attempt successful - playable video found');
          return result;
        } else {
          print('🎬 [TVPlayback] "All videos" attempt failed - not a playable video');
        }
      } catch (e) {
        print('🎬 [TVPlayback] "All videos" attempt failed with error: $e');
        // If "all videos" fails, try "largest file"
      }

      // Second attempt: Try with "largest file" selection
      print('🎬 [TVPlayback] Second attempt: Trying "largest file" selection');
      final result = await DebridService.addTorrentToDebrid(
        apiKey,
        torrent.magnet,
        tempFileSelection: 'largest',
      );

      print('🎬 [TVPlayback] "Largest file" result: ${result != null ? 'SUCCESS' : 'NULL'}');
      if (result != null) {
        print('🎬 [TVPlayback] Download link: ${result['downloadLink']}');
        print('🎬 [TVPlayback] Files count: ${result['files']?.length ?? 0}');
      }

      // Verify it's actually a video file
      if (_isPlayableVideoResult(result)) {
        print('🎬 [TVPlayback] "Largest file" attempt successful - playable video found');
        return result;
      } else {
        print('🎬 [TVPlayback] "Largest file" attempt failed - not a playable video');
      }

      // If we get here, the file is not playable
      print('🎬 [TVPlayback] Both attempts failed - no playable video content');
      return null;
    } catch (e) {
      print('🎬 [TVPlayback] attemptTorrentPlayback failed with error: $e');
      throw Exception('Failed to process torrent: ${e.toString()}');
    }
  }

  /// Checks if the Real Debrid result contains playable video content
  static bool _isPlayableVideoResult(Map<String, dynamic> result) {
    print('🎬 [TVPlayback] Checking if result is playable video...');
    
    final downloadLink = result['downloadLink'] as String?;
    if (downloadLink == null || downloadLink.isEmpty) {
      print('🎬 [TVPlayback] No download link found');
      return false;
    }
    print('🎬 [TVPlayback] Download link found: ${downloadLink.substring(0, 50)}...');

    // Check if we have multiple files (playlist)
    final links = result['links'] as List<dynamic>?;
    if (links != null && links.length > 1) {
      print('🎬 [TVPlayback] Multiple files detected (${links.length}) - assuming video playlist');
      // Multiple files - assume it's a video playlist
      return true;
    }

    // Single file - check MIME type
    final files = result['files'] as List<dynamic>?;
    print('🎬 [TVPlayback] Files array: $files');
    if (files != null && files.isNotEmpty) {
      final file = files[0];
      print('🎬 [TVPlayback] First file object: $file');
      print('🎬 [TVPlayback] Single file detected: ${file['name']}');
      final fileName = file['name'] as String?;
      
      if (fileName != null && FileUtils.isVideoFile(fileName)) {
        print('🎬 [TVPlayback] File is confirmed as video: $fileName');
        return true;
      } else {
        print('🎬 [TVPlayback] File is not a video: $fileName');
      }
    } else {
      print('🎬 [TVPlayback] No files array or empty files array');
    }

    // Check if the download link itself indicates a video file
    if (downloadLink.isNotEmpty) {
      final urlParts = downloadLink.split('/');
      final fileName = urlParts.isNotEmpty ? urlParts.last : '';
      print('🎬 [TVPlayback] Download link filename: $fileName');
      if (fileName.isNotEmpty && FileUtils.isVideoFile(fileName)) {
        print('🎬 [TVPlayback] Download link filename is video: $fileName');
        return true;
      } else {
        print('🎬 [TVPlayback] Download link filename is not a video: $fileName');
      }
    }

    // If we can't determine from files, assume it's playable
    // (Real Debrid should have filtered appropriately)
    print('🎬 [TVPlayback] Assuming file is playable (Real Debrid filtered)');
    return true;
  }

  /// Records a successful playback attempt
  static Future<void> _recordSuccessfulPlay(TVChannel channel, TVChannelTorrent torrent) async {
    try {
      final channels = await TVService.getChannels();
      final channelIndex = channels.indexWhere((c) => c.id == channel.id);
      
      if (channelIndex != -1) {
        final updatedChannel = channels[channelIndex].copyWith(
          lastPlayedAt: DateTime.now(),
          lastPlayedTorrentId: torrent.id,
        );
        
        // Add to playable torrents if not already there
        final playableTorrentIds = List<String>.from(updatedChannel.playableTorrentIds ?? []);
        if (!playableTorrentIds.contains(torrent.id)) {
          playableTorrentIds.add(torrent.id);
        }
        
        final finalChannel = updatedChannel.copyWith(
          playableTorrentIds: playableTorrentIds,
          playSuccessCount: (updatedChannel.playSuccessCount ?? 0) + 1,
        );
        
        await TVService.updateChannel(finalChannel);
      }
    } catch (e) {
      // Silently fail - this is not critical functionality
    }
  }

  /// Records a failed playback attempt
  static Future<void> _recordFailedPlay(TVChannel channel, TVChannelTorrent torrent) async {
    try {
      final channels = await TVService.getChannels();
      final channelIndex = channels.indexWhere((c) => c.id == channel.id);
      
      if (channelIndex != -1) {
        final updatedChannel = channels[channelIndex].copyWith(
          playFailureCount: (channels[channelIndex].playFailureCount ?? 0) + 1,
        );
        
        // Add to failed torrents if not already there
        final failedTorrentIds = List<String>.from(updatedChannel.failedTorrentIds ?? []);
        if (!failedTorrentIds.contains(torrent.id)) {
          failedTorrentIds.add(torrent.id);
        }
        
        final finalChannel = updatedChannel.copyWith(
          failedTorrentIds: failedTorrentIds,
        );
        
        await TVService.updateChannel(finalChannel);
      }
    } catch (e) {
      // Silently fail - this is not critical functionality
    }
  }

  /// Gets a random torrent from the channel, prioritizing known working ones
  static TVChannelTorrent getRandomTorrent(
    TVChannel channel,
    List<TVChannelTorrent> torrents,
  ) {
    if (torrents.isEmpty) {
      throw Exception('No torrents available');
    }

    // First, try to find known playable torrents
    final playableTorrentIds = channel.playableTorrentIds ?? [];
    final playableTorrents = torrents.where((t) => playableTorrentIds.contains(t.id)).toList();
    
    if (playableTorrents.isNotEmpty) {
      return playableTorrents[Random().nextInt(playableTorrents.length)];
    }

    // If no known playable torrents, avoid known failed ones
    final failedTorrentIds = channel.failedTorrentIds ?? [];
    final availableTorrents = torrents.where((t) => !failedTorrentIds.contains(t.id)).toList();
    
    if (availableTorrents.isNotEmpty) {
      return availableTorrents[Random().nextInt(availableTorrents.length)];
    }

    // If all torrents have failed, just pick a random one
    return torrents[Random().nextInt(torrents.length)];
  }
} 