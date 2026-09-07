import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'constants/timing_constants.dart';

class PlayerTransitionSession {
  PlayerTransitionSession({
    required bool Function() isMounted,
    required void Function(VoidCallback) commit,
  }) : _isMounted = isMounted,
       _commit = commit;

  final bool Function() _isMounted;
  final void Function(VoidCallback) _commit;
  bool _isTransitioning = false; // Show black screen during transitions
  late AnimationController _rainbowController;
  late Animation<double> _rainbowOpacity;
  bool _rainbowActive = false;
  bool _transitionRunning = false;
  Timer? _transitionStopTimer;
  Timer? _transitionPhaseTimer;
  int _transitionPhase = 1; // 1 = static, 2 = reveal
  DateTime? _transitionPhase2Started;

  // Retro TV static loading messages
  String _tvStaticMessage = '📺 TUNING...';
  String _tvStaticSubtext = ''; // Second line for video title
  final List<String> _tvStaticMessages = [
    '📺 BUFFERING... JUST KIDDING',
    '📺 RETICULATING SPLINES...',
    '📺 SUMMONING VIDEO GODS...',
    '📺 ENGAGING HYPERDRIVE...',
    '📺 CALIBRATING FLUX CAPACITOR',
    '📺 CONSULTING THE ALGORITHMS',
    '📺 WARMING UP THE PIXELS',
    '📺 BRIBING THE SERVERS...',
  ];

  bool get blocking => _isTransitioning;
  bool get overlayActive => _rainbowActive;
  String get message => _tvStaticMessage;
  String get subtext => _tvStaticSubtext;
  AnimationController get animationController => _rainbowController;

  void initializeAnimation(TickerProvider vsync) {
    _rainbowController = AnimationController(
      vsync: vsync,
      duration: VideoPlayerTimingConstants.rainbowAnimationDuration,
    );
    _rainbowOpacity = CurvedAnimation(
      parent: _rainbowController,
      curve: Curves.easeInOut,
    );
  }

  void setBlocking(bool value) {
    _isTransitioning = value;
  }

  void startOverlay() {
    if (!_isMounted()) return;
    _rainbowActive = true;
    _transitionRunning = true;
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 1;
    // Pick a random retro TV message and reset subtext
    _tvStaticMessage =
        _tvStaticMessages[math.Random().nextInt(_tvStaticMessages.length)];
    _tvStaticSubtext = ''; // Clear subtext until video is ready
    debugPrint('Player: Transition overlay started.');
    // Match Android TV: update every 50ms for smooth static effect
    _rainbowController.repeat(
      period: VideoPlayerTimingConstants.rainbowRepeatPeriod,
    );
    if (_isMounted()) _commit(() {});
  }

  void onPlaybackStarted(bool Function() isCurrent) {
    if (_transitionRunning) {
      _transitionStopTimer?.cancel();
      _transitionPhaseTimer?.cancel();
      _transitionPhase = 1;
      _transitionPhase2Started = null;
      debugPrint(
        'Player: Playback started; overlay phase 1 (static) 1500ms.',
      );
      _transitionPhaseTimer = Timer(const Duration(milliseconds: 1500), () {
        if (!isCurrent()) return;
        _transitionPhase = 2;
        _transitionPhase2Started = DateTime.now();
        _commit(() {});
        debugPrint('Player: Overlay phase 2 (cinematic bars) 1500ms.');
      });
      _transitionStopTimer = Timer(const Duration(milliseconds: 3000), () {
        if (!isCurrent()) return;
        _rainbowController.stop();
        _transitionRunning = false;
        _rainbowActive = false;
        _commit(() {});
        debugPrint('Player: Transition overlay stopped (3s complete).');
      });
    }
  }

  void finishResolvedOpen() {
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _transitionPhase = 2;
    _transitionPhase2Started = DateTime.now();
    _commit(() {
      _isTransitioning = false;
    });
    _transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _rainbowController.stop();
      _transitionRunning = false;
      _rainbowActive = false;
      if (_isMounted()) _commit(() {});
    });
  }

  void stopVisualsForFailedLoad() {
    _transitionStopTimer?.cancel();
    _transitionPhaseTimer?.cancel();
    _rainbowController.stop();
    _transitionRunning = false;
    _rainbowActive = false;
  }

  void showSignal(String title) {
    _tvStaticMessage = '📺 SIGNAL ACQUIRED';
    _tvStaticSubtext = '▶ ${title.toUpperCase()}';
  }

  void showChannelFailure({required bool noStreams}) {
    _tvStaticMessage = noStreams
        ? '⚠ CHANNEL HAS NO STREAMS'
        : '⚠ CHANNEL SWITCH FAILED';
    _tvStaticSubtext = '';
  }

  void retireAtRouteDispose() {
    _transitionStopTimer?.cancel();
    _rainbowController.dispose();
  }
}
