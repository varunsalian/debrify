import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';

final class PlayerSettingsStorage {
  const PlayerSettingsStorage._();

  // Debrify Player default settings
  static const String _playerDefaultAspectIndexKey = 'player_default_aspect_index';
  static const String _playerDefaultAspectIndexTvKey = 'player_default_aspect_index_tv';
  static const String _playerNightModeIndexKey = 'player_night_mode_index';
  static const String _playerSystemAudioEffectsKey = 'player_system_audio_effects';
  static const String _playerStartPortraitKey = 'player_start_portrait';
  static const String _androidVideoRendererModeKey = 'android_video_renderer_mode';
  static const String _androidVideoRendererGpuMigrationKey = 'android_video_renderer_gpu_migration_v1';
  static const String _tvosForceSoftwareDecodeKey = 'tvos_force_software_decode';
  static const String _audioPassthroughKey = 'player_audio_passthrough';
  static const String _appleMultichannelAudioKey = 'player_apple_multichannel_audio';
  static const String _tvosForceStereoAudioKey = 'tvos_force_stereo_audio_v1';
  static const String _tvosLegacyAudioOutputKey = 'tvos_legacy_audio_output_v1';

  // Debrify Player Default Settings

  /// Get default aspect ratio index for Flutter/mobile player
  /// 0=Contain, 1=Cover, 2=FitWidth, 3=FitHeight, 4=16:9, 5=4:3, 6=21:9, 7=1:1, 8=3:2, 9=5:4, 10=CinemaZoom
  /// Default: 2 (Fit Width)
  static Future<int> getPlayerDefaultAspectIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexKey) ?? 2;
  }

  /// Set default aspect ratio index for Flutter/mobile player
  static Future<void> setPlayerDefaultAspectIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexKey, index);
  }

  /// Get default aspect ratio index for Android TV player
  /// 0=Fit, 1=Fill, 2=Zoom, 3=CinemaZoom
  /// Default: 0 (Fit)
  static Future<int> getPlayerDefaultAspectIndexTv() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerDefaultAspectIndexTvKey) ?? 0;
  }

  /// Set default aspect ratio index for Android TV player
  static Future<void> setPlayerDefaultAspectIndexTv(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerDefaultAspectIndexTvKey, index);
  }

  /// Get night mode index (Android TV only)
  /// 0=Off, 1=Low, 2=Medium, 3=High, 4=Higher, 5=Extreme, 6=Max, 7=Sleeping Baby
  /// Default: 0 (Off)
  static Future<int> getPlayerNightModeIndex() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_playerNightModeIndexKey) ?? 0;
  }

  /// Set night mode index (Android TV only)
  static Future<void> setPlayerNightModeIndex(int index) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_playerNightModeIndexKey, index);
  }

  /// Whether to route playback through Android's effects-capable audio output
  /// and announce the session to system equalizer apps (Wavelet, OEM effects).
  /// Android only. Default: false — off changes nothing about how audio is
  /// output today, since enabling it switches the phone player's audio backend.
  static Future<bool> getPlayerSystemAudioEffects() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_playerSystemAudioEffectsKey) ?? false;
  }

  /// Set whether system audio effect apps may process our playback.
  static Future<void> setPlayerSystemAudioEffects(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerSystemAudioEffectsKey, enabled);
  }

  /// Android Dart player only: bitstream AC3/EAC3/DTS-core to the audio
  /// device instead of decoding to PCM (AUDIO_FIDELITY_PLAN.md). Default
  /// false — passthrough is fail-loud on routes that misreport support,
  /// so only the user can turn it on.
  static Future<bool> getAudioPassthroughEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_audioPassthroughKey) ?? false;
  }

  static Future<void> setAudioPassthroughEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_audioPassthroughKey, enabled);
  }

  /// Apple (tvOS/iOS) Dart player: request the track's real channel layout
  /// (`audio-channels=auto`) so an HDMI/eARC AVR route gets full
  /// multichannel LPCM. Default false until route-safety is field-proven
  /// (AUDIO_FIDELITY_PLAN.md rev 2).
  static Future<bool> getAppleMultichannelAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_appleMultichannelAudioKey) ?? false;
  }

  static Future<void> setAppleMultichannelAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_appleMultichannelAudioKey, enabled);
  }

  /// Apple TV diagnostics. The player picks `ao=avfoundation,audiounit` and
  /// caps `audio-channels` to stereo on a route that reports two channels;
  /// these two override that automatic choice from either direction, so a
  /// reporter can narrow an audio problem without a custom build.
  ///
  /// Force stereo: cap regardless of what the route claims. Use when a
  /// multichannel route folds badly.
  static Future<bool> getTvosForceStereoAudio() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceStereoAudioKey) ?? false;
  }

  static Future<void> setTvosForceStereoAudio(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceStereoAudioKey, enabled);
  }

  /// Legacy output: go back to `ao=audiounit`, the pre-2026-08 behaviour.
  /// It is silent on Dolby Atmos routes — which is why avfoundation is now
  /// the default — but it is the escape hatch if the new output misbehaves.
  static Future<bool> getTvosLegacyAudioOutput() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosLegacyAudioOutputKey) ?? false;
  }

  static Future<void> setTvosLegacyAudioOutput(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosLegacyAudioOutputKey, enabled);
  }

  /// Apple TV only: force the media-kit player to software video decoding.
  /// The escape hatch behind the automatic 10-bit remedy ladder (see
  /// PLAYER_TVOS_10BIT_PLAN.md) — for files whose formats read clean but
  /// render wrong. Default false: hardware decoding, today's behavior.
  static Future<bool> getTvosForceSoftwareDecode() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_tvosForceSoftwareDecodeKey) ?? false;
  }

  static Future<void> setTvosForceSoftwareDecode(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_tvosForceSoftwareDecodeKey, enabled);
  }

  /// Renderer used by the Flutter media-kit player on Android phones/tablets.
  /// Android TV ignores this and keeps its native Media3 SurfaceView backend.
  static Future<AndroidVideoRendererMode> getAndroidVideoRendererMode() async {
    final prefs = await ProfilePreferences.instance();
    final migrated = prefs.getBool(_androidVideoRendererGpuMigrationKey) ?? false;
    final stored = prefs.getString(_androidVideoRendererModeKey);
    if (!migrated) {
      // Direct Surface used to be the default, but mediacodec_embed cannot
      // composite bitmap subtitles. Migrate existing installs once; users may
      // still explicitly choose the performance renderer afterwards.
      if (stored == null || stored == AndroidVideoRendererMode.directSurface.storageKey) {
        await prefs.setString(
          _androidVideoRendererModeKey,
          AndroidVideoRendererMode.directMediaCodec.storageKey,
        );
      }
      await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
    }
    return AndroidVideoRendererMode.fromStorage(
      prefs.getString(_androidVideoRendererModeKey),
    );
  }

  static Future<void> setAndroidVideoRendererMode(
    AndroidVideoRendererMode mode,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_androidVideoRendererModeKey, mode.storageKey);
    await prefs.setBool(_androidVideoRendererGpuMigrationKey, true);
  }

  /// Whether the phone player OPENS upright instead of turning the handset
  /// landscape for you. Off by default — a video wants the long edge, and that
  /// is what the player has always done. On, it opens portrait and the
  /// player's own Portrait/Landscape button is how the user turns it.
  /// Phone-only: a TV has no portrait and a desktop window ignores this
  /// entirely.
  ///
  /// [playerStartPortraitCached] mirrors it for SYNCHRONOUS reads. The player
  /// commits its orientation while building, so an async read there would set
  /// landscape and correct it a frame later — performing the exact flip this
  /// setting exists to prevent. Warmed in main() before runApp (the IPTV
  /// startup channel can open a player on the first frame) and kept in sync by
  /// the setter.
  static bool playerStartPortraitCached = false;

  static Future<bool> getPlayerStartPortrait() async {
    final prefs = await ProfilePreferences.instance();
    playerStartPortraitCached = prefs.getBool(_playerStartPortraitKey) ?? false;
    return playerStartPortraitCached;
  }

  static Future<void> setPlayerStartPortrait(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_playerStartPortraitKey, enabled);
    playerStartPortraitCached = enabled;
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    playerStartPortraitCached = false;
  }
}
