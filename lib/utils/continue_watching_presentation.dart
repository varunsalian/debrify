/// Presentation helpers shared by Continue Watching card renderers.
library;

/// Whole minutes left from an exact saved playback position.
///
/// Rounds up so a final partial minute still reads as one minute rather than
/// disappearing while the item remains resumable.
int? continueWatchingMinutesLeft({
  required int positionMs,
  required int durationMs,
}) {
  if (positionMs <= 0 || durationMs <= positionMs) return null;
  return ((durationMs - positionMs) / Duration.millisecondsPerMinute).ceil();
}

/// Whole minutes left when a provider supplies only percent + runtime.
int? continueWatchingMinutesLeftFromProgress({
  required double? progress,
  required int? runtimeMinutes,
}) {
  if (progress == null ||
      runtimeMinutes == null ||
      runtimeMinutes <= 0 ||
      progress <= 0 ||
      progress >= 100) {
    return null;
  }
  return (runtimeMinutes * (1 - progress / 100)).ceil();
}

/// Spotlight's compact informational line, e.g. `S2 · E5 · 24 min left`.
String? continueWatchingCardSubtitle({String? episodeLabel, int? minutesLeft}) {
  final parts = <String>[
    if (episodeLabel != null && episodeLabel.trim().isNotEmpty)
      episodeLabel.trim(),
    if (minutesLeft != null && minutesLeft > 0) '$minutesLeft min left',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Finds one episode still in a Stremio meta endpoint's raw `videos` list.
String? episodeThumbnailFromVideos(
  List<Map<String, dynamic>>? videos, {
  required int season,
  required int episode,
}) {
  if (videos == null) return null;
  for (final video in videos) {
    final rawSeason = video['season'];
    final rawEpisode = video['number'] ?? video['episode'];
    final videoSeason = rawSeason is num ? rawSeason.toInt() : null;
    final videoEpisode = rawEpisode is num ? rawEpisode.toInt() : null;
    if (videoSeason != season || videoEpisode != episode) continue;
    final thumbnail = video['thumbnail'] as String?;
    if (thumbnail == null || thumbnail.isEmpty) return null;
    return downsizeEpisodeThumbnail(thumbnail);
  }
  return null;
}

/// Episode cards do not need MetaHub's full-width source image.
String downsizeEpisodeThumbnail(String url) {
  if (!url.contains('episodes.metahub.space')) return url;
  return url.replaceFirst(RegExp(r'/w\d+\.jpg$'), '/w500.jpg');
}
