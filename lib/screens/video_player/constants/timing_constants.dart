/// Timing constants for video player animations and transitions
class VideoPlayerTimingConstants {
  // Animation durations
  static const rainbowAnimationDuration = Duration(milliseconds: 700);
  static const rainbowRepeatPeriod = Duration(milliseconds: 50);

  // Transition phases
  static const transitionPhase1Duration = Duration(milliseconds: 1500);
  static const transitionTotalDuration = Duration(milliseconds: 3000);
  static const transitionWatchdogTimeout = Duration(seconds: 6);

  // UI delays
  static const shortDelay = Duration(milliseconds: 100);
  static const mediumDelay = Duration(milliseconds: 250);
  static const loadDelay = Duration(milliseconds: 450);
  static const longDelay = Duration(milliseconds: 500);
  static const speedChangeDelay = Duration(milliseconds: 1500);

  // Auto-hide timers
  static const controlsAutoHideDuration = Duration(seconds: 3);
  static const badgeDisplayDuration = Duration(seconds: 4);

  // Seek and playback
  static const seekDelta = Duration(seconds: 10);
  static const minimumPlaybackPosition = Duration(seconds: 2);
  static const endingThreshold = Duration(seconds: 30);
  static const manualSelectionResetDuration = Duration(seconds: 30);

  // Navigation animations
  static const navigationAnimationDuration = Duration(milliseconds: 120);
  static const fadeAnimationDuration = Duration(milliseconds: 200);
}
