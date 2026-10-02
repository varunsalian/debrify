import 'dart:async';
import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/native_mdblist_session.dart';
import 'package:debrify/features/player_launch/data/native_scrobble_session.dart';
import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter/foundation.dart';

final class NativeProgressHandler {
  static Future<void> handleProgressUpdate(
    AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) async {
    try {
      final positionMs = (progress['positionMs'] ?? 0) as int;
      final durationMs = (progress['durationMs'] ?? 0) as int;
      final speed = (progress['speed'] ?? 1.0) as double;
      final aspect = (progress['aspect'] ?? 'contain') as String;
      final completed = progress['completed'] == true;
      final localCompleted = progress['localCompleted'] == true;
      final resumeId = progress['resumeId'] as String?;
      final itemIndex = progress['itemIndex'] as int? ?? 0;
      final progressUrl = progress['url'] as String?;

      if (resumeId != null && progressUrl != null && progressUrl.isNotEmpty) {
        StreamRedirectResolver.cacheResolvedStream(resumeId, progressUrl);
      }

      // Native TV uses this one-shot signal for locally tracked catalog
      // movies. Complete before the generic resume writer runs, otherwise the
      // next native ping would immediately recreate Continue Watching after we
      // intentionally clear it.
      final locallyTrackedMovie =
          payload.localCompletionTracking &&
          payload.trackingContentType == 'movie' &&
          payload.contentType == PlaybackContentType.single &&
          payload.imdbId != null &&
          payload.imdbId!.isNotEmpty;
      if (locallyTrackedMovie && !payload.localMovieCompletionRecorded) {
        final movieProgress = durationMs > 0 ? positionMs * 100 / durationMs : 0.0;
        if (!payload.localMovieRewatchStarted &&
            positionMs > 0 &&
            movieProgress < payload.movieCompletionThreshold) {
          await MovieProgressStorage.unmarkMovieAsFinished(payload.imdbId!);
          payload.localMovieRewatchStarted = true;
        }
        if (localCompleted || completed || progress['localCompletionEligible'] == true) {
          await Future.wait([
            MovieProgressStorage.markMovieAsFinished(payload.imdbId!),
            if (resumeId != null && resumeId.isNotEmpty)
              VideoResumeStorage.removeVideoResume(resumeId),
          ]);
          payload.localMovieCompletionRecorded = true;
        }
      }

      // Trakt scrobble for Android TV player (movies and series)
      if (payload.traktScrobble &&
          payload.imdbId != null &&
          durationMs > 0 &&
          TraktService.isScrobbleReady(
            contentType: payload.trackingContentType,
            season: progress['season'] as int?,
            episode: progress['episode'] as int?,
          )) {
        // Treat buffering as still playing — ExoPlayer sets isPlaying=false during buffer
        final isPlaying = progress['isPlaying'] == true || progress['isBuffering'] == true;
        final traktProgress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
        final imdbId = payload.imdbId!;
        // For series, read season/episode from Kotlin progress update
        // For non-series, ignore parsed values — avoids filename false positives (e.g. "5.1" surround → S5E1)
        final season = payload.trackingContentType == 'series' ? progress['season'] as int? : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (NativeScrobbleSession.traktLastKnownSeason != null &&
            NativeScrobbleSession.traktLastKnownEpisode != null &&
            (season != NativeScrobbleSession.traktLastKnownSeason ||
                episode != NativeScrobbleSession.traktLastKnownEpisode) &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            NativeScrobbleSession.traktLastKnownProgress,
            season: NativeScrobbleSession.traktLastKnownSeason,
            episode: NativeScrobbleSession.traktLastKnownEpisode,
            contentType: payload.trackingContentType,
          );
          NativeScrobbleSession.traktLastScrobbleAction = 'stop';
        }

        NativeScrobbleSession.traktLastKnownProgress = traktProgress;
        NativeScrobbleSession.traktLastKnownSeason = season;
        NativeScrobbleSession.traktLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (NativeScrobbleSession.traktLastScrobbleAction == 'stop' &&
            isPlaying &&
            traktProgress <= 80 &&
            !completed) {
          NativeScrobbleSession.traktLastScrobbleAction = null;
        }
        if (completed && NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          NativeScrobbleSession.traktLastScrobbleAction = 'stop';
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            traktProgress,
            season: season,
            episode: episode,
            contentType: payload.trackingContentType,
          );
        } else if (isPlaying &&
            NativeScrobbleSession.traktLastScrobbleAction != 'start' &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          // Trakt rejects start above 80% — send stop instead, no heartbeat needed
          if (traktProgress > 80) {
            NativeScrobbleSession.traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
          } else {
            NativeScrobbleSession.traktLastScrobbleAction = 'start';
            TraktService.instance.scrobbleStart(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
            // Start heartbeat timer to checkpoint progress every 2 minutes
            NativeScrobbleSession.traktHeartbeatTimer?.cancel();
            NativeScrobbleSession.traktHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              // Trakt rejects start/pause above 80% — send stop and end heartbeat
              if (NativeScrobbleSession.traktLastKnownProgress > 80) {
                NativeScrobbleSession.traktLastScrobbleAction = 'stop';
                TraktService.instance.scrobbleStop(
                  payload.imdbId!,
                  NativeScrobbleSession.traktLastKnownProgress,
                  season: NativeScrobbleSession.traktLastKnownSeason,
                  episode: NativeScrobbleSession.traktLastKnownEpisode,
                  contentType: payload.trackingContentType,
                );
                debugPrint(
                  'Trakt: Heartbeat stop at ${NativeScrobbleSession.traktLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                NativeScrobbleSession.traktHeartbeatTimer?.cancel();
                NativeScrobbleSession.traktHeartbeatTimer = null;
                return;
              }
              // Use latest known progress/season/episode
              NativeScrobbleSession.traktLastScrobbleAction = 'start';
              TraktService.instance.scrobbleStart(
                payload.imdbId!,
                NativeScrobbleSession.traktLastKnownProgress,
                season: NativeScrobbleSession.traktLastKnownSeason,
                episode: NativeScrobbleSession.traktLastKnownEpisode,
                contentType: payload.trackingContentType,
              );
              debugPrint(
                'Trakt: Heartbeat scrobble at ${NativeScrobbleSession.traktLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            NativeScrobbleSession.traktLastScrobbleAction != null &&
            NativeScrobbleSession.traktLastScrobbleAction != 'pause' &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          // Trakt rejects pause when progress > 80% — send stop instead
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          if (traktProgress > 80) {
            NativeScrobbleSession.traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
          } else {
            NativeScrobbleSession.traktLastScrobbleAction = 'pause';
            TraktService.instance.scrobblePause(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
          }
        }
      }

      // Simkl scrobble for Android TV player — fully parallel mirror of the
      // Trakt block above (own state vars/heartbeat, same event stream, same
      // 80% rule — Simkl also finalizes watched server-side at ≥80% on stop).
      // Skips a series frame with unresolved S/E so it can't be recorded as a
      // movie (see _simklSeriesSEUnresolved).
      if (payload.simklScrobble &&
          payload.imdbId != null &&
          durationMs > 0 &&
          !NativeMdblistSession.simklSeriesSEUnresolved(payload, progress)) {
        final isPlaying = progress['isPlaying'] == true || progress['isBuffering'] == true;
        final simklProgress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
        final imdbId = payload.imdbId!;
        final season = payload.trackingContentType == 'series' ? progress['season'] as int? : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (NativeScrobbleSession.simklLastKnownSeason != null &&
            NativeScrobbleSession.simklLastKnownEpisode != null &&
            (season != NativeScrobbleSession.simklLastKnownSeason ||
                episode != NativeScrobbleSession.simklLastKnownEpisode) &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            NativeScrobbleSession.simklLastKnownProgress,
            season: NativeScrobbleSession.simklLastKnownSeason,
            episode: NativeScrobbleSession.simklLastKnownEpisode,
          );
          NativeScrobbleSession.simklLastScrobbleAction = 'stop';
        }

        NativeScrobbleSession.simklLastKnownProgress = simklProgress;
        NativeScrobbleSession.simklLastKnownSeason = season;
        NativeScrobbleSession.simklLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (NativeScrobbleSession.simklLastScrobbleAction == 'stop' &&
            isPlaying &&
            simklProgress <= 80 &&
            !completed) {
          NativeScrobbleSession.simklLastScrobbleAction = null;
        }
        if (completed && NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklLastScrobbleAction = 'stop';
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            simklProgress,
            season: season,
            episode: episode,
          );
        } else if (isPlaying &&
            NativeScrobbleSession.simklLastScrobbleAction != 'start' &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          // ≥80% would just finalize server-side — send stop, no heartbeat
          if (simklProgress > 80) {
            NativeScrobbleSession.simklLastScrobbleAction = 'stop';
            SimklService.instance.scrobbleStop(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          } else {
            // Pause-centric: do NOT scrobble 'start' to Simkl — it persists
            // nothing (id:0) AND wipes the existing /sync/playback resume point.
            // Leave the resume point intact; the pause-based heartbeat below
            // checkpoints it. 'start' is kept only as an in-play state marker
            // (no POST sent) so this isPlaying branch doesn't re-enter on every
            // progress tick.
            NativeScrobbleSession.simklLastScrobbleAction = 'start';
            // 2-minute checkpoint — comfortably above Simkl's 20s rate lock
            NativeScrobbleSession.simklHeartbeatTimer?.cancel();
            NativeScrobbleSession.simklHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              if (NativeScrobbleSession.simklLastKnownProgress > 80) {
                NativeScrobbleSession.simklLastScrobbleAction = 'stop';
                SimklService.instance.scrobbleStop(
                  payload.imdbId!,
                  NativeScrobbleSession.simklLastKnownProgress,
                  season: NativeScrobbleSession.simklLastKnownSeason,
                  episode: NativeScrobbleSession.simklLastKnownEpisode,
                );
                debugPrint(
                  'Simkl: Heartbeat stop at ${NativeScrobbleSession.simklLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                NativeScrobbleSession.simklHeartbeatTimer?.cancel();
                NativeScrobbleSession.simklHeartbeatTimer = null;
                return;
              }
              // Checkpoint a RESUMABLE position via pause. Simkl's /scrobble/start
              // saves nothing (returns id:0) AND wipes any existing /sync/playback
              // entry, so start-based heartbeats never survived a hard kill. Pause
              // is the only call that persists a resume point.
              // Keep _simklLastScrobbleAction as 'start' (do NOT set 'pause'): the
              // native player re-runs this scrobble block on every progress event,
              // and a 'pause' value would re-enter the isPlaying start-branch above
              // on the next tick, re-sending start and wiping the position we just
              // saved. 'start' keeps that branch inert while pause refreshes the
              // resume point each interval.
              NativeScrobbleSession.simklLastScrobbleAction = 'start';
              SimklService.instance.scrobblePause(
                payload.imdbId!,
                NativeScrobbleSession.simklLastKnownProgress,
                season: NativeScrobbleSession.simklLastKnownSeason,
                episode: NativeScrobbleSession.simklLastKnownEpisode,
              );
              debugPrint(
                'Simkl: Heartbeat pause checkpoint at ${NativeScrobbleSession.simklLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            NativeScrobbleSession.simklLastScrobbleAction != null &&
            NativeScrobbleSession.simklLastScrobbleAction != 'pause' &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          if (simklProgress > 80) {
            NativeScrobbleSession.simklLastScrobbleAction = 'stop';
            SimklService.instance.scrobbleStop(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          } else {
            NativeScrobbleSession.simklLastScrobbleAction = 'pause';
            SimklService.instance.scrobblePause(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          }
        }
      }

      if (durationMs > 0) {
        final isPlaying = progress['isPlaying'] == true || progress['isBuffering'] == true;
        final season = payload.trackingContentType == 'series' ? progress['season'] as int? : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;
        final target = NativeMdblistSession.nativeMdblistTarget(
          payload,
          season: season,
          episode: episode,
        );
        final mdblistSession = target == null
            ? null
            : NativeMdblistSession.ensureNativeMdblistSession(payload, target);
        if (mdblistSession != null) {
          if (season != payload.mdblistSeason || episode != payload.mdblistEpisode) {
            await mdblistSession.switchTarget(
              target!,
              position: Duration(milliseconds: positionMs),
              duration: Duration(milliseconds: durationMs),
            );
            payload.mdblistSeason = season;
            payload.mdblistEpisode = episode;
          } else {
            mdblistSession.seek(
              Duration(milliseconds: positionMs),
              Duration(milliseconds: durationMs),
            );
          }
          if (completed) {
            mdblistSession.complete();
          } else if (isPlaying) {
            mdblistSession.play();
          } else {
            mdblistSession.pause();
          }
        }
      }

      // Local completion suppresses resume persistence only. Remote trackers
      // must still receive the threshold frame and all later progress/exit data.
      if (locallyTrackedMovie && payload.localMovieCompletionRecorded) return;

      if (payload.contentType == PlaybackContentType.series) {
        final season = progress['season'] as int?;
        final episode = progress['episode'] as int?;
        final seriesTitle = payload.seriesTitle ?? payload.title;
        if (season != null && episode != null) {
          await SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
            imdbId: payload.imdbId,
          );

          if (completed || (payload.localCompletionTracking && localCompleted)) {
            await EpisodeCompletionStorage.markEpisodeAsFinished(
              seriesTitle: seriesTitle,
              season: season,
              episode: episode,
              imdbId: payload.imdbId,
            );
          }
        }

        if (resumeId != null && payload.items.isNotEmpty) {
          final fallbackIndex = itemIndex.clamp(0, payload.items.length - 1).toInt();
          final item = payload.items.firstWhere(
            (i) => i.resumeId == resumeId,
            orElse: () => payload.items[fallbackIndex],
          );
          final persistedUrl =
              progressUrl ?? StreamRedirectResolver.resolvedStreamCache[resumeId] ?? item.url;

          await VideoProgressStorage.saveVideoPlaybackState(
            videoTitle: resumeId,
            videoUrl: persistedUrl,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
            imdbId: payload.imdbId,
          );
        }

        return;
      }

      final items = payload.items;
      if (items.isEmpty) return;
      final fallbackIndex = itemIndex.clamp(0, items.length - 1).toInt();
      final item = resumeId != null
          ? items.firstWhere(
              (i) => i.resumeId == resumeId,
              orElse: () => items[fallbackIndex],
            )
          : items[fallbackIndex];

      final videoTitle = item.resumeId ?? item.title;
      final persistedUrl =
          progressUrl ??
          (resumeId != null ? StreamRedirectResolver.resolvedStreamCache[resumeId] : null) ??
          item.url;

      await VideoProgressStorage.saveVideoPlaybackState(
        videoTitle: videoTitle,
        videoUrl: persistedUrl,
        positionMs: positionMs,
        durationMs: durationMs,
        speed: speed,
        aspect: aspect,
        imdbId: payload.imdbId,
      );

      if (payload.contentType == PlaybackContentType.single) {
        await VideoResumeStorage.upsertVideoResume(videoTitle, {
          'positionMs': positionMs,
          'durationMs': durationMs,
          'speed': speed,
          'aspect': aspect,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // ALSO save in collection format for Android TV playlist progress tracking
      // This allows the playlist screen to display progress indicators for collections
      if (payload.contentType == PlaybackContentType.collection && payload.seriesTitle != null) {
        debugPrint(
          '📺 AndroidTV Collection Save Check: seriesTitle="${payload.seriesTitle}", itemIndex=$fallbackIndex',
        );

        await SeriesProgressStorage.saveSeriesPlaybackState(
          seriesTitle: payload.seriesTitle!,
          season: 0, // Use season 0 for non-series collections
          episode: fallbackIndex + 1, // Use 1-based index as episode number
          positionMs: positionMs,
          durationMs: durationMs,
          speed: speed,
          aspect: aspect,
          imdbId: payload.imdbId,
        );

        debugPrint(
          '✅ AndroidTV Collection Save: title="${payload.seriesTitle}" S0E${fallbackIndex + 1} pos=${positionMs}ms',
        );

        // Mark as finished if completed
        if (completed) {
          await EpisodeCompletionStorage.markEpisodeAsFinished(
            seriesTitle: payload.seriesTitle!,
            season: 0,
            episode: fallbackIndex + 1,
            imdbId: payload.imdbId,
          );
          debugPrint(
            '✅ AndroidTV Collection: Marked S0E${fallbackIndex + 1} as finished',
          );
        }
      }
    } catch (e) {
      debugPrint('VideoPlayerLauncher: failed to persist progress: $e');
      rethrow;
    }
  }

  static Future<void> handlePlaybackFinished(
    AndroidTvPlaybackPayload payload,
  ) async {
    debugPrint(
      'VideoPlayerLauncher: Android TV playback finished for "${payload.title}"',
    );
    // Final Trakt scrobble stop on playback exit
    // Skip if last action was 'stop' (already stopped) or 'pause' (pause already
    // created the playback entry — sending stop would create a duplicate)
    NativeScrobbleSession.traktHeartbeatTimer?.cancel();
    NativeScrobbleSession.traktHeartbeatTimer = null;
    if (payload.traktScrobble &&
        payload.imdbId != null &&
        NativeScrobbleSession.traktLastScrobbleAction != 'stop' &&
        NativeScrobbleSession.traktLastScrobbleAction != 'pause') {
      TraktService.instance.scrobbleStop(
        payload.imdbId!,
        NativeScrobbleSession.traktLastKnownProgress,
        season: NativeScrobbleSession.traktLastKnownSeason,
        episode: NativeScrobbleSession.traktLastKnownEpisode,
        contentType: payload.trackingContentType,
      );
    }
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.traktLastKnownProgress = 0.0;
    NativeScrobbleSession.traktLastKnownSeason = null;
    NativeScrobbleSession.traktLastKnownEpisode = null;

    // Final Simkl scrobble stop on playback exit — parallel to the Trakt
    // cleanup above, including the same skip-after-pause nuance (a pause
    // already created Simkl's playback entry; stop would duplicate it).
    // The extra series-S/E guard: unlike the per-frame block, this direct
    // stop isn't gated by _simklSeriesSEUnresolved, so a series whose S/E
    // never resolved (every frame was skipped, last-known stays null) would
    // otherwise be finalized as a bogus movie. Skip it in that case.
    NativeScrobbleSession.simklHeartbeatTimer?.cancel();
    NativeScrobbleSession.simklHeartbeatTimer = null;
    final simklSeriesUnresolved =
        payload.trackingContentType == 'series' &&
        (NativeScrobbleSession.simklLastKnownSeason == null ||
            NativeScrobbleSession.simklLastKnownEpisode == null);
    if (payload.simklScrobble &&
        payload.imdbId != null &&
        NativeScrobbleSession.simklLastScrobbleAction != 'stop' &&
        NativeScrobbleSession.simklLastScrobbleAction != 'pause' &&
        !simklSeriesUnresolved) {
      SimklService.instance.scrobbleStop(
        payload.imdbId!,
        NativeScrobbleSession.simklLastKnownProgress,
        season: NativeScrobbleSession.simklLastKnownSeason,
        episode: NativeScrobbleSession.simklLastKnownEpisode,
      );
    }
    NativeScrobbleSession.simklLastScrobbleAction = null;
    NativeScrobbleSession.simklLastKnownProgress = 0.0;
    NativeScrobbleSession.simklLastKnownSeason = null;
    NativeScrobbleSession.simklLastKnownEpisode = null;
    await NativeMdblistSession.closeNativeMdblist(payload);
  }
}
