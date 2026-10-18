import 'dart:async';

import 'package:debrify/features/video_player/models/vp_manual_source_validation_failure.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpSourceSwitchHost {
  Map<String, String>? get activeHttpHeaders;
  set activeHttpHeaders(Map<String, String>? v);
  ValueNotifier<bool> get controlsVisible;
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  String? get currentStreamUrl;
  set currentStreamUrl(String? v);
  Duration get duration;
  Future<String?> Function(Torrent)? get effectiveResolver;
  List<Torrent>? get effectiveSources;
  String? get iptvChannelKey;
  set isTransitioning(bool v);
  set manualSourceGateActive(bool v);
  Torrent? get openedWatchSource;
  mk.Player get player;
  Duration get position;
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  int get resumeVerifyEpoch;
  set resumeVerifyEpoch(int v);
  ResumeWriteGuard get resumeWriteGuard;
  bool get screenDisposed;
  MediaServerWatchController get serverWatch;
  bool get showSourceSheet;
  set showSourceSheet(bool v);
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
  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  });
  Future<void> commitValidatedStremioSource(Torrent? source);
  Future<bool> switchToSourcePlaylist(
    int sourceIndex,
    List<PlaylistEntry> newPlaylist, {
    int? targetSeason,
    int? targetEpisode,
    bool validateExplicitSelection = false,
    bool suppressResume = false,
    EpisodePlaybackRequest? request,
  });
  void resumeTrackingAfterValidationGate();
  void tvAbandonScrub();
  void startTransitionOverlay();
  void clearBufferingIndicator();
  void resetSubtitleState();
  Future<void> waitForVideoReady();
  Future<void> setExternalAudioTrack(String url);
  void setState(VoidCallback fn);
  bool get mounted;
  SourcePlaylistResolve? get resolveSourceToPlaylist;
  String? get audioUrl;
  void hideIptvZapBanner({bool immediate = false});
  Future<void> switchToIptvSource(int index, String url);
  Future<void> seekForResume(int posMs, {bool verifyLanding = false});
  Future<void> restoreTrackPreferences();
}

class VpSourceSwitch {
  VpSourceSwitch(this._host);
  final VpSourceSwitchHost _host;

  List<PlaylistEntry>? pendingSourcePlaylist;
  int sourcePlaylistResolution = 0;

  // ─── Stremio Source Sheet ───────────────────────────────────────────

  void showSourceSheetOverlay() {
    final sources = _host.effectiveSources;
    if (sources == null || sources.isEmpty) return;
    _host.hideIptvZapBanner();
    _host.setState(() {
      _host.showSourceSheet = true;
      _host.controlsVisible.value = false;
    });
  }

  void hideSourceSheet() {
    sourcePlaylistResolution++;
    _host.setState(() {
      _host.showSourceSheet = false;
    });
  }

  Future<String?> Function(Torrent) buildSourceSheetResolver() {
    if (_host.resolveSourceToPlaylist != null) {
      return (Torrent torrent) async {
        final generation = ++sourcePlaylistResolution;
        bool active() =>
            _host.mounted &&
            !_host.screenDisposed &&
            _host.showSourceSheet &&
            generation == sourcePlaylistResolution;
        final playlist = await _host.resolveSourceToPlaylist!(
          torrent,
          canContinue: active,
        );
        if (!active() || playlist == null || playlist.isEmpty) return null;
        pendingSourcePlaylist = playlist;
        final firstUrl = playlist.first.url;
        return firstUrl.isNotEmpty ? firstUrl : null;
      };
    }
    return _host.effectiveResolver!;
  }

  Future<void> handleSourceSelected(int index, String url) async {
    // Picking a source aborts the landing verifier — it must not re-issue the
    // old target against the replacement stream (that could even trip the
    // validator's position gate). The GUARD deliberately stays armed: the
    // switch paths below checkpoint the outgoing position, and that save must
    // still be protected (they substitute the held target where needed).
    _host.resumeVerifyEpoch++;
    // Live IPTV channel: the movie pipeline below seeks to the previous
    // position and reloads subtitles — both meaningless (and harmful) for a
    // live stream. Route to the dedicated live switch instead.
    if (_host.iptvChannelKey != null) {
      await _host.switchToIptvSource(index, url);
      return;
    }
    final pendingPlaylist = pendingSourcePlaylist;
    pendingSourcePlaylist = null;
    if (pendingPlaylist != null && pendingPlaylist.isNotEmpty) {
      await _host.switchToSourcePlaylist(
        index,
        pendingPlaylist,
        validateExplicitSelection: true,
      );
    } else {
      await switchToStremioSource(index, url);
    }
  }

  Future<void> switchToStremioSource(int index, String url) async {
    hideSourceSheet();

    // Capture current position before switching so playback continues
    // seamlessly. A held (unlanded) resume target outranks the live position —
    // the live value is a restart artifact and the new source must open at
    // the bookmark. Pure query; the guard stays armed so the new source's own
    // landing (or failure) keeps the bookmark protected.
    final heldSwitchMs = _host.resumeWriteGuard.heldTargetIfBlocked(
      _host.position.inMilliseconds,
    );
    final resumePosition = heldSwitchMs != null
        ? Duration(milliseconds: heldSwitchMs)
        : _host.position;
    final previousUrl = _host.currentStreamUrl;
    final previousHeaders = _host.activeHttpHeaders;
    final previousSourceIndex = _host.currentSourceIndex;
    final source =
        (_host.effectiveSources != null &&
            index >= 0 &&
            index < _host.effectiveSources!.length)
        ? _host.effectiveSources![index]
        : null;

    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
      _host.currentSourceIndex = index;
    });
    _host.startTransitionOverlay();

    try {
      await _host.player.pause();
    } catch (_) {}

    if (!_host.mounted) return;

    _host.manualSourceGateActive = true;

    // For YouTube each quality is a video-only track sharing one audio stream
    // (widget.audioUrl). Mirror the initial-launch ordering: open PAUSED,
    // attach the external audio, seek, then play — so both tracks load in sync
    // (attaching audio mid-play makes mpv resync and drift). Sources without a
    // separate audio track (torrents) keep the plain open-and-play path.
    final hasExternalAudio =
        _host.audioUrl != null && _host.audioUrl!.isNotEmpty;

    // For direct/torrent switches, `_player.open` discards the old media's
    // subtitle tracks, so an active external/addon subtitle would silently
    // vanish and the cached identifiers would dangle. Reset now (mirrors
    // `_loadPlaylistIndex`) so the new media starts clean and addon-subtitle
    // logic re-runs. Deliberately NOT done for the external-audio (YouTube)
    // path — that flow is left exactly as before to avoid any regression.
    if (!hasExternalAudio) {
      _host.resetSubtitleState();
    }

    var committed = false;
    try {
      final valid = hasExternalAudio
          ? await (() async {
              await _host.openMedia(
                mk.Media(url),
                play: false,
                desiredPlay: true,
              );
              await _host.waitForVideoReady();
              return _host.duration > Duration.zero;
            })()
          : await _host.tryOpenStartupVod(
              url,
              httpHeaders: source?.httpHeaders,
              source: source,
              sourceIndex: index,
            );
      if (!_host.mounted) return;
      if (!valid) {
        throw const VpManualSourceValidationFailure();
      }
      if (!_host.mounted) return;
      if (hasExternalAudio) {
        await _host.setExternalAudioTrack(_host.audioUrl!);
      }
      // Seek to the position from the previous source. _seekForResume
      // re-ARMS the guard (a pure held-target query never restarted the
      // settle window), so a switched-to stream that restarts at 0 cannot
      // have its first autosave file ~0 over the carried bookmark — the
      // identical failure the guard exists for, on the switch path.
      if (resumePosition > Duration.zero) {
        await _host.seekForResume(resumePosition.inMilliseconds);
      }
      if (hasExternalAudio) {
        await _host.player.play();
      } else {
        // Restore stored audio/subtitle track preferences for this content
        // (same as the playlist path). Skipped for the external-audio (YouTube)
        // case above, where the merged audio track is set explicitly and track
        // preferences would fight it.
        //
        // Fire-and-forget: `_restoreTrackPreferences` awaits `_waitForSubtitleTracks`,
        // which polls up to ~5s on media with no embedded subtitle tracks
        // (common for direct MP4/torrent streams). Awaiting it here would hold
        // the black transition overlay for that whole wait — a regression vs the
        // old direct-switch path, which ended the transition right after the
        // seek. Let it apply in the background; the overlay ends below on time.
        unawaited(_host.restoreTrackPreferences());
      }
      _host.currentSourceIndex = index;
      _host.currentStreamUrl = url;
      _host.activeHttpHeaders = source?.httpHeaders;
      committed = true;
      unawaited(_host.commitValidatedStremioSource(source));
    } catch (e) {
      debugPrint('Player: manual Stremio source rejected (${e.runtimeType})');
      logSourceSelection(
        'player_switch_rejected',
        source: source,
        index: index,
        previousIndex: previousSourceIndex,
        player: 'mpv',
        reason: 'validation_failed',
      );
      // The candidate player is stopped by the validator. Restore the known
      // working stream when possible, but never validate/fail over to another
      // row: this was an explicit user selection.
      if (previousUrl != null && previousUrl.isNotEmpty) {
        try {
          _host.activeHttpHeaders = previousHeaders;
          await _host.openMedia(
            mk.Media(previousUrl, httpHeaders: _host.activeHttpHeaders),
            play: true,
            source:
                _host.effectiveSources != null &&
                    previousSourceIndex >= 0 &&
                    previousSourceIndex < _host.effectiveSources!.length &&
                    MediaServerWatchController.isServerSource(
                      _host.effectiveSources![previousSourceIndex],
                    )
                ? _host.effectiveSources![previousSourceIndex]
                : null,
          );
          await _host.waitForVideoReady();
          if (hasExternalAudio) {
            // YouTube-style split streams: the reopen dropped the external
            // audio track — without this the restored video plays silent.
            await _host.setExternalAudioTrack(_host.audioUrl!);
          }
          if (resumePosition > Duration.zero) {
            await _host.seekForResume(resumePosition.inMilliseconds);
          }
          _host.currentStreamUrl = previousUrl;
          _host.serverWatch.commit(_host.openedWatchSource);
          if (!hasExternalAudio) {
            // Subtitle state was reset for the candidate; bring the user's
            // subtitle/audio choices back on the restored stream.
            unawaited(_host.restoreTrackPreferences());
          }
        } catch (restoreError) {
          debugPrint(
            'Player: previous source restore failed '
            '(${restoreError.runtimeType})',
          );
        }
      }
      _host.currentSourceIndex = previousSourceIndex;
    } finally {
      _host.manualSourceGateActive = false;
      _host.resumeTrackingAfterValidationGate();
    }

    if (!_host.mounted) return;

    if (!committed) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(
          content: Text('This source is unavailable. Choose another source.'),
        ),
      );
    }

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
  }
}
