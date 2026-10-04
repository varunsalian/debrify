import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_subtitle_rows_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_values_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_dropdown_setting.dart';
import 'package:debrify/features/playback_settings/presentation/playback_setting_dropdown.dart';
import 'package:debrify/screens/video_player/services/network_tuning.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

typedef PlaybackPlayerSectionDependencies = ({
  Widget Function(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    bool recommended,
    bool disabled,
    FocusNode? focusNode,
  })
  buildPlayerModeOption,
  int Function(int value) completionThresholdIndex,
  List<int> Function() completionThresholdOptions,
  BuildContext Function() context,
  PlaybackCoreState core,
  Widget Function(String title, String subtitle, List<Widget> children)
  defaultsCard,
  List<Widget> Function() externalPlayerSettings,
  Widget Function() playerAppearance,
  PlaybackRowsState rows,
  Future<void> Function(int index) setEpisodeCompletionThresholdIndex,
  Future<void> Function(int index) setMovieCompletionThresholdIndex,
  Future<void> Function(String value) setNetBuffer,
  Future<void> Function(String value) setNetPatience,
  Future<void> Function(String provider) setSkipSegmentProvider,
  Future<void> Function(bool enabled) setSkipSegmentsEnabled,
  Future<void> Function(bool enabled) setStartPortrait,
  PlaybackSubtitleRowsState subRows,
  PlaybackValuesState values,
});

class PlaybackPlayerSection {
  final PlaybackPlayerSectionDependencies _deps;
  PlaybackPlayerSection(this._deps);

  List<Widget> playerSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Default Player',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose which player to use when playing videos',
                style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
              ),
              const SizedBox(height: 16),
              _deps.buildPlayerModeOption(
                _deps.context(),
                value: 'debrify',
                title: 'Debrify Player',
                subtitle: 'Use the built-in video player',
                icon: Icons.play_circle_filled_rounded,
                recommended: true,
                focusNode: _deps.core.firstModeFocusNode,
              ),
              _deps.buildPlayerModeOption(
                _deps.context(),
                value: 'external',
                title: 'External Player',
                subtitle: Platform.isMacOS
                    ? 'Open videos in your preferred external player'
                    : 'Choose which app to use when opening videos',
                icon: Icons.open_in_new_rounded,
              ),
              _deps.buildPlayerModeOption(
                _deps.context(),
                value: 'deovr',
                title: 'DeoVR',
                subtitle: 'Use this only on VR devices',
                icon: Icons.vrpano,
                disabled: !Platform.isAndroid,
              ),
            ],
          ),
        ),
      ),

      if (_deps.core.defaultPlayerMode == 'debrify') ...[
        const SizedBox(height: 16),
        if (PlatformUtil.isPhone) ...[
          _deps.defaultsCard(
            'When playback starts',
            'Choose the starting orientation',
            [
              // Start orientation (phones only — a TV has no
              // portrait, and a desktop window ignores the
              // preferred-orientation call entirely). Gated on the
              // WARM flag, not this page's `_isAndroidTv`: that one
              // is loaded async and starts false, so a TV would
              // paint the row and then drop it.
              if (PlatformUtil.isPhone) ...[
                const SizedBox(height: 4),
                buildCheckboxTile(
                  _deps.context(),
                  title: 'Open the player in portrait',
                  subtitle:
                      'Start videos upright instead of turning the '
                      'phone landscape. The player\'s rotate button '
                      'switches to landscape whenever you want it.',
                  value: _deps.values.startPortrait,
                  onChanged: _deps.setStartPortrait,
                  focusNode: _deps.rows.startPortraitFocusNode,
                  isFocused: _deps.rows.startPortraitFocused,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
        ],
        // Local completion is deliberately independent from tracker
        // scrobbling: Trakt and Simkl keep their own watched rules.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Watch History',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Mark locally tracked videos watched after this much playback. Trakt and Simkl keep their own rules.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                buildSettingDropdown(
                  _deps.context(),
                  label: 'Mark movies watched at',
                  value: _deps.completionThresholdIndex(
                    _deps.values.movieCompletionThreshold,
                  ),
                  items: _deps
                      .completionThresholdOptions()
                      .map((value) => '$value%')
                      .toList(),
                  onChanged: _deps.setMovieCompletionThresholdIndex,
                  focusNode: _deps.subRows.movieCompletionThresholdFocusNode,
                  isFocused: _deps.subRows.movieCompletionThresholdFocused,
                ),
                const SizedBox(height: 12),
                buildSettingDropdown(
                  _deps.context(),
                  label: 'Mark episodes watched at',
                  value: _deps.completionThresholdIndex(
                    _deps.values.episodeCompletionThreshold,
                  ),
                  items: _deps
                      .completionThresholdOptions()
                      .map((value) => '$value%')
                      .toList(),
                  onChanged: _deps.setEpisodeCompletionThresholdIndex,
                  focusNode: _deps.subRows.episodeCompletionThresholdFocusNode,
                  isFocused: _deps.subRows.episodeCompletionThresholdFocused,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Community intro/outro timestamps. This belongs to the
        // built-in player because external players own their own UI
        // and cannot display Debrify's manual skip button.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Skip Segments',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Show manual skip buttons when community timestamps are available',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 8),
                buildCheckboxTile(
                  _deps.context(),
                  title: 'Skip intros & credits',
                  subtitle:
                      'Show a button during supported intros and outros. Playback is never skipped automatically.',
                  value: _deps.values.skipSegmentsEnabled,
                  onChanged: _deps.setSkipSegmentsEnabled,
                  focusNode: _deps.subRows.skipSegmentsEnabledFocusNode,
                  isFocused: _deps.subRows.skipSegmentsEnabledFocused,
                ),
                const SizedBox(height: 12),
                buildDropdownSetting(
                  _deps.context(),
                  label: 'Timestamp provider',
                  value: _deps.values.skipSegmentProvider,
                  items: SkipSegmentProviders.availableLabels,
                  onChanged: _deps.setSkipSegmentProvider,
                  focusNode: _deps.subRows.skipSegmentProviderFocusNode,
                  isFocused: _deps.subRows.skipSegmentProviderFocused,
                  enabled: _deps.values.skipSegmentsEnabled,
                ),
                const SizedBox(height: 10),
                Text(
                  _deps.values.skipSegmentProvider == SkipSegmentProviders.auto
                      ? 'Checks every available source and prefers SkipDB, then TheIntroDB, then IntroDB.'
                      : 'Coverage varies by series, episode, and video release.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim2),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Network & Buffering: the escape hatch for slow stream
        // origins (Plex-backed addons, remote seedboxes). Standard
        // leaves both players untouched — the Debrify (mpv) player
        // reads the presets directly; the native Android TV player
        // gets them via the launch payload.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Network & Buffering',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For stream sources that stall or time out — '
                  'Plex-backed addons, remote servers. Standard '
                  'leaves playback exactly as before.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                buildDropdownSetting(
                  _deps.context(),
                  label: 'Connection patience',
                  value: _deps.values.netPatience,
                  items: NetworkTuning.patienceOptions,
                  onChanged: _deps.setNetPatience,
                  focusNode: _deps.rows.netPatienceFocusNode,
                  isFocused: _deps.rows.netPatienceFocused,
                ),
                const SizedBox(height: 12),
                buildDropdownSetting(
                  _deps.context(),
                  label: 'Stream buffer',
                  value: _deps.values.netBuffer,
                  items: NetworkTuning.bufferOptions,
                  onChanged: _deps.setNetBuffer,
                  focusNode: _deps.rows.netBufferFocusNode,
                  isFocused: _deps.rows.netBufferFocused,
                ),
                const SizedBox(height: 10),
                Text(
                  'Patience raises connection timeouts and adds '
                  'automatic retries where the player supports '
                  'them. Bigger buffers ride over origin stalls '
                  'but use more memory. Live TV keeps its own '
                  'tuned pipeline. Restart playback to apply.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim2),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _deps.playerAppearance(),
      ],
      ..._deps.externalPlayerSettings(),
    ];
  }
}
