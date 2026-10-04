import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_dropdown_setting.dart';
import 'package:debrify/features/playback_settings/presentation/playback_setting_dropdown.dart';
import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/content_display_match_mode.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackVideoSectionDependencies = ({
  BuildContext Function() context,
  Widget Function(String title, String subtitle, List<Widget> children)
  defaultsCard,
  PlaybackRowsState rows,
  Future<void> Function(String storageKey) setAndroidVideoRendererMode,
  Future<void> Function(String storageKey) setContentDisplayMatchMode,
  Future<void> Function(int index) setDefaultAspectIndex,
  Future<void> Function(String value) setIptvDecoderMode,
  Future<void> Function(bool enabled) setTvosForceSoftwareDecode,
  PlaybackValuesState values,
});

class PlaybackVideoSection {
  final PlaybackVideoSectionDependencies _deps;
  PlaybackVideoSection(this._deps);

  // Aspect labels
  List<String> get aspectLabels => _deps.values.isAndroidTv
      ? ['Fit', 'Fill', 'Zoom', 'Cinema Zoom']
      : [
          'Contain',
          'Cover',
          'Fit Width',
          'Fit Height',
          '16:9',
          '4:3',
          '21:9',
          '1:1',
          '3:2',
          '5:4',
          'Cinema Zoom',
        ];

  List<Widget> videoSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      _deps.defaultsCard(
        'Picture & decoding',
        'Default picture fit and device compatibility',
        [
          // Default Aspect
          buildSettingDropdown(
            _deps.context(),
            label: 'Default Aspect',
            value: _deps.values.defaultAspectIndex,
            items: aspectLabels,
            onChanged: (index) => _deps.setDefaultAspectIndex(index),
            focusNode: _deps.rows.aspectFocusNode,
            isFocused: _deps.rows.aspectFocused,
          ),
          const SizedBox(height: 12),

          if (_deps.values.isAndroidTv || PlatformUtil.isTvOS) ...[
            buildDropdownSetting(
              _deps.context(),
              label: 'Match content display',
              value: _deps.values.contentDisplayMatchMode.storageKey,
              items: {
                for (final mode in ContentDisplayMatchMode.values)
                  mode.storageKey: mode.label,
              },
              onChanged: _deps.setContentDisplayMatchMode,
              focusNode: _deps.rows.contentDisplayMatchFocusNode,
              isFocused: _deps.rows.contentDisplayMatchFocused,
            ),
            const SizedBox(height: 6),
            Text(
              switch (_deps.values.contentDisplayMatchMode) {
                ContentDisplayMatchMode.systemDefault =>
                  'Keeps the player’s existing platform behavior. Choose a matching mode to request content-specific output.',
                ContentDisplayMatchMode.off =>
                  'Disables player-requested display matching. Restart playback to apply.',
                ContentDisplayMatchMode.frameRate =>
                  PlatformUtil.isTvOS
                      ? 'Requests the source frame rate from Apple TV. Apple TV Settings → Video and Audio → Match Content → Match Frame Rate must be enabled.'
                      : 'Keeps the current output resolution and selects a compatible refresh rate. A brief black screen during a mode switch is normal.',
                ContentDisplayMatchMode.frameRateAndResolution =>
                  PlatformUtil.isTvOS
                      ? 'Sends Apple TV the source frame rate, dimensions, and video format. tvOS chooses the output mode and may keep its configured resolution; resolution matching is best-effort. Match Content must be enabled in Apple TV settings.'
                      : 'Selects the closest output resolution and compatible refresh rate. A brief black screen during a mode switch is normal.',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    _deps.values.contentDisplayMatchMode ==
                        ContentDisplayMatchMode.systemDefault
                    ? t.dim
                    : t.warning,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Android TV only. A frozen picture with running
          // audio on live IPTV is almost always the box's
          // hardware decoder choking on the stream — a device
          // defect, which is why every IPTV player ships this
          // switch rather than trying to auto-detect it.
          if (Platform.isAndroid && _deps.values.isAndroidTv) ...[
            const SizedBox(height: 12),
            buildDropdownSetting(
              _deps.context(),
              label: 'IPTV decoder',
              value: _deps.values.iptvDecoderMode,
              items: const {
                'auto': 'Automatic',
                'hardware': 'Hardware',
                'software': 'Software',
              },
              onChanged: _deps.setIptvDecoderMode,
              focusNode: _deps.rows.iptvDecoderFocusNode,
              isFocused: _deps.rows.iptvDecoderFocused,
            ),
            const SizedBox(height: 6),
            Text(
              _deps.values.iptvDecoderMode == 'software'
                  ? 'Software decoding fixes channels that freeze '
                        'while audio keeps playing, at the cost of '
                        'more CPU. Re-open the channel to apply.'
                  : 'Switch to Software if a channel freezes but '
                        'audio keeps playing. Re-open the channel '
                        'to apply.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: _deps.values.iptvDecoderMode == 'auto'
                    ? t.dim
                    : t.warning,
              ),
            ),
          ],

          // Android phone/tablet only. Android TV already uses
          // native Media3 + SurfaceView; Apple and desktop
          // platforms have different decoder APIs entirely.
          if (Platform.isAndroid && !_deps.values.isAndroidTv) ...[
            const SizedBox(height: 12),
            buildDropdownSetting(
              _deps.context(),
              label: 'Video renderer',
              value: _deps.values.androidVideoRendererMode.storageKey,
              items: {
                for (final mode in AndroidVideoRendererMode.values)
                  mode.storageKey: mode.label,
              },
              onChanged: _deps.setAndroidVideoRendererMode,
              focusNode: _deps.rows.androidVideoRendererFocusNode,
              isFocused: _deps.rows.androidVideoRendererFocused,
            ),
            const SizedBox(height: 6),
            Text(
              '${_deps.values.androidVideoRendererMode.description} '
              'Restart playback to apply. Use Automatic if a '
              'video is black, has incorrect colors, or loses '
              'a feature.',
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    _deps.values.androidVideoRendererMode ==
                        AndroidVideoRendererMode.automatic
                    ? t.dim
                    : t.warning,
              ),
            ),
          ],

          // Apple TV only. The automatic 10-bit remedy
          // (PLAYER_TVOS_10BIT_PLAN.md) handles what it can
          // detect; this forces software decoding for
          // anything it cannot — wrong colors on a
          // clean-reading format, most likely.
          if (PlatformUtil.isTvOS) ...[
            const SizedBox(height: 4),
            buildCheckboxTile(
              _deps.context(),
              title: 'Force software video decoding',
              subtitle:
                  'Compatibility option if a video plays with '
                  'wrong colors or a blank picture. Slower — '
                  '4K may stutter. Applies from the next '
                  'playback.',
              value: _deps.values.tvosForceSoftwareDecode,
              onChanged: _deps.setTvosForceSoftwareDecode,
              focusNode: _deps.rows.tvosForceSwDecodeFocusNode,
              isFocused: _deps.rows.tvosForceSwDecodeFocused,
            ),
          ],
        ],
      ),
    ];
  }
}
