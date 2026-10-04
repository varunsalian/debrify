import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

typedef PlaybackLinuxSectionDependencies = ({
  Widget Function(LinuxExternalPlayer player) buildLinuxPlayerTile,
  Future<void> Function() clearLinuxCustomCommand,
  BuildContext Function() context,
  PlaybackCoreState core,
  PlaybackLinuxState linux,
  Future<void> Function() saveLinuxCustomCommand,
  void Function(VoidCallback) setState,
});

class PlaybackLinuxSection {
  final PlaybackLinuxSectionDependencies _deps;
  PlaybackLinuxSection(this._deps);
  List<Widget> linuxSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // Linux-specific player selection
      if (Platform.isLinux && _deps.core.defaultPlayerMode == 'external') ...[
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
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.systemDefault),
              const Divider(height: 1),
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.vlc),
              const Divider(height: 1),
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.mpv),
              const Divider(height: 1),
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.celluloid),
              const Divider(height: 1),
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.smplayer),
              const Divider(height: 1),
              _deps.buildLinuxPlayerTile(LinuxExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Linux Custom Command configuration
      if (Platform.isLinux &&
          _deps.core.defaultPlayerMode == 'external' &&
          _deps.linux.selectedLinuxPlayer ==
              LinuxExternalPlayer.customCommand) ...[
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
                    boxShadow: _deps.linux.linuxCommandFocused
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
                    controller: _deps.linux.linuxCommandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _deps.linux.linuxCommandFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Command Template',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _deps.linux.linuxCommandError,
                      prefixIcon: const Icon(Icons.code_rounded),
                    ),
                    onChanged: (_) {
                      if (_deps.linux.linuxCommandError != null) {
                        _deps.setState(() {
                          _deps.linux.linuxCommandError = null;
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
                        onPressed: _deps.saveLinuxCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save'),
                      ),
                    ),
                    if (_deps.linux.linuxCustomCommand != null &&
                        _deps.linux.linuxCustomCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _deps.clearLinuxCustomCommand,
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
                        'celluloid {url}',
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

      // Linux external player info
      if (Platform.isLinux && _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Videos will open in the selected player via command line. Make sure the player is installed on your system.',
        ),
      ],
    ];
  }
}
