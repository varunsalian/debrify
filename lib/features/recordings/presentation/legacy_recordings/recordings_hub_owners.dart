import 'dart:async';

import 'package:debrify/features/recording_output/models/share_recording.dart';
import 'package:debrify/services/live_recording_service.dart';
import 'package:flutter/material.dart';

class RecordingsHubOwners {
  List<LiveRecordingStatus> live = const [];

  List<ScheduledRecording> schedules = const [];

  List<RecordingLibraryEntry> library = const [];

  bool loading = true;

  /// The network share and its recordings; null when none is set up.
  ShareLibrary? share;

  /// False until the first share listing answered (it can take a while).
  bool shareLoaded = false;

  /// Bumped per listing so an older, slower answer cannot overwrite a newer.
  int shareGeneration = 0;

  bool exactAlarms = true;

  /// Wall clock for elapsed/countdown text. Only ticks while something needs
  /// it; listeners are scoped ValueListenableBuilders around the text alone.
  final ValueNotifier<DateTime> now = ValueNotifier<DateTime>(DateTime.now());

  Timer? ticker;

  /// Android: live captures mutate natively (bytes grow, alarms fire, the
  /// engine finalizes) with no in-process signal — poll while anything is
  /// live or could go live, idle otherwise.
  Timer? poll;

  /// False while the app is paused/hidden. _syncTimers refuses to arm
  /// anything in that state — otherwise a revision bump arriving while
  /// covered (a desktop capture ending with the window minimized) would
  /// silently re-start the clocks the lifecycle handler just stopped.
  bool appVisible = true;

  /// Battery-optimization nudge: shown only on EVIDENCE — an interrupted
  /// recording newer than the last dismissal, while the app is not excluded
  /// from optimization. TV boxes have no battery; the nudge never shows
  /// there.
  bool batteryExempt = true;

  int batteryNudgeDismissedAtMs = 0;

  /// The first library row's main (play) focus. The folder button sits on
  /// the same right edge as the rows' delete icons, so geometric DOWN from
  /// it would land on the first DELETE — this node lets the button send
  /// DOWN to the card instead.
  final FocusNode firstLibraryFocus = FocusNode(
    debugLabel: 'recordings_first_library_row',
  );
}
