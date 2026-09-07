import 'dart:async';

import 'package:media_kit/media_kit.dart' as mk;

import '../../../models/android_video_renderer_mode.dart';
import '../../../services/storage_service.dart';
import 'android_renderer_startup_fallback.dart';

abstract interface class RendererSession {
  bool get mounted;
  int get playerInstanceGeneration;
  int get mediaGeneration;
  mk.Player get player;
  mk.Media? get activeOpenedMedia;
  Duration get position;
  bool get activeMediaShouldPlay;
  bool get activeMediaUserPaused;
  bool get sleepStopLatched;
  bool get isLive;
  String? get externalAudio;
  bool get pausedByLifecycle;
  bool get isTeeRecording;
  bool get errorsMuted;
  bool get isTransitioning;
  bool get fallbackPlatformIsAndroid;
  bool get probePlatformIsAndroid;
  bool get isAndroidTv;
  List<StreamSubscription?> takeSubscriptions();
  int? heldResumeTarget(int positionMs);
  Future<void> disposeSubtitleAutoSync();
  void clearExternalSubtitlePath();
  void releaseAudioEffectSession();
  void retainPlayerOwnership();
  Future<void> claimVideoOutput();
  void createPlayerInstance(AndroidVideoRendererMode mode);
  Future<void> configurePlayerAudio(mk.Player player);
  void installSubtitleAutoSync(mk.Player player);
  Future<void> attachAudioEffectSession();
  void notifyStateChanged();
  Future<void> openMedia(mk.Media media, {required bool play, required bool desiredPlay, required bool liveStream});
  Future<void> waitForVideoReady();
  Future<void> setExternalAudioTrack(String url);
  Future<void> seekForResume(int targetMs);
  Future<void> restoreTrackPreferences();
  void diagnostic(String fields);
  void invalidatePlayerForFallback();
  void resetPlaybackPosition();
  void showAutomaticNotice();
}

class RendererCoordinator {
  RendererCoordinator(this.session);
  final RendererSession session;
  AndroidVideoRendererMode mode = AndroidVideoRendererMode.automatic;
  bool _validatedForSession = false;
  bool _fallbackInProgress = false;
  int _guardToken = 0;
  int _validationGeneration = -1;
  bool get validatedForSession => _validatedForSession;
  bool get fallbackInProgress => _fallbackInProgress;

  // Return the original Future without wrapping; non-Android adds no await.
  Future<AndroidVideoRendererMode>? loadRequestedMode() {
    if (session.fallbackPlatformIsAndroid && !session.isAndroidTv) {
      return StorageService.getAndroidVideoRendererMode();
    }
    return null;
  }

  void invalidateGuard() => _guardToken++;
  void invalidateStartup() {
    _guardToken++;
    _validationGeneration = -1;
  }

  Future<void> _cancelPlayerInstanceSubscriptions() async {
    final subscriptions = session.takeSubscriptions();
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

  void scheduleStartupValidation() {
    if (!AndroidRendererStartupFallback.shouldArm(
          isAndroid: session.probePlatformIsAndroid,
          isAndroidTv: session.isAndroidTv,
          mode: mode,
          alreadyValidated: _validatedForSession,
          fallbackInProgress: _fallbackInProgress,
        ) ||
        session.errorsMuted ||
        _validationGeneration == session.mediaGeneration) {
      return;
    }
    _validationGeneration = session.mediaGeneration;
    final guardToken = ++_guardToken;
    final instanceGeneration = session.playerInstanceGeneration;
    final mediaGeneration = session.mediaGeneration;
    final player = session.player;
    unawaited(
      _validateStartup(
        guardToken: guardToken,
        instanceGeneration: instanceGeneration,
        mediaGeneration: mediaGeneration,
        player: player,
      ),
    );
  }

  Future<void> _validateStartup({
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
      if (!session.mounted ||
          guardToken != _guardToken ||
          instanceGeneration != session.playerInstanceGeneration ||
          mediaGeneration != session.mediaGeneration) {
        return;
      }
      try {
        final output = await platform.getProperty('current-vo');
        if (AndroidRendererStartupFallback.isExpectedOutput(
              mode: mode,
              value: output,
            ) &&
            output == previousOutput) {
          _validatedForSession = true;
          _guardToken++;
          return;
        }
        previousOutput = output;
      } catch (_) {
        // A transient property-query failure gets the remainder of the window.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await fallbackToAutomatic(
      instanceGeneration: instanceGeneration,
      mediaGeneration: mediaGeneration,
      reason: 'requested_output_not_ready',
    );
  }

  Future<void> fallbackToAutomatic({
    required int instanceGeneration,
    required int mediaGeneration,
    required String reason,
  }) async {
    if (!AndroidRendererStartupFallback.shouldArm(
          isAndroid: session.fallbackPlatformIsAndroid,
          isAndroidTv: session.isAndroidTv,
          mode: mode,
          alreadyValidated: _validatedForSession,
          fallbackInProgress: _fallbackInProgress,
        ) ||
        !session.mounted ||
        instanceGeneration != session.playerInstanceGeneration ||
        mediaGeneration != session.mediaGeneration ||
        session.activeOpenedMedia == null ||
        session.isTeeRecording ||
        session.errorsMuted ||
        session.isTransitioning) {
      return;
    }

    _fallbackInProgress = true;
    _guardToken++;
    final media = session.activeOpenedMedia!;
    final oldPlayer = session.player;
    final oldState = oldPlayer.state;
    // A renderer rebuild mid-startup can race an unlanded resume seek: the
    // live position is then a restart artifact, and the rebuilt player must
    // come back at the promised target, not ~0. (Pure query — the guard stays
    // armed for the rebuilt player's own landing.)
    final livePosition = session.position > Duration.zero
        ? session.position
        : oldState.position;
    final heldMs = session.heldResumeTarget(
      livePosition.inMilliseconds,
    );
    final resumePosition = heldMs != null
        ? Duration(milliseconds: heldMs)
        : livePosition;
    final shouldResumePlayback =
        session.activeMediaShouldPlay && !session.activeMediaUserPaused && !session.sleepStopLatched;
    final rate = oldState.rate;
    final volume = oldState.volume;
    final isLive = session.isLive;
    final externalAudio = session.externalAudio;
    final hasExternalAudio = externalAudio != null && externalAudio.isNotEmpty;

    final failedRenderer = mode.storageKey;
    session.diagnostic(
      'generation=$mediaGeneration phase=fallback '
      'status=renderer_startup_failed platform=android backend=libmpv '
      'requested_renderer=$failedRenderer fallback=automatic reason=$reason',
    );

    // Invalidate every old callback before the first await. Only one native
    // player may own audio and the Android surface during the restart.
    session.invalidatePlayerForFallback();

    try {
      await _cancelPlayerInstanceSubscriptions();
      await session.disposeSubtitleAutoSync();
      session.clearExternalSubtitlePath();
      session.releaseAudioEffectSession();
      try {
        await oldPlayer.pause();
      } catch (_) {}
      try {
        await oldPlayer.dispose();
      } catch (_) {
        // Disposal normally succeeds, but retain ownership if the native
        // backend throws so route teardown can make one final cleanup attempt.
        session.retainPlayerOwnership();
        rethrow;
      }
      if (!session.mounted) return;

      // Remember the compatibility result. The setting now visibly reads
      // Automatic, and choosing an explicit renderer again retries it.
      mode = AndroidVideoRendererMode.automatic;
      try {
        await StorageService.setAndroidVideoRendererMode(
          AndroidVideoRendererMode.automatic,
        );
      } catch (_) {
        // Playback can still recover for this session if preferences are full
        // or unavailable.
      }
      if (!session.mounted) return;

      session.resetPlaybackPosition();
      await session.claimVideoOutput();
      if (!session.mounted) return;
      session.createPlayerInstance(AndroidVideoRendererMode.automatic);
      await session.configurePlayerAudio(session.player);
      session.installSubtitleAutoSync(session.player);
      await session.attachAudioEffectSession();
      if (!session.mounted) return;
      session.notifyStateChanged();

      final needsPreparation =
          hasExternalAudio || (!isLive && resumePosition > Duration.zero);
      final playOnOpen =
          shouldResumePlayback && !session.pausedByLifecycle && !needsPreparation;
      await session.openMedia(
        media,
        play: playOnOpen,
        desiredPlay: shouldResumePlayback,
        // The recreated player starts with a clean property set — without
        // this a live channel would silently lose its ffmpeg reconnect
        // options at the renderer fallback (codex round 2, finding 16).
        liveStream: isLive,
      );
      if (needsPreparation) await session.waitForVideoReady();
      if (!session.mounted) return;
      await session.player.setRate(rate);
      await session.player.setVolume(volume);
      if (hasExternalAudio) {
        await session.setExternalAudioTrack(externalAudio);
      }
      if (!isLive && resumePosition > Duration.zero) {
        // Re-ARMS the guard at the carried position: the rebuilt player gets
        // its own protected landing instead of an unguarded raw seek.
        await session.seekForResume(resumePosition.inMilliseconds);
      }
      unawaited(session.restoreTrackPreferences());
      if (shouldResumePlayback && !session.pausedByLifecycle && !playOnOpen) {
        await session.player.play();
      }

      if (session.mounted) {
        session.showAutomaticNotice();
      }
    } catch (_) {
      session.diagnostic(
        'generation=$mediaGeneration phase=fallback '
        'status=failed platform=android backend=libmpv '
        'requested_renderer=direct_surface fallback=automatic',
      );
    } finally {
      _fallbackInProgress = false;
    }
  }

}
