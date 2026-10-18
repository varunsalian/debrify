import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpSourcePlaylistSwitchHost {
  Map<String, String>? get activeHttpHeaders;
  set activeHttpHeaders(Map<String, String>? v);
  List<PlaylistEntry>? get activePlaylist;
  set activePlaylist(List<PlaylistEntry>? v);
  set allowResumeForManualSelection(bool v);
  SeriesPlaylist? get cachedSeriesPlaylist;
  set cachedSeriesPlaylist(SeriesPlaylist? v);
  int get currentIndex;
  set currentIndex(int v);
  String? get currentSeriesImdbId;
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  String? get currentStreamUrl;
  set currentStreamUrl(String? v);
  List<Torrent>? get effectiveSources;
  set episodeMetadataReady(Future<void>? v);
  int get episodeNavigationGeneration;
  set episodeNavigationGeneration(int v);
  set isManualEpisodeSelection(bool v);
  set isTransitioning(bool v);
  set manualSourceGateActive(bool v);
  Torrent? get openedWatchSource;
  mk.Player get player;
  int get playlistIdentityToken;
  set playlistIdentityToken(int v);
  Duration get position;
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  ResumeWriteGuard get resumeWriteGuard;
  SeriesPlaylist? get seriesPlaylist;
  MediaServerWatchController get serverWatch;
  SeriesPlaylist? get syntheticGuidePlaylist;
  set transitionPhase(int v);
  set transitionPhase2Started(DateTime? v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set transitionStopTimer(Timer? v);
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  BuildContext get context;
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  Future<void> commitValidatedStremioSource(Torrent? source);
  void resumeTrackingAfterValidationGate();
  void tvAbandonScrub();
  void startTransitionOverlay();
  void clearBufferingIndicator();
  Future<void> waitForVideoReady();
  ({int? season, int? episode}) traktSeasonEpisode();
  Future<void> preloadEpisodeInfo();
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  });
  void hideSourceSheet();
  void setState(VoidCallback fn);
  bool get mounted;
  Future<void> switchMdblistTarget();
  Future<void> seekForResume(int posMs, {bool verifyLanding = false});
  Future<void> saveResume({bool debounced = false, Duration? positionOverride});
  Future<void> restoreTrackPreferences();
}

class VpSourcePlaylistSwitch {
  VpSourcePlaylistSwitch(this._host);
  final VpSourcePlaylistSwitchHost _host;

  Future<bool> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  }) async {
    if (request == null) _host.episodeNavigationGeneration++;
    if (request?.isCurrent == false) return false;
    _host.hideSourceSheet();
    _host.clearBufferingIndicator();
    final outgoingPlaylist = _host.activePlaylist == null
        ? null
        : List<PlaylistEntry>.of(_host.activePlaylist!);
    final outgoingIndex = _host.currentIndex;
    final outgoingCachedSeries = _host.cachedSeriesPlaylist;
    final outgoingSourceIndex = _host.currentSourceIndex;
    // If a startup resume never landed, the live position is a restart
    // artifact — carry the HELD target across the switch (and into the
    // failure-restore path) so the new source opens at the bookmark, not ~0.
    // Pure query: the guard itself stays armed for the checkpoint save below.
    final outgoingHeldMs = _host.resumeWriteGuard.heldTargetIfBlocked(
      _host.position.inMilliseconds,
    );
    final outgoingPosition = outgoingHeldMs != null
        ? Duration(milliseconds: outgoingHeldMs)
        : _host.position;
    final outgoingDirectUrl = _host.currentStreamUrl;
    final outgoingHeaders = _host.activeHttpHeaders;
    final selectedSource =
        (_host.effectiveSources != null &&
            sourceIndex >= 0 &&
            sourceIndex < _host.effectiveSources!.length)
        ? _host.effectiveSources![sourceIndex]
        : null;
    // Capture the episode we're on BEFORE swapping the playlist, so we can
    // land on it in the new source instead of jumping to the pack's first
    // entry (S1E1). Read from the current playlist entry (tracks auto-advance).
    // An episode-guide fetch targets a DIFFERENT episode: land there instead.
    final current = _host.traktSeasonEpisode();
    final explicitTarget = targetSeason != null && targetEpisode != null;
    final se = explicitTarget
        ? (season: targetSeason, episode: targetEpisode)
        : current;
    // Checkpoint the OUTGOING episode now, while _activePlaylist/_currentIndex
    // still point at it — after the swap the index would resolve against the
    // new playlist. _loadPlaylistIndex below is told to skip its own save.
    await _host.saveResume();
    if (!_host.mounted || request?.isCurrent == false) return false;
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
    });
    _host.startTransitionOverlay();
    try {
      await _host.player.pause();
    } catch (_) {}
    if (!_host.mounted || request?.isCurrent == false) return false;

    // Replace playlist and invalidate series cache. A source/episode switch
    // stays within the same show, so the full TVMaze episode list carries
    // over — without it, guide adjacency and the full episode sheet would go
    // dark until another TVMaze fetch succeeds (never, when offline).
    final outgoingSeries = _host.seriesPlaylist ?? _host.syntheticGuidePlaylist;
    final carriedGuide = outgoingSeries?.fullTvmazeEpisodes.isNotEmpty == true
        ? outgoingSeries!.fullTvmazeEpisodes
        : null;
    final carriedImdbId = outgoingSeries?.imdbId ?? _host.currentSeriesImdbId;
    final carriedTvmazeShowId = outgoingSeries?.tvmazeShowId;
    final carriedTvmazeShowName = outgoingSeries?.tvmazeShowName;
    final carriedPosterUrl = outgoingSeries?.showPosterUrl;
    void replacePlaylist() => _host.setState(() {
      _host.currentSourceIndex = sourceIndex;
      _host.activePlaylist = newPlaylist;
      _host.cachedSeriesPlaylist = null;
      _host.playlistIdentityToken++;
    });
    if (request != null) {
      if (!request.replacePlaylist(replacePlaylist)) return false;
    } else {
      replacePlaylist();
    }
    final rebuilt = _host.seriesPlaylist;
    if (rebuilt != null) {
      rebuilt.imdbId ??= carriedImdbId;
      rebuilt.tvmazeShowId ??= carriedTvmazeShowId;
      rebuilt.tvmazeShowName ??= carriedTvmazeShowName;
      rebuilt.showPosterUrl ??= carriedPosterUrl;
      if (carriedGuide != null &&
          carriedGuide.isNotEmpty &&
          rebuilt.fullTvmazeEpisodes.isEmpty) {
        rebuilt.fullTvmazeEpisodes = carriedGuide;
      }
      _host.episodeMetadataReady = _host.preloadEpisodeInfo();
    }

    // Resume the SAME episode from the new source (a season/complete pack would
    // otherwise restart at S1E1); _loadPlaylistIndex restores its saved
    // position.
    var targetIndex = 0;
    // Whether the new source landed on the SAME content we were watching — only
    // then does "prefer the checkpointed local position over Trakt" apply. When
    // we fall back to a different episode, its own Trakt resume must still work.
    // An explicit episode-guide target is different content by definition.
    var landedOnSameContent =
        !explicitTarget ||
        (targetSeason == current.season && targetEpisode == current.episode);
    var containsRequestedEpisode = true;
    if (se.season != null && se.episode != null) {
      final sp = _host.seriesPlaylist;
      final idx =
          sp?.findOriginalIndexBySeasonEpisode(se.season!, se.episode!) ?? -1;
      if (idx >= 0) {
        targetIndex = idx;
      } else if (newPlaylist.length == 1) {
        // A single resolved stream often has an unparseable name ("Torrentio
        // 1080p", anime/absolute numbering); its one entry IS the requested
        // episode — the fetch was episode-scoped. This must hold for manual
        // sheet picks too (no explicit target), or a legitimate singleton
        // would be rejected below without ever being opened. Mirrors the
        // Kotlin cursor's `episodes.size <= 1` exemption.
        targetIndex = 0;
      } else {
        landedOnSameContent = false;
        containsRequestedEpisode = false;
        // The exact episode isn't in this source. Don't fall back to raw entry
        // 0 — in torrent order that's often an extras/bonus clip. Land on the
        // first REAL episode (skips season 0 / specials) and warn the user.
        final firstReal = sp?.getFirstEpisodeOriginalIndex() ?? -1;
        if (firstReal >= 0) targetIndex = firstReal;
        if (_host.mounted && !validateExplicitSelection) {
          ScaffoldMessenger.of(_host.context).showSnackBar(
            SnackBar(
              content: Text(
                'S${se.season}E${se.episode} not in this source — playing from the start',
              ),
            ),
          );
        }
      }
    }
    // A source switch must resume the outgoing episode's position (saved above).
    // Clear any lingering manual-selection state first: if the user had manually
    // jumped to an episode within the last 30s, that stale flag makes
    // `_maybeRestoreResume` bail out and the new source opens at 0:00 instead of
    // resuming. The switch is not a "manual episode pick", so drop the flag.
    _host.isManualEpisodeSelection = false;
    _host.allowResumeForManualSelection = false;
    // Resume the checkpointed LOCAL position, not Trakt (this is a source swap
    // mid-episode, not a fresh open) — but only when the new source landed on
    // the same content; a fallback episode keeps its own Trakt resume.
    var committed = false;
    if (!validateExplicitSelection) {
      try {
        committed = await _host.loadPlaylistIndex(
          targetIndex,
          autoplay: true,
          skipInitialSave: true,
          preferLocalResume: landedOnSameContent,
          suppressResume: suppressResume,
          request: request,
        );
      } catch (error) {
        if (request == null) rethrow;
        debugPrint('Episode source load failed: $error');
        committed = false;
      }
    } else {
      _host.manualSourceGateActive = true;
      try {
        try {
          if (containsRequestedEpisode) {
            committed = await _host.loadPlaylistIndex(
              targetIndex,
              autoplay: true,
              skipInitialSave: true,
              preferLocalResume: landedOnSameContent,
              suppressResume: suppressResume,
              request: request,
              manualValidationSource: selectedSource,
              manualValidationSourceIndex: sourceIndex,
            );
          }
        } catch (error) {
          debugPrint(
            'Player: manual playlist source rejected '
            '(${error.runtimeType})',
          );
          committed = false;
        }
        if (!_host.mounted || request?.isCurrent == false) return false;
        if (!committed &&
            outgoingPlaylist != null &&
            outgoingPlaylist.isNotEmpty) {
          _host.setState(() {
            _host.activePlaylist = outgoingPlaylist;
            _host.cachedSeriesPlaylist = null;
            _host.playlistIdentityToken++;
            _host.currentSourceIndex = outgoingSourceIndex;
            _host.currentIndex = outgoingIndex.clamp(
              0,
              outgoingPlaylist.length - 1,
            );
          });
          final restored = await _host.loadPlaylistIndex(
            _host.currentIndex,
            autoplay: true,
            skipInitialSave: true,
            preferLocalResume: true,
          );
          if (restored && outgoingPosition > Duration.zero) {
            // Guarded: a failure-path restore must not leave the bookmark at
            // the mercy of a stream that answers this seek with a restart.
            await _host.seekForResume(outgoingPosition.inMilliseconds);
          }
        } else if (!committed &&
            outgoingDirectUrl != null &&
            outgoingDirectUrl.isNotEmpty) {
          // A direct launch has no active playlist to restore. The candidate
          // validator has stopped its media on failure, so explicitly rebuild
          // the outgoing direct session instead of leaving the player stopped
          // with the rejected playlist selected.
          _host.setState(() {
            _host.activePlaylist = null;
            _host.cachedSeriesPlaylist = null;
            _host.playlistIdentityToken++;
            _host.currentSourceIndex = outgoingSourceIndex;
            _host.currentIndex = outgoingIndex;
          });
          try {
            _host.activeHttpHeaders = outgoingHeaders;
            await _host.openMedia(
              mk.Media(outgoingDirectUrl, httpHeaders: _host.activeHttpHeaders),
              play: true,
            );
            await _host.waitForVideoReady();
            if (outgoingPosition > Duration.zero) {
              await _host.seekForResume(outgoingPosition.inMilliseconds);
            }
            _host.currentStreamUrl = outgoingDirectUrl;
            _host.serverWatch.commit(_host.openedWatchSource);
            unawaited(_host.restoreTrackPreferences());
          } catch (restoreError) {
            debugPrint(
              'Player: outgoing direct source restore failed '
              '(${restoreError.runtimeType})',
            );
          }
        }
      } finally {
        _host.manualSourceGateActive = false;
        _host.resumeTrackingAfterValidationGate();
      }
    }
    if (!_host.mounted) return false;
    if (!committed && request != null) {
      // Only roll back preparation. If media open has started, the request
      // retains the incoming identity so progress stays with that media.
      final restored = request.restorePlaylist(
        () => _host.setState(() {
          _host.activePlaylist = outgoingPlaylist;
          _host.cachedSeriesPlaylist = outgoingCachedSeries;
          _host.playlistIdentityToken++;
          _host.currentSourceIndex = outgoingSourceIndex;
          _host.currentIndex = outgoingIndex;
          _host.currentStreamUrl = outgoingDirectUrl;
          _host.activeHttpHeaders = outgoingHeaders;
        }),
      );
      if (restored) await _host.switchMdblistTarget();
    }
    if (request?.isCurrent == false) return false;

    if (committed) {
      unawaited(_host.commitValidatedStremioSource(selectedSource));
    }
    if (validateExplicitSelection && !committed) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(
          content: Text('This source is unavailable. Choose another source.'),
        ),
      );
    }

    // End transition (same pattern as _switchToStremioSource)
    _host.transitionStopTimer?.cancel();
    _host.transitionPhaseTimer?.cancel();
    _host.transitionPhase = 2;
    _host.transitionPhase2Started = DateTime.now();
    _host.setState(() {
      _host.isTransitioning = false;
    });
    _host.transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _host.rainbowController.stop();
      _host.transitionRunning = false;
      _host.rainbowActive = false;
      if (_host.mounted) _host.setState(() {});
    });
    return committed;
  }
}
