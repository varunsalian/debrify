import 'package:flutter/material.dart';

class PlaybackVrState {
  // DeoVR settings (Android)
  String vrDefaultScreenType = 'dome';

  String vrDefaultStereoMode = 'sbs';

  bool vrAutoDetectFormat = true;

  bool vrShowDialog = true;

  // DeoVR FocusNodes for DPAD navigation
  final FocusNode screenTypeFocusNode = FocusNode();

  final FocusNode stereoModeFocusNode = FocusNode();

  final FocusNode autoDetectFocusNode = FocusNode();

  final FocusNode showDialogFocusNode = FocusNode();

  bool screenTypeFocused = false;

  bool stereoModeFocused = false;

  bool autoDetectFocused = false;

  bool showDialogFocused = false;
}
