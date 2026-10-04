import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_windows_state.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';

typedef PlaybackWindowsActionsDependencies = ({
  BuildContext Function() context,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PlaybackWindowsState win,
});

class PlaybackWindowsActions {
  final PlaybackWindowsActionsDependencies _deps;
  PlaybackWindowsActions(this._deps);

  // Windows external player settings methods
  Future<void> selectWindowsPlayer(WindowsExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
        player.storageKey,
      );
      _deps.setState(() {
        _deps.win.selectedWindowsPlayer = player;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> saveWindowsCustomCommand() async {
    final command = _deps.win.windowsCommandController.text.trim();

    final validation = validateWindowsCustomCommand(command);
    if (!validation.isValid) {
      _deps.setState(() {
        _deps.win.windowsCommandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setWindowsCustomCommand(command);
      await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
        'custom_command',
      );

      _deps.setState(() {
        _deps.win.windowsCustomCommand = command;
        _deps.win.windowsCommandError = null;
        _deps.win.selectedWindowsPlayer = WindowsExternalPlayer.customCommand;
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

  Future<void> clearWindowsCustomCommand() async {
    try {
      await ExternalPlayerStorage.setWindowsCustomCommand(null);

      if (_deps.win.selectedWindowsPlayer ==
          WindowsExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredWindowsExternalPlayer(
          'system_default',
        );
        _deps.setState(() {
          _deps.win.selectedWindowsPlayer = WindowsExternalPlayer.systemDefault;
        });
      }

      _deps.win.windowsCommandController.clear();
      _deps.setState(() {
        _deps.win.windowsCustomCommand = null;
        _deps.win.windowsCommandError = null;
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
