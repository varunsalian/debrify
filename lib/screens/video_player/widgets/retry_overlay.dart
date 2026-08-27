import 'package:flutter/material.dart';

/// Non-blocking progress indicator shown over the player.
///
/// A semi-transparent box at the bottom-right carrying whatever [message] the
/// caller has — PikPak reactivating a video from cold storage is the case that
/// prompted it, but nothing here knows that. Any provider with a slow recovery
/// step can use it.
class PlaybackRetryOverlay extends StatelessWidget {
  /// Message to display (e.g., "Reactivating video... (1/5)")
  final String message;

  /// Distance from the bottom edge. 80 is the legacy constant, kept as the
  /// default so `classic` is unchanged; the styled dock passes its measured
  /// height so this never sits inside a taller dock.
  final double bottom;

  const PlaybackRetryOverlay({
    super.key,
    required this.message,
    this.bottom = 80,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: bottom,
      right: 20,
      child: IgnorePointer(
        ignoring: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
