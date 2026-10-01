import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:flutter/foundation.dart';

final class CompletionMigrationStorage {
  const CompletionMigrationStorage._();
  static const String _playbackCompletionMigrationGenerationKey = 'playback_completion_migration_generation';
  static const int _currentPlaybackCompletionMigrationGeneration = 1;
  static const String _resumeGhostPurgeGenerationKey = 'resume_ghost_purge_generation';
  static const int _currentResumeGhostPurgeGeneration = 1;

  /// Re-arms the resume-ghost purge for a restore/transfer preference overlay.
  ///
  /// A restore applies the package key-by-key over the destination profile, so
  /// a key the package does NOT carry keeps its destination value. A backup or
  /// device transfer taken on a pre-purge build carries `playback_state_v1`
  /// (ghosts and all) but no purge marker — so a destination that already ran
  /// the purge would keep `generation = 1` and never inspect the playback state
  /// it just imported, stranding those ghosts forever. Resetting the marker
  /// alongside imported playback lets the one-shot purge run once more against
  /// the new data.
  ///
  /// A package that DOES carry a marker came from a build that already purged
  /// at the source, so its value is honoured untouched.
  static void rearmGhostPurgeForImportedPlayback(
    Map<String, Object?> preferences,
  ) {
    if (!preferences.containsKey(PlaybackStateStore.playbackStateKey)) return;
    if (preferences.containsKey(_resumeGhostPurgeGenerationKey)) return;
    preferences[_resumeGhostPurgeGenerationKey] = 0;
  }

  /// One-time, per-profile purge of the resume "ghosts" older builds minted
  /// when an episode was unwatched.
  ///
  /// Until `EpisodeCompletionStorage._clearEpisodeCompletion` learned to drop the row, unwatching a
  /// fully-watched episode zeroed its `positionMs` and stamped `updatedAt` to
  /// now. The leftover row reads as "played, 0% in, not finished", which is the
  /// newest thing in the series — so it won `getLastPlayedEpisode*` and pinned
  /// Continue Watching (home card, detail pill, and Play alike) to an episode
  /// the user had just declared unwatched. Repeating mark→unmark to shake it
  /// loose only re-stamped it fresher.
  ///
  /// This runs ONCE rather than filtering on every read. A zero-position row is
  /// indistinguishable from an episode legitimately opened and closed before
  /// the first autosave tick, and permanently ignoring that shape would make a
  /// pack reopen the previous (already-watched) episode. Bounding the cleanup
  /// to one pass fixes the installs carrying a ghost — including ones that
  /// received it over a device transfer — while leaving normal playback
  /// bookkeeping exactly as it was.
  ///
  /// Rows marked in `finishedEpisodes` are kept: a mark-only watch stores the
  /// dummy 0ms/1ms shape and still means "watched".
  static Future<void> purgeUnwatchedResumeGhosts() async {
    final prefs = await ProfilePreferences.instance();
    final generation = prefs.getInt(_resumeGhostPurgeGenerationKey) ?? 0;
    if (generation >= _currentResumeGhostPurgeGeneration) return;

    final playback = await PlaybackStateStore.getPlaybackStateMap();
    var purged = 0;

    for (final stateEntry in playback.values) {
      if (stateEntry is! Map<String, dynamic> || stateEntry['type'] != 'series') {
        continue;
      }
      final seasons = stateEntry['seasons'];
      if (seasons is! Map) continue;
      final finishedEpisodes = stateEntry['finishedEpisodes'];

      for (final seasonKey in seasons.keys.toList()) {
        final episodes = seasons[seasonKey];
        if (episodes is! Map) continue;
        final seasonFinished = finishedEpisodes is Map ? finishedEpisodes[seasonKey] : null;

        for (final episodeKey in episodes.keys.toList()) {
          final episodeData = episodes[episodeKey];
          if (episodeData is! Map) continue;
          if (seasonFinished is Map && seasonFinished.containsKey(episodeKey)) {
            continue;
          }
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          // durationMs > 1 skips the mark-only dummy shape, which is already
          // excluded above whenever its completion record survived.
          if (positionMs == 0 && durationMs > 1) {
            episodes.remove(episodeKey);
            purged++;
          }
        }
        if (episodes.isEmpty) seasons.remove(seasonKey);
      }
    }

    if (purged > 0) {
      await PlaybackStateStore.savePlaybackStateMap(playback, recordDeletions: true);
      LocalCompletionStorage.localCompletionRevision.value++;
      debugPrint(
        'StorageService: purged $purged unwatched resume ghost(s) from playback state',
      );
    }
    await prefs.setInt(
      _resumeGhostPurgeGenerationKey,
      _currentResumeGhostPurgeGeneration,
    );
  }

  /// One-time, per-profile adoption of the local completion thresholds for
  /// playback recorded before threshold-based watched status existed.
  ///
  /// Movies at/above their threshold become locally finished and leave local
  /// Continue Watching. Series episodes at/above their threshold are folded
  /// into the existing `finishedEpisodes` structure used by episode ticks.
  /// Tracker data is deliberately untouched; this migration only rewrites the
  /// app's local playback state.
  static Future<void> migrateExistingPlaybackCompletionThresholds() async {
    final prefs = await ProfilePreferences.instance();
    final generation = prefs.getInt(_playbackCompletionMigrationGenerationKey) ?? 0;
    if (generation >= _currentPlaybackCompletionMigrationGeneration) return;

    final movieThreshold = await LocalCompletionStorage.getMovieCompletionThreshold();
    final episodeThreshold = await LocalCompletionStorage.getEpisodeCompletionThreshold();
    final playback = await PlaybackStateStore.getPlaybackStateMap();
    final completedMovieIds = await MovieProgressStorage.getFinishedMovieIdsInternal();
    final newlyCompletedMovieIds = <String>{};
    final completedMovieStateKeys = <String>{};
    final completedMovieResumeKeys = <String>{};
    var completedEpisodeCount = 0;
    var playbackChanged = false;

    for (final stateEntry in playback.entries) {
      final rawState = stateEntry.value;
      if (rawState is! Map<String, dynamic>) continue;

      if (rawState['type'] == 'video') {
        final imdbId = (rawState['imdbId'] as String?)?.trim().toLowerCase();
        final positionMs = (rawState['positionMs'] as num?)?.toInt() ?? 0;
        final durationMs = (rawState['durationMs'] as num?)?.toInt() ?? 0;
        if (imdbId == null ||
            imdbId.isEmpty ||
            durationMs <= 0 ||
            positionMs <= 0 ||
            positionMs * 100.0 / durationMs < movieThreshold) {
          continue;
        }
        completedMovieIds.add(imdbId);
        newlyCompletedMovieIds.add(imdbId);
        continue;
      }

      if (rawState['type'] != 'series') continue;
      final seasons = rawState['seasons'];
      if (seasons is! Map<String, dynamic>) continue;
      final finishedEpisodes = rawState['finishedEpisodes'] is Map
          ? Map<String, dynamic>.from(rawState['finishedEpisodes'] as Map)
          : <String, dynamic>{};

      for (final seasonEntry in seasons.entries) {
        final episodesRaw = seasonEntry.value;
        if (episodesRaw is! Map) continue;
        final seasonFinished = finishedEpisodes[seasonEntry.key] is Map
            ? Map<String, dynamic>.from(
                finishedEpisodes[seasonEntry.key] as Map,
              )
            : <String, dynamic>{};

        for (final episodeEntry in episodesRaw.entries) {
          if (episodeEntry.value is! Map) continue;
          final episodeData = Map<String, dynamic>.from(
            episodeEntry.value as Map,
          );
          final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
          if (durationMs <= 0 ||
              positionMs <= 0 ||
              positionMs * 100.0 / durationMs < episodeThreshold ||
              seasonFinished.containsKey(episodeEntry.key)) {
            continue;
          }

          seasonFinished[episodeEntry.key.toString()] = {
            'finishedAt': (episodeData['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
          };
          // Keep the episode's historical updatedAt so migration does not
          // reorder a show's "last played" episode.
          episodeData['positionMs'] = durationMs;
          episodesRaw[episodeEntry.key] = episodeData;
          completedEpisodeCount++;
          playbackChanged = true;
        }

        if (seasonFinished.isNotEmpty) {
          finishedEpisodes[seasonEntry.key] = seasonFinished;
        }
      }
      rawState['finishedEpisodes'] = finishedEpisodes;
    }

    if (newlyCompletedMovieIds.isNotEmpty) {
      for (final stateEntry in playback.entries) {
        final state = stateEntry.value;
        if (state is! Map<String, dynamic> || state['type'] != 'video') {
          continue;
        }
        final imdbId = (state['imdbId'] as String?)?.trim().toLowerCase();
        if (imdbId != null && newlyCompletedMovieIds.contains(imdbId)) {
          completedMovieStateKeys.add(stateEntry.key);
          final resumeKey = (state['title'] as String?)?.trim();
          if (resumeKey != null && resumeKey.isNotEmpty) {
            completedMovieResumeKeys.add(resumeKey);
          }
        }
      }
      playback.removeWhere((key, _) => completedMovieStateKeys.contains(key));
      playbackChanged = true;
      await prefs.setStringList(
        MovieProgressStorage.finishedMoviesKey,
        completedMovieIds.toList()..sort(),
      );
      LocalCompletionStorage.localCompletionRevision.value++;

      final rawContinueWatching = prefs.getString(ContinueWatchingStorage.continueWatchingKey);
      if (rawContinueWatching != null && rawContinueWatching.isNotEmpty) {
        try {
          final decoded = await decodeJsonAsync(rawContinueWatching);
          if (decoded is List) {
            final items = decoded.whereType<Map<String, dynamic>>().map(Map<String, dynamic>.from).where((item) {
              final imdbId = (item['imdbId'] as String?)?.trim().toLowerCase();
              return imdbId == null || !newlyCompletedMovieIds.contains(imdbId);
            }).toList();
            await ContinueWatchingStorage.saveContinueWatchingItems(items);
          }
        } catch (_) {
          // Leave malformed legacy data untouched; the normal CW reader also
          // treats it as empty, and completion migration can still succeed.
        }
      }
    }

    // The older player resume store uses the playback state's title as its
    // key. Clear it as part of the same migration so a later rewatch cannot
    // resurrect a near-credits position after the enhanced state is removed.
    // Do this before saving the removal so a database failure leaves enough
    // playback metadata for the next startup to retry the cleanup.
    for (final resumeKey in completedMovieResumeKeys) {
      await VideoResumeStorage.removeVideoResume(
        resumeKey,
        origin: WebDavSyncMutationOrigin.migration,
      );
    }
    if (playbackChanged) {
      await PlaybackStateStore.savePlaybackStateMap(playback, recordDeletions: true);
    }
    await prefs.setInt(
      _playbackCompletionMigrationGenerationKey,
      _currentPlaybackCompletionMigrationGeneration,
    );
    debugPrint(
      'StorageService: completion migration marked '
      '${newlyCompletedMovieIds.length} movies and '
      '$completedEpisodeCount episodes watched',
    );
  }
}
