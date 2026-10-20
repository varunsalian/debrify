import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpMediaWaitsHost {
  Duration get duration;
  set isPikPakRetrying(bool v);
  bool get isPlaying;
  set pikPakRetryCount(int v);
  int get pikPakRetryId;
  set pikPakRetryMessage(String? v);
  mk.Player get player;
  bool get mounted;
  void setState(VoidCallback fn);
}

class VpMediaWaits {
  VpMediaWaits(this._host);
  final VpMediaWaitsHost _host;

  // Wait for the video to be ready and duration to be available
  Future<void> waitForVideoReady() async {
    // Wait up to 10 seconds for the video to be ready
    for (int i = 0; i < 100; i++) {
      if (_host.duration > Duration.zero) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  // Wait for duration to be available before attempting position restoration
  Future<void> waitForDuration() async {
    // Wait up to 20 seconds for duration to be available
    for (int i = 0; i < 200; i++) {
      if (_host.duration > Duration.zero) {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Waits for video metadata (duration) to become available
  /// Returns true if metadata loads, false if timeout or cancelled
  /// This is the only reliable way to detect if a PikPak file is actually loading
  ///
  /// The additionalMonitoringSeconds parameter allows continuous monitoring during retry delays
  /// to detect if video loads during the delay period (prevents unnecessary player resets)
  Future<bool> waitForVideoMetadata({
    int timeoutSeconds = 15,
    required int retryId,
    int additionalMonitoringSeconds = 0,
  }) async {
    final totalTimeoutSeconds = timeoutSeconds + additionalMonitoringSeconds;
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed.inSeconds < totalTimeoutSeconds) {
      // Check if this retry has been cancelled (user navigated to different video)
      if (_host.pikPakRetryId != retryId) {
        print(
          'PikPak: Retry cancelled (token mismatch: current=${_host.pikPakRetryId}, expected=$retryId)',
        );
        return false;
      }

      // Check if widget was disposed (prevents operations on unmounted widget)
      if (!_host.mounted) {
        print('PikPak: Widget disposed during metadata wait');
        return false;
      }

      // FIX: Check BOTH _duration field (from stream) AND player.state.duration (direct state)
      // This ensures we catch the video loading whether the stream has fired or not
      // For the first video, streams might not fire reliably, so we need the direct state check
      final streamDuration = _host.duration;
      final directDuration = _host.player.state.duration;
      final effectiveDuration = streamDuration > Duration.zero
          ? streamDuration
          : directDuration;

      if (effectiveDuration > Duration.zero) {
        print(
          'PikPak: Video duration available (stream: $streamDuration, direct: $directDuration, effective: $effectiveDuration)',
        );

        // Additional verification: wait a bit longer to ensure playback actually started
        // This gives the player time to transition from "has duration" to "is playing"
        // and allows all stream listeners to synchronize their state updates
        print(
          'PikPak: Duration detected, waiting for playback to stabilize...',
        );
        await Future.delayed(const Duration(milliseconds: 800));

        // Check mounted state after delay
        if (!_host.mounted) {
          print('PikPak: Widget disposed during stabilization delay');
          return false;
        }

        // Final cancellation check after stabilization delay
        if (_host.pikPakRetryId != retryId) {
          print(
            'PikPak: Retry cancelled during stabilization (navigation occurred)',
          );
          return false;
        }

        // Verify playback is actually happening, not just buffering with duration
        // This prevents false positives where duration loads but video won't play
        // Check both stream state and direct player state for reliability
        final streamPlaying = _host.isPlaying;
        final directPlaying = _host.player.state.playing;

        if (streamPlaying || directPlaying) {
          print(
            'PikPak: Video confirmed playing - duration: $effectiveDuration, playing: true (stream: $streamPlaying, direct: $directPlaying)',
          );
        } else {
          // Duration is available but playback hasn't started yet
          // This is acceptable - duration alone is sufficient for cold storage detection
          print(
            'PikPak: Duration available ($effectiveDuration), playback will start shortly',
          );
        }

        // CRITICAL FIX: Clear retry state IMMEDIATELY when video loads
        // This prevents the retry UI from remaining visible if video loaded during monitoring
        _host.isPikPakRetrying = false;
        _host.pikPakRetryMessage = null;
        _host.pikPakRetryCount = 0;

        if (_host.mounted) {
          _host.setState(() {
            // State already cleared above - this just triggers rebuild
          });
        }

        return true;
      }

      // Wait a bit before checking again
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Timeout - video metadata never loaded, file is likely in cold storage
    print(
      'PikPak: Timeout waiting for video metadata (${totalTimeoutSeconds}s elapsed)',
    );
    return false;
  }
}
