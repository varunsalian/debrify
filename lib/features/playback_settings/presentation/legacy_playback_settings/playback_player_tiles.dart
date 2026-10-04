import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_ios_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/theme/app_theme_scope.dart';
import 'package:flutter/material.dart';

typedef PlaybackPlayerTilesDependencies = ({
  BuildContext Function() context,
  PlaybackIosState ios,
  PlaybackLinuxState linux,
  PlaybackMacState mac,
  Future<void> Function(iOSExternalPlayer player) selectIOSPlayer,
  Future<void> Function(LinuxExternalPlayer player) selectLinuxPlayer,
  Future<void> Function(ExternalPlayer player) selectPlayer,
  Future<void> Function(WindowsExternalPlayer player) selectWindowsPlayer,
  PlaybackWindowsState win,
});

class PlaybackPlayerTiles {
  final PlaybackPlayerTilesDependencies _deps;
  PlaybackPlayerTiles(this._deps);

  Widget buildPlayerTile(ExternalPlayer player) {
    final app = AppThemeScope.of(_deps.context());
    final t = app.settings;
    final isInstalled = _deps.mac.installedPlayers[player] ?? false;
    final isCustomApp = player == ExternalPlayer.customApp;
    final isCustomCommand = player == ExternalPlayer.customCommand;
    final isSystemDefault = player == ExternalPlayer.systemDefault;

    bool canSelect;
    if (isSystemDefault) {
      canSelect = true;
    } else if (isCustomApp) {
      canSelect = _deps.mac.customAppPath != null;
    } else if (isCustomCommand) {
      canSelect =
          _deps.mac.customCommand != null &&
          _deps.mac.customCommand!.isNotEmpty;
    } else {
      canSelect = isInstalled;
    }

    String subtitle;
    Color? subtitleColor;

    if (isSystemDefault) {
      subtitle = 'Uses system default video player';
    } else if (isCustomApp) {
      if (_deps.mac.customAppPath != null) {
        subtitle = _deps.mac.customAppName ?? _deps.mac.customAppPath!;
      } else {
        subtitle = 'No application selected';
        subtitleColor = t.dim;
      }
    } else if (isCustomCommand) {
      if (_deps.mac.customCommand != null &&
          _deps.mac.customCommand!.isNotEmpty) {
        final displayCmd = _deps.mac.customCommand!.length > 40
            ? '${_deps.mac.customCommand!.substring(0, 40)}...'
            : _deps.mac.customCommand!;
        subtitle = displayCmd;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else if (isInstalled) {
      subtitle = 'Installed';
      subtitleColor = t.success;
    } else {
      subtitle = 'Not found';
      subtitleColor = t.danger;
    }

    return RadioListTile<ExternalPlayer>(
      value: player,
      groupValue: canSelect ? _deps.mac.selectedPlayer : null,
      onChanged: canSelect
          ? (value) {
              if (value != null) {
                _deps.selectPlayer(value);
              }
            }
          : null,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: canSelect ? t.accent : t.dim2),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: canSelect ? app.core.tx : t.dim2,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget buildIOSPlayerTile(iOSExternalPlayer player) {
    final app = AppThemeScope.of(_deps.context());
    final t = app.settings;
    final isInstalled = _deps.ios.installedIOSPlayers[player] ?? false;
    final isCustom = player == iOSExternalPlayer.customScheme;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_deps.ios.iosCustomScheme != null &&
          _deps.ios.iosCustomScheme!.isNotEmpty) {
        final displayScheme = _deps.ios.iosCustomScheme!.length > 40
            ? '${_deps.ios.iosCustomScheme!.substring(0, 40)}...'
            : _deps.ios.iosCustomScheme!;
        subtitle = displayScheme;
      } else {
        subtitle = 'No URL scheme configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Likely installed • ${player.description}';
      }
    }

    return RadioListTile<iOSExternalPlayer>(
      value: player,
      groupValue: _deps.ios.selectedIOSPlayer,
      onChanged: (value) {
        if (value != null) {
          _deps.selectIOSPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget buildLinuxPlayerTile(LinuxExternalPlayer player) {
    final app = AppThemeScope.of(_deps.context());
    final t = app.settings;
    final isInstalled = _deps.linux.installedLinuxPlayers[player] ?? false;
    final isCustom = player == LinuxExternalPlayer.customCommand;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_deps.linux.linuxCustomCommand != null &&
          _deps.linux.linuxCustomCommand!.isNotEmpty) {
        final displayCommand = _deps.linux.linuxCustomCommand!.length > 40
            ? '${_deps.linux.linuxCustomCommand!.substring(0, 40)}...'
            : _deps.linux.linuxCustomCommand!;
        subtitle = displayCommand;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Installed • ${player.description}';
      }
    }

    return RadioListTile<LinuxExternalPlayer>(
      value: player,
      groupValue: _deps.linux.selectedLinuxPlayer,
      onChanged: (value) {
        if (value != null) {
          _deps.selectLinuxPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget buildWindowsPlayerTile(WindowsExternalPlayer player) {
    final app = AppThemeScope.of(_deps.context());
    final t = app.settings;
    final isInstalled = _deps.win.installedWindowsPlayers[player] ?? false;
    final isCustom = player == WindowsExternalPlayer.customCommand;

    String subtitle;
    Color? subtitleColor;

    if (isCustom) {
      if (_deps.win.windowsCustomCommand != null &&
          _deps.win.windowsCustomCommand!.isNotEmpty) {
        final displayCommand = _deps.win.windowsCustomCommand!.length > 40
            ? '${_deps.win.windowsCustomCommand!.substring(0, 40)}...'
            : _deps.win.windowsCustomCommand!;
        subtitle = displayCommand;
      } else {
        subtitle = 'No command configured';
        subtitleColor = t.dim;
      }
    } else {
      subtitle = player.description;
      if (isInstalled) {
        subtitleColor = t.success;
        subtitle = 'Installed • ${player.description}';
      }
    }

    return RadioListTile<WindowsExternalPlayer>(
      value: player,
      groupValue: _deps.win.selectedWindowsPlayer,
      onChanged: (value) {
        if (value != null) {
          _deps.selectWindowsPlayer(value);
        }
      },
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.14),
          borderRadius: app.shape.br(10),
        ),
        child: Icon(player.icon, color: t.accent),
      ),
      title: Text(
        player.displayName,
        style: TextStyle(fontWeight: FontWeight.w500, color: app.core.tx),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: subtitleColor ?? t.dim),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
