import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/settings/playback_settings_section.dart';
import 'package:debrify/screens/settings/settings_search.dart';
import 'package:debrify/utils/deovr_utils.dart' as deovr;
import 'package:debrify/utils/platform_util.dart';
import 'settings_leaf_builder.dart';

extension SettingsLeafSlice07 on SettingsLeafBuilder {
  List<SettingsSearchEntry> leafSlice7() {
    return [
      if (deps.isAndroid())
        leaf(
          'Playback',
          'Allow system audio effects',
          'Let equalizer apps process audio (Android)',
          const ['audio effects', 'equalizer', 'wavelet', 'dolby'],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (deps.isAndroid())
        leaf(
          'Playback',
          'Audio passthrough (AC3 · EAC3 · DTS core)',
          'Bitstream audio to your receiver instead of decoding',
          const [
            'passthrough',
            'bitstream',
            'dts',
            'ac3',
            'dolby',
            'receiver',
            'avr',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS || PlatformUtil.isIosMobile)
        leaf(
          'Playback',
          'Multichannel audio (LPCM over HDMI)',
          'Surround tracks as 5.1/7.1 PCM on capable receivers',
          const [
            'multichannel',
            'surround',
            '5.1',
            '7.1',
            'lpcm',
            'audio channels',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Force software video decoding',
          'Apple TV compatibility option for videos that render wrong',
          const [
            'software decoding',
            'compatibility',
            'blue screen',
            'wrong colors',
            'hardware decoding',
            '10-bit',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Force stereo audio',
          'Always downmix Apple TV playback to two channels',
          const [
            'stereo',
            'downmix',
            '2 channels',
            'surround',
            'noisy',
            'distorted',
            'receiver',
            'tvos',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.isTvOS)
        leaf(
          'Playback',
          'Use the previous audio engine',
          'Apple TV audio compatibility option',
          const [
            'legacy audio',
            'old audio engine',
            'audio output',
            'compatibility',
            'atmos',
            'no sound',
            'tvos',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (deps.isAndroid() && PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'IPTV decoder',
          'Switch to software decoding when a channel freezes',
          const [
            'iptv',
            'decoder',
            'software',
            'hardware',
            'freeze',
            'frozen',
            'audio only',
            'no picture',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (deps.isAndroid() && !PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Video renderer',
          'Choose the Android phone/tablet video output path',
          [
            'renderer',
            'mediacodec',
            'direct surface',
            'battery',
            'performance',
            'hardware decoding',
            ...optionLabels(
              AndroidVideoRendererMode.values.map((mode) => mode.label),
            ),
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.video),
        ),
      if (deps.isAndroid() && PlatformUtil.isAndroidTvCached)
        leaf(
          'Playback',
          'Night Mode',
          'Boost quiet sounds for late-night viewing',
          const [
            'night',
            'quiet',
            'volume',
            'dynamic range compression',
            'sleeping baby',
            'low',
            'medium',
            'high',
            'higher',
            'extreme',
            'max',
            'off',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.audio),
        ),
      if (PlatformUtil.supportsSubtitleAutoSync)
        leaf(
          'Playback',
          'Auto-sync addon subtitles',
          'Align downloaded subtitles to the audio automatically',
          const [
            'subtitle',
            'sync',
            'auto',
            'align',
            'timing',
            'offset',
            'experimental',
          ],
          onTap: () =>
              deps.openPlaybackSection(PlaybackSettingsSection.subtitles),
        ),
      if (deps.isPhone())
        leaf(
          'Playback',
          'Open the player in portrait',
          'Start videos upright instead of turning the phone landscape',
          const [
            'portrait',
            'landscape',
            'orientation',
            'rotate',
            'rotation',
            'vertical',
            'horizontal',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      if (deps.preferredExternalPlayerSupported())
        leaf(
          'Playback',
          'Preferred external player',
          'Choose the external player app',
          [
            'external',
            'player app',
            'system default',
            'custom command',
            'custom url scheme',
            ...externalPlayerLabels(),
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      if (deps.customPlayerCommandSupported())
        leaf(
          'Playback',
          'Custom player command',
          'Custom launch command or URL scheme for an external player',
          const [
            'custom command',
            'url scheme',
            'launch',
            'arguments',
            'external',
            'save command',
            'command template',
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
        ),
      leaf(
        'Playback',
        'Import Custom Font',
        'Add your own TTF/OTF font for subtitles',
        const [
          'font',
          'ttf',
          'otf',
          'import font',
          'custom font',
          'remove font',
          'delete font',
          'subtitle',
        ],
        onTap: () =>
            deps.openPlaybackSection(PlaybackSettingsSection.subtitles),
      ),
      // Android only: the page disables the DeoVR mode off Android and builds
      // its format controls under `Platform.isAndroid`.
      if (deps.isAndroid())
        leaf(
          'Playback',
          'VR / DeoVR format',
          'Screen type, stereo mode and format detection for DeoVR',
          [
            'vr',
            'deovr',
            'stereo',
            'screen type',
            '180',
            '360',
            'sbs',
            'side by side',
            'over under',
            'format',
            'auto-detect format from filename',
            'show format selection dialog',
            ...optionLabels(deovr.screenTypeLabels.values),
            ...optionLabels(deovr.stereoModeLabels.values),
          ],
          onTap: () => deps.openPlaybackSection(PlaybackSettingsSection.player),
        ),
    ];
  }
}
