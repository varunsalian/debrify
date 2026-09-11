import 'package:flutter/material.dart';

/// Destinations within the top-level Playback setting.
enum PlaybackSettingsSection {
  player(
    'Player',
    'Default player, watch history, skipping, buffering and player appearance',
    Icons.play_circle_outline_rounded,
  ),
  video(
    'Video',
    'Picture fit, rendering and decoding',
    Icons.ondemand_video_rounded,
  ),
  audio(
    'Audio',
    'Preferred language, sound output and night mode',
    Icons.volume_up_rounded,
  ),
  subtitles(
    'Subtitles',
    'Language, timing, appearance and custom fonts',
    Icons.subtitles_outlined,
  );

  const PlaybackSettingsSection(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}
