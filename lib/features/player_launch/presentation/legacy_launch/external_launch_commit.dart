import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/services/mdblist/mdblist_models.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter/foundation.dart';

final class ExternalLaunchCommit {
  /// External players have no decoder callback into Debrify, so a successful
  /// OS/app handoff is their commit boundary. Keep this separate from Android
  /// TV, whose native player reports its validated source after first frame.
  static Future<void> commitExternalLaunchSource(
    VideoPlayerLaunchArgs args,
  ) async {
    final sources = args.stremioSources;
    final commit = args.onStremioSourceCommitted;
    if (sources == null || sources.isEmpty || commit == null) return;
    final index = (args.stremioCurrentSourceIndex ?? 0).clamp(
      0,
      sources.length - 1,
    );
    try {
      await commit(sources[index]);
    } catch (error) {
      debugPrint(
        'VideoPlayerLauncher: external source commit failed '
        '(${error.runtimeType})',
      );
    }
  }

  /// Seed the connected tracker's Continue Watching when playback leaves the
  /// app (external player / DeoVR).
  ///
  /// The shared pre-launch path already writes LOCAL Continue Watching for
  /// untracked titles, but deliberately skips it when a tracker owns the
  /// row — and an external player can never scrobble back, so without this
  /// the title lands in NO row at all. A ~1% scrobble is each tracker's own
  /// idiom for "started watching" — start→pause for Trakt and a bare pause for
  /// Simkl/MDBList (Simkl start would CLEAR an existing session) — and all keep
  /// sub-80% sessions as resumable playback, so the item appears in their CW.
  /// The existing CW row menus then let the user mark it watched on return,
  /// and if the external app scrobbles real progress itself (Infuse + Trakt),
  /// that simply overwrites the seed.
  ///
  /// Fail-soft and fire-and-forget: every service no-ops without credentials, and
  /// the handoff must never wait on tracker HTTP.
  static Future<void> seedTrackerContinueWatching(
    VideoPlayerLaunchArgs args, {
    int? seasonOverride,
    int? episodeOverride,
  }) async {
    final imdbId = args.contentImdbId;
    if (imdbId == null || imdbId.isEmpty) return;
    // Channel rotation is not a watchable title; mirrors the local CW skip.
    if (args.stremioTvChannels != null) return;
    if (!args.traktScrobble && !args.simklScrobble && !args.mdblistScrobble) {
      return;
    }

    // A series seed needs BOTH season and episode — both scrobble services
    // refuse a lone half, and a series imdb id in a movie-shaped body would
    // be worse than no seed. A movie sends neither. The overrides are the
    // episode the external path actually CHOSE (resume/advance) and outrank
    // the launch-time metadata.
    int? season = (seasonOverride != null && episodeOverride != null)
        ? seasonOverride
        : args.contentSeason;
    int? episode = (seasonOverride != null && episodeOverride != null)
        ? episodeOverride
        : args.contentEpisode;
    final isSeries = args.contentType == 'series';
    if (isSeries && ((season ?? 0) <= 0 || (episode ?? 0) <= 0)) return;
    if (!isSeries) {
      season = null;
      episode = null;
    }

    // Just-started sentinel: comfortably under both trackers' ~80% "watched"
    // thresholds, so the session lands as resumable playback.
    const progress = 1.0;

    // Concurrent, not serialized: this runs while another app is taking the
    // foreground, and a suspension mid-sequence must not starve the second
    // tracker of its seed.
    final s = season;
    final e = episode;
    await Future.wait([
      if (args.traktScrobble)
        () async {
          try {
            // Trakt's documented idiom: start opens the session, pause
            // checkpoints it into the playback-progress (CW) list.
            await TraktService.instance.scrobbleStart(
              imdbId,
              progress,
              season: s,
              episode: e,
              contentType: args.contentType,
            );
            await TraktService.instance.scrobblePause(
              imdbId,
              progress,
              season: s,
              episode: e,
              contentType: args.contentType,
            );
          } catch (err) {
            debugPrint('ExternalPlayer: Trakt CW seed failed: $err');
          }
        }(),
      if (args.simklScrobble)
        () async {
          try {
            // PAUSE ONLY, deliberately: Simkl's start CLEARS an existing
            // paused playback (and its 20-second lock could then swallow the
            // follow-up), while a bare pause creates the resumable row on
            // its own — the pause-centric idiom the in-app player already
            // uses.
            await SimklService.instance.scrobblePause(
              imdbId,
              progress,
              season: s,
              episode: e,
            );
          } catch (err) {
            debugPrint('ExternalPlayer: Simkl CW seed failed: $err');
          }
        }(),
      if (args.mdblistScrobble)
        () async {
          try {
            final ids = MdblistMediaIds.forContent(imdbId);
            final target = isSeries
                ? MdblistScrobbleTarget.episode(ids, season: s!, episode: e!)
                : MdblistScrobbleTarget.movie(ids);
            await MdblistService.instance.scrobblePause(target, progress);
          } catch (err) {
            debugPrint('ExternalPlayer: MDBList CW seed failed: $err');
          }
        }(),
    ]);
  }
}
