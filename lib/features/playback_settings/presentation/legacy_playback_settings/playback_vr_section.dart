import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_vr_state.dart';
import 'package:debrify/features/playback_settings/presentation/playback_checkbox_tile.dart';
import 'package:debrify/features/playback_settings/presentation/playback_dropdown_setting.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/utils/deovr_utils.dart' as deovr;
import 'package:flutter/material.dart';

typedef PlaybackVrSectionDependencies = ({
  BuildContext Function() context,
  PlaybackCoreState core,
  Future<void> Function(bool autoDetect) setVrAutoDetectFormat,
  Future<void> Function(String screenType) setVrDefaultScreenType,
  Future<void> Function(String stereoMode) setVrDefaultStereoMode,
  Future<void> Function(bool showDialog) setVrShowDialog,
  PlaybackVrState vr,
});

class PlaybackVrSection {
  final PlaybackVrSectionDependencies _deps;
  PlaybackVrSection(this._deps);
  List<Widget> vrSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // DeoVR settings (Android only, when selected)
      if (Platform.isAndroid && _deps.core.defaultPlayerMode == 'deovr') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.vrpano, color: t.accent, size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'DeoVR Settings',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // VR Format Settings
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Default VR Format',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used when format cannot be detected from filename',
                      style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                    ),
                    const SizedBox(height: 16),

                    // Screen Type dropdown
                    buildDropdownSetting(
                      _deps.context(),
                      label: 'Screen Type',
                      value: _deps.vr.vrDefaultScreenType,
                      items: deovr.screenTypeLabels,
                      onChanged: _deps.setVrDefaultScreenType,
                      focusNode: _deps.vr.screenTypeFocusNode,
                      isFocused: _deps.vr.screenTypeFocused,
                    ),
                    const SizedBox(height: 12),

                    // Stereo Mode dropdown
                    buildDropdownSetting(
                      _deps.context(),
                      label: 'Stereo Mode',
                      value: _deps.vr.vrDefaultStereoMode,
                      items: deovr.stereoModeLabels,
                      onChanged: _deps.setVrDefaultStereoMode,
                      focusNode: _deps.vr.stereoModeFocusNode,
                      isFocused: _deps.vr.stereoModeFocused,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Checkboxes
              buildCheckboxTile(
                _deps.context(),
                title: 'Auto-detect format from filename',
                subtitle: 'Parse filename for VR markers (180, 360, SBS, etc.)',
                value: _deps.vr.vrAutoDetectFormat,
                onChanged: _deps.setVrAutoDetectFormat,
                focusNode: _deps.vr.autoDetectFocusNode,
                isFocused: _deps.vr.autoDetectFocused,
              ),
              buildCheckboxTile(
                _deps.context(),
                title: 'Show format selection dialog',
                subtitle: 'Confirm VR format before launching DeoVR',
                value: _deps.vr.vrShowDialog,
                onChanged: _deps.setVrShowDialog,
                focusNode: _deps.vr.showDialogFocusNode,
                isFocused: _deps.vr.showDialogFocused,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'DeoVR must be installed on your device. All videos will open in DeoVR with the selected VR format settings.',
        ),
      ],
    ];
  }
}
