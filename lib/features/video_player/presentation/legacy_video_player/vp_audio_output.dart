import 'dart:io';

import 'package:debrify/screens/video_player/services/media_kit_subtitle_auto_sync.dart';
import 'package:debrify/services/audio_effect_session_service.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/utils/language_mapping.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/utils/player_audio_config.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpAudioOutputHost {
  bool get appleMultichannelEnabled;
  bool get audioPassthroughEnabled;
  set audioPassthroughEnabled(bool v);
  mk.Player get player;
  bool get systemAudioEffectsEnabled;
  bool get tvosForceStereoAudio;
  bool get tvosLegacyAudioOutput;
  int get tvosRouteOutputChannels;
  MediaKitSubtitleAutoSync? get subtitleAutoSync;
}

class VpAudioOutput {
  VpAudioOutput(this._host);
  final VpAudioOutputHost _host;

  /// Audio session announced to system effect apps (Android only). Non-null
  /// only while an OPEN broadcast is outstanding — see
  /// [attachAudioEffectSession] / [releaseAudioEffectSession].
  int? audioEffectSessionId;

  /// Load an external audio track to play alongside a video-only stream
  /// (high-res YouTube serves video and audio separately). Uses media_kit's
  /// AudioTrack.uri (mpv `audio-add`), which is URL-safe — unlike the
  /// `audio-files` path-list option, which mangles URLs on the `:`/`,`
  /// separators. Must be called AFTER the main media has loaded.
  Future<void> setExternalAudioTrack(String audioUrl) async {
    try {
      await _host.player.setAudioTrack(mk.AudioTrack.uri(audioUrl));
    } catch (e) {
      debugPrint('VideoPlayer: failed to set external audio track: $e');
    }
  }

  /// Put Android audio on an effects-capable output and announce the session,
  /// so system effect apps (Wavelet, OEM equalizers, hearing-accessibility
  /// tools) can process our playback like they do for other video apps.
  ///
  /// Two separate things block that by default:
  ///
  ///  1. media_kit pins Android to `ao=opensles`, and mpv's OpenSL ES output
  ///     never sets SL_ANDROID_KEY_PERFORMANCE_MODE — so Android applies its
  ///     default low-latency path, which is documented to carry *no* hardware
  ///     or software effects. Nothing can attach to our audio at all, which is
  ///     why even a global/"legacy mode" equalizer has no effect on us.
  ///     `audiotrack` is an ordinary AudioTrack and is effects-capable; the
  ///     `opensles` fallback keeps today's behaviour on any device where
  ///     AudioTrack fails to initialise, so audio can't be lost outright.
  ///  2. Effect apps attach to a session id learned from the standard OPEN
  ///     broadcast. mpv generates an id internally and tells nobody, so we pin
  ///     our own via `audiotrack-session-id` and announce that.
  ///
  /// Fails soft at every step: effects are a nice-to-have, playback is not.
  /// Opt-in (Settings → Player Settings): switching the audio backend is a real
  /// change to how every device outputs sound, so off must leave playback byte
  /// for byte as it was.
  Future<void> attachAudioEffectSession() async {
    if (!Platform.isAndroid) return;
    // Everything below is inside the catch: VpPlayerStartup.initializePlayer() runs
    // unawaited, so anything that escapes here would abort the rest of init
    // and leave a black screen — including for users who have this turned off,
    // since the settings read itself happens either way.
    try {
      final platform = _host.player.platform;
      if (platform is! mk.NativePlayer) return;
      // The CACHED field, deliberately: [configurePlayerAudio] chose the
      // audio output from it, and a fresh preference read here could
      // diverge mid-session — announcing a session on an output that was
      // never switched, or vice versa. "Restart playback to apply" is the
      // settings contract for both halves.
      if (!_host.systemAudioEffectsEnabled) return;
      // `ao=audiotrack,...` itself is owned by [configurePlayerAudio] now
      // (the passthrough setting needs the same output, and two writers of
      // `ao` is how the two settings would fight) — this method keeps only
      // the session-id half.
      final sessionId = await AudioEffectSessionService.generateSessionId();
      // No id available: still worth keeping the effects-capable output, since
      // effect apps that detect sessions on their own can then attach.
      if (sessionId == null) return;
      await platform.setProperty('audiotrack-session-id', '$sessionId');
      await AudioEffectSessionService.open(sessionId);
      audioEffectSessionId = sessionId;
    } catch (e) {
      debugPrint('VideoPlayer: audio effect session setup failed: $e');
    }
  }

  /// Release the announced audio session. Unpaired OPENs leave effect apps
  /// attached to dead audio and degrade *other* apps' equalizers, so this must
  /// run on every exit from the player.
  void releaseAudioEffectSession() {
    final sessionId = audioEffectSessionId;
    if (sessionId == null) return;
    audioEffectSessionId = null;
    AudioEffectSessionService.close(sessionId);
  }

  /// Serializes live passthrough flips: each runs WHOLE, in order. Without
  /// this a rapid double-toggle could interleave two aid cycles and leave
  /// the newer one reading `aid=no` mid-way through the older one's cycle —
  /// stranding the player silent.
  Future<void> passthroughFlipChain = Future<void>.value();

  /// The in-player passthrough flip — persists the same setting the
  /// Playback Defaults row writes, applies the explicit property values
  /// (including the OFF restores), then cycles the audio track so the
  /// CURRENT file's audio chain re-initialises: `audio-spdif` is read at
  /// decoder init, and `ao` reloads on the reconfig. Sub-second audio gap,
  /// position untouched. Fails soft: playback outlives any of this (and
  /// mpv gives no rejection signal to roll a switch back on — the toggle's
  /// caption owns the "silence means off" contract).
  Future<void> setAudioPassthroughLive(bool enabled) {
    final flip = passthroughFlipChain.then(
      (_) => applyPassthroughFlip(enabled),
    );
    passthroughFlipChain = flip.catchError((_) {});
    return flip;
  }

  Future<void> applyPassthroughFlip(bool enabled) async {
    _host.audioPassthroughEnabled = enabled;
    try {
      await PlayerSettingsStorage.setAudioPassthroughEnabled(enabled);
      // An audio filter would force compressed passthrough formats through a
      // PCM decoder. Remove the passive analysis chain before the aid cycle;
      // when passthrough is disabled, re-arm only after PCM output is restored.
      if (enabled) {
        await _host.subtitleAutoSync?.setPassthroughEnabled(true);
      }
      final platform = _host.player.platform;
      if (platform is! mk.NativePlayer) return;
      for (final (property, value)
          in PlayerAudioConfig.androidLiveToggleProperties(
            passthroughEnabled: enabled,
            systemAudioEffects: _host.systemAudioEffectsEnabled,
          )) {
        await platform.setProperty(property, value);
      }
      final aid = await platform.getProperty('aid');
      if (aid.isNotEmpty && aid != 'no') {
        await platform.setProperty('aid', 'no');
        await platform.setProperty('aid', aid);
      }
      if (!enabled) {
        await _host.subtitleAutoSync?.setPassthroughEnabled(false);
      }
    } catch (e) {
      debugPrint('VideoPlayer: live passthrough toggle failed: $e');
    }
  }

  /// The single owner of the player's audio-output properties — ordered
  /// list from [PlayerAudioConfig], awaited before the first open, run at
  /// EVERY player-instance creation site (initial + the Android renderer
  /// fallback recreate). Fails soft per property: audio configuration is a
  /// nice-to-have, playback is not.
  Future<void> configurePlayerAudio(mk.Player player) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return;
    final props = PlayerAudioConfig.audioProperties(
      isAndroid: !kIsWeb && Platform.isAndroid,
      isApple: PlatformUtil.isTvOS || PlatformUtil.isIosMobile,
      isTvOS: PlatformUtil.isTvOS,
      routeOutputChannels: _host.tvosRouteOutputChannels,
      tvosForceStereo: _host.tvosForceStereoAudio,
      tvosLegacyAudioOutput: _host.tvosLegacyAudioOutput,
      passthroughEnabled: _host.audioPassthroughEnabled,
      systemAudioEffects: _host.systemAudioEffectsEnabled,
      multichannelEnabled: _host.appleMultichannelEnabled,
    );
    for (final (property, value) in props) {
      try {
        await platform.setProperty(property, value);
      } catch (e) {
        debugPrint('VideoPlayer: audio config $property=$value failed: $e');
      }
    }
    // Preferred audio language, handed to mpv itself as `alang`. The Dart
    // matcher (VpSubtitleLanguagePolicy.applyDefaultAudioLanguage) only runs after the track list
    // reaches Dart and only matches on metadata; mpv applies the preference
    // at stream selection, and its matcher also weighs the default/forced
    // dispositions. Users with no preference set send nothing.
    try {
      final lang = await SubtitleSettingsStorage.getDefaultAudioLanguage();
      if (lang != null && lang.isNotEmpty) {
        final alang = LanguageMapper.alangForCode(lang);
        if (alang.isNotEmpty) await platform.setProperty('alang', alang);
      }
    } catch (e) {
      debugPrint('VideoPlayer: alang config failed: $e');
    }
  }
}
