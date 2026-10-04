import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaybackVrSettersDependencies = ({
  void Function(VoidCallback) setState,
  PlaybackVrState vr,
});

class PlaybackVrSetters {
  final PlaybackVrSettersDependencies _deps;
  PlaybackVrSetters(this._deps);

  // DeoVR settings setters
  Future<void> setVrDefaultScreenType(String screenType) async {
    _deps.setState(() => _deps.vr.vrDefaultScreenType = screenType);
    await QuickPlayStorage.setQuickPlayVrDefaultScreenType(screenType);
  }

  Future<void> setVrDefaultStereoMode(String stereoMode) async {
    _deps.setState(() => _deps.vr.vrDefaultStereoMode = stereoMode);
    await QuickPlayStorage.setQuickPlayVrDefaultStereoMode(stereoMode);
  }

  Future<void> setVrAutoDetectFormat(bool autoDetect) async {
    _deps.setState(() => _deps.vr.vrAutoDetectFormat = autoDetect);
    await QuickPlayStorage.setQuickPlayVrAutoDetectFormat(autoDetect);
  }

  Future<void> setVrShowDialog(bool showDialog) async {
    _deps.setState(() => _deps.vr.vrShowDialog = showDialog);
    await QuickPlayStorage.setQuickPlayVrShowDialog(showDialog);
  }
}
