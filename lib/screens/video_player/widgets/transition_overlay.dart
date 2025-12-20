import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../constants/color_constants.dart';
import '../painters/tv_scanlines_painter.dart';
import '../painters/tv_vignette_painter.dart';

/// Fullscreen transition overlay with retro TV static effect
///
/// Displays an animated rainbow static effect with customizable message
/// during video transitions (matches Android TV aesthetic).
class TransitionOverlay extends StatelessWidget {
  /// Animation controller for the rainbow/static animation
  final AnimationController rainbowController;

  /// Main message to display (e.g., "📺 TUNING...")
  final String tvStaticMessage;

  /// Optional subtitle message
  final String tvStaticSubtext;

  const TransitionOverlay({
    Key? key,
    required this.rainbowController,
    required this.tvStaticMessage,
    required this.tvStaticSubtext,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: true,
        child: AnimatedBuilder(
          animation: rainbowController,
          builder: (_, __) {
            // Generate random gray value for TV static (easier on eyes)
            // Use microseconds for truly random values each frame
            final random = math.Random(DateTime.now().microsecondsSinceEpoch);
            // Moderate range: 30-90 for visible but not harsh static
            final grayValue = 30 + random.nextInt(60); // Random between 30-90
            final staticColor = Color.fromRGBO(grayValue, grayValue, grayValue, 1.0);

            // Randomly flicker text (70% chance full opacity, 30% flicker)
            final textAlpha = random.nextInt(10) > 7
                ? (0.7 + random.nextDouble() * 0.3)
                : 1.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // TV Static background - rapidly changing gray color
                ColoredBox(color: staticColor),

                // Animated scan lines with pattern
                CustomPaint(
                  painter: TvScanlinesPatternPainter(
                    offset: rainbowController.value,
                  ),
                ),

                // Center text with retro TV styling
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(48.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Opacity(
                          opacity: textAlpha,
                          child: Text(
                            tvStaticMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: VideoPlayerColors.retroGreen, // Retro green
                              fontSize: 36,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: VideoPlayerColors.retroGreenDark,
                                  offset: const Offset(2, 2),
                                  blurRadius: 4,
                                ),
                                Shadow(
                                  color: VideoPlayerColors.retroGreen.withOpacity(0.5),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (tvStaticSubtext.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Opacity(
                            opacity: textAlpha,
                            child: Text(
                              tvStaticSubtext,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: VideoPlayerColors.retroGreen, // Retro green
                                fontSize: 16,
                                fontFamily: 'monospace',
                                shadows: [
                                  Shadow(
                                    color: VideoPlayerColors.retroGreenDark,
                                    offset: const Offset(1, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Vignette overlay
                CustomPaint(
                  painter: TvVignettePainter(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
