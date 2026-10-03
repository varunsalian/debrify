import 'package:debrify/features/torbox_downloads/models/torbox_file_entry.dart';
import 'package:debrify/models/torbox_file.dart';
import 'package:debrify/utils/file_utils.dart';
import 'package:debrify/utils/series_parser.dart';

bool torboxFileLooksLikeVideo(TorboxFile file) {
  final name = file.shortName.isNotEmpty
      ? file.shortName
      : FileUtils.getFileName(file.name);
  return FileUtils.isVideoFile(name) ||
      (file.mimetype?.toLowerCase().startsWith('video/') ?? false);
}

String torboxDisplayName(TorboxFile file) {
  if (file.shortName.isNotEmpty) {
    return file.shortName;
  }
  if (file.name.isNotEmpty) {
    return FileUtils.getFileName(file.name);
  }
  return 'File ${file.id}';
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

String formatTorboxPlaylistTitle({
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

String composeTorboxEntryTitle({
  required String? seriesTitle,
  required String episodeLabel,
  required bool isSeriesCollection,
  required String fallback,
}) {
  if (!isSeriesCollection) {
    return fallback;
  }

  final cleanSeries = seriesTitle?.replaceAll(RegExp(r'[._\-]+$'), '').trim();
  if (cleanSeries != null && cleanSeries.isNotEmpty) {
    return '$cleanSeries $episodeLabel';
  }

  return fallback;
}

String formatTorboxError(Object error) {
  final raw = error.toString();
  return raw.replaceFirst('Exception: ', '').trim();
}

bool isLikelySeries(List<TorboxFileEntry> entries) {
  if (entries.length < 2) return false;

  final episodeEntries = entries.where((entry) {
    final info = entry.seriesInfo;
    final season = info.season;
    final episode = info.episode;
    if (!info.isSeries) return false;
    if (season == null || season <= 0) return false;
    if (episode == null || episode <= 0) return false;
    return true;
  }).toList();

  if (episodeEntries.length < 2) return false;

  final uniqueEpisodeKeys = episodeEntries
      .map((entry) => '${entry.seriesInfo.season}:${entry.seriesInfo.episode}')
      .toSet();
  if (uniqueEpisodeKeys.length < 2) return false;

  final ratio = episodeEntries.length / entries.length;
  if (ratio < 0.6) return false;

  return true;
}
