import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';

abstract interface class VpSleepTimerHost {
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  void openPlayerMenuQuick(PlayerMenuSection section);
  Timer? get hideTimer;
  IptvChannel? get currentIptvChannel;
  void scheduleAutoHide();
  set sleepStopLatched(bool v);
  set activeMediaShouldPlay(bool v);
  bool get playerCreated;
  Future<void> saveResume();
  mk.Player get player;
}

class VpSleepTimerController {
  VpSleepTimerController(this._host);
  final VpSleepTimerHost _host;

  // ── Sleep timer ───────────────────────────────────────────────────────────
  // Stops playback after a countdown, or at the end of the current item. The
  // wakelock already follows play state here, so pausing is enough to let the
  // screen sleep — unlike the native players, which pin the screen on.
  SleepTimerMode sleepTimerMode = SleepTimerMode.off;

  /// When the armed countdown fires. The label is derived from this rather
  /// than from the duration picked, so it counts down instead of reading "30
  /// min" right up to the moment it stops.
  DateTime? sleepTimerDeadline;

  /// The preset originally picked, so the sheet can keep it checked while the
  /// remaining time ticks away from it.
  int sleepTimerArmedMinutes = 0;
  Timer? sleepTimer;

  // ── Sleep timer ───────────────────────────────────────────────────────────

  /// Whole minutes left, rounded up so a fresh 30-minute timer reads "30".
  int get sleepTimerMinutesLeft {
    final deadline = sleepTimerDeadline;
    if (sleepTimerMode != SleepTimerMode.countdown || deadline == null) {
      return 0;
    }
    final remaining = deadline.difference(DateTime.now()).inMilliseconds;
    if (remaining <= 0) return 0;
    return (remaining / 60000).ceil();
  }

  /// Short label for the controls button, or null when nothing is armed.
  String? get sleepTimerButtonLabel => switch (sleepTimerMode) {
    SleepTimerMode.off => null,
    SleepTimerMode.endOfItem => 'Episode',
    SleepTimerMode.countdown => '$sleepTimerMinutesLeft min',
  };

  Future<void> showSleepTimerSheet() async {
    if (kUnifiedPlayerMenuEnabled) {
      _host.openPlayerMenuQuick(PlayerMenuSection.sleep);
      return;
    }
    _host.hideTimer?.cancel();
    final picked = await SleepTimerSheet.show(
      _host.context,
      current: sleepTimerMode,
      armedMinutes: sleepTimerArmedMinutes,
      minutesLeft: sleepTimerMinutesLeft,
      // A live channel has no end to stop at, so only the countdown applies —
      // which is the case people actually want a sleep timer for.
      allowEndOfItem: _host.currentIptvChannel?.isLive != true,
    );
    if (!_host.mounted) return;
    _host.scheduleAutoHide();
    if (picked == null) return;
    applySleepTimerSelection(picked);
  }

  void applySleepTimerSelection(SleepTimerSelection picked) {
    switch (picked.mode) {
      case SleepTimerMode.off:
        cancelSleepTimer();
        showSleepTimerToast('Sleep timer off');
      case SleepTimerMode.countdown:
        startSleepCountdown(picked.minutes);
      case SleepTimerMode.endOfItem:
        cancelSleepTimer();
        _host.setState(() => sleepTimerMode = SleepTimerMode.endOfItem);
        showSleepTimerToast('Stopping at the end of this episode');
    }
  }

  void startSleepCountdown(int minutes) {
    cancelSleepTimer();
    final duration = Duration(minutes: minutes);
    _host.setState(() {
      sleepTimerMode = SleepTimerMode.countdown;
      sleepTimerDeadline = DateTime.now().add(duration);
      sleepTimerArmedMinutes = minutes;
    });
    sleepTimer = Timer(duration, fireSleepTimer);
    showSleepTimerToast('Sleep timer set for $minutes minutes');
  }

  void cancelSleepTimer() {
    sleepTimer?.cancel();
    sleepTimer = null;
    if (sleepTimerMode == SleepTimerMode.off) return;
    if (_host.mounted) {
      _host.setState(() {
        sleepTimerMode = SleepTimerMode.off;
        sleepTimerDeadline = null;
        sleepTimerArmedMinutes = 0;
      });
    } else {
      sleepTimerMode = SleepTimerMode.off;
      sleepTimerDeadline = null;
    }
  }

  /// Stop for the night: persist the position first (losing someone's place
  /// overnight is exactly the moment this feature is meant to be helping),
  /// then pause — which releases the wakelock and lets the screen sleep.
  Future<void> fireSleepTimer() async {
    cancelSleepTimer();
    _host.sleepStopLatched = true;
    _host.activeMediaShouldPlay = false;
    if (!_host.playerCreated) return;
    await _host.saveResume();
    await _host.player.pause();
    showSleepTimerToast('Sleep timer ended — paused');
  }

  void showSleepTimerToast(String message) {
    if (!_host.mounted) return;
    ScaffoldMessenger.of(_host.context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}
