import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_linux_state.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';

typedef PlaybackLinuxActionsDependencies = ({
  BuildContext Function() context,
  PlaybackLinuxState linux,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class PlaybackLinuxActions {
  final PlaybackLinuxActionsDependencies _deps;
  PlaybackLinuxActions(this._deps);

  // Linux external player settings methods
  Future<void> selectLinuxPlayer(LinuxExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
        player.storageKey,
      );
      _deps.setState(() {
        _deps.linux.selectedLinuxPlayer = player;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> saveLinuxCustomCommand() async {
    final command = _deps.linux.linuxCommandController.text.trim();

    final validation = validateLinuxCustomCommand(command);
    if (!validation.isValid) {
      _deps.setState(() {
        _deps.linux.linuxCommandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setLinuxCustomCommand(command);
      await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
        'custom_command',
      );

      _deps.setState(() {
        _deps.linux.linuxCustomCommand = command;
        _deps.linux.linuxCommandError = null;
        _deps.linux.selectedLinuxPlayer = LinuxExternalPlayer.customCommand;
      });

      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(const SnackBar(content: Text('Custom command saved')));
      }
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save command: $e')));
      }
    }
  }

  Future<void> clearLinuxCustomCommand() async {
    try {
      await ExternalPlayerStorage.setLinuxCustomCommand(null);

      if (_deps.linux.selectedLinuxPlayer ==
          LinuxExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredLinuxExternalPlayer(
          'system_default',
        );
        _deps.setState(() {
          _deps.linux.selectedLinuxPlayer = LinuxExternalPlayer.systemDefault;
        });
      }

      _deps.linux.linuxCommandController.clear();
      _deps.setState(() {
        _deps.linux.linuxCustomCommand = null;
        _deps.linux.linuxCommandError = null;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to clear command: $e')));
      }
    }
  }
}
