import '../../../models/playback_meta.dart';
import '../../../models/quick_play_rules.dart';
import '../../../models/torrent.dart';
import '../../../services/torrent_service.dart';
import 'curated_source_search.dart';
import 'webdav_quick_play_search.dart';

/// Provider-free candidates (addon direct links, IPTV, WebDAV) for recovery
/// and for the next episode of a direct-link play. Shared so both paths start
/// the title-based searches beside the addon request and give WebDAV only a
/// short grace once addons already found something.
final class DirectOnlySourceSearch {
  const DirectOnlySourceSearch._();

  /// Null keeps the caller retryable: missing addon-episode identity, or
  /// addon failures that left no playable rows.
  static Future<List<Torrent>?> search({
    required PlaybackMeta meta,
    required String contentId,
    required String title,
    required bool isMovie,
    required int? season,
    required int? episode,
    required QuickPlayRules rules,
  }) async {
    final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
      meta,
      season,
      episode,
    );
    if (meta.hasStremioEpisodeIdentity && originVideoId == null) return null;
    final library = meta.hasStremioEpisodeIdentity
        ? null
        : WebDavQuickPlaySearch.startWithIptv(
            contentId,
            title,
            meta.year,
            isMovie,
            season,
            episode,
            rules,
            null,
          );
    final result = await TorrentService.searchStremioAddonsOnly(
      imdbId: contentId,
      isMovie: isMovie,
      season: isMovie ? null : season,
      episode: isMovie ? null : episode,
      timeout: rules.addonTimeoutSeconds == 15
          ? null
          : Duration(seconds: rules.addonTimeoutSeconds),
      preserveOrder: rules.ranking == QuickPlayRanking.exactOrder,
      originAddonKey: meta.stremioAddonKey,
      originVideoId: originVideoId,
    );
    final list = (result['torrents'] as List)
        .cast<Torrent>()
        .where(
          (t) =>
              t.streamType == StreamType.directUrl &&
              (t.directUrl?.isNotEmpty ?? false),
        )
        .toList();
    if (library != null) {
      list.addAll(
        await WebDavQuickPlaySearch.collect(
          library,
          haveOthers: list.isNotEmpty,
        ),
      );
    }
    // Addon failures are reported in-band. Keep the fetch retryable when
    // they leave this provider-free path no playable rows.
    return list.isEmpty &&
            ((result['addonErrors'] as Map?)?.isNotEmpty ?? false)
        ? null
        : list;
  }
}
