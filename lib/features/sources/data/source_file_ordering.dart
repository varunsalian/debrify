import '../../../utils/series_parser.dart';

String sourceFileName(String path) {
  final norm = path.replaceAll('\\', '/');
  final idx = norm.lastIndexOf('/');
  return idx >= 0 ? norm.substring(idx + 1) : norm;
}

(List<T>, int) orderSourceFiles<T>(List<T> items, String Function(T) nameOf) {
  final names = [for (final e in items) sourceFileName(nameOf(e))];
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
  var start = isSeries ? firstSourceEpisodeIndex(sortedInfos) : 0;
  if (start < 0 || start >= sorted.length) start = 0;
  return (sorted, start);
}

int firstSourceEpisodeIndex(List<SeriesInfo> infos) {
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
