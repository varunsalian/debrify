import 'package:flutter/material.dart';

const Color kPremiumBlue = Color(0xFF6366F1);

/// Reusable progress bar overlay for video files
/// Shows watch progress with percentage badge and status indicators
class FileProgressBar extends StatelessWidget {
  /// Progress from 0.0 to 1.0
  final double progress;

  /// Whether the file is finished (watched 90%+)
  final bool isFinished;

  /// Whether this is the currently playing file
  final bool isCurrentlyPlaying;

  /// Whether this was the last played file
  final bool isLastPlayed;

  const FileProgressBar({
    super.key,
    required this.progress,
    this.isFinished = false,
    this.isCurrentlyPlaying = false,
    this.isLastPlayed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Progress bar at the bottom
        if (progress > 0.0 && !isFinished)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kPremiumBlue,
                        kPremiumBlue.withValues(alpha: 0.8),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: kPremiumBlue.withValues(alpha: 0.5),
                        blurRadius: 4,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Progress percentage indicator (only show if progress > 10%)
        if (progress > 0.1 && !isFinished)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: kPremiumBlue.withValues(alpha: 0.8),
                  width: 1,
                ),
              ),
              child: Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: kPremiumBlue,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

        // Currently playing indicator
        if (isCurrentlyPlaying)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kPremiumBlue,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: kPremiumBlue.withValues(alpha: 0.5),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 2),
                  Text(
                    'NOW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Last played indicator
        if (isLastPlayed && !isCurrentlyPlaying)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.replay,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 2),
                  Text(
                    'LAST',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Finished indicator
        if (isFinished && !isCurrentlyPlaying && !isLastPlayed)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF059669),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 12,
                  ),
                  SizedBox(width: 2),
                  Text(
                    'DONE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
