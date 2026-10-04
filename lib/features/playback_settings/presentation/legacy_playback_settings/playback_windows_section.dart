import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

typedef PlaybackWindowsSectionDependencies = ({
  Widget Function(WindowsExternalPlayer player) buildWindowsPlayerTile,
  Future<void> Function() clearWindowsCustomCommand,
  BuildContext Function() context,
  PlaybackCoreState core,
  Future<void> Function() saveWindowsCustomCommand,
  void Function(VoidCallback) setState,
  PlaybackWindowsState win,
});

class PlaybackWindowsSection {
  final PlaybackWindowsSectionDependencies _deps;
  PlaybackWindowsSection(this._deps);
  List<Widget> windowsSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // Windows-specific player selection
      if (Platform.isWindows && _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Preferred Player',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Select the player to open videos with. Players marked as "Installed" were detected on your system.',
                  style: theme.textTheme.bodySmall?.copyWith(color: t.dim),
                ),
              ),
              const SizedBox(height: 8),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.systemDefault),
              const Divider(height: 1),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.vlc),
              const Divider(height: 1),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.mpv),
              const Divider(height: 1),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.mpcHc),
              const Divider(height: 1),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.potPlayer),
              const Divider(height: 1),
              _deps.buildWindowsPlayerTile(WindowsExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Windows Custom Command configuration
      if (Platform.isWindows &&
          _deps.core.defaultPlayerMode == 'external' &&
          _deps.win.selectedWindowsPlayer ==
              WindowsExternalPlayer.customCommand) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.terminal_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom Command',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Define a custom command to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: _deps.win.windowsCommandFocused
                        ? [
                            BoxShadow(
                              color: t.accent.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : null,
                  ),
                  child: TvTextField(
                    controller: _deps.win.windowsCommandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _deps.win.windowsCommandFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Command Template',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _deps.win.windowsCommandError,
                      prefixIcon: const Icon(Icons.code_rounded),
                    ),
                    onChanged: (_) {
                      if (_deps.win.windowsCommandError != null) {
                        _deps.setState(() {
                          _deps.win.windowsCommandError = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _deps.saveWindowsCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_deps.win.windowsCustomCommand != null &&
                        _deps.win.windowsCustomCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _deps.clearWindowsCustomCommand,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: t.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Examples',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'vlc --fullscreen {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'mpv --title="{title}" {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"C:\\Program Files\\MPC-HC\\mpc-hc64.exe" {url} /play',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],

      // Windows external player info
      if (Platform.isWindows && _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected player. For MPC-HC and PotPlayer, the app checks common installation paths. Use Custom Command if the player is installed elsewhere.',
        ),
      ],
    ];
  }
}
