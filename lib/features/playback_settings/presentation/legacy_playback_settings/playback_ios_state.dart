import 'package:debrify/services/external_player_service.dart';
import 'package:flutter/material.dart';

class PlaybackIosState {
  // iOS external player settings
  iOSExternalPlayer selectedIOSPlayer = iOSExternalPlayer.vlc;

  Map<iOSExternalPlayer, bool> installedIOSPlayers = {};

  String? iosCustomScheme;

  final TextEditingController iosSchemeController = TextEditingController();

  final FocusNode iosSchemeFocusNode = FocusNode();

  bool iosSchemeFocused = false;

  String? iosSchemeError;
}
