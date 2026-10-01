import 'dart:convert';
import 'package:debrify/services/playlist_dedupe_key.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/playlist_poster_storage.dart';
import 'package:debrify/services/storage/playlist_preferences_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/tvmaze_mapping_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final class PlaylistStorage {
  const PlaylistStorage._();

  static const String _playlistKey = 'user_playlist_v1';

  // Playlist storage (local-only MVP)
  static Future<List<Map<String, dynamic>>> getPlaylistItemsRaw() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playlistKey);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      return list.whereType<Map<String, dynamic>>().map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> savePlaylistItemsRaw(
    List<Map<String, dynamic>> items, {
    bool recordSyncDeletions = true,
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return;
    final prefs = await ProfilePreferences.instance();
    if (canContinue?.call() == false) return;
    if (recordSyncDeletions) {
      final previous = await getPlaylistItemsRaw();
      if (canContinue?.call() == false) return;
      final retained = items.map(computePlaylistDedupeKey).toSet();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(computePlaylistDedupeKey)
            .where((key) => !retained.contains(key))
            .map(WebDavSyncRecordKey.playlistItem),
      );
    }
    await prefs.setString(
      _playlistKey,
      jsonEncode(items),
      canCommit: canContinue,
    );
  }

  static String computePlaylistDedupeKey(Map<String, dynamic> item) => PlaylistDedupeKey.compute(item);

  /// Add a new playlist item if it does not already exist.
  /// Expected item shape (MVP): { url, title, restrictedLink, rdTorrentId }
  /// Returns true if inserted, false if duplicate.
  static Future<bool> addPlaylistItemRaw(
    Map<String, dynamic> item, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final items = await getPlaylistItemsRaw();
    if (canContinue?.call() == false) return false;
    final initialKey = computePlaylistDedupeKey(item);
    debugPrint('Playlist dedupe: initialKey=$initialKey');
    for (final existing in items) {
      final existingKey = computePlaylistDedupeKey(existing);
      final existingProvider = (existing['provider'] as String?) ?? 'unknown';
      debugPrint(
        'Playlist dedupe: existingKey=$existingKey provider=$existingProvider',
      );
    }
    final initialExists = items.any(
      (entry) => computePlaylistDedupeKey(entry) == initialKey,
    );
    if (initialExists) {
      debugPrint('Playlist dedupe: blocked by initial key match');
      return false;
    }

    final enriched = Map<String, dynamic>.from(item);
    enriched['addedAt'] = DateTime.now().millisecondsSinceEpoch;
    enriched['provider'] = ((item['provider'] as String?)?.isNotEmpty ?? false) ? item['provider'] : 'realdebrid';

    final bool isTorbox = (enriched['provider'] as String?)?.toLowerCase() == 'torbox';

    // Fetch and add torrent hash if we have a torrent ID
    final String? rdTorrentId = item['rdTorrentId'] as String?;
    final String? apiKey = await RealDebridStorage.getApiKey(canContinue: canContinue);
    if (canContinue?.call() == false) return false;

    if (!isTorbox && rdTorrentId != null && rdTorrentId.isNotEmpty && apiKey != null && apiKey.isNotEmpty) {
      try {
        // Import DebridService here to avoid circular dependency
        final response = await http.get(
          Uri.parse(
            'https://api.real-debrid.com/rest/1.0/torrents/info/$rdTorrentId',
          ),
          headers: {'Authorization': 'Bearer $apiKey'},
        );

        if (canContinue?.call() == false) return false;
        if (response.statusCode == 200) {
          final torrentInfo = json.decode(response.body);
          final String? hash = torrentInfo['hash'] as String?;
          if (hash != null && hash.isNotEmpty) {
            enriched['torrent_hash'] = hash;
            debugPrint(
              '✅ Torrent hash fetched and stored: $hash for torrent ID: $rdTorrentId',
            );
          } else {
            debugPrint(
              '⚠️ No hash found in torrent info for torrent ID: $rdTorrentId',
            );
          }
        } else {
          debugPrint(
            '❌ Failed to fetch torrent info. Status code: ${response.statusCode} for torrent ID: $rdTorrentId',
          );
        }
      } catch (e) {
        debugPrint(
          '❌ Error fetching torrent hash for torrent ID: $rdTorrentId - $e',
        );
        // Silently continue without hash if fetch fails
        // This ensures playlist addition doesn't fail due to hash fetch issues
      }
    } else {
      debugPrint(
        'ℹ️ Skipping torrent hash fetch - missing rdTorrentId or API key',
      );
    }

    // Log what's being saved to database
    debugPrint('📝 Adding playlist item to database:');
    debugPrint('   Title: ${enriched['title']}');
    debugPrint('   Kind: ${enriched['kind']}');
    debugPrint('   rdTorrentId: ${enriched['rdTorrentId']}');
    debugPrint('   torrent_hash: ${enriched['torrent_hash'] ?? 'null'}');
    debugPrint('   restrictedLink: ${enriched['restrictedLink'] ?? 'null'}');
    debugPrint(
      '   addedAt: ${DateTime.fromMillisecondsSinceEpoch(enriched['addedAt']).toIso8601String()}',
    );

    final finalKey = computePlaylistDedupeKey(enriched);
    if (finalKey != initialKey) {
      final finalExists = items.any(
        (entry) => computePlaylistDedupeKey(entry) == finalKey,
      );
      if (finalExists) {
        debugPrint('Playlist dedupe: blocked by final key match ($finalKey)');
        return false;
      }
    }

    Future<bool> save() async {
      if (canContinue?.call() == false) return false;
      items.insert(0, enriched);
      await savePlaylistItemsRaw(items, canContinue: canContinue);
      return true;
    }

    if (canContinue == null) return save();
    // Recheck after waiting for sync/profile mutations, before any persisted
    // playlist or tombstone work. Existing unguarded callers retain their path.
    return ProfilePreferences.synchronizeExternalMutation(
      save,
      marksMutation: false,
    );
  }

  static Future<void> removePlaylistItemByKey(String dedupeKey) async {
    final items = await getPlaylistItemsRaw();
    items.removeWhere((e) => computePlaylistDedupeKey(e) == dedupeKey);
    await savePlaylistItemsRaw(items);
  }

  /// Update lastPlayedAt timestamp for a playlist item
  /// Call this when user starts playing a playlist item
  static Future<void> updatePlaylistItemLastPlayed(
    Map<String, dynamic> item,
  ) async {
    final items = await getPlaylistItemsRaw();
    final dedupeKey = computePlaylistDedupeKey(item);
    final index = items.indexWhere(
      (e) => computePlaylistDedupeKey(e) == dedupeKey,
    );

    if (index != -1) {
      items[index]['lastPlayedAt'] = DateTime.now().millisecondsSinceEpoch;
      await savePlaylistItemsRaw(items);
      debugPrint(
        'StorageService: Updated lastPlayedAt for "${items[index]['title']}"',
      );
    }
  }

  /// Get lastPlayedAt timestamp for a playlist item
  /// Returns null if item has never been played
  static int? getPlaylistItemLastPlayed(Map<String, dynamic> item) {
    return item['lastPlayedAt'] as int?;
  }

  static Future<void> clearPlaylist({bool recordSyncDeletions = true}) async {
    await savePlaylistItemsRaw(
      const <Map<String, dynamic>>[],
      recordSyncDeletions: recordSyncDeletions,
    );
  }

  /// Clear all playlist-related metadata (view modes, favorites, poster overrides)
  static Future<void> clearAllPlaylistMetadata({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordSyncDeletions) {
      final favorites = await PlaylistPreferencesStorage.getPlaylistFavoriteKeys();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        favorites.map(WebDavSyncRecordKey.playlistFavorite),
      );
    }
    await prefs.remove(PlaylistPreferencesStorage.playlistViewModesKey);
    await prefs.remove(PlaylistPreferencesStorage.playlistFavoritesKey);
    await prefs.remove(PlaylistPosterStorage.playlistPosterOverridesKey);
    await prefs.remove(TvMazeMappingStorage.tvMazeSeriesMappingKey);
  }
}
