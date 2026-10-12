import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_service.dart';

abstract interface class VpTraktScrobblerHost {
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
  bool get traktScrobble;
  Duration get persistablePosition;
  ResumeWriteGuard get resumeWriteGuard;
  DeferredStartupSeek get stremioTvStartupSeek;
  SeriesPlaylist? get seriesPlaylist;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
}

class VpTraktScrobbler {
  VpTraktScrobbler(this._host);
  final VpTraktScrobblerHost _host;

  // Trakt scrobble state
  bool traktScrobbleEnabled = false;
  // The launched item's widget.traktProgressPercent is a first-load-only
  // signal; once spent it must not apply to a later switched-to episode.
  bool launchTraktPercentSpent = false;
  // Per-episode Trakt cross-device progress ("season_episode" → 0-100), loaded
  // once per series; drives resume for episodes switched to in-session.
  Map<String, double>? traktEpisodeProgress;
  String? traktLastScrobbleAction;
  Timer? traktHeartbeatTimer;

  Future<void> initTraktScrobble() async {
    if (!_host.traktScrobble) return;
    if (_host.contentImdbId == null) return;
    if (_host.contentType != 'movie' && _host.contentType != 'series') return;
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    traktScrobbleEnabled =
        policy.scrobbles(TrackingSource.trakt) &&
        await TraktService.instance.isAuthenticated();
    if (!_host.mounted) return;
    // If player started playing before auth resolved, scrobble start now
    if (traktScrobbleEnabled &&
        _host.isPlaying &&
        _host.duration > Duration.zero) {
      traktScrobble('start');
      if (traktLastScrobbleAction == 'start') {
        startTraktHeartbeat();
      }
    }
  }

  double traktProgress() {
    if (_host.duration.inMilliseconds <= 0) return 0.0;
    return (_host.persistablePosition.inMilliseconds /
            _host.duration.inMilliseconds *
            100)
        .clamp(0.0, 100.0);
  }

  void traktScrobble(String action) {
    if (_host.validationGateActive) return;
    if (!traktScrobbleEnabled || _host.contentImdbId == null) return;
    final imdbId = _host.contentImdbId!;
    final progress = traktProgress();
    final se = _host.traktSeasonEpisode();
    if (!TraktService.isScrobbleReady(
      contentType: _host.contentType,
      season: se.season,
      episode: se.episode,
    )) {
      return;
    }
    // Trakt rejects start/pause when progress > 80% — send stop instead
    if ((action == 'start' || action == 'pause') && progress > 80) {
      action = 'stop';
    }
    if (traktLastScrobbleAction == action) return;
    traktLastScrobbleAction = action;
    switch (action) {
      case 'start':
        TraktService.instance.scrobbleStart(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
          contentType: _host.contentType,
        );
        break;
      case 'pause':
        TraktService.instance.scrobblePause(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
          contentType: _host.contentType,
        );
        break;
      case 'stop':
        TraktService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
          contentType: _host.contentType,
        );
        break;
    }
  }

  /// Start periodic heartbeat to checkpoint progress to Trakt every 2 minutes.
  void startTraktHeartbeat() {
    traktHeartbeatTimer?.cancel();
    traktHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_host.validationGateActive ||
          !traktScrobbleEnabled ||
          _host.contentImdbId == null) {
        return;
      }
      if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
      final imdbId = _host.contentImdbId!;
      final progress = traktProgress();
      final se = _host.traktSeasonEpisode();
      if (!TraktService.isScrobbleReady(
        contentType: _host.contentType,
        season: se.season,
        episode: se.episode,
      )) {
        return;
      }
      // Trakt rejects start/pause above 80% — send stop and end heartbeat
      if (progress > 80) {
        traktLastScrobbleAction = 'stop';
        TraktService.instance.scrobbleStop(
          imdbId,
          progress,
          season: se.season,
          episode: se.episode,
          contentType: _host.contentType,
        );
        debugPrint(
          'Trakt: Heartbeat stop at ${progress.toStringAsFixed(1)}% (>80%)',
        );
        stopTraktHeartbeat();
        return;
      }
      // Force-send start (bypass dedup) to keep session alive and checkpoint progress
      traktLastScrobbleAction = 'start';
      TraktService.instance.scrobbleStart(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
        contentType: _host.contentType,
      );
      debugPrint(
        'Trakt: Heartbeat scrobble at ${progress.toStringAsFixed(1)}%',
      );
    });
  }

  void stopTraktHeartbeat() {
    traktHeartbeatTimer?.cancel();
    traktHeartbeatTimer = null;
  }

  /// Send updated progress to Trakt after a user seek (bypasses dedup guard).
  ///
  /// This is also the shared funnel every user-initiated seek passes through
  /// (scrubber, tap/DPAD seek, pan, skip-segment), so it is where the resume
  /// write guard learns the user has taken over the position. Released before
  /// the Trakt-specific early returns below — the handover happens whether or
  /// not Trakt is connected.
  void traktScrobbleSeek(Duration seekTarget) {
    _host.stremioTvStartupSeek.cancel();
    _host.resumeWriteGuard.noteUserSeek();
    if (_host.validationGateActive) return;
    if (!traktScrobbleEnabled || _host.contentImdbId == null) return;
    if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
    final imdbId = _host.contentImdbId!;
    final progress =
        (seekTarget.inMilliseconds / _host.duration.inMilliseconds * 100).clamp(
          0.0,
          100.0,
        );
    final se = _host.traktSeasonEpisode();
    if (!TraktService.isScrobbleReady(
      contentType: _host.contentType,
      season: se.season,
      episode: se.episode,
    )) {
      return;
    }
    // Trakt rejects start above 80% — send stop instead
    if (progress > 80) {
      traktLastScrobbleAction = 'stop';
      TraktService.instance.scrobbleStop(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
        contentType: _host.contentType,
      );
      stopTraktHeartbeat();
    } else {
      traktLastScrobbleAction = 'start';
      TraktService.instance.scrobbleStart(
        imdbId,
        progress,
        season: se.season,
        episode: se.episode,
        contentType: _host.contentType,
      );
      startTraktHeartbeat();
    }
  }

  Future<double?> currentEpisodeTraktPercent({bool forGuide = false}) async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!forGuide && !policy.progressFrom(TrackingSource.trakt)) return null;
    final imdbId = _host.currentSeriesImdbId;
    if (imdbId == null) return null;
    _host.bindEpisodeTrackerProgressIdentity(imdbId);

    // Await BEFORE reading _currentIndex/season/episode below, so that if the
    // user advances to a different episode while this is in flight, we key
    // off the episode that's actually current when the fetch resolves.
    if (traktEpisodeProgress == null) {
      final loaded =
          await TrackerEpisodeProgressStorage.getEpisodeTraktProgress(
            imdbId: imdbId,
          );
      if (_host.episodeTrackerProgressImdbId != imdbId) return null;
      traktEpisodeProgress = loaded;
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
      // Must be the CURRENT episode — no orElse-to-first fallback, or we'd seek to
      // an unrelated episode's Trakt position on filtered/reordered playlists.
      SeriesEpisode? ep;
      for (final e in seriesPlaylist.allEpisodes) {
        if (e.originalIndex == _host.currentIndex) {
          ep = e;
          break;
        }
      }
      if (ep == null) return null;
      season = ep.seriesInfo.season;
      episode = ep.seriesInfo.episode;
    } else if (_host.effectiveContentType == 'series') {
      // Single-file episode (e.g. a direct-link stream) — no playlist to derive
      // season/episode from; fall back to the same launch args the local
      // resume-state lookup uses.
      season = _host.effectiveContentSeason;
      episode = _host.effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = traktEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.trakt, percent)
        : percent;
  }
}
