import '../models/torrent.dart';

/// Torrent candidate curation shared between the old Home engine
/// (`torrent_search_screen.dart`) and the Search-tab playback service
/// (`torrent_playback_service.dart`), so auto-play probes the RIGHT torrent
/// first instead of the raw seeder-ranked list (which can lead with a
/// wrong-episode single or a wrong-season pack that resolves fine but is then
/// rejected, burning the probe budget).
///
/// This mirrors the logic inlined in `torrent_search_screen.dart` — episode
/// filter+sort at ~3134-3216 and `_torrentMatchesTitle` at ~13464. Kept here as
/// pure functions (no widget state) so both callers stay in sync.

/// Word-based title match: returns true when every significant word of
/// [searchTitle] appears (as a whole word) in [torrentName]. Used to drop
/// unrelated collections/packs before probing. An empty/insignificant title
/// falls back to a plain substring check (so it never over-filters).
bool torrentMatchesTitle(String torrentName, String searchTitle) {
  const skipWords = {'the', 'a', 'an', 'and', 'of', 'in', 'to', 'for'};

  String normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[._\-\[\]\(\)]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  // Only the first line of the torrent name is the actual title; some sources
  // append filename/metadata on later lines.
  final normalizedName = normalize(torrentName.split('\n').first);
  final normalizedTitle = normalize(searchTitle);

  final titleWords = normalizedTitle
      .split(' ')
      .where((w) => w.length > 1 && !skipWords.contains(w))
      .toList();

  if (titleWords.isEmpty) {
    return normalizedName.contains(normalizedTitle);
  }

  for (final word in titleWords) {
    // Whole-word match so "red" doesn't match "redeemed".
    final wordPattern = RegExp(r'\b' + RegExp.escape(word) + r'\b');
    if (!wordPattern.hasMatch(normalizedName)) return false;
  }
  return true;
}

/// Filter + relevance-sort [torrents] for a specific series episode. Keeps
/// single episodes matching the exact S/E pattern and packs that contain the
/// requested season; sorts exact matches first, then season/multi-season/
/// complete packs, then by seeders. For non-series content (or a missing
/// season/episode) the list is returned unchanged.
///
/// If the filter would remove everything (e.g. oddly-named torrents with no
/// coverage metadata and no S/E token in the name), the full list is returned
/// sorted-by-relevance instead of empty — so curation can never turn a
/// non-empty result set into a "no sources" failure. The post-resolve
/// `_resolvedHasEpisode` guard remains the final safety net.
List<Torrent> curateEpisodeCandidates(
  List<Torrent> torrents, {
  required bool isSeries,
  int? season,
  int? episode,
}) {
  if (!isSeries || season == null || episode == null || torrents.isEmpty) {
    return torrents;
  }

  final s = 'S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}'
      .toUpperCase();
  final sNoZero = 'S${season}E$episode'.toUpperCase();
  final x = '${season}x${episode.toString().padLeft(2, '0')}'.toUpperCase();
  final xNoZero = '${season}x$episode'.toUpperCase();

  bool hasExactEpisodeMatch(String name) {
    final u = name.toUpperCase();
    return u.contains(s) || u.contains(sNoZero) || u.contains(x) ||
        u.contains(xNoZero);
  }

  bool packContainsSeason(Torrent t) {
    switch (t.coverageType) {
      case 'completeSeries':
        return true;
      case 'multiSeasonPack':
        if (t.startSeason != null && t.endSeason != null) {
          return t.startSeason! <= season && t.endSeason! >= season;
        }
        return true; // unknown range → assume it contains the season
      case 'seasonPack':
        return t.seasonNumber == season;
      default:
        return false;
    }
  }

  int priority(Torrent t) {
    if (hasExactEpisodeMatch(t.name)) return 0;
    switch (t.coverageType) {
      case 'seasonPack':
        return 1;
      case 'multiSeasonPack':
        return 2;
      case 'completeSeries':
        return 3;
      default:
        return 4;
    }
  }

  int byRelevance(Torrent a, Torrent b) {
    final d = priority(a) - priority(b);
    if (d != 0) return d;
    return b.seeders - a.seeders; // within a tier, more seeders first
  }

  final filtered = torrents.where((t) {
    if (t.coverageType == 'singleEpisode' || t.coverageType == null) {
      return hasExactEpisodeMatch(t.name);
    }
    return packContainsSeason(t);
  }).toList();

  // Never return empty when we started with candidates — fall back to the full
  // list, relevance-sorted, and let the resolve-time guard reject wrong packs.
  final result = filtered.isEmpty ? List<Torrent>.from(torrents) : filtered;
  result.sort(byRelevance);
  return result;
}
