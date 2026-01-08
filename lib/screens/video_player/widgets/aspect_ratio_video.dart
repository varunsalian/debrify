import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

class AspectRatioVideo extends StatelessWidget {
  final mkv.VideoController videoController;
  final double? customAspectRatio;
  final BoxFit currentFit;
  final mkv.SubtitleViewConfiguration? subtitleViewConfiguration;

  const AspectRatioVideo({
    Key? key,
    required this.videoController,
    required this.customAspectRatio,
    required this.currentFit,
    this.subtitleViewConfiguration,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (customAspectRatio == null) {
      // No forced aspect ratio; let the Video widget scale internally
      return mkv.Video(
        controller: videoController,
        controls: null,
        fit: currentFit,
        subtitleViewConfiguration:
            subtitleViewConfiguration ?? const mkv.SubtitleViewConfiguration(),
      );
    }

    // Forced aspect ratio: center the constrained box and let Video cover inside it
    return Center(
      child: AspectRatio(
        aspectRatio: customAspectRatio!,
        child: mkv.Video(
          controller: videoController,
          controls: null,
          fit: BoxFit.cover,
          subtitleViewConfiguration:
              subtitleViewConfiguration ?? const mkv.SubtitleViewConfiguration(),
        ),
      ),
    );
  }
}
