import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/foundation.dart';

abstract interface class VpLedgerScrobblerHost {
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

  /// The launch asked for Ledger scrobbling (policy + auth already applied).
  bool get ledgerScrobble;

  /// Tracker-agnostic percent watched, shared with the Trakt scrobbler.
  double traktProgress();
  SeriesPlaylist? get seriesPlaylist;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
}

/// Ledger scrobbling for the in-app player. Ledger follows Trakt's model:
/// START and PAUSE both save a resume point, and a STOP at or past the
/// user's watched percent records a play. So this mirrors the Trakt machine
/// (start on play, pause on pause, stop at the end, a two-minute start
/// heartbeat), with its own state: trackers never share dedup guards.
class VpLedgerScrobbler {
  VpLedgerScrobbler(this._host, {LedgerService? service})
    : _service = service ?? LedgerService.instance;

  final VpLedgerScrobblerHost _host;
  final LedgerService _service;

  bool ledgerScrobbleEnabled = false;

  /// The launch's explicit percent applies to the first load only.
  bool launchLedgerPercentSpent = false;

  /// Whether a resume consults Ledger at all: launches that scrobble to it,
  /// or any launch while it is the (connected) Progress source. Synchronous,
  /// so other launches take no extra async step (see [resumePercent]).
  bool consultsLedger(TrackingSourcePolicy policy) =>
      _host.ledgerScrobble ||
      policy.progressSource == WatchProgressSource.ledger;

  /// Per-episode snapshot ("season_episode" → 0-100) for in-session episode
  /// switches; cleared whenever the series changes.
  Map<String, double>? ledgerEpisodeProgress;
  String? ledgerLastScrobbleAction;
  Timer? ledgerHeartbeatTimer;

  /// The account's watched percent (50–100, default 80): a STOP at or past
  /// it records a play, so above it start/pause become stop. Read from the
  /// server when scrobbling starts.
  double _finishPercent = LedgerService.defaultFinishPercent.toDouble();

  Future<void> initLedgerScrobble() async {
    if (!_host.ledgerScrobble) return;
    if (_host.contentImdbId == null) return;
    if (_host.contentType != 'movie' && _host.contentType != 'series') return;
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    final enabled =
        policy.scrobbles(TrackingSource.ledger) &&
        await _service.isAuthenticated();
    if (!_host.mounted) return;
    if (enabled) {
      final finish = await _service.finishPercent();
      if (!_host.mounted) return;
      _finishPercent = finish.toDouble();
    }
    ledgerScrobbleEnabled = enabled;
    // Playback may have started before the policy resolved.
    if (enabled && _host.isPlaying && _host.duration > Duration.zero) {
      onPlaying();
    }
  }

  /// A series whose season/episode can't be resolved must not be scrobbled:
  /// it would be sent as a movie and record the wrong title.
  bool _ready(({int? season, int? episode}) se) {
    if (_host.contentType == 'movie') return true;
    return _host.contentType == 'series' &&
        se.season != null &&
        se.episode != null;
  }

  void _send(String action, double progress, ({int? season, int? episode}) se) {
    final imdbId = _host.contentImdbId;
    if (imdbId == null) return;
    final ledgerAction = switch (action) {
      'start' => LedgerScrobbleAction.start,
      'pause' => LedgerScrobbleAction.pause,
      _ => LedgerScrobbleAction.stop,
    };
    unawaited(
      _service.scrobble(
        ledgerAction,
        imdbId,
        progress,
        season: _host.contentType == 'series' ? se.season : null,
        episode: _host.contentType == 'series' ? se.episode : null,
      ),
    );
  }

  /// Deduplicated scrobble of [action] at the current position.
  void ledgerScrobble(String action) {
    if (_host.validationGateActive) return;
    if (!ledgerScrobbleEnabled || _host.contentImdbId == null) return;
    final progress = _host.traktProgress();
    final se = _host.traktSeasonEpisode();
    if (!_ready(se)) return;
    if ((action == 'start' || action == 'pause') &&
        progress >= _finishPercent) {
      action = 'stop';
    }
    if (ledgerLastScrobbleAction == action) return;
    ledgerLastScrobbleAction = action;
    _send(action, progress, se);
  }

  /// Playback (re)started: scrobble start and keep a heartbeat.
  void onPlaying() {
    if (_host.validationGateActive || _host.duration <= Duration.zero) return;
    ledgerScrobble('start');
    if (ledgerLastScrobbleAction == 'start') startLedgerHeartbeat();
  }

  /// The user paused (not a transition between items).
  void onPaused() {
    if (_host.validationGateActive) return;
    if (ledgerLastScrobbleAction == 'stop') return;
    ledgerScrobble('pause');
    stopLedgerHeartbeat();
  }

  /// Item finished, changed or the player is closing.
  void onStopped() {
    stopLedgerHeartbeat();
    ledgerScrobble('stop');
  }

  void startLedgerHeartbeat() {
    ledgerHeartbeatTimer?.cancel();
    ledgerHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_host.validationGateActive ||
          !ledgerScrobbleEnabled ||
          _host.contentImdbId == null) {
        return;
      }
      if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
      final progress = _host.traktProgress();
      final se = _host.traktSeasonEpisode();
      if (!_ready(se)) return;
      if (progress >= _finishPercent) {
        ledgerLastScrobbleAction = 'stop';
        _send('stop', progress, se);
        debugPrint('Ledger: heartbeat stop at ${progress.toStringAsFixed(1)}%');
        stopLedgerHeartbeat();
        return;
      }
      // Bypasses dedup on purpose: refreshes the saved resume point.
      ledgerLastScrobbleAction = 'start';
      _send('start', progress, se);
    });
  }

  void stopLedgerHeartbeat() {
    ledgerHeartbeatTimer?.cancel();
    ledgerHeartbeatTimer = null;
  }

  /// A user seek: re-send the new position (crossing 80% finalises).
  void ledgerScrobbleSeek(Duration seekTarget) {
    if (_host.validationGateActive) return;
    if (!ledgerScrobbleEnabled || _host.contentImdbId == null) return;
    if (!_host.isPlaying || _host.duration.inMilliseconds <= 0) return;
    final progress =
        (seekTarget.inMilliseconds / _host.duration.inMilliseconds * 100).clamp(
          0.0,
          100.0,
        );
    final se = _host.traktSeasonEpisode();
    if (!_ready(se)) return;
    if (progress >= _finishPercent) {
      ledgerLastScrobbleAction = 'stop';
      _send('stop', progress, se);
      stopLedgerHeartbeat();
    } else {
      ledgerLastScrobbleAction = 'start';
      _send('start', progress, se);
      startLedgerHeartbeat();
    }
  }

  void dispose() => stopLedgerHeartbeat();

  /// Resume candidate for the current item: a movie's saved Ledger resume
  /// point (read live, so a position saved on another device counts), or the
  /// current episode's launch-snapshot percent.
  Future<double?> resumePercent({required TrackingSourcePolicy policy}) async {
    // Only launches that track Ledger consult it, so playback without Ledger
    // resumes exactly as before; a Ledger failure never blocks the resume.
    if (!consultsLedger(policy)) return null;
    try {
      return await _resumePercent();
    } catch (error) {
      debugPrint('Ledger: resume lookup failed (${error.runtimeType})');
      return null;
    }
  }

  Future<double?> _resumePercent() async {
    if (_host.effectiveContentType != 'movie') {
      return currentEpisodeLedgerPercent();
    }
    final imdbId = _host.effectiveContentImdbId;
    if (!LedgerService.supportsId(imdbId)) return null;
    final policy = (await TrackingSourcePolicy.load()).forContent(imdbId);
    if (!policy.progressFrom(TrackingSource.ledger)) return null;
    if (!await _service.isAuthenticated()) return null;
    final percent = await _service.movieResumePercent(imdbId);
    if (!_host.mounted || _host.effectiveContentImdbId != imdbId) return null;
    return percent;
  }

  /// The current episode's Ledger percent from the launch snapshot.
  Future<double?> currentEpisodeLedgerPercent({bool forGuide = false}) async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!forGuide && !policy.progressFrom(TrackingSource.ledger)) return null;
    final imdbId = _host.currentSeriesImdbId;
    if (imdbId == null) return null;
    _host.bindEpisodeTrackerProgressIdentity(imdbId);
    // Await before resolving the current episode, so an episode switch while
    // this is in flight keys off the episode that is current afterwards.
    if (ledgerEpisodeProgress == null) {
      final loaded =
          await TrackerEpisodeProgressStorage.getConnectedEpisodeLedgerProgress(
            imdbId: imdbId,
          );
      if (_host.episodeTrackerProgressImdbId != imdbId) return null;
      ledgerEpisodeProgress = loaded;
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
      SeriesEpisode? current;
      for (final candidate in seriesPlaylist.allEpisodes) {
        if (candidate.originalIndex == _host.currentIndex) {
          current = candidate;
          break;
        }
      }
      if (current == null) return null;
      season = current.seriesInfo.season;
      episode = current.seriesInfo.episode;
    } else if (_host.effectiveContentType == 'series') {
      season = _host.effectiveContentSeason;
      episode = _host.effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;
    final percent = ledgerEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.ledger, percent)
        : percent;
  }
}
