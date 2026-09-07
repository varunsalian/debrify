import 'dart:async';

import '../../models/series_playlist.dart';
import '../../services/analytics_service.dart';
import '../../services/scrobble/scrobble.dart';
import '../../services/storage/playback_progress_store.dart';
import '../../services/tracking_source_policy.dart';
import 'models/playlist_entry.dart';

abstract interface class PlayerTrackerSession {
  String? get currentSeriesImdbId;
  SeriesPlaylist? get seriesPlaylist;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  String? get effectiveContentType;
  int? get effectiveContentSeason;
  int? get effectiveContentEpisode;
  bool get isPlaying;
  ({int? season, int? episode}) trackerSeasonEpisode();
}

class PlayerTrackerLifecycle {
  PlayerTrackerLifecycle(this.session);
  final PlayerTrackerSession session;
  late final ScrobbleCoordinator coordinator;
  bool launchTraktPercentSpent = false;
  bool launchSimklPercentSpent = false;
  bool launchMdblistPercentSpent = false;
  Map<String, double>? _traktEpisodeProgress;
  Map<String, double>? _simklEpisodeProgress;
  Map<String, double>? _mdblistEpisodeProgress;
  String? _episodeTrackerProgressImdbId;
  Timer? _analyticsHeartbeatTimer;

  void initializeScrobble({
    required ScrobblePlayback playback,
    required bool traktRequested,
    required bool simklRequested,
    required bool mdblistRequested,
    required Future<void> playerReady,
  }) {
    coordinator = ScrobbleCoordinator(
      playback: playback,
      targets: [
        TraktScrobbleTarget.production(
          requested: traktRequested,
          playback: playback,
        ),
        SimklScrobbleTarget.production(
          requested: simklRequested,
          playback: playback,
        ),
        MdblistScrobbleSessionTarget.production(
          requested: mdblistRequested,
          playback: playback,
          playerReady: playerReady,
        ),
      ],
    );
    coordinator.init();
  }

  /// Periodic analytics ping so a long, interaction-free watch keeps the
  /// analytics session alive. Independent of Trakt (fires regardless of Trakt
  /// auth); only emits while actually playing. No content details are sent.
  void startHeartbeat() {
    _analyticsHeartbeatTimer?.cancel();
    _analyticsHeartbeatTimer = Timer.periodic(
      AnalyticsService.heartbeatInterval,
      (_) {
        if (session.isPlaying) {
          AnalyticsService.playbackHeartbeat('dart');
        }
      },
    );
  }

  void cancelHeartbeat() => _analyticsHeartbeatTimer?.cancel();

  /// The current episode's cross-device Trakt progress percent (0-100), or null.
  /// Loaded once per series from the dedicated store (kept apart from the
  /// ms-based resume state) and looked up by the current episode's season/episode.
  void _bindEpisodeTrackerProgressIdentity(String imdbId) {
    if (_episodeTrackerProgressImdbId == imdbId) return;
    _episodeTrackerProgressImdbId = imdbId;
    _traktEpisodeProgress = null;
    _simklEpisodeProgress = null;
    _mdblistEpisodeProgress = null;
  }

  Future<double?> currentEpisodeTraktPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.trakt)) return null;
    final imdbId = session.currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);

    // Await BEFORE reading session.currentIndex/season/episode below, so that if the
    // user advances to a different episode while this is in flight, we key
    // off the episode that's actually current when the fetch resolves.
    if (_traktEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeTraktProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _traktEpisodeProgress = loaded;
    }

    int? season;
    int? episode;
    final seriesPlaylist = session.seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlist = session.activePlaylist;
      if (playlist == null ||
          session.currentIndex < 0 ||
          session.currentIndex >= playlist.length) {
        return null;
      }
      // Must be the CURRENT episode — no orElse-to-first fallback, or we'd seek to
      // an unrelated episode's Trakt position on filtered/reordered playlists.
      SeriesEpisode? ep;
      for (final e in seriesPlaylist.allEpisodes) {
        if (e.originalIndex == session.currentIndex) {
          ep = e;
          break;
        }
      }
      if (ep == null) return null;
      season = ep.seriesInfo.season;
      episode = ep.seriesInfo.episode;
    } else if (session.effectiveContentType == 'series') {
      // Single-file episode (e.g. a direct-link stream) — no playlist to derive
      // season/episode from; fall back to the same launch args the local
      // resume-state lookup uses.
      season = session.effectiveContentSeason;
      episode = session.effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = _traktEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.trakt, percent)
        : percent;
  }

  /// Current episode's Simkl snapshot percent. This mirrors the Trakt lookup
  /// above but remains independently stored so remote unwatch changes never
  /// mutate local playback history.
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.simkl)) return null;
    final imdbId = session.currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);

    // Await before resolving the episode identity for the same race-safety as
    // [currentEpisodeTraktPercent].
    if (_simklEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeSimklProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _simklEpisodeProgress = loaded;
    }

    int? season;
    int? episode;
    final seriesPlaylist = session.seriesPlaylist;
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      final playlist = session.activePlaylist;
      if (playlist == null ||
          session.currentIndex < 0 ||
          session.currentIndex >= playlist.length) {
        return null;
      }
      SeriesEpisode? currentEpisode;
      for (final candidate in seriesPlaylist.allEpisodes) {
        if (candidate.originalIndex == session.currentIndex) {
          currentEpisode = candidate;
          break;
        }
      }
      if (currentEpisode == null) return null;
      season = currentEpisode.seriesInfo.season;
      episode = currentEpisode.seriesInfo.episode;
    } else if (session.effectiveContentType == 'series') {
      season = session.effectiveContentSeason;
      episode = session.effectiveContentEpisode;
    }
    if (season == null || episode == null) return null;

    final percent = _simklEpisodeProgress!['${season}_$episode'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.simkl, percent)
        : percent;
  }

  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false}) async {
    final policy = await TrackingSourcePolicy.load();
    if (!forGuide && !policy.progressFrom(TrackingSource.mdblist)) return null;
    final imdbId = session.currentSeriesImdbId;
    if (imdbId == null) return null;
    _bindEpisodeTrackerProgressIdentity(imdbId);
    if (_mdblistEpisodeProgress == null) {
      final loaded = await PlaybackProgressStore.getEpisodeMdblistProgress(
        imdbId: imdbId,
      );
      if (_episodeTrackerProgressImdbId != imdbId) return null;
      _mdblistEpisodeProgress = loaded;
    }
    final se = session.trackerSeasonEpisode();
    if (se.season == null || se.episode == null) return null;
    final percent = _mdblistEpisodeProgress!['${se.season}_${se.episode}'];
    return forGuide
        ? policy.guideProgressFrom(TrackingSource.mdblist, percent)
        : percent;
  }

}
