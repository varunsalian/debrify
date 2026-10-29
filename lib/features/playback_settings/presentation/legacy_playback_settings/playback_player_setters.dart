import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/video_player/data/player_gesture_settings.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/player_network_storage.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/skip_segments_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaybackPlayerSettersDependencies = ({
  void Function(VoidCallback) setState,
  PlaybackValuesState values,
});

class PlaybackPlayerSetters {
  final PlaybackPlayerSettersDependencies _deps;
  PlaybackPlayerSetters(this._deps);

  // Debrify Player settings setters
  Future<void> setDefaultAspectIndex(int index) async {
    _deps.setState(() => _deps.values.defaultAspectIndex = index);
    // Use platform-specific storage key
    if (_deps.values.isAndroidTv) {
      await PlayerSettingsStorage.setPlayerDefaultAspectIndexTv(index);
    } else {
      await PlayerSettingsStorage.setPlayerDefaultAspectIndex(index);
    }
  }

  Future<void> setNightModeIndex(int index) async {
    _deps.setState(() => _deps.values.nightModeIndex = index);
    await PlayerSettingsStorage.setPlayerNightModeIndex(index);
  }

  Future<void> setSystemAudioEffects(bool enabled) async {
    _deps.setState(() => _deps.values.systemAudioEffects = enabled);
    await PlayerSettingsStorage.setPlayerSystemAudioEffects(enabled);
  }

  Future<void> setTvosForceSoftwareDecode(bool enabled) async {
    _deps.setState(() => _deps.values.tvosForceSoftwareDecode = enabled);
    await PlayerSettingsStorage.setTvosForceSoftwareDecode(enabled);
  }

  Future<void> setTvosForceStereo(bool enabled) async {
    _deps.setState(() => _deps.values.tvosForceStereo = enabled);
    await PlayerSettingsStorage.setTvosForceStereoAudio(enabled);
  }

  Future<void> setTvosLegacyAudioOutput(bool enabled) async {
    _deps.setState(() => _deps.values.tvosLegacyAudioOutput = enabled);
    await PlayerSettingsStorage.setTvosLegacyAudioOutput(enabled);
  }

  Future<void> setAudioPassthrough(bool enabled) async {
    _deps.setState(() => _deps.values.audioPassthrough = enabled);
    await PlayerSettingsStorage.setAudioPassthroughEnabled(enabled);
  }

  Future<void> setAppleMultichannel(bool enabled) async {
    _deps.setState(() => _deps.values.appleMultichannel = enabled);
    await PlayerSettingsStorage.setAppleMultichannelAudio(enabled);
  }

  Future<void> setAndroidVideoRendererMode(String storageKey) async {
    final mode = AndroidVideoRendererMode.fromStorage(storageKey);
    _deps.setState(() => _deps.values.androidVideoRendererMode = mode);
    await PlayerSettingsStorage.setAndroidVideoRendererMode(mode);
  }

  Future<void> setContentDisplayMatchMode(String storageKey) async {
    final mode = ContentDisplayMatchMode.fromStorage(storageKey);
    _deps.setState(() => _deps.values.contentDisplayMatchMode = mode);
    await PlayerNetworkStorage.setContentDisplayMatchMode(mode);
  }

  Future<void> setIptvDecoderMode(String value) async {
    _deps.setState(() => _deps.values.iptvDecoderMode = value);
    await PlayerNetworkStorage.setIptvDecoderMode(value);
  }

  Future<void> setStartPortrait(bool enabled) async {
    _deps.setState(() => _deps.values.startPortrait = enabled);
    await PlayerSettingsStorage.setPlayerStartPortrait(enabled);
  }

  /// Also refreshes [PlayerGestureSettings]'s synchronous cache so an open
  /// or next player picks the choice up without another settings load.
  Future<void> setSwipeSeek(bool enabled) async {
    _deps.setState(() => _deps.values.swipeSeek = enabled);
    await PlayerGestureSettings.setSwipeSeek(enabled);
  }

  List<int> get completionThresholdOptions =>
      LocalCompletionStorage.localCompletionThresholdOptions;

  int completionThresholdIndex(int value) {
    final index = completionThresholdOptions.indexOf(value);
    return index < 0
        ? completionThresholdOptions.indexOf(
            LocalCompletionStorage.defaultLocalCompletionThreshold,
          )
        : index;
  }

  Future<void> setMovieCompletionThresholdIndex(int index) async {
    final value = completionThresholdOptions[index];
    _deps.setState(() => _deps.values.movieCompletionThreshold = value);
    await LocalCompletionStorage.setMovieCompletionThreshold(value);
  }

  Future<void> setEpisodeCompletionThresholdIndex(int index) async {
    final value = completionThresholdOptions[index];
    _deps.setState(() => _deps.values.episodeCompletionThreshold = value);
    await LocalCompletionStorage.setEpisodeCompletionThreshold(value);
  }

  Future<void> setSkipSegmentsEnabled(bool enabled) async {
    _deps.setState(() => _deps.values.skipSegmentsEnabled = enabled);
    await SkipSegmentsStorage.setSkipSegmentsEnabled(enabled);
  }

  Future<void> setSkipSegmentProvider(String provider) async {
    _deps.setState(() => _deps.values.skipSegmentProvider = provider);
    await SkipSegmentsStorage.setSkipSegmentProvider(provider);
  }

  Future<void> setNetPatience(String value) async {
    _deps.setState(() => _deps.values.netPatience = value);
    await PlayerNetworkStorage.setNetworkConnectPatience(value);
  }

  Future<void> setNetBuffer(String value) async {
    _deps.setState(() => _deps.values.netBuffer = value);
    await PlayerNetworkStorage.setNetworkBufferSize(value);
  }
}
