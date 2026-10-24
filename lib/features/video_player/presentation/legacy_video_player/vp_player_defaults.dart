import 'dart:io';

import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_guide_style.dart';
import 'package:debrify/services/storage/iptv_appearance_storage.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/tvos_display_match_service.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class VpPlayerDefaultsHost {
  set appleMultichannelEnabled(bool v);
  set audioPassthroughEnabled(bool v);
  ContentDisplayMatchMode get contentDisplayMatchMode;
  set contentDisplayMatchMode(ContentDisplayMatchMode v);
  PlayerGuideStyle get playerGuideStyle;
  set playerGuideStyle(PlayerGuideStyle v);
  set playerGuideTokens(IptvStyleTokens? v);
  set subtitleForcedOnly(bool v);
  set subtitleOnlyForeignAudio(bool v);
  set subtitlePreferredAudio(String? v);
  set systemAudioEffectsEnabled(bool v);
  set tvosForceSoftwareDecode(bool v);
  set tvosForceStereoAudio(bool v);
  set tvosLegacyAudioOutput(bool v);
  set tvosRouteOutputChannels(int v);
  MethodChannel get tvReleaseLogChannel;
  AspectMode get aspectMode;
  set aspectMode(AspectMode v);
  bool get subtitleAutoSyncEnabled;
  set subtitleAutoSyncEnabled(bool v);
}

class VpPlayerDefaults {
  VpPlayerDefaults(this._host);
  final VpPlayerDefaultsHost _host;

  Future<void> loadPlayerDefaults() async {
    _host.subtitleOnlyForeignAudio =
        await SubtitleSettingsStorage.getSubtitleOnlyForeignAudio();
    _host.subtitleForcedOnly =
        await SubtitleSettingsStorage.getSubtitleForcedOnly();
    _host.subtitlePreferredAudio =
        await SubtitleSettingsStorage.getDefaultAudioLanguage();
    _host.subtitleAutoSyncEnabled =
        await SubtitleSettingsStorage.getSubtitleAutoSyncEnabled();
    debugPrint(
      'SubtitleAutoSync: pref loaded, enabled=${_host.subtitleAutoSyncEnabled}',
    );
    // Load default aspect index
    final aspectIndex =
        await PlayerSettingsStorage.getPlayerDefaultAspectIndex();
    const aspects = AspectMode.values;
    _host.aspectMode = aspects[aspectIndex.clamp(0, aspects.length - 1)];

    // In-player guide look. `_initializePlayer` awaits this before playback
    // setup, so every IPTV surface that can actually appear (first tune,
    // zap, guide) already has the real value.
    _host.playerGuideStyle = PlayerGuideStyle.fromPref(
      await IptvAppearanceStorage.getIptvPlayerGuideStyle(),
    );
    _host.playerGuideTokens = PlayerGuideTokens.of(_host.playerGuideStyle);

    if (PlatformUtil.isTvOS) {
      _host.tvosForceSoftwareDecode =
          await PlayerSettingsStorage.getTvosForceSoftwareDecode();
      _host.contentDisplayMatchMode =
          await PlayerNetworkStorage.getContentDisplayMatchMode();
      if (!_host.contentDisplayMatchMode.requestsMatching) {
        try {
          await TvosDisplayMatchService.clear();
        } catch (error) {
          debugPrint('DisplayMatch: tvOS clear failed: $error');
        }
      }
    }

    // Audio-output settings, preloaded for [_configurePlayerAudio] — the
    // single owner of ao / audio-spdif / audio-channels
    // (AUDIO_FIDELITY_PLAN.md).
    if (!kIsWeb && Platform.isAndroid) {
      _host.audioPassthroughEnabled =
          await PlayerSettingsStorage.getAudioPassthroughEnabled();
      _host.systemAudioEffectsEnabled =
          await PlayerSettingsStorage.getPlayerSystemAudioEffects();
    } else if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile) {
      _host.appleMultichannelEnabled =
          await PlayerSettingsStorage.getAppleMultichannelAudio();
    }
    if (PlatformUtil.isTvOS) {
      _host.tvosForceStereoAudio =
          await PlayerSettingsStorage.getTvosForceStereoAudio();
      _host.tvosLegacyAudioOutput =
          await PlayerSettingsStorage.getTvosLegacyAudioOutput();
      // What the CURRENT output route can take. ao_avfoundation passes the
      // file's native layout through, so a 5.1 track on a two-channel route
      // (AirPods, Bluetooth, stereo TV) folds badly; PlayerAudioConfig caps
      // those to stereo. 0 means "unknown" and leaves mpv's default alone.
      try {
        _host.tvosRouteOutputChannels =
            await _host.tvReleaseLogChannel.invokeMethod<int>(
              'outputChannelCount',
            ) ??
            0;
      } catch (_) {
        _host.tvosRouteOutputChannels = 0;
      }
    }

    debugPrint('VideoPlayer: Loaded defaults - aspect=${_host.aspectMode}');
  }
}
