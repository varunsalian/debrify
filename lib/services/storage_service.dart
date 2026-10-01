import 'dart:convert';
import 'package:debrify/models/media_identity.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/playback_recovery_intent.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/services/storage/playback_identity_storage.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

export '../models/home_preferences.dart';

class StorageService {
  static const String _explicitlyWatchedSeriesKey =
      'explicitly_watched_series_v1';

  /// Tracker/account watched-title invalidation. Kept separate from local
  /// playback so finishing an episode never reloads entire remote histories.
  static final ValueNotifier<int> movieFinishedRevision = ValueNotifier(0);

  /// Local movie, episode, and derived-series completion invalidation.
  static final ValueNotifier<int> localCompletionRevision = ValueNotifier(0);

  /// The tracker snapshots are each stored as one JSON object containing every
  /// show. Serializing their read/modify/write cycle prevents two concurrent
  /// show refreshes from both reading the same old object and dropping whichever
  /// write finishes first.
  static final Lock _episodeTrackerSnapshotWriteLock = Lock(); // granted|denied|never|unknown
  static const String _videoResumeKey = 'video_resume_v1';
  static const String _continueWatchingKey = 'continue_watching_v1';
  static const String localSeriesCompletionStateKey =
      'local_series_completion_v1';
  static const String localSeriesCalendarCheckedAtKey =
      'local_series_completion_calendar_checked_at_v1';
  static const String localSeriesCalendarAttemptedAtKey =
      'local_series_completion_calendar_attempted_at_v1';
  static const String _finishedMoviesKey = 'finished_movies_v1';
  static const String _movieCompletionThresholdKey =
      'movie_completion_threshold';
  static const String _episodeCompletionThresholdKey =
      'episode_completion_threshold';
  static const String _playbackCompletionMigrationGenerationKey =
      'playback_completion_migration_generation';
  static const int _currentPlaybackCompletionMigrationGeneration = 1;
  static const String _resumeGhostPurgeGenerationKey =
      'resume_ghost_purge_generation';
  static const int _currentResumeGhostPurgeGeneration = 1;

  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 100% lets users
  /// require playback to reach the end.
  static const List<int> localCompletionThresholdOptions = <int>[
    50,
    60,
    70,
    75,
    80,
    85,
    90,
    95,
    100,
  ];
  static const int defaultLocalCompletionThreshold = 80;

  // ── Continue Watching (recently watched items for home screen) ──────────

  /// Get all continue watching items, sorted by most recent first.
  static Future<List<Map<String, dynamic>>> getContinueWatchingItems() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      for (final item in items) {
        final id = item['imdbId'];
        final type = item['contentType'];
        if (id is String && type is String) {
          item['imdbId'] = MediaIdentity.progressId(id, type);
        }
      }
      items.sort(
        (a, b) => ((b['updatedAt'] as int?) ?? 0).compareTo(
          (a['updatedAt'] as int?) ?? 0,
        ),
      );
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Add or update a continue watching entry.
  /// Deduplicates by IMDB ID — updates existing entry if found.
  static Future<void> saveContinueWatchingItem({
    required String imdbId,
    required String title,
    required String contentType,
    String? posterUrl,
    String? addonId,
    String? year,
  }) async {
    imdbId = MediaIdentity.progressId(imdbId, contentType);
    // Server-owned titles reopen through Discover, not catalog lookup.
    if (imdbId.startsWith('medialibrary:')) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    List<Map<String, dynamic>> items = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        final List<dynamic> list = await decodeJsonAsync(raw);
        items = list
            .whereType<Map<String, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {}
    }

    // Remove existing entry with same IMDB ID
    items.removeWhere((e) => MediaIdentity.progressId(
      e['imdbId'] as String? ?? '', e['contentType'] as String? ?? '',
    ) == imdbId);

    // Add at front
    items.insert(0, {
      'imdbId': imdbId,
      'title': title,
      'contentType': contentType,
      'posterUrl': posterUrl,
      'addonId': addonId,
      'year': year,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });

    // Keep max 50 items
    if (items.length > 50) items = items.sublist(0, 50);

    await _saveContinueWatchingItems(items, tombstoneRemovals: false);
  }

  /// Remove a continue watching entry by IMDB ID.
  static Future<void> removeContinueWatchingItem(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_continueWatchingKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final List<dynamic> list = await decodeJsonAsync(raw);
      final items = list
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final before = items.length;
      items.removeWhere(
        (e) => MediaIdentity.progressId(
          (e['imdbId'] as String? ?? '').trim().toLowerCase(),
          e['contentType'] as String? ?? '',
        ) == normalized,
      );
      if (items.length == before) return;
      await _saveContinueWatchingItems(items);
    } catch (_) {}
  }

  /// Clear all continue watching items.
  static Future<void> clearContinueWatching({
    bool recordSyncDeletions = true,
  }) async {
    await _saveContinueWatchingItems(
      const <Map<String, dynamic>>[],
      tombstoneRemovals: recordSyncDeletions,
    );
  }

  static Future<void> _saveContinueWatchingItems(
    List<Map<String, dynamic>> items, {
    bool tombstoneRemovals = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    if (tombstoneRemovals) {
      final previous = await getContinueWatchingItems();
      final retained = <String>{
        for (final item in items)
          if ((item['imdbId']?.toString().trim().toLowerCase() ?? '')
              .isNotEmpty)
            item['imdbId'].toString().trim().toLowerCase(),
      };
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        previous
            .map(
              (item) => item['imdbId']?.toString().trim().toLowerCase() ?? '',
            )
            .where((id) => id.isNotEmpty && !retained.contains(id))
            .map(WebDavSyncRecordKey.continueWatching),
      );
    }
    await prefs.setString(_continueWatchingKey, jsonEncode(items));
  }

  /// Movies finished locally by the Debrify player. This intentionally stays
  /// separate from Trakt and Simkl: tracker-backed sessions use the tracker as
  /// their source of truth, while offline/local sessions still need a durable
  /// completed state for the detail screen.
  static Future<Set<String>> _getFinishedMovieIds() async {
    final prefs = await ProfilePreferences.instance();
    final stored = prefs.getStringList(_finishedMoviesKey) ?? const <String>[];
    return {
      for (final raw in stored)
        if (raw.trim().isNotEmpty) MediaIdentity.progressId(raw.trim().toLowerCase(), 'movie'),
    };
  }

  /// Snapshot used by poster badges. Returned IDs are normalized lowercase.
  static Future<Set<String>> getFinishedMovieIds() => _getFinishedMovieIds();

  static Future<bool> isMovieFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return (await _getFinishedMovieIds()).contains(normalized);
  }

  /// Mark a locally tracked movie finished, remove it from Continue Watching,
  /// and clear its resumable state. The finished record itself remains so the
  /// detail action can accurately read "Rewatch".
  static Future<void> markMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (finished.add(normalized)) {
      final prefs = await ProfilePreferences.instance();
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
      localCompletionRevision.value++;
    }
    await Future.wait([
      removeContinueWatchingItem(normalized),
      clearPlaybackStateByImdbId(normalized),
    ]);
    debugPrint('StorageService: markMovieAsFinished imdbId="$normalized"');
  }

  /// Start a local rewatch. The caller saves a fresh resume point afterwards,
  /// so only the completed marker is removed here.
  static Future<void> unmarkMovieAsFinished(String imdbId) async {
    imdbId = MediaIdentity.progressId(imdbId, 'movie');
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final finished = await _getFinishedMovieIds();
    if (!finished.remove(normalized)) return;

    await PlaybackRecoveryIntent.record({
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
      WebDavSyncRecordKey.finishedMovie(normalized),
    });
    final prefs = await ProfilePreferences.instance();
    if (finished.isEmpty) {
      await prefs.remove(_finishedMoviesKey);
    } else {
      await prefs.setStringList(_finishedMoviesKey, finished.toList()..sort());
    }
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkMovieAsFinished imdbId="$normalized"');
  }

  static Future<Set<String>> getExplicitlyWatchedSeriesIds() async {
    final prefs = await ProfilePreferences.instance();
    return (prefs.getStringList(_explicitlyWatchedSeriesKey) ?? const [])
        .map((id) => id.trim().toLowerCase())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> setSeriesExplicitlyWatched(
    String imdbId, {
    required bool watched,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final ids = await getExplicitlyWatchedSeriesIds();
    final changed = watched ? ids.add(normalized) : ids.remove(normalized);
    if (!changed) return;
    if (!watched) {
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(<String>{
        WebDavSyncRecordKey.explicitlyWatchedSeries(normalized),
      });
    }
    final prefs = await ProfilePreferences.instance();
    if (ids.isEmpty) {
      await prefs.remove(_explicitlyWatchedSeriesKey);
    } else {
      await prefs.setStringList(
        _explicitlyWatchedSeriesKey,
        ids.toList()..sort(),
      );
    }
    localCompletionRevision.value++;
  }

  /// Remove all playback state entries (series progress, video progress) for an IMDB ID.
  static Future<void> clearPlaybackStateByImdbId(String imdbId) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final keysToRemove = <String>[];
    for (final entry in map.entries) {
      if (entry.value is Map<String, dynamic> &&
          (entry.value['imdbId'] as String?)?.trim().toLowerCase() ==
              normalized) {
        keysToRemove.add(entry.key);
      }
    }
    if (keysToRemove.isEmpty) return;
    for (final key in keysToRemove) {
      map.remove(key);
    }
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    // Series finished-episode markers share this map, so clearing a Continue
    // Watching item must also invalidate derived series completion.
    localCompletionRevision.value++;
    debugPrint(
      'StorageService: Cleared ${keysToRemove.length} playback state entries for "$imdbId"',
    );
  }

  /// Exact series reset; never touches source bindings or unrelated titles.
  static Future<void> clearSeriesWatchProgress(
    String imdbId,
    String title,
  ) async {
    final id = imdbId.trim().toLowerCase();
    if (id.isEmpty) throw ArgumentError.value(imdbId, 'imdbId');
    final map = await PlaybackStateStore.getPlaybackStateMap();
    map.removeWhere((key, raw) {
      if (raw is! Map) return false;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      return storedId == id ||
          (!PlaybackIdentityStorage.requiresExactProgressIdentity(id) && (storedId == null || storedId.isEmpty) &&
              raw['type'] == 'series' &&
              raw['title']?.toString().trim().toLowerCase() ==
                  title.trim().toLowerCase());
    });
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    await setSeriesExplicitlyWatched(id, watched: false);
    await saveEpisodeTraktProgress(imdbId: id, percents: {});
    await saveEpisodeSimklProgress(imdbId: id, percents: {});
    await saveEpisodeMdblistProgress(imdbId: id, percents: {});
    localCompletionRevision.value++;
  }

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
    String alias(String type, String title) =>
        '${type}_${title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
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
      return includePositions &&
          (state['updatedAt'] as num? ?? 0) >= checkpointAtMs;
    }

    final seriesAliases = <String>{
      if (seriesTitle != null) PlaybackIdentityStorage.seriesProgressKey(seriesTitle, stableId),
    };
    final videoAliases = <String>{
      if (resumeId != null) PlaybackIdentityStorage.requiresExactProgressIdentity(stableId)
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
        if (value is! Map ||
            value['imdbId']?.toString().trim().toLowerCase() != stableId) {
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
      final state =
          map[key]?['seasons']?[season.toString()]?[episode.toString()];
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
              ownRecoveryKeys.contains(key) &&
              (matchesRecoveryPosition?.call(payload) ?? false),
        );
  }

  static Future<void> saveSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {'type': 'series', 'title': seriesTitle, 'seasons': {}};
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided (enables lookup by IMDB ID)
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    seriesData['seasons'][season.toString()][episode.toString()] = {
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null)
        'recoveryCheckpointId': recoveryCheckpointId,
    };

    debugPrint(
      'StorageService: saveSeriesPlaybackState title="$seriesTitle" S${season}E$episode position=${positionMs}ms duration=${durationMs}ms',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Mark an episode as finished (watched completely)
  static Future<void> markEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
    int? recoveryUpdatedAtMs,
  }) async {
    // Recovery is a historical observation, not a new playback event. Both
    // records must keep its original time so the latest episode remains last.
    final completedAtMs =
        recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    if (!map.containsKey(key)) {
      map[key] = {
        'type': 'series',
        'title': seriesTitle,
        'seasons': {},
        'finishedEpisodes': {},
      };
    }

    final seriesData = map[key] as Map<String, dynamic>;

    // Store IMDB ID if provided
    if (imdbId != null && imdbId.isNotEmpty) {
      seriesData['imdbId'] = imdbId;
    }

    // Ensure seasons map exists
    if (!seriesData.containsKey('seasons')) {
      seriesData['seasons'] = {};
    }

    // Ensure finishedEpisodes map exists
    if (!seriesData.containsKey('finishedEpisodes')) {
      seriesData['finishedEpisodes'] = {};
    }

    if (!seriesData['finishedEpisodes'].containsKey(season.toString())) {
      seriesData['finishedEpisodes'][season.toString()] = {};
    }

    seriesData['finishedEpisodes'][season.toString()][episode.toString()] = {
      'finishedAt': completedAtMs,
    };

    // Also add/update in seasons map so it appears in getEpisodeProgress()
    // This ensures UI can find the episode even if it was never played
    if (!seriesData['seasons'].containsKey(season.toString())) {
      seriesData['seasons'][season.toString()] = {};
    }

    final episodeData =
        seriesData['seasons'][season.toString()][episode.toString()];

    if (episodeData == null) {
      // Episode was never played - add dummy data to mark as watched
      seriesData['seasons'][season.toString()][episode.toString()] = {
        'positionMs': 0,
        'durationMs': 1,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': completedAtMs,
      };
    } else {
      // Episode has existing progress - update it to show as finished
      // Set position = duration to show 100% progress
      final existingData = episodeData as Map<String, dynamic>;
      // A later rewatch can already be saved while the older watched marker
      // is still pending. Preserve that newer bookmark when filling the gap.
      if (recoveryUpdatedAtMs == null ||
          (existingData['updatedAt'] as num? ?? 0) <= completedAtMs) {
        final durationMs = existingData['durationMs'] as int? ?? 1;
        existingData['positionMs'] = durationMs; // Mark as fully watched
        existingData['updatedAt'] = completedAtMs;
        existingData.remove('recoveryCheckpointId');
      }
    }

    debugPrint(
      'StorageService: markEpisodeAsFinished title="$seriesTitle" S${season}E$episode',
    );

    await PlaybackStateStore.savePlaybackStateMap(map);
    localCompletionRevision.value++;
  }

  /// Unmark an episode as finished (mark as unwatched)
  static Future<void> unmarkEpisodeAsFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;
    var changed = false;
    var aliasesChanged = 0;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      if (_clearEpisodeCompletion(
        seriesData: seriesData,
        season: season,
        episode: episode,
      )) {
        changed = true;
        aliasesChanged++;
      }
    }

    if (!changed) return;

    debugPrint(
      'StorageService: unmarkEpisodeAsFinished title="$seriesTitle" '
      'S${season}E$episode aliases=$aliasesChanged',
    );

    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
  }

  /// Clear every completed episode owned by a stable series identity.
  ///
  /// This is the local equivalent of removing a show from tracker history.
  /// Synthetic watched rows and completed checkpoints are cleared across all
  /// release-title aliases, while genuine partial rewatch progress survives.
  static Future<void> unmarkSeriesAsFinished(
    String imdbId, {
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final normalizedTitle = seriesTitle?.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    var changed = false;

    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      final storedTitle = raw['title']?.toString().trim().toLowerCase();
      final matchesStableId = storedId == normalized;
      final matchesLegacyTitle =
          !PlaybackIdentityStorage.requiresExactProgressIdentity(normalized) &&
          !PlaybackIdentityStorage.requiresExactProgressIdentity(storedId) &&
          normalizedTitle != null &&
          normalizedTitle.isNotEmpty &&
          storedTitle == normalizedTitle;
      if (!matchesStableId && !matchesLegacyTitle) continue;

      final coordinates = <({int season, int episode})>{};
      void collect(Object? seasons) {
        if (seasons is! Map) return;
        for (final seasonEntry in seasons.entries) {
          final season = int.tryParse(seasonEntry.key.toString());
          final episodes = seasonEntry.value;
          if (season == null || episodes is! Map) continue;
          for (final episodeKey in episodes.keys) {
            final episode = int.tryParse(episodeKey.toString());
            if (episode != null) {
              coordinates.add((season: season, episode: episode));
            }
          }
        }
      }

      collect(raw['finishedEpisodes']);
      collect(raw['seasons']);
      for (final coordinate in coordinates) {
        if (_clearEpisodeCompletion(
          seriesData: raw,
          season: coordinate.season,
          episode: coordinate.episode,
        )) {
          changed = true;
        }
      }
    }

    if (!changed) return;
    await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    localCompletionRevision.value++;
    debugPrint('StorageService: unmarkSeriesAsFinished imdbId="$normalized"');
  }

  /// Remove one episode's explicit completion and any synthetic/completed
  /// progress produced by marking it watched. Genuine partial progress remains
  /// intact, including a rewatch in progress under another title alias.
  static bool _clearEpisodeCompletion({
    required Map<String, dynamic> seriesData,
    required int season,
    required int episode,
  }) {
    final seasonKey = season.toString();
    final episodeKey = episode.toString();
    var changed = false;

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes is Map) {
      final seasonData = finishedEpisodes[seasonKey];
      if (seasonData is Map && seasonData.containsKey(episodeKey)) {
        seasonData.remove(episodeKey);
        if (seasonData.isEmpty) finishedEpisodes.remove(seasonKey);
        changed = true;
      }
    }

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return changed;
    final seasonData = seasons[seasonKey];
    if (seasonData is! Map) return changed;
    final episodeData = seasonData[episodeKey];
    if (episodeData is! Map) return changed;

    final positionMs = (episodeData['positionMs'] as num?)?.toInt() ?? 0;
    final durationMs = (episodeData['durationMs'] as num?)?.toInt() ?? 0;
    final isDummy = positionMs == 0 && durationMs == 1;
    final isCompleted = durationMs > 0 && positionMs >= durationMs;
    // Unwatching a fully-watched episode DROPS its row. Zeroing the offset
    // instead used to leave a "played, 0% in, not finished" ghost carrying a
    // fresh updatedAt, which then won `getLastPlayedEpisode*` and pinned
    // Continue Watching to an episode the user had just declared unwatched —
    // and every repeat of mark→unmark re-stamped it fresher.
    if (isDummy || isCompleted) {
      seasonData.remove(episodeKey);
      if (seasonData.isEmpty) seasons.remove(seasonKey);
      return true;
    }
    // Reached only for rows that were never marked watched through
    // [markEpisodeAsFinished] (it overwrites positionMs with durationMs, so a
    // marked row always lands in the branch above). A genuine partial — e.g. a
    // rewatch in progress under another title alias, swept by
    // [unmarkSeriesAsFinished] — keeps its offset.
    return changed;
  }

  /// Check if an episode is marked as finished
  static Future<bool> isEpisodeFinished({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final currentTitleKey = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);
    final normalizedImdbId = imdbId?.trim().toLowerCase();
    final stableImdbId = normalizedImdbId == null || normalizedImdbId.isEmpty
        ? null
        : normalizedImdbId;

    for (final entry in map.entries) {
      final seriesData = entry.value;
      if (seriesData is! Map<String, dynamic> ||
          seriesData['type'] != 'series') {
        continue;
      }
      final matchesCurrentTitle = entry.key == currentTitleKey;
      final storedImdbId = seriesData['imdbId']
          ?.toString()
          .trim()
          .toLowerCase();
      final matchesStableId =
          stableImdbId != null && storedImdbId == stableImdbId;
      if (!matchesCurrentTitle && !matchesStableId) continue;

      final finishedEpisodes = seriesData['finishedEpisodes'];
      if (finishedEpisodes is! Map) continue;
      final seasonData = finishedEpisodes[season.toString()];
      if (seasonData is Map && seasonData.containsKey(episode.toString())) {
        return true;
      }
    }
    return false;
  }

  /// Get all finished episodes for a series
  static Future<Map<String, Set<int>>> getFinishedEpisodes({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final finishedEpisodes = seriesData['finishedEpisodes'];
    if (finishedEpisodes == null) return {};

    final result = <String, Set<int>>{};

    for (final seasonEntry in finishedEpisodes.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;
      result[season] = episodes.keys.map((e) => int.parse(e)).toSet();
    }

    return result;
  }

  /// Resolve finished episodes by stable title identity, falling back to the
  /// historical title-keyed record for installs created before IMDb IDs were
  /// persisted with series playback.
  static Future<Map<String, Set<int>>> getFinishedEpisodesByImdbId({
    required String imdbId,
    String? seriesTitle,
  }) async {
    final normalized = imdbId.trim().toLowerCase();
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Set<int>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final storedId = raw['imdbId']?.toString().trim().toLowerCase();
      if (storedId != normalized) continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      for (final entry in finished.entries) {
        final episodes = entry.value;
        if (episodes is! Map) continue;
        result.putIfAbsent(entry.key.toString(), () => <int>{}).addAll({
          for (final episode in episodes.keys)
            if (int.tryParse(episode.toString()) case final value?) value,
        });
      }
    }
    if (result.isNotEmpty) return result;
    if (!PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) && seriesTitle != null && seriesTitle.isNotEmpty) {
      // Only ID-less legacy records may provide title fallback. A matching
      // display title does not make another IMDb series the same show.
      final index = await getFinishedSeriesEpisodeIndex();
      return index['title:${seriesTitle.trim().toLowerCase()}'] ?? {};
    }
    return {};
  }

  /// One-pass index for derived series completion. IMDb keys are preferred;
  /// title keys preserve older playback records that predate stable IDs.
  static Future<Map<String, Map<String, Set<int>>>>
  getFinishedSeriesEpisodeIndex() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, Map<String, Set<int>>>{};
    for (final raw in map.values) {
      if (raw is! Map<String, dynamic> || raw['type'] != 'series') continue;
      final finished = raw['finishedEpisodes'];
      if (finished is! Map) continue;
      final parsed = <String, Set<int>>{
        for (final entry in finished.entries)
          entry.key.toString(): {
            if (entry.value is Map)
              for (final episode in (entry.value as Map).keys)
                if (int.tryParse(episode.toString()) case final value?) value,
          },
      };
      void mergeInto(String key) {
        final target = result.putIfAbsent(key, () => <String, Set<int>>{});
        for (final season in parsed.entries) {
          target.putIfAbsent(season.key, () => <int>{}).addAll(season.value);
        }
      }

      final imdbId = raw['imdbId']?.toString().trim().toLowerCase();
      if (imdbId != null && imdbId.isNotEmpty) {
        mergeInto(imdbId);
        continue;
      }
      final title = raw['title']?.toString().trim().toLowerCase();
      if (title != null && title.isNotEmpty) mergeInto('title:$title');
    }
    return result;
  }

  /// Get episode progress for a series
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgress({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return {};

    final seasons = seriesData['seasons'];
    if (seasons == null) return {};

    final result = <String, Map<String, dynamic>>{};

    for (final seasonEntry in seasons.entries) {
      final season = seasonEntry.key;
      final episodes = seasonEntry.value as Map<String, dynamic>;

      for (final episodeEntry in episodes.entries) {
        final episode = episodeEntry.key;
        final episodeData = episodeEntry.value as Map<String, dynamic>;
        final episodeKey = '${season}_$episode';
        result[episodeKey] = episodeData;
      }
    }

    return result;
  }

  // v2: keyed by IMDb id (stable, unambiguous) instead of the normalized series
  // title. Title-keying silently broke the playlist bars whenever the writer's
  // and readers' title derivations diverged; the seed and every reader always
  // have the show's IMDb id, so we key on that. Bumped from _v1 so stale
  // title-keyed data is dropped (it re-seeds on the next series launch).
  static const String _episodeTraktProgressKey = 'episode_trakt_progress_v2';

  /// Normalized storage key for the per-episode Trakt store (keyed by IMDb id).
  static String _episodeTraktKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Trakt playback progress per episode (percent, 0–100), kept
  /// SEPARATE from the ms-based resume state. It drives the playlist progress
  /// bars only — never a resume seek directly (the players convert % → ms at
  /// play time once the real duration is known, so we never store a fake
  /// position). Keyed by the show's IMDb id; episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeTraktProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeTraktProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Trakt per-episode percents for the show [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeTraktProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeTraktProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  // Kept separate from both local playback state and Trakt. This is a
  // replace-on-launch snapshot of Simkl's remote truth, so marking an episode
  // unwatched on Simkl can clear the player tick without mutating local
  // history.
  static const String _episodeSimklProgressKey = 'episode_simkl_progress_v1';

  static String _episodeSimklKeyFor(String imdbId) =>
      'imdb_${imdbId.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

  /// Cross-device Simkl progress per episode (percent, 0–100), keyed by the
  /// show's IMDb id. Episode keys are "season_episode".
  static Future<Map<String, double>> getEpisodeSimklProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeSimklProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeSimklKeyFor(imdbId)];
      if (series is! Map) return {};
      final out = <String, double>{};
      series.forEach((k, v) {
        final p = (v as num?)?.toDouble();
        if (p != null) out[k.toString()] = p;
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Replace the stored Simkl per-episode snapshot for [imdbId].
  /// [percents] is keyed by "season_episode".
  static Future<void> saveEpisodeSimklProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeSimklProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  static const String _episodeMdblistProgressKey =
      'episode_mdblist_progress_v1';

  static Future<Map<String, double>> getEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (imdbId.isEmpty) return {};
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_episodeMdblistProgressKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = await decodeJsonAsync(raw);
      if (decoded is! Map) return {};
      final series = decoded[_episodeTraktKeyFor(imdbId)];
      if (series is! Map) return {};
      return {
        for (final entry in series.entries)
          if (entry.value is num)
            entry.key.toString(): (entry.value as num).toDouble(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Player-facing read: never display a departed account's cached snapshot.
  static Future<Map<String, double>> getConnectedEpisodeMdblistProgress({
    required String imdbId,
  }) async {
    if (!await MdblistStorage.hasMdblistCredential()) return {};
    return getEpisodeMdblistProgress(imdbId: imdbId);
  }

  static Future<void> saveEpisodeMdblistProgress({
    required String imdbId,
    required Map<String, double> percents,
  }) => _saveEpisodeTrackerProgress(
    storeKey: _episodeMdblistProgressKey,
    imdbId: imdbId,
    percents: percents,
  );

  /// Replace one show's entry inside a provider's whole-store snapshot.
  /// Capture the originating profile before this operation queues so a profile
  /// switch cannot redirect a delayed write into the newly active profile.
  static Future<void> _saveEpisodeTrackerProgress({
    required String storeKey,
    required String imdbId,
    required Map<String, double> percents,
  }) {
    if (imdbId.isEmpty) return Future.value();
    final normalizedKey = _episodeTraktKeyFor(imdbId);
    final snapshot = Map<String, double>.from(percents);
    final profileScope =
        ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;

    Future<void> commit() =>
        _episodeTrackerSnapshotWriteLock.synchronized(() async {
          final prefs = await ProfilePreferences.instance();
          final raw = prefs.getString(storeKey);
          Map<String, dynamic> all = {};
          if (raw != null && raw.isNotEmpty) {
            try {
              final decoded = await decodeJsonAsync(raw);
              if (decoded is Map<String, dynamic>) all = decoded;
            } catch (_) {}
          }
          all[normalizedKey] = snapshot;
          await prefs.setString(storeKey, jsonEncode(all));
        });

    return profileScope == null
        ? commit()
        : ProfileRuntime.withCapturedScope(profileScope, commit);
  }

  /// Get episode progress by IMDB ID (scans playback state for matching imdbId)
  /// Also checks single-file video entries and parses season/episode from title.
  static Future<Map<String, Map<String, dynamic>>> getEpisodeProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final normalizedImdbId = imdbId.trim().toLowerCase();

    // Merge every legacy title-keyed series entry with this IMDb id. Older
    // builds could save the same show under multiple release-derived titles;
    // stopping at the first record silently hid episodes from the others.
    final seriesResult = <String, Map<String, dynamic>>{};
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> &&
          entry['imdbId']?.toString().trim().toLowerCase() ==
              normalizedImdbId) {
        if (entry['type'] == 'series') {
          final seasons = entry['seasons'];
          if (seasons is! Map) continue;
          for (final seasonEntry in seasons.entries) {
            final episodes = seasonEntry.value;
            if (episodes is! Map) continue;
            for (final episodeEntry in episodes.entries) {
              final episodeData = episodeEntry.value;
              if (episodeData is! Map) continue;
              final episodeKey = '${seasonEntry.key}_${episodeEntry.key}';
              final candidate = Map<String, dynamic>.from(episodeData);
              final existing = seriesResult[episodeKey];
              final candidateUpdatedAt =
                  (candidate['updatedAt'] as num?)?.toInt() ?? 0;
              final existingUpdatedAt =
                  (existing?['updatedAt'] as num?)?.toInt() ?? -1;
              if (candidateUpdatedAt >= existingUpdatedAt) {
                seriesResult[episodeKey] = candidate;
              }
            }
          }
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesResult.isNotEmpty) return seriesResult;

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        return {
          '${season}_$episode': {
            'positionMs': videoFallback['positionMs'] ?? 0,
            'durationMs': videoFallback['durationMs'] ?? 1,
            'updatedAt': videoFallback['updatedAt'] ?? 0,
          },
        };
      }
    }

    return {};
  }

  /// Merge local episode progress across stable IMDb identity and the current
  /// title-keyed record. The newest update wins duplicate coordinates. Equal
  /// or missing timestamps prefer the current title deterministically, which
  /// preserves legacy behavior without letting an older title record move a
  /// newer cross-alias resume position backwards.
  static Future<Map<String, Map<String, dynamic>>> getMergedEpisodeProgress({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return getEpisodeProgressByImdbId(imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getEpisodeProgressByImdbId(imdbId)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
      if (seriesTitle.isNotEmpty)
        getEpisodeProgress(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Map<String, dynamic>>{}),
    ]);
    int updatedAt(Map<String, dynamic> state) {
      final value = state['updatedAt'];
      if (value is! num || !value.isFinite) return 0;
      final timestamp = value.toInt();
      return timestamp > 0 ? timestamp : 0;
    }

    final merged = Map<String, Map<String, dynamic>>.from(reads[0]);
    for (final entry in reads[1].entries) {
      final previous = merged[entry.key];
      if (previous == null || updatedAt(entry.value) >= updatedAt(previous)) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// IMDb-aware counterpart to [getFinishedEpisodes], unioning historical
  /// release-title records with the current title record.
  static Future<Map<String, Set<int>>> getMergedFinishedEpisodes({
    required String seriesTitle,
    String? imdbId,
  }) async {
    if (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
        (imdbId?.startsWith('medialibrary:') ?? false)) {
      return getFinishedEpisodesByImdbId(imdbId: imdbId!);
    }
    final reads = await Future.wait([
      if (imdbId != null && imdbId.isNotEmpty)
        getFinishedEpisodesByImdbId(imdbId: imdbId)
      else
        Future.value(const <String, Set<int>>{}),
      if (seriesTitle.isNotEmpty)
        getFinishedEpisodes(seriesTitle: seriesTitle)
      else
        Future.value(const <String, Set<int>>{}),
    ]);
    final merged = <String, Set<int>>{};
    for (final snapshot in reads) {
      for (final entry in snapshot.entries) {
        merged.putIfAbsent(entry.key, () => <int>{}).addAll(entry.value);
      }
    }
    return merged;
  }

  /// Get finished episodes for a specific season
  static Future<Set<int>> getFinishedEpisodesForSeason({
    required String seriesTitle,
    required int season,
  }) async {
    final allFinished = await getFinishedEpisodes(seriesTitle: seriesTitle);
    return allFinished[season.toString()] ?? <int>{};
  }

  /// Get playback state for series content
  static Future<Map<String, dynamic>?> getSeriesPlaybackState({
    required String seriesTitle,
    required int season,
    required int episode,
    String? imdbId,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = PlaybackIdentityStorage.seriesProgressKey(seriesTitle, imdbId);

    final seriesData = map[key];
    if (seriesData == null || seriesData['type'] != 'series') return null;

    final seasonData = seriesData['seasons'][season.toString()];
    if (seasonData == null) return null;

    final episodeData = seasonData[episode.toString()];
    if (episodeData == null) return null;

    return episodeData as Map<String, dynamic>;
  }

  /// Save playback state for non-series content (movies, single videos)
  static Future<void> saveVideoPlaybackState({
    required String videoTitle,
    required String videoUrl,
    required int positionMs,
    required int durationMs,
    double speed = 1.0,
    String aspect = 'contain',
    String? imdbId,
    String? recoveryCheckpointId,
    int? recoveryUpdatedAtMs,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = (PlaybackIdentityStorage.requiresExactProgressIdentity(imdbId) ||
            (imdbId?.startsWith('medialibrary:') ?? false))
        ? 'video_${imdbId}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    map[key] = {
      'type': 'video',
      'title': videoTitle,
      'url': videoUrl,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'speed': speed,
      'aspect': aspect,
      'updatedAt': recoveryUpdatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      if (recoveryCheckpointId != null)
        'recoveryCheckpointId': recoveryCheckpointId,
      if (imdbId != null) 'imdbId': imdbId,
    };

    await PlaybackStateStore.savePlaybackStateMap(map);
  }

  /// Get playback state for non-series content
  static Future<Map<String, dynamic>?> getVideoPlaybackState({
    required String videoTitle,
    bool includeFinished = false,
    String? contentIdentity,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key = (PlaybackIdentityStorage.requiresExactProgressIdentity(contentIdentity) ||
            (contentIdentity?.startsWith('medialibrary:') ?? false))
        ? 'video_${contentIdentity}_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}'
        : 'video_${videoTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final videoData = map[key];
    if (videoData == null || videoData['type'] != 'video') return null;

    final imdbId = (videoData['imdbId'] as String?)?.trim();
    // A finished movie can have a stale source-specific state from a final
    // autosave tick. Its local completion record wins over that stale resume.
    if (!includeFinished &&
        imdbId != null &&
        imdbId.isNotEmpty &&
        await isMovieFinished(imdbId)) {
      return null;
    }

    return videoData as Map<String, dynamic>;
  }

  /// Get video playback state by IMDB ID (scans all video entries, returns most recent).
  static Future<Map<String, dynamic>?> getVideoPlaybackStateByImdbId(
    String imdbId,
  ) async {
    // A blank id would match every record saved without one and hand back an
    // unrelated movie's position.
    final wanted = imdbId.trim();
    if (wanted.isEmpty) return null;
    // A completion write and the periodic player autosave can overlap by one
    // tick. The finished marker is authoritative for movies, so never expose
    // a stale resume record that slipped back in during that tiny window.
    if (await isMovieFinished(wanted)) return null;
    final map = await PlaybackStateStore.getPlaybackStateMap();
    Map<String, dynamic>? best;
    int bestUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is! Map<String, dynamic> || entry['type'] != 'video') continue;
      // Pattern-matched, not cast: one malformed legacy record must not throw
      // out of a scan over every saved video.
      final recorded = entry['imdbId'];
      if (recorded is String && recorded.trim() == wanted) {
        final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
        if (updatedAt > bestUpdatedAt) {
          bestUpdatedAt = updatedAt;
          best = entry;
        }
      }
    }
    return best;
  }

  /// Get the last played episode for a series
  static Future<Map<String, dynamic>?> getLastPlayedEpisode({
    required String seriesTitle,
  }) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final key =
        'series_${seriesTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';

    final seriesData = map[key];
    if (seriesData is! Map || seriesData['type'] != 'series') return null;

    // Find the most recently updated episode. Parse defensively (matching
    // getVideoPlaybackStateByImdbId above): a corrupt or old-schema entry
    // must skip, not throw, on this resume hot path.
    Map<String, dynamic>? lastEpisode;
    int lastUpdated = 0;

    final seasons = seriesData['seasons'];
    if (seasons is! Map) return null;
    for (final seasonEntry in seasons.entries) {
      final season = int.tryParse(seasonEntry.key.toString());
      final episodes = seasonEntry.value;
      if (season == null || episodes is! Map) continue;

      for (final episodeEntry in episodes.entries) {
        final episode = int.tryParse(episodeEntry.key.toString());
        final episodeData = episodeEntry.value;
        if (episode == null || episodeData is! Map) continue;
        final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

        if (updatedAt > lastUpdated) {
          lastUpdated = updatedAt;
          lastEpisode = {
            'season': season,
            'episode': episode,
            ...Map<String, dynamic>.from(episodeData),
          };
        }
      }
    }

    if (lastEpisode != null) {
      debugPrint(
        'StorageService: getLastPlayedEpisode found S${lastEpisode['season']}E${lastEpisode['episode']} for "$seriesTitle"',
      );
    } else {
      debugPrint(
        'StorageService: getLastPlayedEpisode no episodes for "$seriesTitle"',
      );
    }

    return lastEpisode;
  }

  /// Get all episode watch progress for a series by IMDB ID.
  /// Returns a map of "season-episode" → progress percentage (0-100).
  static Future<Map<String, double>> getEpisodeWatchProgressByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final result = <String, double>{};

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys). Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (seriesEntries.isEmpty && videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!).toString();
        final episode = int.parse(match.group(2)!).toString();
        final posMs = (videoFallback['positionMs'] as num?)?.toInt() ?? 0;
        final durMs = (videoFallback['durationMs'] as num?)?.toInt() ?? 1;
        if (durMs > 0 && posMs > 0) {
          result['$season-$episode'] = (posMs / durMs * 100).clamp(0.0, 100.0);
        }
        return result;
      }
    }

    if (seriesEntries.isEmpty) return result;

    // Aggregate progress across ALL matching series entries
    for (final seriesData in seriesEntries) {
      final finishedMap =
          seriesData['finishedEpisodes'] as Map<String, dynamic>?;

      final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
      for (final seasonEntry in seasons.entries) {
        final seasonNum = seasonEntry.key;
        final episodes = seasonEntry.value as Map<String, dynamic>? ?? {};

        // Get finished episodes for this season
        final finishedEps = finishedMap?[seasonNum] as Map<String, dynamic>?;

        for (final episodeEntry in episodes.entries) {
          final epNum = episodeEntry.key;
          final epData = episodeEntry.value as Map<String, dynamic>;
          final key = '$seasonNum-$epNum';

          // Check if finished first
          if (finishedEps != null && finishedEps.containsKey(epNum)) {
            result[key] = 100.0;
            continue;
          }

          final positionMs = (epData['positionMs'] as num?)?.toInt() ?? 0;
          final durationMs = (epData['durationMs'] as num?)?.toInt() ?? 1;
          if (durationMs > 0 && positionMs > 0) {
            final progress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
            // Keep higher progress if duplicate across entries
            if (!result.containsKey(key) || progress > result[key]!) {
              result[key] = progress;
            }
          }
        }
      }
    }

    return result;
  }

  /// Look up the last played episode by IMDB ID.
  /// Scans all series entries for a matching imdbId field.
  /// Also checks single-file video entries (type=video) as a fallback,
  /// parsing season/episode from the title.
  static Future<Map<String, dynamic>?> getLastPlayedEpisodeByImdbId(
    String imdbId,
  ) async {
    final map = await PlaybackStateStore.getPlaybackStateMap();

    // Find ALL series entries with matching imdbId (different season packs may
    // have different title keys, e.g. "young sheldon (2017)" vs "young sheldon").
    // Also track most recent video fallback.
    final seriesEntries = <Map<String, dynamic>>[];
    Map<String, dynamic>? videoFallback;
    int videoFallbackUpdatedAt = -1;
    for (final entry in map.values) {
      if (entry is Map<String, dynamic> && entry['imdbId'] == imdbId) {
        if (entry['type'] == 'series') {
          seriesEntries.add(entry);
        } else if (entry['type'] == 'video') {
          final updatedAt = (entry['updatedAt'] as num?)?.toInt() ?? 0;
          if (updatedAt > videoFallbackUpdatedAt) {
            videoFallbackUpdatedAt = updatedAt;
            videoFallback = entry;
          }
        }
      }
    }

    if (seriesEntries.isNotEmpty) {
      // Find most recently updated episode across ALL matching series entries
      Map<String, dynamic>? lastEpisode;
      Map<String, dynamic>?
      lastEpisodeSeriesData; // track which entry it came from
      int lastUpdated = 0;

      for (final seriesData in seriesEntries) {
        final seasons = seriesData['seasons'] as Map<String, dynamic>? ?? {};
        for (final seasonEntry in seasons.entries) {
          final season = int.parse(seasonEntry.key);
          final episodes = seasonEntry.value as Map<String, dynamic>;

          for (final episodeEntry in episodes.entries) {
            final episode = int.parse(episodeEntry.key);
            final episodeData = episodeEntry.value as Map<String, dynamic>;
            final updatedAt = (episodeData['updatedAt'] as num?)?.toInt() ?? 0;

            if (updatedAt > lastUpdated) {
              lastUpdated = updatedAt;
              lastEpisode = {
                'season': season,
                'episode': episode,
                ...episodeData,
              };
              lastEpisodeSeriesData = seriesData;
            }
          }
        }
      }

      if (lastEpisode != null && lastEpisodeSeriesData != null) {
        // Check if this episode is marked as finished (in its own series entry)
        final finishedEpisodes =
            lastEpisodeSeriesData['finishedEpisodes'] as Map<String, dynamic>?;
        if (finishedEpisodes != null) {
          final seasonFinished =
              finishedEpisodes[lastEpisode['season'].toString()]
                  as Map<String, dynamic>?;
          if (seasonFinished != null &&
              seasonFinished.containsKey(lastEpisode['episode'].toString())) {
            lastEpisode['finished'] = true;
          }
        }
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId found S${lastEpisode['season']}E${lastEpisode['episode']} for "$imdbId"${lastEpisode['finished'] == true ? ' (finished)' : ''}',
        );
      }
      return lastEpisode;
    }

    // Fallback: single-file video entry — parse season/episode from title
    if (videoFallback != null) {
      final title = videoFallback['title'] as String? ?? '';
      final match = RegExp(r'[Ss](\d+)[Ee](\d+)').firstMatch(title);
      if (match != null) {
        final season = int.parse(match.group(1)!);
        final episode = int.parse(match.group(2)!);
        debugPrint(
          'StorageService: getLastPlayedEpisodeByImdbId (video fallback) parsed S${season}E$episode from "$title" for "$imdbId"',
        );
        return {
          'season': season,
          'episode': episode,
          'positionMs': videoFallback['positionMs'] ?? 0,
          'durationMs': videoFallback['durationMs'] ?? 1,
          'updatedAt': videoFallback['updatedAt'] ?? 0,
        };
      }
    }

    return null;
  }

  /// Clean up old playback state data (older than 30 days)
  static Future<void> cleanupOldPlaybackState() async {
    final map = await PlaybackStateStore.getPlaybackStateMap();
    final now = DateTime.now().millisecondsSinceEpoch;
    final thirtyDaysAgo = now - (30 * 24 * 60 * 60 * 1000);

    final keysToRemove = <String>[];

    for (final entry in map.entries) {
      final data = entry.value as Map<String, dynamic>;
      final updatedAt = data['updatedAt'] as int?;

      if (updatedAt != null && updatedAt < thirtyDaysAgo) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      map.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      await PlaybackStateStore.savePlaybackStateMap(map, recordDeletions: true);
    }
  }

  /// Clear all playback-related data (series and video states, track prefs, legacy resume)
  /// [recordSyncDeletions] distinguishes a deliberate clear (default, which
  /// deletes on every synced device) from a device-local wipe such as app
  /// reset, which must never mint circle-wide deletions.
  static Future<void> clearAllPlaybackData({
    bool recordSyncDeletions = true,
  }) async {
    final prefs = await ProfilePreferences.instance();
    // Device-local clears must invalidate native recovery too, without
    // publishing a deletion to the user's other devices.
    await PlaybackRecoveryIntent.recordClearAll();
    await PlaybackStateStore.savePlaybackStateMap(
      <String, dynamic>{},
      recordDeletions: recordSyncDeletions,
    );
    if (recordSyncDeletions) {
      final finishedMovies = await _getFinishedMovieIds();
      await WebDavSyncTombstoneRecorder.recordForCurrentProfile(
        finishedMovies.map(WebDavSyncRecordKey.finishedMovie),
      );
    }
    await prefs.remove(_finishedMoviesKey);
    await prefs.remove(localSeriesCompletionStateKey);
    await prefs.remove(localSeriesCalendarCheckedAtKey);
    await prefs.remove(localSeriesCalendarAttemptedAtKey);
    localCompletionRevision.value++;
    // Resume lives in the DB now; the prefs key only still exists for users
    // who wipe before the one-time import has run.
    await prefs.remove(_videoResumeKey);
    await IptvMediaStore.clearVideoResume(
      origin: recordSyncDeletions
          ? WebDavSyncMutationOrigin.user
          : WebDavSyncMutationOrigin.maintenance,
    );
    debugPrint(
      'StorageService: cleared playback state, completed movies, and video resume data',
    );
  }

  // Video resume — one row per item in debrify_tv.db (see IptvMediaStore).
  static Future<Map<String, dynamic>?> getVideoResume(String key) {
    return IptvMediaStore.videoResume(key);
  }

  static Future<void> upsertVideoResume(
    String key,
    Map<String, dynamic> entry, {
    String? sourceId,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.upsertVideoResume(
      key,
      entry,
      sourceId: sourceId,
      origin: origin,
    );
  }

  static Future<void> removeVideoResume(
    String key, {
    bool playbackCheckpoint = false,
    WebDavSyncMutationOrigin origin = WebDavSyncMutationOrigin.user,
  }) {
    return IptvMediaStore.removeVideoResume(
      key,
      origin: origin,
      playbackCheckpoint: playbackCheckpoint,
    );
  }

  static int _normalizeLocalCompletionThreshold(int value) {
    return localCompletionThresholdOptions.contains(value)
        ? value
        : defaultLocalCompletionThreshold;
  }

  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.
  static Future<int> getMovieCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_movieCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setMovieCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _movieCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.
  static Future<int> getEpisodeCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_episodeCompletionThresholdKey) ??
          defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setEpisodeCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _episodeCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

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
  /// Until [_clearEpisodeCompletion] learned to drop the row, unwatching a
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
      if (stateEntry is! Map<String, dynamic> ||
          stateEntry['type'] != 'series') {
        continue;
      }
      final seasons = stateEntry['seasons'];
      if (seasons is! Map) continue;
      final finishedEpisodes = stateEntry['finishedEpisodes'];

      for (final seasonKey in seasons.keys.toList()) {
        final episodes = seasons[seasonKey];
        if (episodes is! Map) continue;
        final seasonFinished = finishedEpisodes is Map
            ? finishedEpisodes[seasonKey]
            : null;

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
      localCompletionRevision.value++;
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
    final generation =
        prefs.getInt(_playbackCompletionMigrationGenerationKey) ?? 0;
    if (generation >= _currentPlaybackCompletionMigrationGeneration) return;

    final movieThreshold = await getMovieCompletionThreshold();
    final episodeThreshold = await getEpisodeCompletionThreshold();
    final playback = await PlaybackStateStore.getPlaybackStateMap();
    final completedMovieIds = await _getFinishedMovieIds();
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
            'finishedAt':
                (episodeData['updatedAt'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
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
        _finishedMoviesKey,
        completedMovieIds.toList()..sort(),
      );
      localCompletionRevision.value++;

      final rawContinueWatching = prefs.getString(_continueWatchingKey);
      if (rawContinueWatching != null && rawContinueWatching.isNotEmpty) {
        try {
          final decoded = await decodeJsonAsync(rawContinueWatching);
          if (decoded is List) {
            final items = decoded
                .whereType<Map<String, dynamic>>()
                .map(Map<String, dynamic>.from)
                .where((item) {
                  final imdbId = (item['imdbId'] as String?)
                      ?.trim()
                      .toLowerCase();
                  return imdbId == null ||
                      !newlyCompletedMovieIds.contains(imdbId);
                })
                .toList();
            await _saveContinueWatchingItems(items);
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
      await removeVideoResume(
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

  static void resetProfileCaches() {}
}
