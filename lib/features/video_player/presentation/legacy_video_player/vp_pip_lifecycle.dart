import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/services/player_display_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPipLifecycleHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  Object get pipOwner;
  bool get isIOS;
  bool get isAndroid;
  mk.Player get player;
  bool get playerCreated;
  bool get isTransitioning;
  bool get isPipActive;
  set isPipActive(bool v);
  bool get isPlaying;
  bool get hasAnyNext;
  Timer? get hideTimer;
  ValueNotifier<bool> get controlsVisible;
  Future<void> setNativeSubtitleVisibilityForTrack(mk.SubtitleTrack track);
  void togglePlay();
  Future<void> goToNextEpisode();
  void cancelPendingIptvCatchup({bool hideFeedback = true});
  bool get rendererFallbackInProgress;
  bool get pausedByLifecycle;
  set pausedByLifecycle(bool v);
  bool get iptvStartOverActive;
  bool get activeMediaShouldPlay;
  bool get activeMediaUserPaused;
  IptvLiveRecovery get iptvLiveRecovery;
  ValueNotifier<String?> get iptvReconnectText;
  IptvChannel? get currentIptvChannel;
  bool get sleepStopLatched;
  void traktScrobbleSeek(Duration position);
  void simklScrobbleSeek(Duration position);
  void mdblistScrobbleSeek(Duration position);
  bool get landscapeLocked;
}

class VpPipLifecycle {
  VpPipLifecycle(this._host);
  final VpPipLifecycleHost _host;

  /// Wall time we were backgrounded; a live channel resumed after more than
  /// 30s away re-tunes to the live edge instead of resuming stale bytes.
  DateTime? backgroundedAt;

  bool iosPipStarting = false;
  bool iosPipDetached = false;
  PlayerPipSession? iosPipSession;
  int lastIosPipPositionSecond = -1;

  /// Enter PiP now, sized to the current video's pixel aspect when known.
  Future<void> enterPip() async {
    if (!PipService.isOwner(_host.pipOwner) ||
        !_host.playerCreated ||
        _host.isTransitioning ||
        iosPipStarting ||
        _host.isPipActive) {
      return;
    }
    final player = _host.player;
    if (_host.isIOS) _host.setState(() => iosPipStarting = true);
    var entered = false;
    try {
      final handle = _host.isIOS ? await player.handle : null;
      if (!_host.mounted ||
          !PipService.isOwner(_host.pipOwner) ||
          !identical(player, _host.player)) {
        return;
      }
      if (_host.isIOS) {
        await _host.setNativeSubtitleVisibilityForTrack(
          player.state.track.subtitle,
        );
      }
      pushPipState();
      entered = await PipService.enterPip(
        aspectWidth: player.state.width,
        aspectHeight: player.state.height,
        playerHandle: handle,
      );
    } catch (error) {
      debugPrint('PiP entry failed: $error');
    } finally {
      if (_host.mounted &&
          PipService.isOwner(_host.pipOwner) &&
          identical(player, _host.player)) {
        if (_host.isIOS) {
          _host.setState(() => iosPipStarting = false);
          unawaited(
            _host.setNativeSubtitleVisibilityForTrack(
              player.state.track.subtitle,
            ),
          );
        }
        if (!entered) {
          if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.paused) {
            pauseForBackground();
          }
          ScaffoldMessenger.of(_host.context).showSnackBar(
            const SnackBar(
              content: Text(
                'Picture in Picture could not start. Please try again.',
              ),
            ),
          );
        }
      }
    }
  }

  /// Arm auto-enter (Home button) for this screen, seeding the current video
  /// aspect so the auto-entered window matches the video shape. No-op unless
  /// this screen is the active, supported PiP owner.
  void armPipAutoEnter() {
    if (_host.isIOS) return; // iOS prepares its renderer on explicit entry.
    if (!PipService.isOwner(_host.pipOwner)) return;
    final w = _host.player.state.width ?? 0;
    final h = _host.player.state.height ?? 0;
    unawaited(PipService.setAutoEnter(true, aspectWidth: w, aspectHeight: h));
  }

  /// Keep the native side's play/pause icon, Next button and window aspect in
  /// sync with the live player — both for an open PiP window and for the next
  /// Home-button auto-enter. No-op unless this screen is the active PiP owner.
  void pushPipState() {
    if (!PipService.isOwner(_host.pipOwner)) return;
    final w = _host.player.state.width ?? 0;
    final h = _host.player.state.height ?? 0;
    unawaited(
      PipService.updatePlaybackState(
        isPlaying: _host.isPlaying,
        hasNext: _host.hasAnyNext,
        positionMs: _host.player.state.position.inMilliseconds,
        durationMs: _host.player.state.duration.inMilliseconds,
        aspectWidth: w,
        aspectHeight: h,
      ),
    );
  }

  /// Collapse the control chrome while inside the small PiP window, and restore
  /// it when the window expands back to fullscreen.
  void onPipModeChanged(bool inPip) {
    if (!_host.mounted) return;
    if (inPip) {
      _host.hideTimer?.cancel();
      _host.controlsVisible.value = false;
      pushPipState();
    }
    _host.setState(() => _host.isPipActive = inPip);
    if (_host.isIOS && _host.playerCreated) {
      if (inPip && (iosPipSession?.park() ?? false)) {
        iosPipDetached = true;
        unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
        unawaited(
          SystemChrome.setPreferredOrientations(DeviceOrientation.values),
        );
      } else if (!inPip && (iosPipSession?.isParked ?? false)) {
        // Native close (or a newer playback owner) ends the detached session.
        // Fullscreen restoration has already reattached it before this event.
        iosPipSession?.close();
        return;
      }
      unawaited(
        _host.setNativeSubtitleVisibilityForTrack(
          _host.player.state.track.subtitle,
        ),
      );
    }
  }

  Future<bool> restoreIosPipPlayer() async {
    if (!_host.mounted || !PipService.isOwner(_host.pipOwner)) return false;
    final session = iosPipSession;
    if (session == null) return false;
    if (session.isParked && !session.restore()) return false;
    iosPipDetached = false;
    await SystemChrome.setPreferredOrientations(
      _host.landscapeLocked
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await WidgetsBinding.instance.endOfFrame;
    return _host.mounted && PipService.isOwner(_host.pipOwner);
  }

  /// Handle taps on the PiP window's action buttons.
  void onPipAction(String action) {
    if (!_host.mounted || !_host.playerCreated) return;
    if (action.startsWith('seek:')) {
      final seconds = double.tryParse(action.substring(5));
      if (seconds == null || !seconds.isFinite || _host.isTransitioning) return;
      final target =
          (_host.player.state.position.inMilliseconds +
                  (seconds * 1000).round())
              .clamp(0, _host.player.state.duration.inMilliseconds);
      final position = Duration(milliseconds: target);
      unawaited(_host.player.seek(position));
      _host.traktScrobbleSeek(position);
      _host.simklScrobbleSeek(position);
      _host.mdblistScrobbleSeek(position);
      return;
    }
    switch (action) {
      case 'play':
        if (!_host.isPlaying) _host.togglePlay();
        break;
      case 'pause':
        if (_host.isPlaying) _host.togglePlay();
        break;
      case 'playpause':
        _host.togglePlay();
        break;
      case 'next':
        if (_host.hasAnyNext) _host.goToNextEpisode();
        break;
    }
  }

  /// The app left the foreground (Home, power button, app switch): stop
  /// playback instead of decoding video nobody can see. Mobile only — on
  /// desktop a minimized/covered window keeping its audio is normal use, and
  /// desktop power budgets are not why this exists. PiP never gets here: a
  /// visible PiP activity stays at `inactive` (see [_lifecycle]).
  void pauseForBackground() {
    if (!_host.isAndroid && !_host.isIOS) return;
    if (_host.isIOS && (_host.isPipActive || iosPipStarting)) return;
    // Even paused playback can have a Start Over probe in flight. Cancel
    // before the playing/transition checks, including recording teardown.
    _host.cancelPendingIptvCatchup(hideFeedback: false);
    // A renderer restart has intentionally invalidated the old player and may
    // not have created the replacement yet. Preserve playback intent without
    // requiring either instance to be live at this exact lifecycle callback.
    if (_host.rendererFallbackInProgress) {
      _host.pausedByLifecycle = true;
      if (_host.playerCreated) unawaited(_host.player.pause());
      return;
    }
    // _isTransitioning too, not just _isPlaying: mid-switch (next episode, a
    // zap) `playing` is briefly false while an open(play: true) is in flight.
    // Backgrounding in that window must still arm the flag, or the open lands
    // moments later and plays behind the backgrounded app with the guard in
    // the playing listener disarmed. A user's own pause has neither set.
    final openingStartOver =
        _host.iptvStartOverActive &&
        _host.activeMediaShouldPlay &&
        !_host.activeMediaUserPaused;
    if (!_host.playerCreated ||
        (!_host.isPlaying && !_host.isTransitioning && !openingStartOver)) {
      return;
    }
    // A recovery in flight must not re-open streams behind a backgrounded
    // app; the resume path below re-arms recovery when it matters.
    backgroundedAt = DateTime.now();
    _host.iptvLiveRecovery.cancel();
    _host.iptvReconnectText.value = null;
    _host.pausedByLifecycle = true;
    unawaited(_host.player.pause());
  }

  /// Undo [_pauseForBackground] when the app returns, restoring the
  /// pre-existing contract that coming back to this screen shows it playing.
  /// A pause the user made themselves (flag unset) stays a pause.
  void resumeFromBackground() {
    if (!_host.pausedByLifecycle) return;
    // Cleared BEFORE play(): the playing event this triggers must not read as
    // "playback restarted behind a backgrounded app" to the guard in the
    // playing listener.
    _host.pausedByLifecycle = false;
    // The replacement player will read the cleared lifecycle flag immediately
    // before open/play. Calling play on the disposing instance would race the
    // one-player ownership guarantee.
    if (_host.rendererFallbackInProgress) return;
    if (!_host.playerCreated || !_host.mounted) return;
    // Coming back from the background is not a request to un-stop the night:
    // if the sleep timer fired while we were away, stay paused until someone
    // presses play.
    if (_host.sleepStopLatched) return;
    // LIVE, back after a real absence: the paused stream is minutes behind
    // the edge (or dead). Re-tune to the live edge — same "comes back
    // playing" contract, at the right point in the broadcast. Short trips
    // keep the cheap in-buffer resume (legitimate timeshift).
    final backgroundedAt = this.backgroundedAt;
    this.backgroundedAt = null;
    if (_host.currentIptvChannel?.isLive == true &&
        !_host.iptvStartOverActive &&
        backgroundedAt != null &&
        DateTime.now().difference(backgroundedAt) >
            const Duration(seconds: 30)) {
      _host.iptvLiveRecovery.userRetry('lifecycle-rejoin');
      return;
    }
    unawaited(_host.player.play());
  }

  /// The screen wakelock follows PLAYBACK, not this screen's lifetime: a
  /// paused video left on a table must not pin the display on until the
  /// route pops — on phones the display is the single biggest battery
  /// consumer. Buffering stalls keep the lock (media_kit's `playing` tracks
  /// the pause property, which stays false during a stall). initState still
  /// takes the lock up front so the screen can't sleep through a slow
  /// resolve/open before the first playing event arrives.
  void syncWakelock(bool playing) {
    unawaited(PlayerDisplayControls.instance.setWakelock(playing));
  }
}
