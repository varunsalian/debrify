import 'package:flutter/material.dart';

class PlaybackCoreState {
  bool loading = true;

  final contentFocusNode = FocusNode(
    debugLabel: 'playback-settings-content',
    canRequestFocus: false,
    skipTraversal: true,
  );

  // Default player mode: 'debrify', 'external', 'deovr'
  String defaultPlayerMode = 'debrify';

  // First interactive row ("Debrify Player" mode option) — receives entry
  // focus on TV so DPAD users are never stranded on nothing.
  final FocusNode firstModeFocusNode = FocusNode();
}
