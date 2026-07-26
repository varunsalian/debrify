import 'package:flutter/material.dart';

import '../see_all/stremio_dropdown.dart';

/// Selectable max playback resolutions for YouTube (pixel height). 1440p/2160p
/// are served by YouTube only in VP9 (no H.264 above 1080p); picking them opts
/// into VP9 playback. Any preference at/under 1080p stays H.264.
const List<int> kYoutubeQualities = [2160, 1440, 1080, 720, 480, 360];

String youtubeQualityLabel(int height) => '${height}p';

/// Filter bar for the YouTube source: a Stremio-styled quality (resolution)
/// selector plus an optional result count / download hint. Left-aligned to
/// match the Discover / See-All filter bars.
class YoutubeFiltersBar extends StatelessWidget {
  final int selectedHeight;
  final int resultCount;
  final bool isTelevision;
  final ValueChanged<int> onQualityChanged;
  final FocusNode? qualityFocusNode;

  /// Called when DPAD-up is pressed on the first filter, to return focus to the
  /// search field (TV navigation).
  final VoidCallback? onUpArrowPressed;

  const YoutubeFiltersBar({
    super.key,
    required this.selectedHeight,
    required this.resultCount,
    required this.isTelevision,
    required this.onQualityChanged,
    this.qualityFocusNode,
    this.onUpArrowPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              StremioDropdown<int>(
                label: 'Quality',
                value: selectedHeight,
                options: [
                  for (final h in kYoutubeQualities)
                    StremioDropdownOption(h, youtubeQualityLabel(h)),
                ],
                onSelected: onQualityChanged,
                focusNode: qualityFocusNode,
                isTelevision: isTelevision,
                onUpArrowPressed: onUpArrowPressed,
              ),
              const SizedBox(width: 10),
              // Explains the resolver's step-down: the preference is a ceiling,
              // not a requirement — a video that lacks the chosen height plays
              // the next best one down rather than failing.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "Plays the next best if a video doesn't have this quality",
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              if (resultCount > 0)
                Text(
                  '$resultCount video${resultCount != 1 ? 's' : ''}'
                  '${isTelevision ? ' • hold OK to download' : ' • long press to download'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
