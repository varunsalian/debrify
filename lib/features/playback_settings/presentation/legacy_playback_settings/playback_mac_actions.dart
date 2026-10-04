import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_mac_state.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

typedef PlaybackMacActionsDependencies = ({
  BuildContext Function() context,
  PlaybackMacState mac,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class PlaybackMacActions {
  final PlaybackMacActionsDependencies _deps;
  PlaybackMacActions(this._deps);

  Future<void> selectPlayer(ExternalPlayer player) async {
    try {
      await ExternalPlayerStorage.setPreferredExternalPlayer(player.storageKey);
      _deps.setState(() {
        _deps.mac.selectedPlayer = player;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }

  Future<void> browseForCustomApp() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['app'],
        dialogTitle: 'Select Video Player Application',
      );

      if (result != null && result.files.isNotEmpty) {
        final path = result.files.first.path;
        if (path != null) {
          final appName = path.split('/').last.replaceAll('.app', '');

          await ExternalPlayerStorage.setCustomExternalPlayerPath(path);
          await ExternalPlayerStorage.setCustomExternalPlayerName(appName);
          await ExternalPlayerStorage.setPreferredExternalPlayer('custom_app');

          _deps.setState(() {
            _deps.mac.customAppPath = path;
            _deps.mac.customAppName = appName;
            _deps.mac.selectedPlayer = ExternalPlayer.customApp;
          });
        }
      }
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(content: Text('Failed to select application: $e')),
        );
      }
    }
  }

  Future<void> clearCustomApp() async {
    try {
      await ExternalPlayerStorage.setCustomExternalPlayerPath(null);
      await ExternalPlayerStorage.setCustomExternalPlayerName(null);

      if (_deps.mac.selectedPlayer == ExternalPlayer.customApp) {
        await ExternalPlayerStorage.setPreferredExternalPlayer(
          'system_default',
        );
        _deps.setState(() {
          _deps.mac.selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      _deps.setState(() {
        _deps.mac.customAppPath = null;
        _deps.mac.customAppName = null;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(content: Text('Failed to clear custom app: $e')),
        );
      }
    }
  }

  Future<void> saveCustomCommand() async {
    final command = _deps.mac.commandController.text.trim();

    final validation = ExternalPlayerService.validateCustomCommand(command);
    if (!validation.isValid) {
      _deps.setState(() {
        _deps.mac.commandError = validation.errorMessage;
      });
      return;
    }

    try {
      await ExternalPlayerStorage.setCustomExternalPlayerCommand(command);
      await ExternalPlayerStorage.setPreferredExternalPlayer('custom_command');

      _deps.setState(() {
        _deps.mac.customCommand = command;
        _deps.mac.commandError = null;
        _deps.mac.selectedPlayer = ExternalPlayer.customCommand;
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

  Future<void> clearCustomCommand() async {
    try {
      await ExternalPlayerStorage.setCustomExternalPlayerCommand(null);

      if (_deps.mac.selectedPlayer == ExternalPlayer.customCommand) {
        await ExternalPlayerStorage.setPreferredExternalPlayer(
          'system_default',
        );
        _deps.setState(() {
          _deps.mac.selectedPlayer = ExternalPlayer.systemDefault;
        });
      }

      _deps.mac.commandController.clear();
      _deps.setState(() {
        _deps.mac.customCommand = null;
        _deps.mac.commandError = null;
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
