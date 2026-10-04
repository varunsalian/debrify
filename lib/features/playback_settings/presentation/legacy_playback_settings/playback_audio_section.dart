import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_setting_dropdown.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackAudioSectionDependencies = ({
  BuildContext Function() context,
  Widget Function(String title, String subtitle, List<Widget> children)
  defaultsCard,
  List<Widget> Function() nightModeSettings,
  PlaybackRowsState rows,
  Future<void> Function(bool enabled) setAppleMultichannel,
  Future<void> Function(bool enabled) setAudioPassthrough,
  Future<void> Function(String? languageCode) setDefaultAudioLanguage,
  Future<void> Function(bool enabled) setSystemAudioEffects,
  Future<void> Function(bool enabled) setTvosForceStereo,
  Future<void> Function(bool enabled) setTvosLegacyAudioOutput,
  PlaybackSubtitleState sub,
  PlaybackValuesState values,
});

class PlaybackAudioSection {
  final PlaybackAudioSectionDependencies _deps;
  PlaybackAudioSection(this._deps);

  // Audio language options: (code, label) - no "Off" option for audio
  static const List<(String?, String)> audioLanguageOptions = [
    (null, 'No Preference'),
    ('en', 'English'),
    ('es', 'Spanish'),
    ('fr', 'French'),
    ('de', 'German'),
    ('it', 'Italian'),
    ('pt', 'Portuguese'),
    ('ru', 'Russian'),
    ('ja', 'Japanese'),
    ('ko', 'Korean'),
    ('zh', 'Chinese'),
    ('ar', 'Arabic'),
    ('hi', 'Hindi'),
    ('te', 'Telugu'),
    ('nl', 'Dutch'),
    ('pl', 'Polish'),
    ('tr', 'Turkish'),
    ('sv', 'Swedish'),
    ('da', 'Danish'),
    ('no', 'Norwegian'),
    ('fi', 'Finnish'),
  ];

  int get audioLanguageIndex {
    final idx = audioLanguageOptions.indexWhere(
      (opt) => opt.$1 == _deps.sub.defaultAudioLanguage,
    );
    return idx >= 0 ? idx : 0;
  }

  List<Widget> audioSettings() {
    return [
      _deps.defaultsCard(
        'Audio defaults',
        'Language and sound output for the built-in player',
        [
          // Default Audio Language
          buildSettingDropdown(
            _deps.context(),
            label: 'Default Audio',
            value: audioLanguageIndex,
            items: audioLanguageOptions.map((opt) => opt.$2).toList(),
            onChanged: (index) =>
                _deps.setDefaultAudioLanguage(audioLanguageOptions[index].$1),
            focusNode: _deps.rows.defaultAudioLangFocusNode,
            isFocused: _deps.rows.defaultAudioLangFocused,
          ),
          const SizedBox(height: 12),

          // System audio effects (Android only). Off by
          // default because enabling it switches the audio
          // output backend — see _attachAudioEffectSession in
          // the player screen.
          if (Platform.isAndroid) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Allow system audio effects',
              subtitle:
                  'Let equalizer apps (Wavelet, Dolby, etc.) process playback. '
                  'Changes the audio output — restart playback to apply.',
              value: _deps.values.systemAudioEffects,
              onChanged: _deps.setSystemAudioEffects,
              focusNode: _deps.rows.systemAudioEffectsFocusNode,
              isFocused: _deps.rows.systemAudioEffectsFocused,
            ),
            // Bitstream passthrough (AUDIO_FIDELITY_PLAN.md).
            // Opt-in: a route that misreports support plays
            // silence, and only the user knows their chain.
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Audio passthrough (AC3 · EAC3 · DTS core)',
              subtitle:
                  'Send the original bitstream to your receiver '
                  'instead of decoding. Requires an HDMI chain '
                  'that supports it — if you hear silence, turn '
                  'this off. Restart playback to apply.',
              value: _deps.values.audioPassthrough,
              onChanged: _deps.setAudioPassthrough,
              focusNode: _deps.rows.audioPassthroughFocusNode,
              isFocused: _deps.rows.audioPassthroughFocused,
            ),
          ],

          // Apple multichannel LPCM (AUDIO_FIDELITY_PLAN.md).
          // Opt-in until AirPlay/spatial routes are proven.
          if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Multichannel audio (LPCM over HDMI)',
              subtitle:
                  'Output surround tracks as 5.1/7.1 PCM when '
                  'the connected receiver supports it, instead '
                  'of stereo. Restart playback to apply.',
              value: _deps.values.appleMultichannel,
              onChanged: _deps.setAppleMultichannel,
              focusNode: _deps.rows.appleMultichannelFocusNode,
              isFocused: _deps.rows.appleMultichannelFocused,
            ),
          ],

          // Apple TV audio diagnostics. The player normally
          // decides both of these from the output route; these
          // let a reporter narrow an audio problem without
          // waiting on a custom build.
          if (PlatformUtil.isTvOS) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Force stereo audio',
              subtitle:
                  'Always downmix to 2 channels, whatever the '
                  'TV or receiver reports. Try this if '
                  'surround sound is noisy or distorted. '
                  'Restart playback to apply.',
              value: _deps.values.tvosForceStereo,
              onChanged: _deps.setTvosForceStereo,
              focusNode: _deps.rows.tvosForceStereoFocusNode,
              isFocused: _deps.rows.tvosForceStereoFocused,
            ),
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Use the previous audio engine',
              subtitle:
                  'Go back to the audio output used before '
                  'August 2026. It has no sound at all when '
                  'Dolby Atmos is enabled, so only use it if '
                  'the current one misbehaves. Restart '
                  'playback to apply.',
              value: _deps.values.tvosLegacyAudioOutput,
              onChanged: _deps.setTvosLegacyAudioOutput,
              focusNode: _deps.rows.tvosLegacyAudioFocusNode,
              isFocused: _deps.rows.tvosLegacyAudioFocused,
            ),
          ],
        ],
      ),
      ..._deps.nightModeSettings(),
    ];
  }
}
