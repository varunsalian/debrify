import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpRendererFallbackHost {
  set activeExternalSubtitlePath(String? v);
  bool get activeMediaShouldPlay;
  bool get activeMediaUserPaused;
  mk.Media? get activeOpenedMedia;
  AndroidVideoRendererMode get androidVideoRendererMode;
  set androidVideoRendererMode(AndroidVideoRendererMode v);
  IptvChannel? get currentIptvChannel;
  int get decoderProbeGeneration;
  set duration(Duration v);
  bool get iptvErrorsMuted;
  set isPlaying(bool v);
  set isReady(bool v);
  bool get isRecording;
  bool get isTransitioning;
  bool get pausedByLifecycle;
  mk.Player get player;
  set playerCreated(bool v);
  int get playerInstanceGeneration;
  set playerInstanceGeneration(int v);
  Duration get position;
  set position(Duration v);
  bool get rendererFallbackInProgress;
  set rendererFallbackInProgress(bool v);
  int get rendererStartupGuardToken;
  set rendererStartupGuardToken(int v);
  int get rendererStartupValidationGeneration;
  set rendererStartupValidationGeneration(int v);
  bool get rendererValidatedForSession;
  set rendererValidatedForSession(bool v);
  int get resumeVerifyEpoch;
  ResumeWriteGuard get resumeWriteGuard;
  ValueNotifier<bool> get showBufferingIndicator;
  bool get sleepStopLatched;
  DeferredStartupSeek get stremioTvStartupSeek;
  ChannelStartupWatch? get stremioTvStartupWatch;
  void createPlayerInstance(AndroidVideoRendererMode rendererMode);
  Future<void> cancelPlayerInstanceSubscriptions();
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
  Future<void> attachAudioEffectSession();
  Future<void> claimVideoOutput();
  Future<void> configurePlayerAudio(mk.Player player);
  void releaseAudioEffectSession();
  void releasePlayerDiagnostic(String fields);
  Future<void> setExternalAudioTrack(String audioUrl);
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  String? get audioUrl;
  bool get isAndroid;
  bool get isAndroidRendererValidation;
  Future<void> disposeSubtitleAutoSync();
  void installSubtitleAutoSyncForPlayer(mk.Player player);
  Future<void> waitForVideoReady();
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false});
  Future<void> restoreTrackPreferences();
  void watchStremioTvStartup(String url);
  Future<void> reportStartupFailure({bool Function()? isCurrent});
}

class VpRendererFallback {
  VpRendererFallback(this._host);
  final VpRendererFallbackHost _host;

  void scheduleRendererStartupValidation() {
    if (!AndroidRendererStartupFallback.shouldArm(
          isAndroid: _host.isAndroidRendererValidation,
          isAndroidTv: PlatformUtil.isAndroidTvCached,
          mode: _host.androidVideoRendererMode,
          alreadyValidated: _host.rendererValidatedForSession,
          fallbackInProgress: _host.rendererFallbackInProgress,
        ) ||
        _host.iptvErrorsMuted ||
        _host.rendererStartupValidationGeneration ==
            _host.decoderProbeGeneration) {
      return;
    }
    _host.rendererStartupValidationGeneration = _host.decoderProbeGeneration;
    final guardToken = ++_host.rendererStartupGuardToken;
    final instanceGeneration = _host.playerInstanceGeneration;
    final mediaGeneration = _host.decoderProbeGeneration;
    final player = _host.player;
    unawaited(
      validateRendererStartup(
        guardToken: guardToken,
        instanceGeneration: instanceGeneration,
        mediaGeneration: mediaGeneration,
        player: player,
      ),
    );
  }

  Future<void> validateRendererStartup({
    required int guardToken,
    required int instanceGeneration,
    required int mediaGeneration,
    required mk.Player player,
  }) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;

    // VideoParams is already positive at this point, so this is not a network
    // startup timeout. Give Android's SurfaceProducer/codec bridge three seconds
    // to attach the requested output and require two matching reads.
    var previousOutput = '';
    for (var attempt = 0; attempt < 12; attempt++) {
      if (!_host.mounted ||
          guardToken != _host.rendererStartupGuardToken ||
          instanceGeneration != _host.playerInstanceGeneration ||
          mediaGeneration != _host.decoderProbeGeneration) {
        return;
      }
      try {
        final output = await platform.getProperty('current-vo');
        if (AndroidRendererStartupFallback.isExpectedOutput(
              mode: _host.androidVideoRendererMode,
              value: output,
            ) &&
            output == previousOutput) {
          _host.rendererValidatedForSession = true;
          _host.rendererStartupGuardToken++;
          return;
        }
        previousOutput = output;
      } catch (_) {
        // A transient property-query failure gets the remainder of the window.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await fallbackExplicitRendererToAutomatic(
      instanceGeneration: instanceGeneration,
      mediaGeneration: mediaGeneration,
      reason: 'requested_output_not_ready',
    );
  }

  bool canFallbackExplicitRenderer({
    required int instanceGeneration,
    required int mediaGeneration,
  }) =>
      AndroidRendererStartupFallback.shouldArm(
        isAndroid: _host.isAndroid,
        isAndroidTv: PlatformUtil.isAndroidTvCached,
        mode: _host.androidVideoRendererMode,
        alreadyValidated: _host.rendererValidatedForSession,
        fallbackInProgress: _host.rendererFallbackInProgress,
      ) &&
      _host.mounted &&
      instanceGeneration == _host.playerInstanceGeneration &&
      mediaGeneration == _host.decoderProbeGeneration &&
      _host.activeOpenedMedia != null &&
      !_host.isRecording &&
      !_host.iptvErrorsMuted &&
      !_host.isTransitioning;

  Future<void> fallbackExplicitRendererToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  }) async {
    if (!canFallbackExplicitRenderer(
      instanceGeneration: instanceGeneration,
      mediaGeneration: mediaGeneration,
    )) {
      return;
    }

    _host.rendererFallbackInProgress = true;
    _host.rendererStartupGuardToken++;
    final startupEpoch = _host.resumeVerifyEpoch;
    final restartChannelWatch = _host.stremioTvStartupWatch?.isPending == true;
    int? recoveryOpenEpoch;
    final media = _host.activeOpenedMedia!;
    final oldPlayer = _host.player;
    final oldState = oldPlayer.state;
    // A renderer rebuild mid-startup can race an unlanded resume seek: the
    // live position is then a restart artifact, and the rebuilt player must
    // come back at the promised target, not ~0. (Pure query — the guard stays
    // armed for the rebuilt player's own landing.)
    final livePosition = _host.position > Duration.zero
        ? _host.position
        : oldState.position;
    final heldMs = _host.resumeWriteGuard.heldTargetIfBlocked(
      livePosition.inMilliseconds,
    );
    final resumePosition = heldMs != null
        ? Duration(milliseconds: heldMs)
        : livePosition;
    final shouldResumePlayback =
        _host.activeMediaShouldPlay &&
        !_host.activeMediaUserPaused &&
        !_host.sleepStopLatched;
    final rate = oldState.rate;
    final volume = oldState.volume;
    final isLive = _host.currentIptvChannel?.isLive == true;
    final externalAudio = _host.audioUrl;
    final hasExternalAudio = externalAudio != null && externalAudio.isNotEmpty;

    final failedRenderer = _host.androidVideoRendererMode.storageKey;
    _host.releasePlayerDiagnostic(
      'generation=$mediaGeneration phase=fallback '
      'status=renderer_startup_failed platform=android backend=libmpv '
      'requested_renderer=$failedRenderer fallback=automatic reason=$reason',
    );

    // Invalidate every old callback before the first await. Only one native
    // player may own audio and the Android surface during the restart.
    _host.playerInstanceGeneration++;
    _host.playerCreated = false;
    _host.isReady = false;
    _host.isPlaying = false;
    _host.showBufferingIndicator.value = false;
    _host.setState(() {});

    try {
      await _host.cancelPlayerInstanceSubscriptions();
      await _host.disposeSubtitleAutoSync();
      _host.activeExternalSubtitlePath = null;
      _host.releaseAudioEffectSession();
      try {
        await oldPlayer.pause();
      } catch (_) {}
      try {
        await oldPlayer.dispose();
      } catch (_) {
        // Disposal normally succeeds, but retain ownership if the native
        // backend throws so route teardown can make one final cleanup attempt.
        _host.playerCreated = true;
        rethrow;
      }
      if (!_host.mounted) return;

      // Remember the compatibility result. The setting now visibly reads
      // Automatic, and choosing an explicit renderer again retries it.
      _host.androidVideoRendererMode = AndroidVideoRendererMode.automatic;
      try {
        await PlayerSettingsStorage.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.automatic,
        );
      } catch (_) {
        // Playback can still recover for this session if preferences are full
        // or unavailable.
      }
      if (!_host.mounted) return;

      _host.duration = Duration.zero;
      _host.position = Duration.zero;
      await _host.claimVideoOutput();
      if (!_host.mounted) return;
      _host.createPlayerInstance(AndroidVideoRendererMode.automatic);
      await _host.configurePlayerAudio(_host.player);
      _host.installSubtitleAutoSyncForPlayer(_host.player);
      await _host.attachAudioEffectSession();
      if (!_host.mounted) return;
      _host.setState(() {});

      final needsPreparation =
          hasExternalAudio || (!isLive && resumePosition > Duration.zero);
      final playOnOpen =
          shouldResumePlayback && !_host.pausedByLifecycle && !needsPreparation;
      // Navigation during the rebuild wins over this old media's restart.
      if (startupEpoch != _host.resumeVerifyEpoch) return;
      final reopening = _host.openMedia(
        media,
        play: playOnOpen,
        desiredPlay: shouldResumePlayback,
        // The recreated player starts with a clean property set — without
        // this a live channel would silently lose its ffmpeg reconnect
        // options at the renderer fallback (codex round 2, finding 16).
        liveStream: isLive,
        preserveStartupEpoch: startupEpoch,
        beforeOpen: restartChannelWatch
            ? () {
                _host.watchStremioTvStartup(media.uri);
                return true;
              }
            : null,
      );
      recoveryOpenEpoch = _host.resumeVerifyEpoch;
      await reopening;
      if (needsPreparation) await _host.waitForVideoReady();
      if (!_host.mounted) return;
      await _host.player.setRate(rate);
      await _host.player.setVolume(volume);
      if (hasExternalAudio) {
        await _host.setExternalAudioTrack(externalAudio);
      }
      if (!isLive && resumePosition > Duration.zero) {
        // Re-ARMS the guard at the carried position: the rebuilt player gets
        // its own protected landing instead of an unguarded raw seek.
        await _host.seekForResume(resumePosition.inMilliseconds);
      }
      unawaited(_host.restoreTrackPreferences());
      if (shouldResumePlayback && !_host.pausedByLifecycle && !playOnOpen) {
        await _host.player.play();
      }

      if (_host.mounted) {
        ScaffoldMessenger.of(_host.context).showSnackBar(
          const SnackBar(
            content: Text(
              'Direct Surface was unavailable. Using Automatic renderer.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      _host.releasePlayerDiagnostic(
        'generation=$mediaGeneration phase=fallback '
        'status=failed platform=android backend=libmpv '
        'requested_renderer=direct_surface fallback=automatic',
      );
      final failureEpoch = recoveryOpenEpoch ?? startupEpoch;
      if (restartChannelWatch && failureEpoch == _host.resumeVerifyEpoch) {
        final watch = _host.stremioTvStartupWatch;
        if (watch?.hasFailed != true) {
          watch?.dispose();
          _host.stremioTvStartupSeek.cancel();
          unawaited(
            _host.reportStartupFailure(
              isCurrent: () => failureEpoch == _host.resumeVerifyEpoch,
            ),
          );
        }
      }
    } finally {
      _host.rendererFallbackInProgress = false;
    }
  }
}
