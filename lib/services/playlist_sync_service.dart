import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dropbox_service.dart';
import 'dropbox_auth_service.dart';
import 'storage_service.dart';

class PlaylistSyncService {
  static const String _remoteFileName = 'playlist_data.json';
  static const String _syncStatusKey = 'playlist_sync_status';
  static const String _lastSyncTimeKey = 'playlist_last_sync';

  /// Check if Dropbox is connected and ready for sync
  static Future<bool> isConnected() async {
    return await DropboxAuthService.isConnected();
  }

  /// Upload local playlist to Dropbox (merge with remote)
  static Future<bool> uploadPlaylist() async {
    try {
      debugPrint('🔄 Starting playlist upload to Dropbox...');
      
      // Get local playlist data
      final localItems = await StorageService.getPlaylistItemsRaw();
      debugPrint('📤 Local playlist has ${localItems.length} items');
      
      // Try to download existing remote playlist
      List<Map<String, dynamic>> remoteItems = [];
      final downloadResult = await DropboxService.downloadFile(_remoteFileName);
      
      if (downloadResult.success && downloadResult.content != null) {
        try {
          final List<dynamic> parsedRemote = jsonDecode(downloadResult.content!);
          remoteItems = parsedRemote
              .whereType<Map<String, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          debugPrint('📥 Remote playlist has ${remoteItems.length} items');
        } catch (e) {
          debugPrint('⚠️ Invalid remote playlist JSON, treating as empty: $e');
          remoteItems = [];
        }
      } else {
        debugPrint('📥 No existing remote playlist found (first time sync)');
      }
      
      // Merge playlists using deduplication key
      final mergedItems = await _mergePlaylists(localItems, remoteItems);
      debugPrint('🔄 Merged playlist has ${mergedItems.length} items');
      
      // Upload merged data to Dropbox
      final jsonData = jsonEncode(mergedItems);
      final uploadResult = await DropboxService.uploadStringContent(
        jsonData, 
        _remoteFileName
      );
      
      if (uploadResult.success) {
        // Update sync status
        await _updateSyncStatus(true, DateTime.now());
        debugPrint('✅ Playlist uploaded successfully');
        return true;
      } else {
        await _updateSyncStatus(false, DateTime.now(), uploadResult.error);
        debugPrint('❌ Playlist upload failed: ${uploadResult.error}');
        return false;
      }
    } catch (e) {
      await _updateSyncStatus(false, DateTime.now(), e.toString());
      debugPrint('❌ Playlist upload error: $e');
      return false;
    }
  }

  /// Download playlist from Dropbox and replace local data
  static Future<bool> downloadPlaylist() async {
    try {
      debugPrint('🔄 Starting playlist download from Dropbox...');
      
      // Download from Dropbox
      final downloadResult = await DropboxService.downloadFile(_remoteFileName);
      
      if (downloadResult.success && downloadResult.content != null) {
        // Parse and validate JSON
        final List<dynamic> remoteItems;
        try {
          remoteItems = jsonDecode(downloadResult.content!);
        } catch (e) {
          debugPrint('❌ Invalid JSON from Dropbox: $e');
          await _updateSyncStatus(false, DateTime.now(), 'Invalid playlist data');
          return false;
        }
        
        // Convert to proper format
        final List<Map<String, dynamic>> playlistItems = remoteItems
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        
        // Replace local playlist with remote data
        await StorageService.savePlaylistItemsRaw(playlistItems);
        
        // Update sync status
        await _updateSyncStatus(true, DateTime.now());
        debugPrint('✅ Playlist downloaded successfully (${playlistItems.length} items)');
        return true;
      } else {
        await _updateSyncStatus(false, DateTime.now(), downloadResult.error);
        debugPrint('❌ Playlist download failed: ${downloadResult.error}');
        return false;
      }
    } catch (e) {
      await _updateSyncStatus(false, DateTime.now(), e.toString());
      debugPrint('❌ Playlist download error: $e');
      return false;
    }
  }

  /// Delete remote playlist data from Dropbox
  static Future<bool> deleteRemotePlaylist() async {
    try {
      debugPrint('🗑️ Deleting remote playlist from Dropbox...');
      
      final deleteResult = await DropboxService.deleteFile(_remoteFileName);
      
      if (deleteResult.success) {
        await _updateSyncStatus(true, DateTime.now());
        debugPrint('✅ Remote playlist deleted successfully');
        return true;
      } else {
        await _updateSyncStatus(false, DateTime.now(), deleteResult.error);
        debugPrint('❌ Remote playlist deletion failed: ${deleteResult.error}');
        return false;
      }
    } catch (e) {
      await _updateSyncStatus(false, DateTime.now(), e.toString());
      debugPrint('❌ Remote playlist deletion error: $e');
      return false;
    }
  }

  /// Get current sync status
  static Future<PlaylistSyncStatus> getSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isSuccess = prefs.getBool(_syncStatusKey) ?? false;
    final lastSyncTime = prefs.getInt(_lastSyncTimeKey);
    final errorMessage = prefs.getString('${_syncStatusKey}_error');
    
    return PlaylistSyncStatus(
      isSuccess: isSuccess,
      lastSyncTime: lastSyncTime != null ? DateTime.fromMillisecondsSinceEpoch(lastSyncTime) : null,
      errorMessage: errorMessage,
    );
  }

  /// Clear sync status (used when disconnecting)
  static Future<void> clearSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_syncStatusKey);
    await prefs.remove(_lastSyncTimeKey);
    await prefs.remove('${_syncStatusKey}_error');
  }

  /// Merge local and remote playlists using deduplication key
  static Future<List<Map<String, dynamic>>> _mergePlaylists(
    List<Map<String, dynamic>> localItems,
    List<Map<String, dynamic>> remoteItems,
  ) async {
    final Map<String, Map<String, dynamic>> mergedMap = {};
    
    // Add all remote items first (remote items take precedence for existing entries)
    for (final remoteItem in remoteItems) {
      final key = StorageService.computePlaylistDedupeKey(remoteItem);
      mergedMap[key] = remoteItem;
    }
    
    // Add local items that don't exist in remote (local wins for new entries)
    int localItemsAdded = 0;
    for (final localItem in localItems) {
      final key = StorageService.computePlaylistDedupeKey(localItem);
      if (!mergedMap.containsKey(key)) {
        mergedMap[key] = localItem;
        localItemsAdded++;
      }
    }
    
    debugPrint('🔄 Merge result: ${localItemsAdded} new local items added, ${mergedMap.length} total items');
    
    // Convert back to list and sort by addedAt (newest first)
    final mergedList = mergedMap.values.toList();
    mergedList.sort((a, b) {
      final aTime = a['addedAt'] as int? ?? 0;
      final bTime = b['addedAt'] as int? ?? 0;
      return bTime.compareTo(aTime); // Descending order (newest first)
    });
    
    return mergedList;
  }

  /// Update sync status in local storage
  static Future<void> _updateSyncStatus(bool success, DateTime timestamp, [String? error]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_syncStatusKey, success);
    await prefs.setInt(_lastSyncTimeKey, timestamp.millisecondsSinceEpoch);
    
    if (error != null) {
      await prefs.setString('${_syncStatusKey}_error', error);
    } else {
      await prefs.remove('${_syncStatusKey}_error');
    }
  }

  /// Get formatted last sync time string
  static String getLastSyncTimeString(DateTime? lastSync) {
    if (lastSync == null) return 'Never';
    
    final now = DateTime.now();
    final difference = now.difference(lastSync);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Sync status information
class PlaylistSyncStatus {
  final bool isSuccess;
  final DateTime? lastSyncTime;
  final String? errorMessage;

  PlaylistSyncStatus({
    required this.isSuccess,
    this.lastSyncTime,
    this.errorMessage,
  });

  String get statusText {
    if (!isSuccess && errorMessage != null) {
      return 'Sync Error';
    } else if (lastSyncTime != null) {
      return 'Last synced ${PlaylistSyncService.getLastSyncTimeString(lastSyncTime)}';
    } else {
      return 'Not synced';
    }
  }
}
