import 'dart:convert';

import 'package:debrify/features/sources/data/source_file_ordering.dart';
import 'package:debrify/features/sources/models/resolved_source.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/series_source_service.dart';
import 'package:debrify/utils/series_parser.dart';

final class SourceCandidateChecks {
  const SourceCandidateChecks._();

  /// Selects the direct-URL stream to play instantly ([direct]) and the one
  /// kept as the dead-end rescue ([fallbackDirect]) — always the FIRST direct
  /// stream in [torrents] (tier-sorted when the ladder is active). [direct]
  /// is set only when no PLAYABLE candidate (probeable torrent or direct
  /// stream — external links and acquisition-less entries don't count)
  /// occupies a strictly better tier, so a full-match torrent beats a
  /// relaxed-tier direct link, but unplayable tier-0 noise can't suppress
  /// the instant play. Null/inactive ladder ⇒ legacy first-direct-wins.
  static bool isDirectCandidate(Torrent torrent) =>
      (torrent.streamType == StreamType.directUrl &&
          (torrent.directUrl?.isNotEmpty ?? false)) ||
      IptvSourceSearch.isDeferredXtreamSeries(torrent);

  static bool bindingMatchesMeta(SeriesSource source, PlaybackMeta meta) {
    final catalogId = meta.hasStremioEpisodeIdentity
        ? meta.stremioCatalogId
        : null;
    return source.matchesCatalogScope(
      catalogId: catalogId,
      catalogKey: meta.hasStremioEpisodeIdentity ? meta.stremioAddonKey : null,
    );
  }

  /// Whether the resolved add actually contains [season]/[episode] — the same
  /// SeriesParser filename check Home runs before launching a bound pack
  /// (_findEpisodeInFilenames). Without it, a binding that only covers earlier
  /// seasons still resolves fine and the player silently starts a different
  /// episode (last-played or S1E1) instead of falling back to search.
  ///
  /// Parses BASENAMES only — Home and the player's SeriesPlaylist both parse
  /// the filename, not the folder path; a folder segment like
  /// "Show.S04E01-E10.Pack/" would make this check disagree with the player.
  ///
  /// Errs toward playing: when the resolve exposes no real filename
  /// (single-file RD/PikPak, RAR archives) or nothing in the pack parses to a
  /// season/episode at all (absolute-numbered anime, "Episode 5" naming),
  /// trust the binding and let the player open it — rejecting those would
  /// regress packs that played fine before this check existed.
  /// The (season, episode) of a source whose name is exactly ONE specific
  /// episode, else null. STRICT — returns null for anything that could cover
  /// more than one episode (ranges "S01E01-E10", doubles "S01E01E02",
  /// multiple tokens, or non-singleEpisode coverage) so the [_playViaBound]
  /// cheap-skip below never drops a binding that genuinely contains the
  /// requested episode. When null, the source falls through to the normal
  /// resolve + [_resolvedHasEpisode] check (always correct, just not free).
  static bool resolvedHasEpisode(ResolvedSource r, int season, int episode) {
    final List<String> names;
    if (r.playlist != null && r.playlist!.length > 1) {
      names = r.playlist!.map((e) => sourceFileName(e.title)).toList();
    } else {
      // Single-file resolve: only RD/PikPak leave fileName unset (RD single
      // and RAR resolves carry just the torrent name, which isn't the file).
      final single =
          r.fileName ??
          ((r.playlist?.isNotEmpty ?? false) ? r.playlist!.first.title : null);
      if (single == null) return true; // no filename to judge → play
      names = <String>[sourceFileName(single)];
    }
    var sawEpisode = false;
    for (final info in SeriesParser.parsePlaylist(names)) {
      if (info.season == null || info.episode == null) continue;
      if (info.season == season && info.episode == episode) return true;
      sawEpisode = true;
    }
    return !sawEpisode;
  }

  static String directValidationKey(Torrent source) {
    final keys = source.httpHeaders?.keys.toList() ?? <String>[];
    keys.sort();
    return jsonEncode([
      source.directUrl,
      {for (final key in keys) key: source.httpHeaders![key]},
    ]);
  }

  // ── Acquisition URL ────────────────────────────────────────────────────────

  /// True when [t] carries something we can turn into a magnet (real magnet,
  /// infohash, or a .torrent URL). Sync, for filtering candidate lists.
  static bool hasAcquisition(Torrent t) =>
      (t.magnetUrl?.startsWith('magnet:') ?? false) ||
      (t.hasRealInfoHash && t.infohash.isNotEmpty) ||
      (t.torrentUrl?.isNotEmpty ?? false);
}
