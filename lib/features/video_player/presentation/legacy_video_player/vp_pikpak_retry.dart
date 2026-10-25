import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpPikPakRetryHost {
  Map<String, String>? get activeHttpHeaders;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  set isPikPakRetrying(bool v);
  set pikPakRetryCount(int v);
  int get pikPakRetryId;
  set pikPakRetryId(int v);
  set pikPakRetryMessage(String? v);
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  Future<void> goToNextEpisode();
  Future<bool> waitForVideoMetadata({
    int timeoutSeconds = 15,
    required int retryId,
    int additionalMonitoringSeconds = 0,
  });
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
}

class VpPikPakRetry {
  VpPikPakRetry(this._host);
  final VpPikPakRetryHost _host;

  /// Attempts to play a PikPak video with retry logic for cold storage
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  }) async {
    if (request?.isCurrent == false) return false;
    // Only apply retry logic for PikPak videos
    // Support both playlist entries and Debrify TV (requestMagicNext) flows
    final currentEntry =
        _host.activePlaylist != null &&
            _host.currentIndex >= 0 &&
            _host.currentIndex < _host.activePlaylist!.length
        ? _host.activePlaylist![_host.currentIndex]
        : null;
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
      'PikPak: _playPikPakVideoWithRetry called for index ${_host.currentIndex}, isPikPak: $isPikPak, overrideProvider: $overrideProvider, overridePikPakFileId: $overridePikPakFileId, isDebrifyTV: $isDebrifyTV',
    );

    if (!isPikPak) {
      // Not a PikPak video, play normally
      await _host.openMedia(
        mk.Media(videoUrl, httpHeaders: _host.activeHttpHeaders),
        play: true,
        request: request,
      );
      return true;
    }

    print('PikPak: Starting retry logic for cold storage handling');

    // Generate a new retry ID to cancel any previous retry loops
    _host.pikPakRetryId++;
    final myRetryId = _host.pikPakRetryId;
    print('PikPak: Generated retry ID: $myRetryId');

    // Reset retry state
    _host.pikPakRetryCount = 0;
    _host.isPikPakRetrying = false;
    _host.pikPakRetryMessage = null;

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
      await _host.openMedia(
        mk.Media(videoUrl, httpHeaders: _host.activeHttpHeaders),
        play: true,
        request: request,
      );
    } catch (e) {
      print('PikPak: Initial player.open() failed with error: $e');
      // Continue with retry loop - might work on subsequent attempts
    }

    int attempt = 0;
    while (attempt <= maxRetries) {
      try {
        // Check if cancelled before starting attempt
        if (_host.pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled before attempt ${attempt + 1} (navigation occurred)',
          );
          // Clear state synchronously
          _host.isPikPakRetrying = false;
          _host.pikPakRetryMessage = null;
          _host.pikPakRetryCount = 0;
          if (_host.mounted) {
            _host.setState(() {});
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
        final loadSuccess = await _host.waitForVideoMetadata(
          timeoutSeconds: metadataTimeoutSeconds,
          retryId: myRetryId,
          additionalMonitoringSeconds: cappedDelay,
        );

        if (request?.isCurrent == false) return false;
        if (loadSuccess) {
          // Success! Video loaded (either immediately or during monitoring/delay)
          print('PikPak: Video metadata loaded successfully - file is ready!');
          // Note: Retry state already cleared by VpMediaWaits.waitForVideoMetadata
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
          _host.isPikPakRetrying = false;
          _host.pikPakRetryMessage = null;
          _host.pikPakRetryCount = 0;

          if (_host.mounted) {
            _host.setState(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              ScaffoldMessenger.of(_host.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Video failed to load. Skipping to next...',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              await _host.goToNextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              ScaffoldMessenger.of(_host.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Failed to play video after multiple attempts. Please try again later.',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
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
        if (_host.mounted) {
          _host.setState(() {
            _host.isPikPakRetrying = true;
            _host.pikPakRetryCount = attempt + 1;
            _host.pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Retry ${attempt + 1} - reopening player and waiting ${nextDelay}s before next check...',
        );

        // Check if widget was disposed
        if (!_host.mounted) {
          print('PikPak: Widget disposed before retry');
          return false;
        }

        // Check if cancelled
        if (_host.pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled before reopening player (navigation occurred)',
          );
          // Clear state synchronously
          _host.isPikPakRetrying = false;
          _host.pikPakRetryMessage = null;
          _host.pikPakRetryCount = 0;
          if (_host.mounted) {
            _host.setState(() {});
          }
          return false;
        }

        // Try reopening the player (might help reactivate cold storage file)
        try {
          await _host.openMedia(
            mk.Media(videoUrl, httpHeaders: _host.activeHttpHeaders),
            play: true,
            request: request,
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
          _host.isPikPakRetrying = false;
          _host.pikPakRetryMessage = null;
          _host.pikPakRetryCount = 0;

          if (_host.mounted) {
            _host.setState(() {});

            if (isDebrifyTV) {
              // Auto-skip for Debrify TV
              print('PikPak: Auto-advancing to next video in Debrify TV queue');
              ScaffoldMessenger.of(_host.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Video failed to load. Skipping to next...',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 3),
                ),
              );
              await _host.goToNextEpisode();
            } else if (showFailure) {
              // Show error for regular playlist
              ScaffoldMessenger.of(_host.context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Failed to play video after multiple attempts. Please try again later.',
                    style: TextStyle(color: Colors.white),
                  ),
                  backgroundColor: Colors.red,
                  duration: Duration(seconds: 5),
                ),
              );
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

        if (_host.mounted) {
          _host.setState(() {
            _host.isPikPakRetrying = true;
            _host.pikPakRetryCount = attempt + 1;
            _host.pikPakRetryMessage = 'Reactivating video...';
          });
        }

        print(
          'PikPak: Error in attempt ${attempt + 1}, waiting ${nextDelay}s before retry...',
        );

        // Check if widget was disposed
        if (!_host.mounted) {
          print('PikPak: Widget disposed during error handling');
          return false;
        }

        // Check if cancelled
        if (_host.pikPakRetryId != myRetryId || request?.isCurrent == false) {
          print(
            'PikPak: Retry loop cancelled during error handling (navigation occurred)',
          );
          // Clear state synchronously
          _host.isPikPakRetrying = false;
          _host.pikPakRetryMessage = null;
          _host.pikPakRetryCount = 0;
          if (_host.mounted) {
            _host.setState(() {});
          }
          return false;
        }

        // Try reopening the player for next attempt
        try {
          await _host.openMedia(
            mk.Media(videoUrl, httpHeaders: _host.activeHttpHeaders),
            play: true,
            request: request,
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
