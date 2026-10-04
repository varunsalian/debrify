import 'package:debrify/services/external_player_service.dart';
import 'package:flutter/material.dart';

class PlaybackLinuxState {
  // Linux external player settings
  LinuxExternalPlayer selectedLinuxPlayer = LinuxExternalPlayer.systemDefault;

  Map<LinuxExternalPlayer, bool> installedLinuxPlayers = {};

  String? linuxCustomCommand;

  final TextEditingController linuxCommandController = TextEditingController();

  final FocusNode linuxCommandFocusNode = FocusNode();

  bool linuxCommandFocused = false;

  String? linuxCommandError;
}
