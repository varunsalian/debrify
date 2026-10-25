import 'dart:async';
import 'dart:math' as math;

import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:flutter/widgets.dart';

abstract interface class VpTransitionOverlayHost {
  Timer? get bufferingDebounceTimer;
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  ValueNotifier<bool> get showBufferingIndicator;
  set transitionPhase(int v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set tvStaticMessage(String v);
  set tvStaticSubtext(String v);
  bool get mounted;
  void setState(VoidCallback fn);
}

class VpTransitionOverlay {
  VpTransitionOverlay(this._host);
  final VpTransitionOverlayHost _host;
  final List<String> tvStaticMessages = [
    '📺 BUFFERING... JUST KIDDING',
    '📺 RETICULATING SPLINES...',
    '📺 SUMMONING VIDEO GODS...',
    '📺 ENGAGING HYPERDRIVE...',
    '📺 CALIBRATING FLUX CAPACITOR',
    '📺 CONSULTING THE ALGORITHMS',
    '📺 WARMING UP THE PIXELS',
    '📺 BRIBING THE SERVERS...',
  ];

  void startTransitionOverlay() {
    if (!_host.mounted) return;
    _host.rainbowActive = true;
    _host.transitionRunning = true;
    _host.transitionStopTimer?.cancel();
    _host.transitionPhaseTimer?.cancel();
    _host.transitionPhase = 1;
    // Pick a random retro TV message and reset subtext
    _host.tvStaticMessage =
        tvStaticMessages[math.Random().nextInt(tvStaticMessages.length)];
    _host.tvStaticSubtext = ''; // Clear subtext until video is ready
    debugPrint('Player: Transition overlay started.');
    // Match Android TV: update every 50ms for smooth static effect
    _host.rainbowController.repeat(
      period: VideoPlayerTimingConstants.rainbowRepeatPeriod,
    );
    if (_host.mounted) _host.setState(() {});
  }

  void clearBufferingIndicator() {
    _host.bufferingDebounceTimer?.cancel();
    _host.showBufferingIndicator.value = false;
  }
}
