import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/screens/video_player/services/subtitle_settings_service.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:debrify/services/subtitle_font_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PlaybackSubtitleSettersDependencies = ({
  void Function(VoidCallback) setState,
  PlaybackSubtitleState sub,
});

class PlaybackSubtitleSetters {
  final PlaybackSubtitleSettersDependencies _deps;
  PlaybackSubtitleSetters(this._deps);

  Future<void> setSubtitleOnlyForeignAudio(bool enabled) async {
    _deps.setState(() => _deps.sub.subtitleOnlyForeignAudio = enabled);
    await SubtitleSettingsStorage.setSubtitleOnlyForeignAudio(enabled);
  }

  Future<void> setSubtitleForcedOnly(bool enabled) async {
    _deps.setState(() => _deps.sub.subtitleForcedOnly = enabled);
    await SubtitleSettingsStorage.setSubtitleForcedOnly(enabled);
  }

  Future<void> setSubtitleAutoSync(bool enabled) async {
    _deps.setState(() => _deps.sub.subtitleAutoSync = enabled);
    await SubtitleSettingsStorage.setSubtitleAutoSyncEnabled(enabled);
  }

  Future<void> setDefaultSubtitleLanguage(String? languageCode) async {
    _deps.setState(() => _deps.sub.defaultSubtitleLanguage = languageCode);
    await SubtitleSettingsStorage.setDefaultSubtitleLanguage(languageCode);
  }

  Future<void> setDefaultAudioLanguage(String? languageCode) async {
    _deps.setState(() => _deps.sub.defaultAudioLanguage = languageCode);
    await SubtitleSettingsStorage.setDefaultAudioLanguage(languageCode);
  }

  Future<void> setSubtitleSizeIndex(int index) async {
    _deps.setState(() => _deps.sub.subtitleSizeIndex = index);
    await SubtitleSettingsService.instance.setSizeIndex(index);
  }

  Future<void> setSubtitleStyleIndex(int index) async {
    _deps.setState(() => _deps.sub.subtitleStyleIndex = index);
    await SubtitleSettingsService.instance.setStyleIndex(index);
  }

  Future<void> setSubtitleColorIndex(int index) async {
    _deps.setState(() => _deps.sub.subtitleColorIndex = index);
    await SubtitleSettingsService.instance.setColorIndex(index);
  }

  Future<void> setSubtitleBgIndex(int index) async {
    _deps.setState(() => _deps.sub.subtitleBgIndex = index);
    await SubtitleSettingsService.instance.setBgIndex(index);
  }

  Future<void> setSubtitleFontIndex(int index) async {
    _deps.setState(() => _deps.sub.subtitleFontIndex = index);
    await SubtitleFontService.instance.setFontIndex(index);
  }

  Future<void> setSubtitleBold(bool value) async {
    _deps.setState(() => _deps.sub.subtitleBold = value);
    await SubtitleSettingsService.instance.setBold(value);
  }
}
