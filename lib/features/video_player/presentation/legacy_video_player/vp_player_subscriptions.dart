import 'dart:async';

import 'package:debrify/features/video_player/models/vp_subtitle_apply_attempt.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';
import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/screens/video_player/services/playback_ui_clock.dart';
import 'package:debrify/services/player_visibility.dart';
import 'package:debrify/services/profiles/profile_lock_controller.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPlayerSubscriptionsHost {
  VpSubtitleApplyAttempt? get activeSubtitleApplyAttempt;
  Timer? get bufferingDebounceTimer;
  set bufferingDebounceTimer(Timer? v);
  StreamSubscription? get bufferingSub;
  set bufferingSub(StreamSubscription? v);
  StreamSubscription? get completedSub;
  set completedSub(StreamSubscription? v);
  int get decoderProbeGeneration;
  StreamSubscription? get durSub;
  set durSub(StreamSubscription? v);
  Duration get duration;
  set duration(Duration v);
  List<IptvChannel>? get effectiveIptvChannels;
  bool get hasSubtitlePolicy;
  IptvTuneDiagnostics get iptvDiag;
  StreamSubscription? get iptvErrorSub;
  set iptvErrorSub(StreamSubscription? v);
  IptvLiveRecovery get iptvLiveRecovery;
  bool get isPikPakRetrying;
  bool get isPipActive;
  bool get isPlaying;
  set isPlaying(bool v);
  bool get isReady;
  bool get isTransitioning;
  Torrent? get openedWatchSource;
  StreamSubscription? get paramsSub;
  set paramsSub(StreamSubscription? v);
  bool get pausedByLifecycle;
  StreamSubscription? get playSub;
  set playSub(StreamSubscription? v);
  PlaybackUiClockController get playbackUiClock;
  int get playerInstanceGeneration;
  StreamSubscription? get posSub;
  set posSub(StreamSubscription? v);
  Duration get position;
  set position(Duration v);
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  StreamSubscription? get rendererStartupErrorSub;
  set rendererStartupErrorSub(StreamSubscription? v);
  int get resumeVerifyEpoch;
  ValueNotifier<bool> get showBufferingIndicator;
  DeferredStartupSeek get stremioTvStartupSeek;
  StreamSubscription<mk.PlayerLog>? get subtitleDiagnosticLogSub;
  set subtitleDiagnosticLogSub(StreamSubscription<mk.PlayerLog>? v);
  StreamSubscription? get trackSub;
  set trackSub(StreamSubscription? v);
  set transitionPhase(int v);
  set transitionPhase2Started(DateTime? v);
  Timer? get transitionPhaseTimer;
  set transitionPhaseTimer(Timer? v);
  bool get transitionRunning;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set transitionStopTimer(Timer? v);
  bool get validationGateActive;
  bool get mounted;
  void setState(VoidCallback fn);
  bool get isIOS;
  void checkAndApplyLocalCompletion();
  void handleDecoderProbeParams(mk.VideoParams params);
  void prepareNextDirectEpisode();
  void noteLiveChannelPlaying();
  void onIptvStreamError(String error);
  void mdblistPause();
  void mdblistPlay();
  void updateMdblistPosition();
  int get lastIosPipPositionSecond;
  set lastIosPipPositionSecond(int v);
  void pushPipState();
  void syncWakelock(bool playing);
  Future<void> onPlaybackEnded();
  Future<void> fallbackExplicitRendererToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  });
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false});
  void observeServerWatch({bool completed = false});
  String? get simklLastScrobbleAction;
  set simklLastScrobbleAction(String? v);
  void simklScrobble(String action);
  bool get simklScrobbleEnabled;
  void startSimklHeartbeat();
  void stopSimklHeartbeat();
  set skipSegmentsMediaReady(bool v);
  void syncActiveSkipSegmentUi();
  void syncSkipSegmentsForCurrentContent();
  Future<void> handleSubtitleApplyFailure(
    VpSubtitleApplyAttempt attempt,
    String reason,
  );
  Future<void> refreshSubtitleAudioPolicy({bool reselect = true});
  MediaKitSubtitleAutoSync? get subtitleAutoSync;
  bool get subtitleAutoSyncEnabled;
  set subtitleAutoSyncEnabled(bool v);
  void startTraktHeartbeat();
  void stopTraktHeartbeat();
  String? get traktLastScrobbleAction;
  void traktScrobble(String action);
  Object get visibilityOwner;
}

class VpPlayerSubscriptions {
  VpPlayerSubscriptions(this._host);
  final VpPlayerSubscriptionsHost _host;

  void bindPlayerInstanceSubscriptions(
    int instanceGeneration,
    mk.Player player,
  ) {
    bool isCurrent() =>
        _host.mounted && instanceGeneration == _host.playerInstanceGeneration;

    _host.subtitleDiagnosticLogSub = player.stream.log.listen((log) {
      if (!isCurrent()) return;
      final searchable = '${log.prefix} ${log.text}'.toLowerCase();
      if (!searchable.contains('sub') &&
          !searchable.contains('libass') &&
          !searchable.contains('track')) {
        return;
      }
      debugPrint('[SubtitleDiag] mpv[${log.level}] ${log.prefix}: ${log.text}');
      final level = log.level.toLowerCase();
      final subtitleFailure =
          (level == 'error' || level == 'fatal') &&
          (log.prefix.toLowerCase().startsWith('sub') ||
              searchable.contains('subtitle decoder') ||
              searchable.contains('subtitle converter'));
      final attempt = _host.activeSubtitleApplyAttempt;
      if (subtitleFailure && attempt != null) {
        unawaited(_host.handleSubtitleApplyFailure(attempt, log.text));
      }
    });
    // Subscribe before open() so fast local media and immediate renderer
    // failures are visible to both diagnostics and the startup guard.
    _host.paramsSub = player.stream.videoParams.listen((params) {
      if (!isCurrent()) return;
      // First sized params ≈ first decoded frame — close enough for the
      // zap-speed number, and it avoids one more subscription slot.
      if ((params.w ?? 0) > 0) {
        _host.iptvDiag.onFirstFrame();
        _host.iptvLiveRecovery.onFirstFrame();
      }
      _host.handleDecoderProbeParams(params);
    });
    _host.rendererStartupErrorSub = player.stream.error.listen((error) {
      final source = _host.openedWatchSource;
      if (isCurrent() && source != null) {
        // mpv errors can contain credential-bearing URLs; record only category.
        logSourceSelection(
          'media_server_player_error',
          source: source,
          player: 'mpv',
          reason: mediaServerPlayerErrorCategory(error),
        );
      }
      // mpv also emits nonfatal decoder/stream log errors here. Re-evaluate
      // actual state; healthy playback may not emit another state event.
      if (isCurrent()) {
        PlayerVisibility.playbackState(
          _host.visibilityOwner,
          ready: player.state.playing && !player.state.buffering,
        );
      }
      if (!isCurrent() ||
          !AndroidRendererStartupFallback.isRendererFailure(error)) {
        return;
      }
      unawaited(
        _host.fallbackExplicitRendererToAutomatic(
          instanceGeneration: instanceGeneration,
          mediaGeneration: _host.decoderProbeGeneration,
          reason: 'renderer_error',
        ),
      );
    });
    _host.posSub = player.stream.position.listen((d) {
      if (!isCurrent()) return;
      if (_host.isIOS && d.inSeconds != _host.lastIosPipPositionSecond) {
        _host.lastIosPipPositionSecond = d.inSeconds;
        _host.pushPipState();
      }
      _host.subtitleAutoSync?.observePosition(d.inMilliseconds);
      _host.iptvDiag.onProgress(d, playing: _host.isPlaying);
      // _isPlaying tracks mpv's pause property: a cache-stall keeps it true
      // (stall detector armed), a user pause flips it false (excluded).
      if (_host.effectiveIptvChannels != null) {
        _host.iptvLiveRecovery.onProgress(d, wantsPlayback: _host.isPlaying);
      }
      _host.position = d;
      _host.observeServerWatch();
      _host.prepareNextDirectEpisode();
      _host.updateMdblistPosition();
      _host.playbackUiClock.updatePosition(d);
      _host.syncSkipSegmentsForCurrentContent();
      _host.syncActiveSkipSegmentUi();
      _host.checkAndApplyLocalCompletion();
    });
    if (_host.subtitleAutoSyncEnabled || _host.hasSubtitlePolicy) {
      var lastAudioTrackId = player.state.track.audio.id;
      var lastAudioLanguage = player.state.track.audio.language;
      _host.trackSub = player.stream.track.listen((track) {
        if (!isCurrent()) return;
        final audioTrackId = track.audio.id;
        if (audioTrackId != lastAudioTrackId ||
            track.audio.language != lastAudioLanguage) {
          lastAudioTrackId = audioTrackId;
          lastAudioLanguage = track.audio.language;
          unawaited(_host.refreshSubtitleAudioPolicy());
          _host.subtitleAutoSync?.audioTrackChanged();
        }
      });
    }
    _host.durSub = player.stream.duration.listen((d) {
      if (!isCurrent()) return;
      final hadDuration = _host.duration > Duration.zero;
      _host.duration = d;
      final startupOffset = _host.stremioTvStartupSeek.take(
        d,
        epoch: _host.resumeVerifyEpoch,
      );
      if (startupOffset != null) {
        unawaited(
          _host
              .seekForResume(startupOffset.inMilliseconds, verifyLanding: true)
              .catchError((Object error) {
                debugPrint('Player: Stremio TV startup seek failed: $error');
              }),
        );
      }
      _host.updateMdblistPosition();
      // `playing=true` commonly arrives before libmpv publishes duration. In
      // that ordering the playing listener cannot arm MDBList, and no second
      // playing event is guaranteed. Treat the first usable duration as the
      // missing edge so the initial durable pause checkpoint is sent.
      if (!hadDuration && d > Duration.zero && _host.isPlaying) {
        _host.mdblistPlay();
      }
      _host.playbackUiClock.updateDuration(d);
      if (d > Duration.zero) _host.skipSegmentsMediaReady = true;
      _host.syncSkipSegmentsForCurrentContent();
      _host.syncActiveSkipSegmentUi();
      _host.setState(() {});
    });
    _host.playSub = player.stream.playing.listen((p) {
      if (!isCurrent()) return;
      PlayerVisibility.playbackState(
        _host.visibilityOwner,
        ready: p && !player.state.buffering,
      );
      if (p && _host.pausedByLifecycle && !_host.isPipActive) {
        unawaited(player.pause());
        return;
      }
      final wasPlaying = _host.isPlaying;
      _host.isPlaying = p;
      _host.observeServerWatch();
      ProfileLockController.instance.setPlaybackActive(p);
      _host.syncWakelock(p);
      _host.pushPipState();
      if (p) _host.noteLiveChannelPlaying();
      if (!_host.validationGateActive && p && _host.duration > Duration.zero) {
        _host.traktScrobble('start');
        if (_host.traktLastScrobbleAction == 'start') {
          _host.startTraktHeartbeat();
        }
      } else if (!_host.validationGateActive &&
          !p &&
          wasPlaying &&
          !_host.isTransitioning &&
          _host.traktLastScrobbleAction != 'stop') {
        _host.traktScrobble('pause');
        _host.stopTraktHeartbeat();
      }
      if (!_host.validationGateActive &&
          _host.simklScrobbleEnabled &&
          p &&
          _host.duration > Duration.zero) {
        _host.simklLastScrobbleAction = 'start';
        _host.startSimklHeartbeat();
      } else if (!_host.validationGateActive &&
          !p &&
          wasPlaying &&
          !_host.isTransitioning &&
          _host.simklLastScrobbleAction != 'stop') {
        _host.simklScrobble('pause');
        _host.stopSimklHeartbeat();
      }
      if (!_host.validationGateActive && p && _host.duration > Duration.zero) {
        _host.mdblistPlay();
      } else if (!_host.validationGateActive &&
          !p &&
          wasPlaying &&
          !_host.isTransitioning) {
        _host.mdblistPause();
      }
      if (p && _host.transitionRunning) {
        _host.transitionStopTimer?.cancel();
        _host.transitionPhaseTimer?.cancel();
        _host.transitionPhase = 1;
        _host.transitionPhase2Started = null;
        debugPrint(
          'Player: Playback started; overlay phase 1 (static) 1500ms.',
        );
        _host.transitionPhaseTimer = Timer(
          const Duration(milliseconds: 1500),
          () {
            if (!isCurrent()) return;
            _host.transitionPhase = 2;
            _host.transitionPhase2Started = DateTime.now();
            _host.setState(() {});
            debugPrint('Player: Overlay phase 2 (cinematic bars) 1500ms.');
          },
        );
        _host.transitionStopTimer = Timer(
          const Duration(milliseconds: 3000),
          () {
            if (!isCurrent()) return;
            _host.rainbowController.stop();
            _host.transitionRunning = false;
            _host.rainbowActive = false;
            _host.setState(() {});
            debugPrint('Player: Transition overlay stopped (3s complete).');
          },
        );
      }
      _host.setState(() {});
    });
    _host.completedSub = player.stream.completed.listen((done) {
      if (done && isCurrent()) {
        PlayerVisibility.playbackState(_host.visibilityOwner, ready: false);
        _host.iptvDiag.onPlaybackEnded(_host.position);
        _host.onPlaybackEnded();
      }
    });
    _host.bufferingSub = player.stream.buffering.listen((isBuffering) {
      if (isCurrent()) {
        PlayerVisibility.playbackState(
          _host.visibilityOwner,
          ready: !isBuffering && player.state.playing,
        );
      }
      if (isCurrent()) _host.iptvDiag.onBuffering(isBuffering, _host.position);
      if (!isCurrent() || !_host.isReady || _host.isTransitioning) return;
      if (isBuffering) {
        _host.bufferingDebounceTimer?.cancel();
        _host.bufferingDebounceTimer = Timer(
          VideoPlayerTimingConstants.bufferingDebounceDelay,
          () {
            if (isCurrent() &&
                player.state.buffering &&
                _host.isReady &&
                !_host.isTransitioning &&
                !_host.isPikPakRetrying) {
              _host.showBufferingIndicator.value = true;
            }
          },
        );
      } else {
        _host.bufferingDebounceTimer?.cancel();
        _host.showBufferingIndicator.value = false;
      }
    });
    if (_host.effectiveIptvChannels != null) {
      _host.iptvErrorSub = player.stream.error.listen((error) {
        if (isCurrent()) _host.onIptvStreamError(error);
      });
    }
  }

  Future<void> cancelPlayerInstanceSubscriptions() async {
    final subscriptions = <StreamSubscription?>[
      _host.posSub,
      _host.durSub,
      _host.playSub,
      _host.paramsSub,
      _host.trackSub,
      _host.completedSub,
      _host.bufferingSub,
      _host.iptvErrorSub,
      _host.rendererStartupErrorSub,
      _host.subtitleDiagnosticLogSub,
    ];
    _host.posSub = null;
    _host.durSub = null;
    _host.playSub = null;
    _host.paramsSub = null;
    _host.trackSub = null;
    _host.completedSub = null;
    _host.bufferingSub = null;
    _host.iptvErrorSub = null;
    _host.rendererStartupErrorSub = null;
    _host.subtitleDiagnosticLogSub = null;
    for (final subscription in subscriptions) {
      if (subscription == null) continue;
      try {
        await subscription.cancel();
      } catch (_) {
        // A broken listener must not strand the old native player during the
        // compatibility restart.
      }
    }
  }
}
