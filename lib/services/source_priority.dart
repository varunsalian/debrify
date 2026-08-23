import '../models/indexer_manager_config.dart';
import '../models/torrent.dart';
import 'stremio_service.dart';
import 'torrent_service.dart';

/// One row of the Quick Play "Addon Priority" list: a place results come
/// from — a torrent search engine or a Stremio addon. Users see one flat
/// list; the distinction only matters for key normalization.
class SourceProviderRef {
  final String key; // 'engine:<id>' or 'stremio:<name>', lowercase
  final String name; // display name
  final bool isEngine;

  const SourceProviderRef({
    required this.key,
    required this.name,
    required this.isEngine,
  });
}

/// Provider-priority ordering for search results.
///
/// The priority list is the user's arranged order of provider keys. An empty
/// list means no explicit reordering: the caller's incoming order is retained.
class SourcePriority {
  SourcePriority._();

  /// Put each addon's ready-to-play links ahead of that same addon's
  /// torrent-backed rows. Rows from engines and other addons keep their
  /// original slots, so this does not otherwise change relevance/provider
  /// ordering. Explicit user-selected sorts are applied afterwards.
  static List<Torrent> directAddonLinksFirst(List<Torrent> torrents) {
    if (torrents.length < 2) return torrents;

    final byAddon = <String, List<Torrent>>{};
    for (final torrent in torrents) {
      final key = torrent.source.trim().toLowerCase();
      if (key.startsWith('stremio:')) {
        byAddon.putIfAbsent(key, () => <Torrent>[]).add(torrent);
      }
    }
    if (byAddon.isEmpty) return torrents;

    var changed = false;
    final reordered = <String, List<Torrent>>{};
    for (final entry in byAddon.entries) {
      final direct = entry.value
          .where((torrent) => torrent.streamType == StreamType.directUrl)
          .toList();
      final remaining = entry.value
          .where((torrent) => torrent.streamType != StreamType.directUrl)
          .toList();
      if (direct.isEmpty || remaining.isEmpty) continue;
      final ordered = [...direct, ...remaining];
      if (!changed) {
        for (var i = 0; i < ordered.length; i++) {
          if (!identical(ordered[i], entry.value[i])) {
            changed = true;
            break;
          }
        }
      }
      reordered[entry.key] = ordered;
    }
    if (!changed) return torrents;

    final offsets = <String, int>{};
    return [
      for (final torrent in torrents)
        if (reordered[torrent.source.trim().toLowerCase()] case final rows?)
          rows[offsets.update(
            torrent.source.trim().toLowerCase(),
            (value) => value + 1,
            ifAbsent: () => 0,
          )]
        else
          torrent,
    ];
  }

  /// Addons that use Stremio's stream resource exclusively to return detail
  /// navigation links. They feed recommendation rails, not playable sources,
  /// so they do not belong in scraper priority or source-status controls.
  static bool isRecommendationOnlyAddon(String addonId) =>
      addonId.trim().toLowerCase() == 'community.watch.next';

  /// Normalize a [Torrent.source] value to a priority key. Addon rows carry
  /// `stremio:name`; YAML engines stamp their engine id; indexer-manager
  /// engines stamp their DISPLAY name, which [aliases] maps back to the id.
  static String keyForSource(String source, {Map<String, String>? aliases}) {
    final s = source.trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.startsWith('stremio:')) return s;
    return aliases?[s] ?? 'engine:$s';
  }

  /// Stable, priority-primary reorder. Rows from providers earlier in
  /// [priority] come first; rows from unlisted providers keep their relative
  /// order after all listed ones. Returns [torrents] unchanged when the user
  /// never customized the order.
  static List<Torrent> order(
    List<Torrent> torrents,
    List<String> priority, {
    Map<String, String>? aliases,
  }) {
    if (priority.isEmpty || torrents.length < 2) return torrents;
    final rank = <String, int>{
      for (var i = 0; i < priority.length; i++) priority[i]: i,
    };
    const unlisted = 1 << 20;
    final indexed = List.generate(torrents.length, (i) => i);
    indexed.sort((a, b) {
      final ra =
          rank[keyForSource(torrents[a].source, aliases: aliases)] ?? unlisted;
      final rb =
          rank[keyForSource(torrents[b].source, aliases: aliases)] ?? unlisted;
      if (ra != rb) return ra - rb;
      return a - b; // stable: preserve incoming order within a provider
    });
    return [for (final i in indexed) torrents[i]];
  }

  /// Provider-priority order followed by stable identity dedupe. The first
  /// provider in [priority] wins a shared torrent hash; within each provider,
  /// the exact returned sequence is retained. Direct/external rows already
  /// carry transport-specific synthetic identities, so they remain distinct
  /// from a real torrent row for the same stream.
  static List<Torrent> orderAndDedupe(
    List<Torrent> torrents,
    List<String> priority, {
    Map<String, String>? aliases,
  }) {
    final ordered = order(torrents, priority, aliases: aliases);
    return dedupe(ordered);
  }

  /// Stable identity dedupe without changing the incoming order.
  ///
  /// This is separate from [orderAndDedupe] so callers can remove candidates
  /// that fail strict eligibility checks before choosing which provider's
  /// representation owns a shared torrent hash.
  static List<Torrent> dedupe(List<Torrent> torrents) {
    final seen = <String>{};
    return [
      for (final torrent in torrents)
        if (seen.add(torrent.infohash.toLowerCase())) torrent,
    ];
  }

  /// Ordering for bare provider keys (chips, addon strips). Same contract as
  /// [order]: empty priority = unchanged.
  static List<T> orderBy<T>(
    List<T> values,
    String Function(T) keyOf,
    List<String> priority,
  ) {
    if (priority.isEmpty || values.length < 2) return values;
    final rank = <String, int>{
      for (var i = 0; i < priority.length; i++) priority[i]: i,
    };
    const unlisted = 1 << 20;
    final indexed = List.generate(values.length, (i) => i);
    indexed.sort((a, b) {
      final ra = rank[keyOf(values[a])] ?? unlisted;
      final rb = rank[keyOf(values[b])] ?? unlisted;
      if (ra != rb) return ra - rb;
      return a - b;
    });
    return [for (final i in indexed) values[i]];
  }

  /// Indexer-manager engines stamp results with their display name instead of
  /// their engine id; this maps `display name` → `engine:engineId`.
  static Future<Map<String, String>> engineAliases() async {
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
    return aliases;
  }

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
        final key = 'stremio:${a.name.trim().toLowerCase()}';
        if (seen.add(key)) {
          refs.add(SourceProviderRef(key: key, name: a.name, isEngine: false));
        }
      }
    } catch (_) {}
    return refs;
  }
}
