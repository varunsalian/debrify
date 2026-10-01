import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import '../models/source_provider_ref.dart';
import 'source_ordering.dart';
import '../models/indexer_manager_config.dart';
import '../models/torrent.dart';
import 'stremio_service.dart';
import 'torrent_service.dart';
import 'iptv_source_search.dart';
import 'media_server_service.dart';

export '../models/source_provider_ref.dart';

/// Provider-priority ordering for search results.
///
/// The priority list is the user's arranged order of provider keys. An empty
/// list means no explicit reordering: the caller's incoming order is retained.
class SourcePriority {
  SourcePriority._();

  static List<SourceProviderRef> orderedProviders(
    List<SourceProviderRef> providers,
    List<String> stored,
  ) => SourceOrdering.orderedProviders(providers, stored);

  static List<Torrent> directAddonLinksFirst(List<Torrent> torrents) =>
      SourceOrdering.directAddonLinksFirst(torrents);

  static bool isRecommendationOnlyAddon(String addonId) =>
      SourceOrdering.isRecommendationOnlyAddon(addonId);

  static String keyForSource(String source, {Map<String, String>? aliases}) =>
      SourceOrdering.keyForSource(source, aliases: aliases);

  static List<Torrent> order(
    List<Torrent> torrents,
    List<String> priority, {
    Map<String, String>? aliases,
  }) => SourceOrdering.order(torrents, priority, aliases: aliases);

  static List<Torrent> orderAndDedupe(
    List<Torrent> torrents,
    List<String> priority, {
    Map<String, String>? aliases,
  }) => SourceOrdering.orderAndDedupe(torrents, priority, aliases: aliases);

  static List<Torrent> dedupe(List<Torrent> torrents) =>
      SourceOrdering.dedupe(torrents);

  static List<T> orderBy<T>(
    List<T> values,
    String Function(T) keyOf,
    List<String> priority, {
    Map<String, String>? aliases,
  }) => SourceOrdering.orderBy(values, keyOf, priority, aliases: aliases);

  /// Indexer-manager engines stamp results with their display name instead of
  /// their engine id; this maps `display name` → `engine:engineId`.
  static Future<Map<String, String>> sourceAliases() async {
    final aliases = <String, String>{};
    try {
      final engines = await TorrentService.getAvailableEngines();
      for (final e in engines) {
        if (IndexerManagerConfig.isIndexerManagerEngine(e.name)) {
          aliases[e.displayName.trim().toLowerCase()] =
              'engine:${e.name.toLowerCase()}';
        }
      }
    } catch (_) {}
    try {
      final addons = await StremioService.instance.getStreamingAddons();
      for (final addon in addons) {
        aliases[addon.sourceKey] = addon.legacySourceKey;
      }
    } catch (_) {}
    return aliases;
  }

  /// Backwards-compatible name for callers that only need alias warming.
  static Future<Map<String, String>> engineAliases() => sourceAliases();

  /// Every provider a priority list can order, in shipped-default order:
  /// engines (registry order), then streaming addons (install order).
  static Future<List<SourceProviderRef>> providers() async {
    final refs = <SourceProviderRef>[];
    final seen = <String>{};
    try {
      final engines = await TorrentService.getAvailableEngines();
      for (final e in engines) {
        final key = 'engine:${e.name.toLowerCase()}';
        if (seen.add(key)) {
          refs.add(
            SourceProviderRef(key: key, name: e.displayName, isEngine: true),
          );
        }
      }
    } catch (_) {}
    try {
      final addons = await StremioService.instance.getStreamingAddons();
      for (final a in addons) {
        if (isRecommendationOnlyAddon(a.id)) continue;
        final key = a.sourceKey;
        if (seen.add(key)) {
          refs.add(
            SourceProviderRef(
              key: key,
              name: a.displayName,
              isEngine: false,
              legacyKeys: {a.legacySourceKey},
            ),
          );
        }
      }
    } catch (_) {}
    try {
      final playlists = await IptvPlaylistStorage.getIptvPlaylists(
        forSettings: false,
      );
      for (final playlist in playlists.where(
        (p) =>
            !p.credentialsRedacted &&
            !p.isVirtual &&
            !p.isLocalFile &&
            (p.isXtreamCodes || p.url.isNotEmpty),
      )) {
        final key = IptvSourceSearch.keyFor(playlist);
        if (seen.add(key)) {
          refs.add(
            SourceProviderRef(key: key, name: playlist.name, isEngine: false),
          );
        }
      }
    } catch (_) {}
    try {
      for (final server in await MediaServerService.connections()) {
        final key = 'mediaserver:${server.id}'.toLowerCase();
        if (seen.add(key))
          refs.add(
            SourceProviderRef(key: key, name: server.label, isEngine: false),
          );
      }
    } catch (_) {}
    return refs;
  }
}
