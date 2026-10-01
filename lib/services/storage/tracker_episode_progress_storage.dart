import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/mdblist_storage.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:synchronized/synchronized.dart';

final class TrackerEpisodeProgressStorage {
  const TrackerEpisodeProgressStorage._();

  /// The tracker snapshots are each stored as one JSON object containing every
  /// show. Serializing their read/modify/write cycle prevents two concurrent
  /// show refreshes from both reading the same old object and dropping whichever
  /// write finishes first.
  static final Lock _episodeTrackerSnapshotWriteLock = Lock();

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

  static const String _episodeMdblistProgressKey = 'episode_mdblist_progress_v1';

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
          if (entry.value is num) entry.key.toString(): (entry.value as num).toDouble(),
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
    final profileScope = ProfileRuntime.isInitialized && ProfileRuntime.isProfileCommitted
        ? ProfileRuntime.capture()
        : null;

    Future<void> commit() => _episodeTrackerSnapshotWriteLock.synchronized(() async {
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

    return profileScope == null ? commit() : ProfileRuntime.withCapturedScope(profileScope, commit);
  }
}
