import 'package:debrify/services/external_player_service.dart';
import 'package:flutter/material.dart';

class PlaybackMacState {
  // macOS external player settings
  ExternalPlayer selectedPlayer = ExternalPlayer.systemDefault;

  Map<ExternalPlayer, bool> installedPlayers = {};

  String? customAppPath;

  String? customAppName;

  String? customCommand;

  final TextEditingController commandController = TextEditingController();

  final FocusNode commandFocusNode = FocusNode();

  bool commandFocused = false;

  String? commandError;
}
