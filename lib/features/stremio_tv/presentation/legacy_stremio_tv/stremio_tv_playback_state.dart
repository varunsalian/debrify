import 'package:debrify/features/stremio_tv/models/stremio_tv_playback_records.dart';

class StremioTvPlaybackState {
  double? currentSlotProgress;

  int playGeneration = 0;
  // Overrides item.name when playing series episodes
  String? currentPlayTitle;

  final Map<String, StremioTvPlaybackCursor> playbackCursors = {};
  // Track mounted state for auto-play
  String? pendingChannelId;

  bool startupAutoPlayActive = false;

  bool pushingChannelDetail = false;
}
