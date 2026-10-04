import 'package:debrify/features/playback_settings/presentation/legacy_playback_settings/playback_core_state.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:flutter/material.dart';

typedef PlaybackPlayerModeActionsDependencies = ({
  BuildContext Function() context,
  PlaybackCoreState core,
  bool Function() mounted,
  void Function(VoidCallback) setState,
});

class PlaybackPlayerModeActions {
  final PlaybackPlayerModeActionsDependencies _deps;
  PlaybackPlayerModeActions(this._deps);

  Future<void> setDefaultPlayerMode(String mode) async {
    try {
      await ExternalPlayerStorage.setDefaultPlayerMode(mode);
      _deps.setState(() {
        _deps.core.defaultPlayerMode = mode;
      });
    } catch (e) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(
          _deps.context(),
        ).showSnackBar(SnackBar(content: Text('Failed to save setting: $e')));
      }
    }
  }
}
