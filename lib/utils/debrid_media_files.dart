import 'file_utils.dart';
import 'series_parser.dart';

/// File-naming and episode-ordering helpers shared by the debrid providers and
/// the playback flow. Pure logic; no provider APIs.

String debridFileName(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx >= 0 ? norm.substring(idx + 1) : norm;
}

/// Video files, or every file when none of them look like video.
List<T> debridVideoPool<T>(List<T> files, String Function(T) nameOf) {
  final videos = files.where((f) => FileUtils.isVideoFile(nameOf(f))).toList();
  return videos.isNotEmpty ? videos : List<T>.from(files);
}

/// Order video items by season/episode (falling back to filename) and return
/// the sorted list plus the first-episode start index — matching Home's
/// episode-aware playlist builders (so E2 plays before E10, starting at E1).
(List<T>, int) debridOrderBySeries<T>(
  List<T> items,
  String Function(T) nameOf,
) {
  final names = [for (final e in items) debridFileName(nameOf(e))];
  final infos = [for (final n in names) SeriesParser.parseFilename(n)];
  final isSeries = items.length > 1 && SeriesParser.isSeriesPlaylist(names);
  final order = List<int>.generate(items.length, (i) => i);
  if (isSeries) {
    order.sort((a, b) {
      final sc = (infos[a].season ?? 0).compareTo(infos[b].season ?? 0);
      if (sc != 0) return sc;
      final ec = (infos[a].episode ?? 0).compareTo(infos[b].episode ?? 0);
      if (ec != 0) return ec;
      return names[a].toLowerCase().compareTo(names[b].toLowerCase());
    });
  } else {
    order.sort(
      (a, b) => names[a].toLowerCase().compareTo(names[b].toLowerCase()),
    );
  }
  final sorted = [for (final i in order) items[i]];
  final sortedInfos = [for (final i in order) infos[i]];
  var start = isSeries ? debridFirstEpisodeIndex(sortedInfos) : 0;
  if (start < 0 || start >= sorted.length) start = 0;
  return (sorted, start);
}

int debridFirstEpisodeIndex(List<SeriesInfo> infos) {
  var startIndex = 0;
  int? bestSeason;
  int? bestEpisode;
  for (var i = 0; i < infos.length; i++) {
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
