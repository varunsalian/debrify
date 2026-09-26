import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';

/// Preserve source-browser season-pack eligibility and provider order. The
/// caller supplies IPTV ownership so this policy does not invoke a service.
List<Torrent> filterSourceSeasonPacks(
  List<Torrent> torrents, {
  required AdvancedSearchSelection selection,
  required bool bindMode,
  required bool Function(Torrent) isIptvSource,
}) {
  final sel = selection;
  var filtered = torrents;

  // Direct links are individual episode streams that can't be added as a
  // season/series pack. Movies are single files, so they're left alone.
  if (sel.isSeries && sel.episode == null) {
    filtered = filtered
        .where(
          (torrent) =>
              torrent.streamType == StreamType.torrent ||
              (bindMode && isIptvSource(torrent)),
        )
        .toList(growable: false);
  }

  // Filter by season when a season is specified but no episode, so only
  // torrents that include the requested season remain.
  if (sel.isSeries && sel.season != null && sel.episode == null) {
    final requestedSeason = sel.season!;
    filtered = filtered
        .where((torrent) {
          switch (torrent.coverageType) {
            case 'completeSeries':
              // Always include complete series (they include all seasons).
              return true;
            case 'multiSeasonPack':
              // Include if the requested season is within the range.
              if (torrent.startSeason != null && torrent.endSeason != null) {
                return torrent.startSeason! <= requestedSeason &&
                    torrent.endSeason! >= requestedSeason;
              }
              // If season range data is missing, exclude to be safe.
              return false;
            case 'seasonPack':
              // Include only if it matches the requested season exactly.
              return torrent.seasonNumber == requestedSeason;
            case 'singleEpisode':
              // Keep only if the name resolves to the requested season.
              final name = torrent.name.toUpperCase();
              final seasonPadded = requestedSeason.toString().padLeft(2, '0');
              final seasonPatterns = [
                'S$seasonPadded', // S04
                'S$requestedSeason', // S4
                'SEASON $requestedSeason', // Season 4
                'SEASON$requestedSeason', // Season4
                '${requestedSeason}X', // 4x (for 4x01 format)
              ];
              for (final pattern in seasonPatterns) {
                if (name.contains(pattern)) return true;
              }
              // If we can't determine the season, exclude the single episode.
              return false;
            default:
              // Unknown coverage type — keep it to avoid over-filtering.
              return true;
          }
        })
        .toList(growable: false);
  }
  return filtered;
}

/// Distinct season numbers inferable from [torrents]' coverage info (pack
/// season numbers and range bounds).
List<int> deriveSourceSeasons(List<Torrent> torrents) {
  final derived = <int>{};
  for (final t in torrents) {
    final n = t.seasonNumber;
    if (n != null && n > 0) derived.add(n);
    final start = t.startSeason;
    final end = t.endSeason;
    if (start != null && end != null && end >= start && end - start <= 50) {
      for (var s = start; s <= end; s++) {
        if (s > 0) derived.add(s);
      }
    }
  }
  return derived.toList()..sort();
}

/// Prefer metadata seasons, falling back to the last unscoped result set.
/// Keep the selected season reachable even if nothing currently covers it.
List<int> sourceSeasonMenu({
  required List<int> available,
  required List<int> derived,
  required int? selected,
}) {
  final base = available.isNotEmpty ? available : derived;
  if (selected != null && !base.contains(selected)) {
    return [...base, selected]..sort();
  }
  return base;
}
