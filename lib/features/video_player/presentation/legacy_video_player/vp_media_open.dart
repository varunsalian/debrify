import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/player_visibility.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/tvos_decode_remedy.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpMediaOpenHost {
  set activeMediaShouldPlay(bool v);
  set activeMediaUserPaused(bool v);
  set activeOpenedMedia(mk.Media? v);
  SkipSegmentUiController get activeSkipSegmentUi;
  int get currentSourceIndex;
  int get decoderProbeGeneration;
  set decoderProbeGeneration(int v);
  set decoderProbeParams(mk.VideoParams? v);
  Timer? get decoderProbeTimer;
  set decoderProbeTimer(Timer? v);
  int get decoderProbeToken;
  set decoderProbeToken(int v);
  String? get effectiveContentTitle;
  List<Torrent>? get effectiveSources;
  bool get hasSubtitlePolicy;
  bool get isPipActive;
  set lastDecoderDiagnosticSignature(String? v);
  Torrent? get openedWatchSource;
  set openedWatchSource(Torrent? v);
  PlaybackUiClockController get playbackUiClock;
  mk.Player get player;
  int get rendererStartupGuardToken;
  set rendererStartupGuardToken(int v);
  set rendererStartupValidationGeneration(int v);
  int get resumeVerifyEpoch;
  set resumeVerifyEpoch(int v);
  ResumeWriteGuard get resumeWriteGuard;
  bool get screenDisposed;
  MediaServerWatchController get serverWatch;
  DeferredStartupSeek get stremioTvStartupSeek;
  ChannelStartupWatch? get stremioTvStartupWatch;
  set stremioTvStartupWatch(ChannelStartupWatch? v);
  TvosDecodeRemedy? get tvosDecodeRemedy;
  int get watchOpenEpoch;
  set watchOpenEpoch(int v);
  Future<void> applyNetworkTuning(
    mk.NativePlayer platform,
    NetworkTuning tuning, {
    required bool liveStream,
    required int generation,
  });
  bool get mounted;
  bool get isIOS;
  bool get iosPipStarting;
  void observeServerWatch({bool completed = false});
  void resetTvosDisplayMatchForMediaBoundary();
  Object get visibilityOwner;
}

class VpMediaOpen {
  VpMediaOpen(this._host);
  final VpMediaOpenHost _host;

  void beginMediaGeneration({int? preserveStartupEpoch}) {
    if (preserveStartupEpoch == null) {
      _host.stremioTvStartupSeek.cancel();
    } else {
      _host.stremioTvStartupSeek.carryTo(
        fromEpoch: preserveStartupEpoch,
        toEpoch: _host.resumeVerifyEpoch,
      );
    }
    _host.stremioTvStartupWatch?.dispose();
    _host.stremioTvStartupWatch = null;
    _host.decoderProbeGeneration++;
    _host.decoderProbeToken++;
    _host.rendererStartupGuardToken++;
    _host.rendererStartupValidationGeneration = -1;
    _host.decoderProbeTimer?.cancel();
    _host.decoderProbeTimer = null;
    _host.decoderProbeParams = null;
    _host.lastDecoderDiagnosticSignature = null;
    // This is the guaranteed boundary for every playlist item, IPTV zap,
    // startup candidate, and manual source switch. VideoParams normally emits
    // an invalid value too, but display correctness must not depend on it.
    _host.resetTvosDisplayMatchForMediaBoundary();
    _host.playbackUiClock.beginMedia();
    _host.activeSkipSegmentUi.clear();
  }

  /// The user's Network & Buffering presets, loaded once per screen. A
  /// mid-session settings change applies on the next playback — accurate
  /// today because Settings isn't reachable without popping the player; an
  /// in-player settings entry point would have to re-read this.
  NetworkTuning? networkTuning;

  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  }) async {
    if (request?.isCurrent == false) return;
    final watchEpoch = ++_host.watchOpenEpoch;
    final sources = _host.effectiveSources;
    final indexedSource =
        sources != null &&
            _host.currentSourceIndex >= 0 &&
            _host.currentSourceIndex < sources.length
        ? sources[_host.currentSourceIndex]
        : null;
    final candidate =
        source ??
        (indexedSource?.directUrl == media.uri ? indexedSource : null);
    final watchSource = MediaServerWatchController.isServerSource(candidate)
        ? candidate
        : null;
    if (!identical(watchSource, _host.openedWatchSource)) {
      _host.observeServerWatch();
      _host.serverWatch.commit(null);
    }
    // EVERY content open invalidates the outgoing media's resume protection —
    // the one choke point all switch paths share, so no path (Stremio TV
    // channel, Magic TV next, zap, source switch, startup ladder) can leave a
    // stale guard suppressing the new media's saves or a live verifier
    // re-seeking the old target against it. Ordering is safe by construction:
    // every outgoing checkpoint save runs BEFORE its new open, and every path
    // that re-protects (_seekForResume) re-arms AFTER it.
    _host.resumeVerifyEpoch++;
    _host.resumeWriteGuard.clear();
    beginMediaGeneration(preserveStartupEpoch: preserveStartupEpoch);
    // Live IPTV (Phase 2, Layer 1): ffmpeg-level reconnect. mpv's default
    // reconnect covers only seekable inputs — a live/streamed input NEVER
    // reconnects without reconnect_streamed. Repairs happen inside the
    // protocol layer while the demuxer cache plays through, so the common
    // connection drop is invisible. Cleared for non-live opens: the
    // property is player-global and reconnect-on-error semantics are wrong
    // for finite files (mpv's own defaults handle those).
    final platform = _host.player.platform;
    if (platform is mk.NativePlayer) {
      final tuningGeneration = _host.decoderProbeGeneration;
      NetworkTuning tuning;
      try {
        tuning = networkTuning ??= await NetworkTuning.load();
      } catch (e) {
        // Profile storage refusing a read must degrade to "no tuning", never
        // block playback — this line is on the Standard path too.
        debugPrint('Player: network tuning load failed: $e');
        tuning = networkTuning = const NetworkTuning(
          patience: NetworkTuning.standard,
          buffer: NetworkTuning.standard,
        );
      }
      try {
        await platform.setProperty(
          'stream-lavf-o',
          // reconnect_on_http_error=5xx covers server-side hiccups at the
          // protocol layer. Deliberately narrow: NOT auth-class 4xx (same
          // answer every time — must surface), and not 429 (a comma-list
          // value can't ride mpv's key-value list safely, and escalating a
          // rate limit to the slower ladder is politer to the origin).
          //
          // VOD opens carry the user's Network & Buffering patience preset
          // ('' at Standard — today's exact behavior).
          liveStream
              ? 'reconnect=1,reconnect_streamed=1,'
                    'reconnect_on_network_error=1,'
                    'reconnect_on_http_error=5xx,'
                    'reconnect_delay_max=5'
              : tuning.vodLavfOptions,
        );
      } catch (e) {
        debugPrint('Player: stream-lavf-o set failed: $e');
      }
      await _host.applyNetworkTuning(
        platform,
        tuning,
        liveStream: liveStream,
        generation: tuningGeneration,
      );
    }
    final remedy = _host.tvosDecodeRemedy;
    if (remedy != null) {
      // AWAITED before open: remedy properties are ordinary runtime options
      // on a reused native player — this is the boundary that restores them
      // (and pre-applies the session hint) so a previous file's ladder can
      // never leak into this one.
      final generation = _host.decoderProbeGeneration;
      await remedy.onNewMedia(generation);
      // A rapid zap can start a newer open while the restore ran; the newer
      // call owns the player now.
      if (_host.screenDisposed || generation != _host.decoderProbeGeneration)
        return;
    }
    // `sub-visibility` is player-global. Reset it before a reused player opens
    // new media so a previous bitmap track cannot make auto-selected text draw
    // both natively and in Flutter. Restored bitmap selections re-enable it.
    if (platform is mk.NativePlayer) {
      try {
        if (_host.hasSubtitlePolicy) {
          await platform.setProperty('sid', 'no');
        }
        await platform.setProperty(
          'sub-visibility',
          _host.isIOS && (_host.isPipActive || _host.iosPipStarting)
              ? 'yes'
              : 'no',
        );
      } catch (error) {
        debugPrint('Player: subtitle visibility reset failed: $error');
      }
    }
    Future<void> commitOpen() async {
      // Final ownership check after setup AND asynchronous authorization.
      if (_host.screenDisposed || !_host.mounted) return;
      if (watchSource != null) {
        await _host.serverWatch.prepare(
          watchSource,
          contentTitle: _host.effectiveContentTitle,
        );
        await DirectSourceAuthorization.authorize(watchSource);
      }
      if (_host.screenDisposed ||
          !_host.mounted ||
          watchEpoch != _host.watchOpenEpoch ||
          request?.isCurrent == false) {
        return;
      }
      // This callback arms candidate validation. Never arm it while the old
      // media could still emit events during a server watch-state request.
      if (beforeOpen != null && !beforeOpen()) return;
      if (watchSource != null) {
        logSourceSelection(
          'media_server_open',
          source: watchSource,
          player: 'mpv',
        );
      }
      _host.openedWatchSource = watchSource;
      _host.activeOpenedMedia = media;
      _host.activeMediaShouldPlay = desiredPlay ?? play;
      _host.activeMediaUserPaused = false;
      PlayerVisibility.playbackState(_host.visibilityOwner, ready: false);
      if (request != null) {
        await request.commit(() => _host.player.open(media, play: play));
        return;
      }
      return _host.player.open(media, play: play);
    }

    // Startup direct fallbacks bypass URL resolvers. Recheck their captured
    // capability here so revoked/disabled/reconnected sources cannot open.
    if (source != null) {
      return DirectSourceAuthorization.runIfAuthorized(source, commitOpen);
    }
    return commitOpen();
  }
}
