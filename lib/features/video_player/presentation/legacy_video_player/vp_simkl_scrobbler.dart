import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/simkl/simkl_service.dart';

abstract interface class VpSimklScrobblerHost {
  bool get mounted;
  bool get validationGateActive;
  bool get isPlaying;
  Duration get duration;
  String? get effectiveContentImdbId;
  String? get contentImdbId;
  String? get contentType;
  String? get currentSeriesImdbId;
  String? get episodeTrackerProgressImdbId;
  ({int? season, int? episode}) traktSeasonEpisode();
  void bindEpisodeTrackerProgressIdentity(String imdbId);
  bool get simklScrobble;
  double traktProgress();
  SeriesPlaylist? get seriesPlaylist;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
}

class VpSimklScrobbler {
  VpSimklScrobbler(this._host);
  final VpSimklScrobblerHost _host;

  // Simkl scrobble state — a fully parallel mirror of the Trakt fields above
  // (independent dedup guard + heartbeat; the two trackers never share state).
  bool simklScrobbleEnabled = false;
  bool launchSimklPercentSpent = false;
  // Per-episode Simkl cross-device snapshot ("season_episode" → 0-100),
  // refreshed by the launcher and used when switching episodes in-session.
  Map<String, double>? simklEpisodeProgress;
  String? simklLastScrobbleAction;
  Timer? simklHeartbeatTimer;

  // ── Simkl scrobble machine — fully parallel mirror of the Trakt one above.
  // Zero shared state: its own enable flag, dedup guard and heartbeat, driven
  // by the same (tracker-agnostic) _traktProgress()/_traktSeasonEpisode()
  // helpers. See the Simkl integration plan.

  Future<void> initSimklScrobble() async {
    if (!_host.simklScrobble) return;
    if (_host.contentImdbId == null) return;
    if (_host.contentType != 'movie' && _host.contentType != 'series') return;
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    simklScrobbleEnabled =
        policy.scrobbles(TrackingSource.simkl) &&
        await SimklService.instance.isAuthenticated();
    if (!_host.mounted) return;
    // Pause-centric model: do NOT POST Simkl's /scrobble/start. Unlike Trakt,
    // it persists NO resumable position AND deletes the existing /sync/playback
    // entry (verified: returns id:0, wipes the session). We leave the resume
    // point untouched and let the pause-based heartbeat keep it current.
    // BUT still stamp the marker 'start' (no POST) — the local action marker
    // must read "playing" so a later user-pause / exit-stop isn't dedup-
    // suppressed at _simklScrobble's guard. Mirrors the Trakt block and the TV
    // launcher's self-healing marker. (Field assignment, NOT _simklScrobble
    // ('start'), which now routes to a pause POST.)
    if (!_host.validationGateActive &&
        simklScrobbleEnabled &&
        _host.isPlaying &&
        _host.duration > Duration.zero) {
      simklLastScrobbleAction = 'start';
      startSimklHeartbeat();
    }
  }

  /// A series whose season/episode can't be resolved must NOT be scrobbled to
  /// Simkl: [SimklService._scrobble] would send the show id in a movie-shaped
  /// body, recording a bogus movie on the account. A movie legitimately has
  /// (null, null), so this only blocks the series case. (Trakt has the same
  /// latent gap; this guard is Simkl-only per the no-touch-Trakt convention.)
  bool simklSeriesSEUnresolved(({int? season, int? episode}) se) =>
      _host.contentType == 'series' &&
      (se.season == null || se.episode == null);

  void simklScrobble(String action) {
    if (_host.validationGateActive) return;
    if (!simklScrobbleEnabled || _host.contentImdbId == null) return;
    final imdbId = _host.contentImdbId!;
    final progress = _host.traktProgress();
    final se = _host.traktSeasonEpisode();
    if (simklSeriesSEUnresolved(se)) return;
    // Simkl marks watched server-side at ≥80% on stop — mirror Trakt's rule
    // and finalize instead of keeping a start/pause session alive.
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (simklLastScrobbleAction == action) return;
    simklLastScrobbleAction = action;
    switch (action) {
      // 'start' shares the pause path (no caller passes it in the pause-centric
      // model; play stamps the marker directly). Kept defensive and merged so
      // the two can't silently diverge: NEVER send Simkl's /scrobble/start — it
      // persists nothing and wipes the resume point, so a 'start' intent maps to
      // a pause checkpoint.
      case 'start':
      case 'pause':
        SimklService.instance.scrobblePause(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
      case 'stop':
        SimklService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        break;
    }
  }

  /// Periodic Simkl checkpoint — comfortably above Simkl's 20-second per-user
  /// scrobble rate lock. Uses /scrobble/pause (NOT /scrobble/start): on Simkl,
  /// start returns id:0 and persists NO resumable position — only pause/stop
  /// create the /sync/playback entry that Continue Watching + episode-card
  /// resume read. So the heartbeat pauses to keep a resume point current every
  /// interval; a hard kill (SIGINT/power-off, no graceful stop) then still
  /// resumes from the last checkpoint instead of the episode start.
  void startSimklHeartbeat() {
    simklHeartbeatTimer?.cancel();
    simklHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_host.validationGateActive ||
          !simklScrobbleEnabled ||
          _host.contentImdbId == null) {
        return;
      }
      if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
      final imdbId = _host.contentImdbId!;
      final progress = _host.traktProgress();
      final se = _host.traktSeasonEpisode();
      if (simklSeriesSEUnresolved(se)) return;
      if (progress > 80) {
        simklLastScrobbleAction = 'stop';
        SimklService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
        );
        debugPrint(
          'Simkl: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        stopSimklHeartbeat();
        return;
      }
      // Force-send pause (direct call, bypasses dedup) to checkpoint a RESUMABLE
      // position. Simkl's /scrobble/start saves nothing (id:0); only pause/stop
      // persist to /sync/playback, so this must be pause to survive a hard kill.
      // Leave the marker 'start' (live), NOT 'pause': stamping 'pause' here would
      // make the user's real pause dedup-suppress at _simklScrobble and strand
      // the true pause position at this (older) heartbeat %.
      simklLastScrobbleAction = 'start';
      SimklService.instance.scrobblePause(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      debugPrint(
        'Simkl: Heartbeat pause checkpoint at ${progress.toStringAsFixed(1)}%',
      );
    });
  }

  void stopSimklHeartbeat() {
    simklHeartbeatTimer?.cancel();
    simklHeartbeatTimer = null;
  }

  /// Simkl reaction to a user seek. Deliberately TRANSITION-ONLY, unlike
  /// Trakt's seek handler which re-sends start with fresh progress on every
  /// seek: Simkl's docs say not to call /scrobble/start on seek events (plus
  /// a 20s rate lock), so this only acts when the seek changes the effective
  /// action — crossing the 80% boundary (→ stop), or seeking back below it
  /// after a stop (→ a new start). The 2-minute heartbeat carries fresh
  /// progress either way.
  void simklScrobbleSeek(Duration seekTarget) {
    if (_host.validationGateActive) return;
    if (!simklScrobbleEnabled || _host.contentImdbId == null) return;
    if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
    final imdbId = _host.contentImdbId!;
    final progress =
        (seekTarget.inMilliseconds / _host.duration.inMilliseconds * 100).clamp(
          0.0,
          100.0,
        );
    final se = _host.traktSeasonEpisode();
    if (simklSeriesSEUnresolved(se)) return;
    if (progress > 80 && simklLastScrobbleAction != 'stop') {
      simklLastScrobbleAction = 'stop';
      SimklService.instance.scrobbleStop(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      stopSimklHeartbeat();
    } else if (progress <= 80 && simklLastScrobbleAction == 'stop') {
      // Seeked back under 80% after a finalize — re-establish a RESUMABLE
      // session via pause (start would wipe it and persist nothing) and resume
      // the heartbeat.
      simklLastScrobbleAction = 'pause';
      SimklService.instance.scrobblePause(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
      );
      startSimklHeartbeat();
    }
  }

  /// Current episode's Simkl snapshot percent. This mirrors the Trakt lookup
  /// above but remains independently stored so remote unwatch changes never
  /// mutate local playback history.
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false}) async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!forGuide && !policy.progressFrom(TrackingSource.simkl)) return null;
    final imdbId = _host.currentSeriesImdbId;
    if (imdbId == null) return null;
    _host.bindEpisodeTrackerProgressIdentity(imdbId);

    // Await before resolving the episode identity for the same race-safety as
    // [_currentEpisodeTraktPercent].
    if (simklEpisodeProgress == null) {
      final loaded =
          await TrackerEpisodeProgressStorage.getEpisodeSimklProgress(
            imdbId: imdbId,
          );
      if (_host.episodeTrackerProgressImdbId != imdbId) return null;
      simklEpisodeProgress = loaded;
    }

    int? season;
    int? episode;
    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlist = _host.activePlaylist;
      if (playlist == null ||
          _host.currentIndex < 0 ||
          _host.currentIndex >= playlist.length) {
        return null;
      }
      SeriesEpisode? currentEpisode;
      for (final candidate in seriesPlaylist.allEpisodes) {
        if (candidate.originalIndex == _host.currentIndex) {
          currentEpisode = candidate;
          break;
        }
      }
      if (currentEpisode == null) return null;
      season = currentEpisode.seriesInfo.season;
      episode = currentEpisode.seriesInfo.episode;
    } else if (_host.effectiveContentType == 'series') {
      season = _host.effectiveContentSeason;
      episode = _host.effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = simklEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.simkl, percent)
        : percent;
  }
}
