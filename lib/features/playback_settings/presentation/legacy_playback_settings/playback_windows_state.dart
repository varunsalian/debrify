import 'package:debrify/services/external_player_service.dart';
import 'package:flutter/material.dart';

class PlaybackWindowsState {
  // Windows external player settings
  WindowsExternalPlayer selectedWindowsPlayer =
      WindowsExternalPlayer.systemDefault;

  Map<WindowsExternalPlayer, bool> installedWindowsPlayers = {};

  String? windowsCustomCommand;

  final TextEditingController windowsCommandController =
      TextEditingController();

  final FocusNode windowsCommandFocusNode = FocusNode();

  bool windowsCommandFocused = false;

  String? windowsCommandError;
}
