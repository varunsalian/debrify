import 'dart:io';

import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/screens/settings/widgets/settings_widgets.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:debrify/widgets/tv_text_field.dart';
import 'package:flutter/material.dart';

typedef PlaybackMacSectionDependencies = ({
  Future<void> Function() browseForCustomApp,
  Widget Function(ExternalPlayer player) buildPlayerTile,
  Future<void> Function() clearCustomApp,
  Future<void> Function() clearCustomCommand,
  BuildContext Function() context,
  PlaybackCoreState core,
  PlaybackMacState mac,
  Future<void> Function() saveCustomCommand,
  void Function(VoidCallback) setState,
});

class PlaybackMacSection {
  final PlaybackMacSectionDependencies _deps;
  PlaybackMacSection(this._deps);
  List<Widget> macSettings() {
    final theme = Theme.of(_deps.context());
    final t = AppThemeScope.of(_deps.context()).settings;
    return [
      // macOS-specific player selection
      if (Platform.isMacOS && _deps.core.defaultPlayerMode == 'external') ...[
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
              _deps.buildPlayerTile(ExternalPlayer.systemDefault),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.vlc),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.iina),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.mpv),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.quickTime),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.infuse),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.customApp),
              const Divider(height: 1),
              _deps.buildPlayerTile(ExternalPlayer.customCommand),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],

      // Custom App configuration (macOS only, when selected)
      if (Platform.isMacOS &&
          _deps.core.defaultPlayerMode == 'external' &&
          _deps.mac.selectedPlayer == ExternalPlayer.customApp) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: t.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Custom App',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a .app to use as your video player',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                if (_deps.mac.customAppPath != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.panel2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.apps_rounded, color: t.accent),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _deps.mac.customAppName ?? 'Custom App',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                _deps.mac.customAppPath!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: t.dim,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _deps.browseForCustomApp,
                        icon: const Icon(Icons.folder_open_rounded),
                        label: Text(
                          _deps.mac.customAppPath == null ? 'Browse' : 'Change',
                        ),
                      ),
                    ),
                    if (_deps.mac.customAppPath != null) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _deps.clearCustomApp,
                        child: const Text('Clear'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],

      // Custom Command configuration (macOS only, when selected)
      if (Platform.isMacOS &&
          _deps.core.defaultPlayerMode == 'external' &&
          _deps.mac.selectedPlayer == ExternalPlayer.customCommand) ...[
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.code_rounded, color: t.accent),
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
                  'Define a custom shell command to launch videos',
                  style: theme.textTheme.bodyMedium?.copyWith(color: t.dim),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: _deps.mac.commandFocused
                        ? Border.all(color: t.accent, width: 1.8)
                        : null,
                    boxShadow: _deps.mac.commandFocused
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
                    controller: _deps.mac.commandController,
                    // The surrounding Container draws this field's focus ring;
                    // skip the shell's fallback ring so they don't double up.
                    shellRing: false,
                    focusNode: _deps.mac.commandFocusNode,
                    // Directional (non-wrapping): DOWN on the last
                    // row must not jump back to the top of the page.
                    onDownArrow: () => FocusScope.of(
                      _deps.context(),
                    ).focusInDirection(TraversalDirection.down),
                    onUpArrow: () => FocusScope.of(
                      _deps.context(),
                    ).focusInDirection(TraversalDirection.up),
                    decoration: InputDecoration(
                      labelText: 'Command',
                      hintText: 'vlc --fullscreen {url}',
                      helperText: 'Use {url} for video URL, {title} for title',
                      helperMaxLines: 2,
                      errorText: _deps.mac.commandError,
                      prefixIcon: const Icon(Icons.terminal_rounded),
                    ),
                    onChanged: (_) {
                      if (_deps.mac.commandError != null) {
                        _deps.setState(() {
                          _deps.mac.commandError = null;
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
                        onPressed: _deps.saveCustomCommand,
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Command'),
                      ),
                    ),
                    if (_deps.mac.customCommand != null &&
                        _deps.mac.customCommand!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _deps.clearCustomCommand,
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
                        'mpv --fs --title="{title}" {url}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: t.dim,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '/opt/homebrew/bin/mpv {url}',
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

      // macOS external player info
      if (Platform.isMacOS && _deps.core.defaultPlayerMode == 'external') ...[
        const SizedBox(height: 16),
        SettingsInfoBanner(
          text:
              'Players marked as "Not found" are not installed on your system. Install them via the App Store, Homebrew, or their official websites.',
        ),
      ],
    ];
  }
}
