import 'dart:convert';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/utils/json_isolate.dart';

final class PlaybackStateStore {
  const PlaybackStateStore._();
  // Shared within lib/services/storage/.
  static const String playbackStateKey = 'playback_state_v1';

  // Enhanced Playback State methods
  // Shared within lib/services/storage/.
  static Future<Map<String, dynamic>> getPlaybackStateMap() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(playbackStateKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  // Shared within lib/services/storage/.
  static Future<void> savePlaybackStateMap(
    Map<String, dynamic> map, {
    bool recordDeletions = false,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (recordDeletions &&
        (PlaybackRecoveryIntent.isSupported || await WebDavSyncTombstoneRecorder.shouldRecordForCurrentProfile())) {
      final previous = await getPlaybackStateMap();
      if (PlaybackRecoveryIntent.isSupported) {
        await PlaybackRecoveryIntent.record(
          _playbackRecoveryRecordKeys(
            previous,
          ).difference(_playbackRecoveryRecordKeys(map)),
        );
      }
      final retained = _webDavPlaybackRecordKeys(map);
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        _webDavPlaybackRecordKeys(previous).difference(retained),
      );
    }
    await prefs.setString(playbackStateKey, jsonEncode(map));
  }

  static Set<String> _playbackRecoveryRecordKeys(Map<String, dynamic> map) => {
    ..._webDavPlaybackRecordKeys(map),
    for (final entry in map.entries)
      if (entry.value is Map && entry.value['imdbId'] is String)
        ..._webDavPlaybackRecordKeys({
          'imdb:${(entry.value['imdbId'] as String).trim().toLowerCase()}': entry.value,
        }),
  };

  static Set<String> _webDavPlaybackRecordKeys(Map<String, dynamic> map) {
    final keys = <String>{};
    for (final entry in map.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final record = Map<String, dynamic>.from(value);
      final seasons = record['seasons'];
      final finished = record['finishedEpisodes'];
      if (seasons is Map || finished is Map || record['type'] == 'series') {
        keys.add(WebDavSyncRecordKey.playbackMeta(entry.key));
        void addEpisodes(Object? source, {required bool completion}) {
          if (source is! Map) return;
          for (final seasonEntry in source.entries) {
            final season = int.tryParse(seasonEntry.key.toString());
            if (season == null || season < 0 || seasonEntry.value is! Map) {
              continue;
            }
            for (final episodeEntry in (seasonEntry.value as Map).entries) {
              final episode = int.tryParse(episodeEntry.key.toString());
              if (episode == null || episode < 0 || episodeEntry.value is! Map) {
                continue;
              }
              keys.add(
                completion
                    ? WebDavSyncRecordKey.playbackFinished(
                        entry.key,
                        season,
                        episode,
                      )
                    : WebDavSyncRecordKey.playbackEpisode(
                        entry.key,
                        season,
                        episode,
                      ),
              );
            }
          }
        }

        addEpisodes(seasons, completion: false);
        addEpisodes(finished, completion: true);
      } else {
        keys.add(WebDavSyncRecordKey.playback(entry.key));
      }
    }
    return keys;
  }
}
