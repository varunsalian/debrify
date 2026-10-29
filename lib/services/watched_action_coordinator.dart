import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'profiles/profile_local_writes.dart';
import 'profiles/profile_runtime.dart';
import 'profiles/profile_session_memory.dart';
import '../models/media_identity.dart';
import 'episode_tracker_snapshot_revision.dart';
import '../models/custom_series_identity.dart';
import 'local_series_completion_service.dart';
import 'mdblist/mdblist_models.dart';
import 'mdblist/mdblist_service.dart';
import 'simkl/simkl_service.dart';
import 'tracking_source_policy.dart';
import 'trakt/trakt_service.dart';
import 'watched_status_service.dart';

class WatchedActionResult {
  const WatchedActionResult(this.failedTargets, {this.cancelled = false});

  final bool cancelled;

  final List<String> failedTargets;
  bool get success => !cancelled && failedTargets.isEmpty;
}

/// Single fan-out point for every user-initiated watched/unwatched action.
/// Local is unconditional; remote writes follow the Scrobble selection.
///
/// [forceTargets] is the ONE exception, and it exists for tracker-BRANDED
/// surfaces only — the Trakt sheet, the Simkl sheet, the MDBList menu. A row
/// labelled with a tracker's name must write to that tracker whether or not
/// it's ticked in Scrobble; the Scrobble set governs automatic scrobbling and
/// the generic (episode-panel / Home-card / guide) actions, not a command the
/// user aimed at one service by name. Auth is still required — a forced target
/// you aren't signed into is skipped, same as before.
class WatchedActionCoordinator {
  WatchedActionCoordinator._();

  static bool _writes(
    TrackingSourcePolicy policy,
    Set<TrackingSource> forceTargets,
    TrackingSource source,
  ) => policy.scrobbleTargets.contains(source) || forceTargets.contains(source);

  static Future<WatchedActionResult> setTitleWatched({
    required String imdbId,
    required String contentType,
    required bool watched,
    Set<TrackingSource> forceTargets = const <TrackingSource>{},
    bool Function()? canContinue,
  }) {
    final owner = ProfileSessionMemory.captureOwner();
    bool current() =>
        owner == ProfileSessionMemory.captureOwner() &&
        (canContinue?.call() ?? true) &&
        (owner.scope == null || ProfileRuntime.capture() == owner.scope);
    if (!current()) {
      return Future.value(const WatchedActionResult([], cancelled: true));
    }
    Future<WatchedActionResult> run() => _setTitleWatched(
      imdbId: imdbId,
      contentType: contentType,
      watched: watched,
      forceTargets: forceTargets,
      current: current,
    );
    final scope = owner.scope;
    return scope == null ? run() : ProfileRuntime.withCapturedScope(scope, run);
  }

  static Future<WatchedActionResult> _setTitleWatched({
    required String imdbId,
    required String contentType,
    required bool watched,
    required Set<TrackingSource> forceTargets,
    required bool Function() current,
  }) async {
    final id = MediaIdentity.progressId(imdbId.trim(), contentType);
    if (id.isEmpty) return const WatchedActionResult(['this device']);
    final series = contentType == 'series' || contentType == 'show';
    // Once accepted, complete local flags/history/recovery writes in the
    // originating scope. The profile lifecycle drains this whole sequence.
    await ProfileLocalWrites.run(() async {
      if (series) {
        await MovieProgressStorage.setSeriesExplicitlyWatched(
          id,
          watched: watched,
        );
        if (!watched) {
          await LocalSeriesCompletionService.instance.clearCompletedHistory(id);
        }
      } else if (watched) {
        await MovieProgressStorage.markMovieAsFinished(id);
      } else {
        await MovieProgressStorage.unmarkMovieAsFinished(id);
      }
    });
    final failures = <String>[];
    WatchedActionResult retired() =>
        WatchedActionResult(failures, cancelled: true);
    if (!current()) return retired();
    if (CustomSeriesIdentity.isCustom(id)) return const WatchedActionResult([]);
    late TrackingSourcePolicy policy;
    try {
      policy = (await TrackingSourcePolicy.load(
        canContinue: current,
      )).forContent(id);
    } catch (_) {
      if (!current()) return retired();
      rethrow;
    }
    if (!current()) return retired();
    if (_writes(policy, forceTargets, TrackingSource.trakt)) {
      final service = TraktService.instance;
      final connected = await service.isAuthenticated(canContinue: current);
      if (!current()) return retired();
      if (connected) {
        final ok = watched
            ? await service.addToHistory(id, contentType, canContinue: current)
            : await service.removeFromHistory(
                id,
                contentType,
                canContinue: current,
              );
        if (!ok) failures.add('Trakt');
      }
    }
    if (!current()) return retired();
    if (_writes(policy, forceTargets, TrackingSource.simkl)) {
      final service = SimklService.instance;
      final connected = await service.isAuthenticated(canContinue: current);
      if (!current()) return retired();
      if (connected) {
        var ok = watched
            ? await service.markWatched(id, contentType, canContinue: current)
            : await service.markUnwatched(
                id,
                contentType,
                canContinue: current,
              );
        if (!current()) return retired();
        if (watched && ok) {
          // Completed titles may still be rewatching: clear the paused session
          // after marking history and include cleanup failure in the result.
          ok = await service.deletePlaybackForImdb(
            id,
            contentType: contentType,
            canContinue: current,
          );
        }
        if (!ok) failures.add('Simkl');
      }
    }
    if (!current()) return retired();
    if ((MediaIdentity.isImdb(id) || MediaIdentity.isNative(id)) &&
        _writes(policy, forceTargets, TrackingSource.mdblist)) {
      final service = MdblistService.instance;
      final connected = await service.isAuthenticated(canContinue: current);
      if (!current()) return retired();
      if (connected) {
        final ids = MdblistMediaIds.forContent(id);
        final type = series ? 'show' : 'movie';
        final ok = watched
            ? await service.markWatched(ids, type, canContinue: current)
            : await service.markUnwatched(ids, type, canContinue: current);
        if (!ok) failures.add('MDBList');
      }
    }
    if (!current()) return retired();
    WatchedStatusService.instance.ensureStarted();
    return WatchedActionResult(failures);
  }

  /// The providers a watched-write for this series id would actually touch,
  /// in fan-out order: this device first, then every authenticated tracker
  /// the Scrobble selection targets. Mirrors the auth/policy checks
  /// [setEpisodeWatched] makes, so "mark earlier" writes exactly where a
  /// single-episode mark would.
  static Future<List<TrackingSource>> episodeWriteProviders(
    String imdbId,
  ) async {
    if (CustomSeriesIdentity.isCustom(imdbId)) {
      return const [TrackingSource.local];
    }
    final providers = <TrackingSource>[TrackingSource.local];
    final policy = (await TrackingSourcePolicy.load()).forContent(imdbId);
    if (_writes(policy, const <TrackingSource>{}, TrackingSource.trakt) &&
        await TraktService.instance.isAuthenticated()) {
      providers.add(TrackingSource.trakt);
    }
    if (_writes(policy, const <TrackingSource>{}, TrackingSource.simkl) &&
        await SimklService.instance.isAuthenticated()) {
      providers.add(TrackingSource.simkl);
    }
    if ((MediaIdentity.isImdb(imdbId) || MediaIdentity.isNative(imdbId)) &&
        _writes(policy, const <TrackingSource>{}, TrackingSource.mdblist) &&
        await MdblistService.instance.isAuthenticated() &&
        !MdblistMediaIds.forContent(imdbId).isEmpty) {
      providers.add(TrackingSource.mdblist);
    }
    return providers;
  }

  static Future<WatchedActionResult> setEpisodeWatched({
    required String imdbId,
    required String seriesTitle,
    required int season,
    required int episode,
    required bool watched,
    Set<TrackingSource> forceTargets = const <TrackingSource>{},
  }) async {
    if (watched) {
      await EpisodeCompletionStorage.markEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );
    } else {
      await EpisodeCompletionStorage.unmarkEpisodeAsFinished(
        seriesTitle: seriesTitle,
        season: season,
        episode: episode,
        imdbId: imdbId,
      );
    }
    EpisodeTrackerSnapshotRevision.invalidateTitle('local', imdbId);

    if (CustomSeriesIdentity.isCustom(imdbId)) {
      return const WatchedActionResult([]);
    }

    final policy = (await TrackingSourcePolicy.load()).forContent(imdbId);
    final failures = <String>[];
    if (_writes(policy, forceTargets, TrackingSource.trakt) &&
        await TraktService.instance.isAuthenticated()) {
      final ok = watched
          ? await TraktService.instance.markEpisodeWatched(
              imdbId,
              season,
              episode,
            )
          : await TraktService.instance.markEpisodeUnwatched(
              imdbId,
              season,
              episode,
            );
      if (!ok) failures.add('Trakt');
    }
    if (_writes(policy, forceTargets, TrackingSource.simkl) &&
        await SimklService.instance.isAuthenticated()) {
      final ok = watched
          ? await SimklService.instance.markEpisodeWatched(
              imdbId,
              season,
              episode,
            )
          : await SimklService.instance.markEpisodeUnwatched(
              imdbId,
              season,
              episode,
            );
      if (watched && ok) {
        await SimklService.instance.deletePlaybackForEpisode(
          imdbId,
          season,
          episode,
        );
      }
      if (!ok) failures.add('Simkl');
    }
    if ((MediaIdentity.isImdb(imdbId) || MediaIdentity.isNative(imdbId)) &&
        _writes(policy, forceTargets, TrackingSource.mdblist) &&
        await MdblistService.instance.isAuthenticated()) {
      final ids = MdblistMediaIds.forContent(imdbId);
      final ok = watched
          ? await MdblistService.instance.markWatched(
              ids,
              'episode',
              season: season,
              episode: episode,
            )
          : await MdblistService.instance.markUnwatched(
              ids,
              'episode',
              season: season,
              episode: episode,
            );
      if (!ok) failures.add('MDBList');
    }
    return WatchedActionResult(failures);
  }
}
