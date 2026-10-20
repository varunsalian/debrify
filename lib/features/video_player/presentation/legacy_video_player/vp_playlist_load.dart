import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlaylistLoadHost {
  Map<String, String>? get activeHttpHeaders;
  set activeHttpHeaders(Map<String, String>? v);
  bool get activeMediaShouldPlay;
  set activeMediaShouldPlay(bool v);
  bool get activeMediaUserPaused;
  set activeMediaUserPaused(bool v);
  mk.Media? get activeOpenedMedia;
  set activeOpenedMedia(mk.Media? v);
  List<PlaylistEntry>? get activePlaylist;
  set allowResumeForManualSelection(bool v);
  int get currentIndex;
  set currentIndex(int v);
  String? get currentStreamUrl;
  set currentStreamUrl(String? v);
  int get episodeNavigationGeneration;
  set episodeNavigationGeneration(int v);
  bool get isAutoAdvancing;
  set isAutoAdvancing(bool v);
  set isManualEpisodeSelection(bool v);
  set isTransitioning(bool v);
  Timer? get manualSelectionResetTimer;
  set manualSelectionResetTimer(Timer? v);
  Torrent? get openedWatchSource;
  bool get pausedByLifecycle;
  int get pikPakRetryId;
  set pikPakRetryId(int v);
  mk.Player get player;
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  int get resumeVerifyEpoch;
  set resumeVerifyEpoch(int v);
  ResumeWriteGuard get resumeWriteGuard;
  SeriesPlaylist? get seriesPlaylist;
  MediaServerWatchController get serverWatch;
  bool get sleepStopLatched;
  set sleepStopLatched(bool v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  void tvAbandonScrub();
  void resetSubtitleState();
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
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  });
  Future<void> waitForVideoReady();
  Future<String> resolvePlaylistEntryUrl(int index);
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  Future<void> saveResume();
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  });
  void stopTraktHeartbeat();
  void traktScrobble(String action);
  void stopSimklHeartbeat();
  void simklScrobble(String action);
  void updateMdblistPosition();
  Future<void> switchMdblistTarget();
  void resetLocalCompletionState();
  set skipSegmentsMediaReady(bool v);
  void resetSkipSegmentState();
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  });
  Future<void> restoreTrackPreferences();
}

class VpPlaylistLoad {
  VpPlaylistLoad(this._host);
  final VpPlaylistLoadHost _host;

  /// Tear down the black transition overlay when a load fails partway (bad
  /// index, or no resolvable URL — e.g. a dead debrid/torbox link on the next
  /// episode). Without this the UI stays stuck on the black transition
  /// `Container` and the rainbow overlay never stops. The source-switch caller
  /// clears transition state itself, so this only rescues the other callers
  /// (`_goToNextEpisode`, shuffle). Safe to call redundantly.
  void clearTransitionOnFailure() {
    _host.transitionStopTimer?.cancel();
    _host.transitionPhaseTimer?.cancel();
    _host.rainbowController.stop();
    _host.transitionRunning = false;
    _host.rainbowActive = false;
    // No new media will open, so the duration emit that normally re-arms the
    // skip lookup never comes. Leaving it disarmed would silently cost the
    // skip button for the rest of whatever is still playing.
    _host.skipSegmentsMediaReady = true;
    if (_host.mounted) {
      _host.setState(() {
        _host.isTransitioning = false;
      });
    } else {
      _host.isTransitioning = false;
    }
  }

  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) async {
    if (request == null) {
      return loadPlaylistIndexAttempt(
        index,
        autoplay: autoplay,
        skipInitialSave: skipInitialSave,
        preferLocalResume: preferLocalResume,
        suppressResume: suppressResume,
        manualValidationSource: manualValidationSource,
        manualValidationSourceIndex: manualValidationSourceIndex,
      );
    }
    final outgoingIndex = _host.currentIndex;
    final outgoingUrl = _host.currentStreamUrl;
    final outgoingHeaders = _host.activeHttpHeaders;
    final outgoingMedia = _host.activeOpenedMedia;
    final outgoingShouldPlay = _host.activeMediaShouldPlay;
    final outgoingPaused = _host.activeMediaUserPaused;
    var loaded = false;
    try {
      loaded = await loadPlaylistIndexAttempt(
        index,
        autoplay: autoplay,
        request: request,
        skipInitialSave: skipInitialSave,
        preferLocalResume: preferLocalResume,
        suppressResume: suppressResume,
        manualValidationSource: manualValidationSource,
        manualValidationSourceIndex: manualValidationSourceIndex,
      );
      return loaded;
    } finally {
      if (!loaded && _host.mounted) {
        final restored = request.restorePlaylist(() {
          _host.currentIndex = outgoingIndex;
          _host.currentStreamUrl = outgoingUrl;
          _host.activeHttpHeaders = outgoingHeaders;
          _host.activeOpenedMedia = outgoingMedia;
          _host.activeMediaShouldPlay = outgoingShouldPlay;
          _host.activeMediaUserPaused = outgoingPaused;
          _host.isAutoAdvancing = false;
        });
        if (restored) await _host.switchMdblistTarget();
      }
    }
  }

  Future<bool> loadPlaylistIndexAttempt(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    // Source switch on the same content: resume the checkpointed local position
    // exactly (see _maybeRestoreResume).
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  }) async {
    if (request == null) _host.episodeNavigationGeneration++;
    if (request?.isCurrent == false) return false;
    // A new item is being loaded: any scrub in flight belongs to the outgoing
    // one and must never land on this one; same for the landing verifier
    // (epoch bump — a verifier retry must never seek the incoming item).
    // NOTE: the resume write GUARD is deliberately NOT cleared here — the
    // outgoing item's checkpoint _saveResume() below must still run against
    // the armed guard, or an unlanded resume's ~0 position would be filed over
    // that item's bookmark by the very switch that abandons it. The clear sits
    // immediately after that save.
    _host.tvScrubGeneration++;
    _host.tvAbandonScrub();
    _host.resumeVerifyEpoch++;
    if (_host.activePlaylist == null ||
        index < 0 ||
        index >= _host.activePlaylist!.length) {
      clearTransitionOnFailure();
      return false;
    }

    // A sleep stop wins over anything already queued. Checked BEFORE any state
    // moves: bailing out after _currentIndex has advanced would leave the
    // playlist pointing at an episode that never opened, so resume and
    // metadata would file against the wrong item. Only automatic advances are
    // suppressed — picking something by hand means the viewer is awake, so it
    // clears the latch instead.
    if (_host.sleepStopLatched) {
      if (autoplay && _host.isAutoAdvancing) {
        _host.isAutoAdvancing = false;
        clearTransitionOnFailure();
        return false;
      }
      _host.sleepStopLatched = false;
    }

    print(
      'PikPak: _loadPlaylistIndex called with index: $index, autoplay: $autoplay',
    );

    // Resolve before changing the playing identity: a cancelled or failed
    // lookup must not label the outgoing stream as the unplayed target.
    final entry = _host.activePlaylist![index];
    // Resolve the actual streaming URL if needed
    String videoUrl = entry.url;
    if (videoUrl.isEmpty) {
      try {
        videoUrl = await _host.resolvePlaylistEntryUrl(index);
      } catch (e) {
        final errorText = e.toString().replaceFirst('Exception: ', '');
        if (_host.mounted && request?.isCurrent != false) {
          ScaffoldMessenger.of(_host.context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to prepare video: $errorText',
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: Theme.of(_host.context).colorScheme.error,
              duration: VideoPlayerTimingConstants.controlsAutoHideDuration,
            ),
          );
        }
        videoUrl = entry.url;
      }
    }
    if (!_host.mounted || request?.isCurrent == false) return false;
    if (videoUrl.isEmpty) {
      if (request == null) _host.currentStreamUrl = null;
      if (_host.mounted) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          SnackBar(
            content: const Text(
              'No playable URL found for this entry',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Theme.of(_host.context).colorScheme.error,
            duration: VideoPlayerTimingConstants.controlsAutoHideDuration,
          ),
        );
      }
      clearTransitionOnFailure();
      return false;
    }

    // Scrobble stop for the current episode before switching
    _host.stopTraktHeartbeat();
    _host.traktScrobble('stop');
    _host.stopSimklHeartbeat();
    _host.simklScrobble('stop');
    // Keep the MDBList session's playing bit until switchTarget captures it.
    // Calling exit here would make the incoming episode look paused and would
    // prevent its initial checkpoint/timer from starting.
    _host.updateMdblistPosition();

    // Callers that already checkpointed the outgoing episode (e.g. a source
    // switch, which saves BEFORE swapping the playlist) skip this save so it
    // can't write the current position against the newly-swapped playlist.
    if (!skipInitialSave) {
      await _host.saveResume();
    }
    if (!_host.mounted || request?.isCurrent == false) return false;
    // The outgoing item's guarded checkpoint has run; from here on the guard
    // belongs to nobody. Clearing now stops it suppressing the incoming item's
    // saves and makes any in-flight landing verifier abort instead of
    // re-issuing the outgoing item's target against the new one.
    _host.resumeWriteGuard.clear();
    _host.currentIndex = index;
    await _host.switchMdblistTarget();
    if (!_host.mounted || request?.isCurrent == false) return false;
    _host.resetLocalCompletionState();

    // Clear subtitle cache and selection when changing content
    _host.resetSubtitleState();
    _host.resetSkipSegmentState();

    // For movie collections, prefetch movie metadata for the new index
    // This runs in background so subtitles are ready when user opens TracksSheet
    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null && !seriesPlaylist.isSeries) {
      seriesPlaylist.fetchMovieMetadataForIndex(index).catchError((e) {
        // Silently ignore errors - metadata is optional
        return null;
      });
    }

    print(
      'PikPak: Loading playlist entry - provider: ${entry.provider}, pikpakFileId: ${entry.pikpakFileId}',
    );

    _host.currentStreamUrl = videoUrl;

    // Check if this is a PikPak video
    final currentEntry = _host.activePlaylist?[index];
    _host.activeHttpHeaders = currentEntry?.httpHeaders;
    final isPikPak =
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null;

    // ALWAYS use retry logic for PikPak videos, regardless of autoplay
    if (isPikPak) {
      // For PikPak, we need retry logic even if not autoplaying
      // _playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
      final pikPakLoaded = await _host.playPikPakVideoWithRetry(
        videoUrl,
        request: request,
        // A manual source transaction owns its single failure message. The
        // retry UI remains unchanged while cold storage is being reactivated.
        showFailure: manualValidationSourceIndex == null,
      );
      if (manualValidationSourceIndex != null && !pikPakLoaded) return false;
      if (request != null && suppressResume && !pikPakLoaded) return false;
      if (!autoplay) {
        // Still use retry but without autoplay; pause only after it succeeds.
        _host.activeMediaShouldPlay = false;
        if (pikPakLoaded) await _host.player.pause();
      }
    } else {
      // Non-PikPak videos play normally
      // Cancel any ongoing PikPak retry when switching to non-PikPak video
      _host.pikPakRetryId++;
      if (manualValidationSourceIndex != null) {
        final valid = await _host.tryOpenStartupVod(
          videoUrl,
          httpHeaders: _host.activeHttpHeaders,
          source: manualValidationSource,
          sourceIndex: manualValidationSourceIndex,
        );
        if (!valid) return false;
        if (!autoplay) await _host.player.pause();
      } else {
        await _host.openMedia(
          mk.Media(videoUrl, httpHeaders: _host.activeHttpHeaders),
          play: autoplay,
          request: request,
        );
      }
    }

    if (!_host.mounted || request?.isCurrent == false) return false;
    // Shuffle needs playback proof to decide whether to try another episode.
    // Ordinary episode/source navigation retains its existing readiness path.
    if (request != null && suppressResume) {
      final ready = await waitForEpisodePlayback(
        isCurrent: () => request.isCurrent,
        isPaused: () => _host.activeMediaUserPaused || _host.pausedByLifecycle,
        isReady: () =>
            _host.player.state.duration > Duration.zero &&
            (_host.activeMediaUserPaused ||
                _host.pausedByLifecycle ||
                (_host.player.state.playing &&
                    _host.player.state.position >=
                        const Duration(milliseconds: 40))),
      );
      if (!ready) return false;
    } else {
      await _host.waitForVideoReady();
    }
    if (!_host.mounted || request?.isCurrent == false) return false;
    if (suppressResume) {
      // Starting a random episode at zero is independent of whether the
      // viewer requested it or EOF advanced automatically.
      _host.resumeWriteGuard.clear();
      _host.isAutoAdvancing = false;
    } else {
      await _host.maybeRestoreResume(preferLocalResume: preferLocalResume);
    }
    // Restore audio and subtitle track preferences
    await _host.restoreTrackPreferences();

    // Clear transition state when video is ready
    if (_host.mounted) {
      _host.setState(() {
        _host.isTransitioning = false;
      });
    }
    // Ordinary episode opens use the readiness path above, rather than the
    // startup/manual-source commit callback. Bind sync only after that lands.
    if (manualValidationSourceIndex == null) {
      _host.serverWatch.commit(_host.openedWatchSource);
    }
    return true;
  }

  /// Sets manual episode selection mode with automatic reset after 30 seconds
  void setManualSelectionMode({bool allowResume = false}) {
    _host.isManualEpisodeSelection = true;
    _host.allowResumeForManualSelection = allowResume;
    _host.manualSelectionResetTimer?.cancel();
    _host.manualSelectionResetTimer = Timer(
      VideoPlayerTimingConstants.manualSelectionResetDuration,
      () {
        _host.isManualEpisodeSelection = false;
        _host.allowResumeForManualSelection = false;
      },
    );
  }
}
