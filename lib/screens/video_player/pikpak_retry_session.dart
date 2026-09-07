import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:media_kit/media_kit.dart' as mk;

import 'models/playlist_entry.dart';

/// PikPak retry state and monitoring; screen callbacks retain UI/player authority.
class PikPakRetrySession {
  PikPakRetrySession({
    required bool Function() readMounted,
    required Duration Function() readStreamDuration,
    required bool Function() readStreamPlaying,
    required Duration Function() readDirectDuration,
    required bool Function() readDirectPlaying,
    required Map<String, String>? Function() readHeaders,
    required Future<void> Function(mk.Media, {required bool play}) openMedia,
    required void Function(VoidCallback) commit,
    required void Function(bool skipping) showFailureNotice,
    required Future<void> Function() nextEpisode,
  }) : _readMounted = readMounted,
       _readStreamDuration = readStreamDuration,
       _readStreamPlaying = readStreamPlaying,
       _readDirectDuration = readDirectDuration,
       _readDirectPlaying = readDirectPlaying,
       _readHeaders = readHeaders,
       _openMedia = openMedia,
       _commit = commit,
       _showFailureNotice = showFailureNotice,
       _nextEpisode = nextEpisode;

  final bool Function() _readMounted;
  final Duration Function() _readStreamDuration;
  final bool Function() _readStreamPlaying;
  final Duration Function() _readDirectDuration;
  final bool Function() _readDirectPlaying;
  final Map<String, String>? Function() _readHeaders;
  final Future<void> Function(mk.Media, {required bool play}) _openMedia;
  final void Function(VoidCallback) _commit;
  final void Function(bool skipping) _showFailureNotice;
  final Future<void> Function() _nextEpisode;

  // PikPak cold storage retry logic
  bool _isPikPakRetrying = false;
  int _pikPakRetryCount = 0;
  String? _pikPakRetryMessage;
  int _pikPakRetryId =
      0; // Cancellation token: increments on each new video to cancel old retries

  bool get isRetrying => _isPikPakRetrying;
  String? get message => _pikPakRetryMessage;

  void invalidateOnly() {
    _pikPakRetryId++;
  }

  void close() {
    _pikPakRetryId++;
    _isPikPakRetrying = false;
    _pikPakRetryCount = 0;
    _pikPakRetryMessage = null;
  }

  /// Waits for video metadata (duration) to become available
  /// Returns true if metadata loads, false if timeout or cancelled
  /// This is the only reliable way to detect if a PikPak file is actually loading
  ///
  /// The additionalMonitoringSeconds parameter allows continuous monitoring during retry delays
  /// to detect if video loads during the delay period (prevents unnecessary player resets)
  Future<bool> _waitForVideoMetadata({
    int timeoutSeconds = 15,
    required int retryId,
    int additionalMonitoringSeconds = 0,
  }) async {
    final totalTimeoutSeconds = timeoutSeconds + additionalMonitoringSeconds;
    final stopwatch = Stopwatch()..start();

    while (stopwatch.elapsed.inSeconds < totalTimeoutSeconds) {
      // Check if this retry has been cancelled (user navigated to different video)
      if (_pikPakRetryId != retryId) {
        print(
          'PikPak: Retry cancelled (token mismatch: current=$_pikPakRetryId, expected=$retryId)',
        );
        return false;
      }

      // Check if widget was disposed (prevents operations on unmounted widget)
      if (!_readMounted()) {
        print('PikPak: Widget disposed during metadata wait');
        return false;
      }

      // FIX: Check BOTH _duration field (from stream) AND player.state.duration (direct state)
      // This ensures we catch the video loading whether the stream has fired or not
      // For the first video, streams might not fire reliably, so we need the direct state check
      final streamDuration = _readStreamDuration();
      final directDuration = _readDirectDuration();
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
        if (!_readMounted()) {
          print('PikPak: Widget disposed during stabilization delay');
          return false;
        }

        // Final cancellation check after stabilization delay
        if (_pikPakRetryId != retryId) {
          print(
            'PikPak: Retry cancelled during stabilization (navigation occurred)',
          );
          return false;
        }

        // Verify playback is actually happening, not just buffering with duration
        // This prevents false positives where duration loads but video won't play
        // Check both stream state and direct player state for reliability
        final streamPlaying = _readStreamPlaying();
        final directPlaying = _readDirectPlaying();

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
        _isPikPakRetrying = false;
        _pikPakRetryMessage = null;
        _pikPakRetryCount = 0;

        if (_readMounted()) {
          _commit(() {
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

  /// Attempts to play a PikPak video with retry logic for cold storage
  Future<bool> play(
    String videoUrl, {
    required PlaylistEntry? Function() readCurrentEntry,
    required int Function() readDiagnosticIndex,
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
  }) async {
    // Only apply retry logic for PikPak videos
    // Support both playlist entries and Debrify TV (requestMagicNext) flows
    final currentEntry = readCurrentEntry();
    final isPikPak =
        overrideProvider?.toLowerCase() == 'pikpak' ||
        overridePikPakFileId != null ||
        currentEntry?.provider?.toLowerCase() == 'pikpak' ||
        currentEntry?.pikpakFileId != null ||
        isDebrifyTV ||
        videoUrl.contains(
          'mypikpak.com',
        ); // Detect PikPak by URL (Stremio TV, etc.)

    print(
      'PikPak: _playPikPakVideoWithRetry called for index ${readDiagnosticIndex()}, isPikPak: $isPikPak, overrideProvider: $overrideProvider, overridePikPakFileId: $overridePikPakFileId, isDebrifyTV: $isDebrifyTV',
    );

    if (!isPikPak) {
      // Not a PikPak video, play normally
      await _openMedia(
        mk.Media(videoUrl, httpHeaders: _readHeaders()),
        play: true,
      );
      return true;
    }

    print('PikPak: Starting retry logic for cold storage handling');

    // Generate a new retry ID to cancel any previous retry loops
    _pikPakRetryId++;
    final myRetryId = _pikPakRetryId;
    print('PikPak: Generated retry ID: $myRetryId');

    // Reset retry state
    _pikPakRetryCount = 0;
    _isPikPakRetrying = false;
    _pikPakRetryMessage = null;

    // Retry with exponential backoff
    // Standardized retry parameters to match Java/Kotlin implementation
    const maxRetries = 5; // 6 total attempts including initial
    const baseDelaySeconds = 2;
    const metadataTimeoutSeconds = 10; // Standardized timeout
    const maxDelaySeconds = 18; // Standardized max delay cap

    // CRITICAL FIX: Open player ONCE before the retry loop
    // This prevents resetting the video to 0:00 if it loads during a retry delay
    print('PikPak: Initial playback attempt - opening media...');
    try {
      await _openMedia(
        mk.Media(videoUrl, httpHeaders: _readHeaders()),
        play: true,
      );
    } catch (e) {
      print('PikPak: Initial player.open() failed with error: $e');
      // Continue with retry loop - might work on subsequent attempts
    }

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // Check if cancelled before starting attempt
        if (_pikPakRetryId != myRetryId) {
          print(
            'PikPak: Retry loop cancelled before attempt ${attempt + 1} (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (_readMounted()) {
            _commit(() {});
          }
          return false;
        }

        print('PikPak: Monitoring attempt ${attempt + 1}/${maxRetries + 1}...');

        // Calculate delay for this attempt (0 for first attempt)
        final delaySeconds = attempt == 0
            ? 0
            : (baseDelaySeconds * (1 << (attempt - 1)));
        final cappedDelay = delaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : delaySeconds;

        // CRITICAL FIX: Wait for video metadata with EXTENDED monitoring during delay period
        // This allows detection of video loading DURING the delay, preventing unnecessary player resets
        print(
          'PikPak: Waiting for video duration (${metadataTimeoutSeconds}s) + monitoring during delay (${cappedDelay}s)...',
        );
        final loadSuccess = await _waitForVideoMetadata(
          timeoutSeconds: metadataTimeoutSeconds,
          retryId: myRetryId,
          additionalMonitoringSeconds: cappedDelay,
        );

        if (loadSuccess) {
          // Success! Video loaded (either immediately or during monitoring/delay)
          print('PikPak: Video metadata loaded successfully - file is ready!');
          // Note: Retry state already cleared by _waitForVideoMetadata
          print('PikPak: Retry mechanism fully deactivated, playback ready');
          return true;
        }

        // Video didn't load even after monitoring during delay
        print(
          'PikPak: Video metadata failed to load after ${metadataTimeoutSeconds + cappedDelay}s - file likely in cold storage',
        );

        // Check if this was the last attempt (all retries exhausted)
        if (attempt >= maxRetries) {
          // ALL RETRIES EXHAUSTED - handle here
          print('PikPak: All retry attempts exhausted. Video failed to load.');

          // Clear retry state
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;

          if (_readMounted()) {
            _commit(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              _showFailureNotice(true);
              await _nextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              _showFailureNotice(false);
            }
          }
          return false; // Exhausted the cold-storage retries.
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for NEXT attempt
        final nextDelaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = nextDelaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : nextDelaySeconds;

        // Update UI to show retry state
        if (_readMounted()) {
          _commit(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Retry ${attempt + 1} - reopening player and waiting ${nextDelay}s before next check...',
        );

        // Check if widget was disposed
        if (!_readMounted()) {
          print('PikPak: Widget disposed before retry');
          return false;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId) {
          print(
            'PikPak: Retry loop cancelled before reopening player (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (_readMounted()) {
            _commit(() {});
          }
          return false;
        }

        // Try reopening the player (might help reactivate cold storage file)
        try {
          await _openMedia(
            mk.Media(videoUrl, httpHeaders: _readHeaders()),
            play: true,
          );
        } catch (e) {
          print(
            'PikPak: Retry ${attempt + 1} - player.open() failed with error: $e',
          );
          // Continue - the monitoring in next iteration might still detect if it loads
        }
      } catch (e) {
        print('PikPak: Retry attempt ${attempt + 1} failed with error: $e');

        // Check if this was the last attempt (all retries exhausted)
        if (attempt >= maxRetries) {
          // ALL RETRIES EXHAUSTED - handle here
          print(
            'PikPak: All retry attempts exhausted after error. Video failed to load.',
          );

          // Clear retry state
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;

          if (_readMounted()) {
            _commit(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              _showFailureNotice(true);
              await _nextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              _showFailureNotice(false);
            }
          }
          return false; // Exhausted the cold-storage retries.
        }

        // Still have retries left - continue with retry logic
        // Calculate delay for next attempt
        final delaySeconds = baseDelaySeconds * (1 << attempt);
        final nextDelay = delaySeconds > maxDelaySeconds
            ? maxDelaySeconds
            : delaySeconds;

        if (_readMounted()) {
          _commit(() {
            _isPikPakRetrying = true;
            _pikPakRetryCount = attempt + 1;
            _pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Error in attempt ${attempt + 1}, waiting ${nextDelay}s before retry...',
        );

        // Check if widget was disposed
        if (!_readMounted()) {
          print('PikPak: Widget disposed during error handling');
          return false;
        }

        // Check if cancelled
        if (_pikPakRetryId != myRetryId) {
          print(
            'PikPak: Retry loop cancelled during error handling (navigation occurred)',
          );
          // Clear state synchronously
          _isPikPakRetrying = false;
          _pikPakRetryMessage = null;
          _pikPakRetryCount = 0;
          if (_readMounted()) {
            _commit(() {});
          }
          return false;
        }

        // Try reopening the player for next attempt
        try {
          await _openMedia(
            mk.Media(videoUrl, httpHeaders: _readHeaders()),
            play: true,
          );
        } catch (reopenError) {
          print(
            'PikPak: Error retry - player.open() failed with error: $reopenError',
          );
          // Continue - next iteration might succeed
        }
      }

      attempt++;
    }
    return false;
  }
}
