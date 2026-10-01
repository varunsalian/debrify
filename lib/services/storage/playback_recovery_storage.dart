import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';

final class PlaybackRecoveryStorage {
  const PlaybackRecoveryStorage._();

  /// Deletions and sync intent fence every replay. Cold recovery also checks
  /// local position timestamps; a proven return can finish an interrupted
  /// normal save whose position was written just after its native snapshot.
  static Future<bool> hasNewerPlaybackRecoveryIntent({
    String? seriesTitle,
    int? season,
    int? episode,
    String? imdbId,
    String? resumeId,
    required int checkpointAtMs,
    bool includePositions = true,
    bool includeSyncedPositions = true,
    bool Function(Map<String, dynamic>)? isOwnRecoveryWrite,
    bool Function(Map<String, dynamic>)? matchesRecoveryPosition,
  }) async {
    String alias(String type, String title) => '${type}_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final stableId = imdbId?.trim().toLowerCase();
    final keys = <String>{};
    final ownRecoveryKeys = <String>{};
    bool newerPosition(Object? value, String key) {
      if (value is! Map) return false;
      final state = Map<String, dynamic>.from(value);
      if (isOwnRecoveryWrite?.call(state) ?? false) {
        ownRecoveryKeys.add(key);
        return false;
      }
      return includePositions && (state['updatedAt'] as num? ?? 0) >= checkpointAtMs;
    }

    final seriesAliases = <String>{
      if (seriesTitle != null) PlaybackIdentityStorage.seriesProgressKey(seriesTitle, stableId),
    };
    final videoAliases = <String>{
      if (resumeId != null)
        PlaybackIdentityStorage.requiresExactProgressIdentity(stableId)
            ? 'video_${stableId}_${resumeId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
            : alias('video', resumeId),
    };
    if (stableId != null && stableId.isNotEmpty) {
      if (seriesTitle == null) {
        keys.add(WebDavSyncRecordKey.finishedMovie(stableId));
        keys.add(WebDavSyncRecordKey.playback('imdb:$stableId'));
      }
      for (final entry in map.entries) {
        final value = entry.value;
        if (value is! Map || value['imdbId']?.toString().trim().toLowerCase() != stableId) {
          continue;
        }
        if (value['type'] == 'series' && seriesTitle != null) {
          seriesAliases.add(entry.key);
        } else if (value['type'] == 'video' && seriesTitle == null) {
          videoAliases.add(entry.key);
        }
      }
    }
    for (final key in seriesAliases) {
      if (season == null || episode == null) continue;
      keys.addAll({
        WebDavSyncRecordKey.playbackMeta(key),
        WebDavSyncRecordKey.playbackEpisode(key, season, episode),
        WebDavSyncRecordKey.playbackFinished(key, season, episode),
        if (stableId != null) ...{
          WebDavSyncRecordKey.playbackEpisode(
            'imdb:$stableId',
            season,
            episode,
          ),
          WebDavSyncRecordKey.playbackFinished(
            'imdb:$stableId',
            season,
            episode,
          ),
        },
      });
      final state = map[key]?['seasons']?[season.toString()]?[episode.toString()];
      if (newerPosition(
        state,
        WebDavSyncRecordKey.playbackEpisode(key, season, episode),
      )) {
        return true;
      }
    }
    for (final key in videoAliases) {
      keys.add(WebDavSyncRecordKey.playback(key));
      final state = map[key];
      if (newerPosition(state, WebDavSyncRecordKey.playback(key))) {
        return true;
      }
    }
    return await PlaybackRecoveryIntent.hasNewer(keys, checkpointAtMs) ||
        await WebDavSyncTombstoneRecorder.hasNewerPlaybackIntent(
          keys,
          checkpointAtMs,
          includePositions: includeSyncedPositions,
          isOwnRecoveryWrite: (key, payload) =>
              ownRecoveryKeys.contains(key) && (matchesRecoveryPosition?.call(payload) ?? false),
        );
  }
}
