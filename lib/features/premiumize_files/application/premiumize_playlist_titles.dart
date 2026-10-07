import 'package:debrify/utils/series_parser.dart';

String formatPlaylistTitle({
  required SeriesInfo info,
  required String fallback,
  required bool isSeriesCollection,
}) {
  if (!isSeriesCollection) return fallback;
  final season = info.season;
  final episode = info.episode;
  if (info.isSeries && season != null && episode != null) {
    final s = season.toString().padLeft(2, '0');
    final e = episode.toString().padLeft(2, '0');
    final desc = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : info.title?.trim().isNotEmpty == true
        ? info.title!.trim()
        : fallback;
    return 'S${s}E$e · $desc';
  }
  return fallback;
}

String composeEntryTitle({
  required String? seriesTitle,
  required String episodeLabel,
  required bool isSeriesCollection,
  required String fallback,
}) {
  if (!isSeriesCollection) return fallback;
  final clean = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
  if (clean != null && clean.isNotEmpty) return '$clean $episodeLabel';
  return fallback;
}

int findFirstEpisodeIndex(List<SeriesInfo> infos) {
  int startIndex = 0;
  int? bestSeason;
  int? bestEpisode;
  for (int i = 0; i < infos.length; i++) {
    final info = infos[i];
    final season = info.season;
    final episode = info.episode;
    if (!info.isSeries || season == null || episode == null) continue;
    final betterSeason = bestSeason == null || season < bestSeason;
    final betterEpisode =
        bestSeason != null &&
        season == bestSeason &&
        (bestEpisode == null || episode < bestEpisode);
    if (betterSeason || betterEpisode) {
      bestSeason = season;
      bestEpisode = episode;
      startIndex = i;
    }
  }
  return startIndex;
}
