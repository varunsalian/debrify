import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';

String pikpakDisplayName(Map<String, dynamic> file) {
  final name = file['name']?.toString() ?? '';
  if (name.isNotEmpty) {
    return FileUtils.getFileName(name);
  }
  return 'File ${file['id']}';
}

String formatPikPakPlaylistTitle({
  required SeriesInfo info,
  required String fallback,
  required bool isSeriesCollection,
}) {
  if (!isSeriesCollection) {
    return fallback;
  }

  final season = info.season;
  final episode = info.episode;
  if (info.isSeries && season != null && episode != null) {
    final seasonLabel = season.toString().padLeft(2, '0');
    final episodeLabel = episode.toString().padLeft(2, '0');
    final description = info.episodeTitle?.trim().isNotEmpty == true
        ? info.episodeTitle!.trim()
        : info.title?.trim().isNotEmpty == true
        ? info.title!.trim()
        : fallback;
    return 'S${seasonLabel}E$episodeLabel · $description';
  }

  return fallback;
}

String combineSeriesAndEpisodeTitle({
  required String? seriesTitle,
  required String episodeLabel,
  required bool isSeriesCollection,
  required String fallback,
}) {
  if (!isSeriesCollection) {
    return fallback;
  }

  final cleanSeriesTitle = seriesTitle
      ?.replaceAll(RegExp(r'[._\-]+$'), '')
      .trim();
  if (cleanSeriesTitle != null && cleanSeriesTitle.isNotEmpty) {
    return '$cleanSeriesTitle $episodeLabel';
  }

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
    if (!info.isSeries || season == null || episode == null) {
      continue;
    }

    final bool isBetterSeason = bestSeason == null || season < bestSeason;
    final bool isBetterEpisode =
        bestSeason != null &&
        season == bestSeason &&
        (bestEpisode == null || episode < bestEpisode);

    if (isBetterSeason || isBetterEpisode) {
      bestSeason = season;
      bestEpisode = episode;
      startIndex = i;
    }
  }

  return startIndex;
}
