import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../../services/imdb_lookup_service.dart';
import '../../services/storage_service.dart';
import '../../services/stremio_service.dart';

/// Service for Stremio TV — channel discovery, time-based rotation, and item loading.
///
/// Turns Stremio addon catalogs into TV-like channels with deterministic
/// "now playing" items that rotate on a configurable schedule.
class StremioTvService {
  static final StremioTvService _instance = StremioTvService._internal();
  static StremioTvService get instance => _instance;
  factory StremioTvService() => _instance;
  StremioTvService._internal();

  final StremioService _stremioService = StremioService.instance;

  // ============================================================================
  // Channel Discovery
  // ============================================================================

  /// Discover all channels from installed catalog addons.
  ///
  /// For catalogs that support genre filtering, each genre becomes its own
  /// channel (e.g., "Popular Movies - Crime", "Popular Movies - Action").
  /// Catalogs without genre support remain as a single channel.
  /// All channels are auto-numbered 1..N. Favorite status is loaded from StorageService.
  Future<List<StremioTvChannel>> discoverChannels() async {
    try {
      final addons = await _stremioService.getCatalogAddons();
      final favoriteIds = await StorageService.getStremioTvFavoriteChannelIds();
      final disabled = await StorageService.getStremioTvDisabledFilters();

      final channels = <StremioTvChannel>[];
      int channelNumber = 1;

      for (final addon in addons) {
        // Skip entire addon if disabled
        if (disabled.contains(addon.id)) continue;

        for (final catalog in addon.catalogs) {

          // Skip catalog if disabled
          final catalogId = '${addon.id}:${catalog.id}:${catalog.type}';
          if (disabled.contains(catalogId)) continue;

          final genres = catalog.genreOptions;

          if (genres.isNotEmpty) {
            // Expand each genre into its own channel
            for (final genre in genres) {
              final id = '$catalogId:$genre';
              // Skip genre if disabled
              if (disabled.contains(id)) continue;
              channels.add(StremioTvChannel.fromCatalog(
                addon: addon,
                catalog: catalog,
                channelNumber: channelNumber++,
                genre: genre,
                isFavorite: favoriteIds.contains(id),
              ));
            }
          } else {
            // No genres — single channel for the catalog
            channels.add(StremioTvChannel.fromCatalog(
              addon: addon,
              catalog: catalog,
              channelNumber: channelNumber++,
              isFavorite: favoriteIds.contains(catalogId),
            ));
          }
        }
      }

      // Append local catalog channels
      final localCatalogs = await StorageService.getStremioTvLocalCatalogs();
      for (final catalog in localCatalogs) {
        final catalogId = catalog['id'] as String? ?? '';
        final catalogName = catalog['name'] as String? ?? 'Unknown';
        final catalogType = catalog['type'] as String? ?? 'movie';
        final channelId = 'local:$catalogId:$catalogType';

        // Skip if disabled (addon-level 'local' or specific channel ID)
        if (disabled.contains('local') || disabled.contains(channelId)) {
          continue;
        }

        final rawItems = catalog['items'] as List<dynamic>? ?? [];
        final items = rawItems
            .whereType<Map<String, dynamic>>()
            .map((json) {
              // Auto-fill type from catalog type if not present in item
              if (!json.containsKey('type')) {
                json = {...json, 'type': catalogType};
              }
              return StremioMeta.fromJson(json);
            })
            .toList();

        if (items.isEmpty) continue;

        channels.add(StremioTvChannel.local(
          catalogId: catalogId,
          catalogName: catalogName,
          catalogType: catalogType,
          channelNumber: channelNumber++,
          items: items,
          isFavorite: favoriteIds.contains(channelId),
        ));
      }

      return channels;
    } catch (e) {
      debugPrint('StremioTvService: Error discovering channels: $e');
      return [];
    }
  }

  /// Get the raw addon→catalog→genre tree for the filter UI.
  /// Returns all addons with their catalogs,
  /// plus a synthetic "Local Catalogs" addon entry.
  Future<List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>>
      getFilterTree() async {
    final addons = await _stremioService.getCatalogAddons();

    final tree = addons.map((addon) {
      return (addon: addon, catalogs: addon.catalogs.toList());
    }).where((entry) => entry.catalogs.isNotEmpty).toList();

    // Append local catalogs as a synthetic addon entry
    final localCatalogs = await StorageService.getStremioTvLocalCatalogs();
    if (localCatalogs.isNotEmpty) {
      final localAddon = StremioAddon(
        id: 'local',
        name: 'Local Catalogs',
        manifestUrl: '',
        baseUrl: '',
      );
      final localCatalogEntries = localCatalogs.map((c) {
        return StremioAddonCatalog(
          id: c['id'] as String? ?? '',
          type: c['type'] as String? ?? 'movie',
          name: c['name'] as String? ?? 'Unknown',
        );
      }).toList();
      tree.add((addon: localAddon, catalogs: localCatalogEntries));
    }

    return tree;
  }

  // ============================================================================
  // Item Loading
  // ============================================================================

  /// Page size used by most Stremio addons.
  static const int _pageSize = 100;

  /// Max number of pages to consider when picking a random page.
  static const int _maxPages = 50;

  /// Load items for a single channel from a random catalog page.
  /// Uses a deterministic hash of the channel ID to pick a page, so the
  /// same channel always loads the same page (until cache expires).
  /// Falls back to page 0 if the random page returns no results.
  /// Caches results for 30 minutes.
  Future<void> loadChannelItems(StremioTvChannel channel) async {
    if (channel.isLocal) return;
    if (!channel.isCacheStale) return;

    try {
      // Pick a deterministic page based on channel ID + day, so the pool rotates daily
      final dayKey = DateTime.now().millisecondsSinceEpoch ~/ (24 * 60 * 60 * 1000);
      final pageHash = _djb2('page:${channel.id}:$dayKey');
      final page = pageHash % _maxPages; // 0.._maxPages-1
      final skip = page * _pageSize;

      List<StremioMeta> items = [];

      if (skip > 0) {
        final fetched = await _stremioService.fetchCatalog(
          channel.addon,
          channel.catalog,
          genre: channel.genre,
          skip: skip,
        );
        items = fetched.toList();
      }

      // Fall back to first page if random page was empty or skip was 0
      if (items.isEmpty) {
        final fetched = await _stremioService.fetchCatalog(
          channel.addon,
          channel.catalog,
          genre: channel.genre,
        );
        items = fetched.toList();
      }

      // Filter out items that don't match the channel's content type
      // (mixed catalogs can return series in movie channels and vice versa)
      items = items.where((m) => m.type == channel.type).toList();

      channel.items = items;
      channel.lastFetched = DateTime.now();
    } catch (e) {
      debugPrint(
        'StremioTvService: Error loading items for ${channel.displayName}: $e',
      );
    }
  }

  /// Load items for all channels in parallel.
  Future<void> loadAllChannelItems(List<StremioTvChannel> channels) async {
    await Future.wait(
      channels.map((ch) => loadChannelItems(ch)),
      eagerError: false,
    );
  }

  // ============================================================================
  // Time-Based Rotation (the "currently playing" algorithm)
  // ============================================================================

  /// DJB2 hash function for deterministic rotation.
  static int _djb2(String input) {
    int hash = 5381;
    for (int i = 0; i < input.length; i++) {
      hash = ((hash << 5) + hash) + input.codeUnitAt(i); // hash * 33 + c
      hash = hash & 0x7FFFFFFF; // Keep positive 31-bit
    }
    return hash;
  }

  /// Per-channel time offset so each channel has independent slot boundaries.
  /// Applies integer mixing after DJB2 to ensure good distribution even for
  /// IDs that differ only in their suffix (e.g., genre years like 1975, 1976).
  static int _channelOffsetMs(String channelId, int slotDurationMs) {
    var h = _djb2(channelId);
    // Murmur3-style finalizer for better bit distribution
    h = (((h >> 16) ^ h) * 0x45d9f3b) & 0x7FFFFFFF;
    h = (((h >> 16) ^ h) * 0x45d9f3b) & 0x7FFFFFFF;
    h = (h >> 16) ^ h;
    return (h % slotDurationMs).abs();
  }

  /// Get the "now playing" item for a channel based on current time.
  ///
  /// Uses time-based hashing so the same channel shows the same item
  /// to everyone within the same time slot.
  /// Each channel's slots are offset independently so they don't all
  /// rotate at the same time.
  /// Returns null if the channel has no items.
  StremioTvNowPlaying? getNowPlaying(
    StremioTvChannel channel, {
    int rotationMinutes = 90,
    int salt = 0,
  }) {
    if (channel.items.isEmpty) return null;

    final now = DateTime.now();
    final slotDurationMs = rotationMinutes * 60 * 1000;
    final offset = _channelOffsetMs(channel.id, slotDurationMs);
    final adjusted = now.millisecondsSinceEpoch - offset;
    final slotNumber = adjusted ~/ slotDurationMs;

    final seed = salt == 0
        ? '${channel.id}:$slotNumber'
        : '${channel.id}:$slotNumber:$salt';
    final hash = _djb2(seed);
    final index = hash % channel.items.length;

    final slotStartMs = slotNumber * slotDurationMs + offset;
    final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMs);
    final slotEnd = DateTime.fromMillisecondsSinceEpoch(
      slotStartMs + slotDurationMs,
    );

    return StremioTvNowPlaying(
      item: channel.items[index],
      itemIndex: index,
      slotStart: slotStart,
      slotEnd: slotEnd,
    );
  }

  /// Get a schedule of N consecutive slot items starting from the current slot.
  ///
  /// Returns a list of [StremioTvNowPlaying] for the current slot plus
  /// the next [count]-1 future slots. Useful for showing a channel guide.
  List<StremioTvNowPlaying> getSchedule(
    StremioTvChannel channel, {
    int count = 5,
    int rotationMinutes = 90,
    int salt = 0,
  }) {
    if (channel.items.isEmpty) return [];

    final now = DateTime.now();
    final slotDurationMs = rotationMinutes * 60 * 1000;
    final offset = _channelOffsetMs(channel.id, slotDurationMs);
    final adjusted = now.millisecondsSinceEpoch - offset;
    final currentSlotNumber = adjusted ~/ slotDurationMs;

    final schedule = <StremioTvNowPlaying>[];
    for (int i = 0; i < count; i++) {
      final slotNumber = currentSlotNumber + i;
      final seed = salt == 0
          ? '${channel.id}:$slotNumber'
          : '${channel.id}:$slotNumber:$salt';
      final hash = _djb2(seed);
      final index = hash % channel.items.length;

      final slotStartMs = slotNumber * slotDurationMs + offset;
      final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMs);
      final slotEnd = DateTime.fromMillisecondsSinceEpoch(
        slotStartMs + slotDurationMs,
      );

      schedule.add(StremioTvNowPlaying(
        item: channel.items[index],
        itemIndex: index,
        slotStart: slotStart,
        slotEnd: slotEnd,
      ));
    }

    return schedule;
  }

  /// Get the next slot's item (for "Up Next" / skip).
  StremioTvNowPlaying? getNextPlaying(
    StremioTvChannel channel, {
    int rotationMinutes = 90,
    int salt = 0,
  }) {
    if (channel.items.isEmpty) return null;

    final now = DateTime.now();
    final slotDurationMs = rotationMinutes * 60 * 1000;
    final offset = _channelOffsetMs(channel.id, slotDurationMs);
    final adjusted = now.millisecondsSinceEpoch - offset;
    final currentSlotNumber = adjusted ~/ slotDurationMs;
    final nextSlotNumber = currentSlotNumber + 1;

    final seed = salt == 0
        ? '${channel.id}:$nextSlotNumber'
        : '${channel.id}:$nextSlotNumber:$salt';
    final hash = _djb2(seed);
    final index = hash % channel.items.length;

    final slotStartMs = nextSlotNumber * slotDurationMs + offset;
    final slotStart = DateTime.fromMillisecondsSinceEpoch(slotStartMs);
    final slotEnd = DateTime.fromMillisecondsSinceEpoch(
      slotStartMs + slotDurationMs,
    );

    return StremioTvNowPlaying(
      item: channel.items[index],
      itemIndex: index,
      slotStart: slotStart,
      slotEnd: slotEnd,
    );
  }

  // ============================================================================
  // Series Episode Resolution
  // ============================================================================

  /// Resolve a deterministic episode for a series item.
  ///
  /// Uses [seed] (typically channelId:slotStart) to pick the same episode
  /// for the same time slot, giving a TV-like deterministic experience.
  ///
  /// Strategy:
  /// 1. If the source addon has a `meta` resource, fetch `/meta/series/{id}.json`
  ///    and pick an episode from the videos array (season > 0) using DJB2 hash.
  /// 2. Fallback: call IMDbbot to get season list, pick a season via DJB2,
  ///    then an episode 1-5 via DJB2. If streams fail, caller can retry with episode 1.
  ///
  /// Returns `({int season, int episode})` or null if resolution fails entirely.
  Future<({int season, int episode})?> resolveRandomEpisode({
    required StremioMeta item,
    required StremioAddon addon,
    required String seed,
  }) async {
    // Try addon's own meta endpoint first (only if it declares meta resource
    // and supports this item's ID prefix to avoid pointless 404s)
    if (addon.resources.contains('meta') &&
        addon.baseUrl.isNotEmpty &&
        addon.supportsContentId(item.id)) {
      final result = await _resolveViaAddonMeta(item, addon, seed);
      if (result != null) return result;
    }

    // Fallback: IMDbbot
    final imdbId = item.effectiveImdbId;
    if (imdbId != null) {
      return _resolveViaImdbBot(imdbId, seed);
    }

    return null;
  }

  /// Try to resolve an episode via the addon's meta endpoint.
  /// Uses DJB2 hash of [seed] for deterministic selection.
  Future<({int season, int episode})?> _resolveViaAddonMeta(
    StremioMeta item,
    StremioAddon addon,
    String seed,
  ) async {
    try {
      final url = '${addon.baseUrl}/meta/series/${Uri.encodeComponent(item.id)}.json';
      debugPrint('StremioTvService: Fetching meta from $url');

      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>?;
      if (data == null) return null;

      final meta = data['meta'] as Map<String, dynamic>?;
      if (meta == null) return null;

      final videos = meta['videos'] as List<dynamic>?;
      if (videos == null || videos.isEmpty) return null;

      // Filter to actual episodes (season > 0) that have aired
      final episodes = videos.where((v) {
        if (v is! Map<String, dynamic>) return false;
        final s = v['season'];
        final seasonNum = s is int ? s : (s is num ? s.toInt() : null);
        if (seasonNum == null || seasonNum <= 0) return false;
        return true;
      }).toList();

      if (episodes.isEmpty) return null;

      // Pick a deterministic episode using DJB2 hash
      final hash = _djb2('episode:$seed');
      final picked = episodes[hash % episodes.length] as Map<String, dynamic>;
      final seasonRaw = picked['season'];
      final season = seasonRaw is int ? seasonRaw : (seasonRaw as num).toInt();
      final episodeRaw = picked['number'] ?? picked['episode'];
      final episode = episodeRaw is int
          ? episodeRaw
          : (episodeRaw is num ? episodeRaw.toInt() : 1);

      debugPrint('StremioTvService: Resolved episode via addon meta: S${season}E$episode');
      return (season: season, episode: episode);
    } catch (e) {
      debugPrint('StremioTvService: Addon meta fetch failed: $e');
      return null;
    }
  }

  /// Fallback: resolve an episode via IMDbbot.
  /// Gets season list, picks a season via DJB2, then episode 1-5 via DJB2.
  Future<({int season, int episode})?> _resolveViaImdbBot(
    String imdbId,
    String seed,
  ) async {
    try {
      final details = await ImdbLookupService.getTitleDetails(imdbId)
          .timeout(const Duration(seconds: 10));
      final seasons = details['main']?['episodes']?['seasons'] as List<dynamic>?;
      if (seasons == null || seasons.isEmpty) return null;

      // Extract season numbers, filter out season 0 (specials)
      final seasonNumbers = seasons
          .map((s) {
            if (s is Map) return s['number'] as int?;
            if (s is int) return s;
            return null;
          })
          .whereType<int>()
          .where((s) => s > 0)
          .toList();

      if (seasonNumbers.isEmpty) return null;

      // Deterministic pick using DJB2
      final seasonHash = _djb2('season:$seed');
      final season = seasonNumbers[seasonHash % seasonNumbers.length];
      final episodeHash = _djb2('episode:$seed');
      final episode = (episodeHash % 5) + 1; // 1-5

      debugPrint('StremioTvService: Resolved episode via IMDbbot: S${season}E$episode');
      return (season: season, episode: episode);
    } catch (e) {
      debugPrint('StremioTvService: IMDbbot fallback failed: $e');
      return null;
    }
  }

  // ============================================================================
  // Stream Search
  // ============================================================================

  /// Search for streams for a given content item.
  /// Delegates to StremioService.searchStreams.
  Future<Map<String, dynamic>> searchStreams({
    required String type,
    required String imdbId,
    int? season,
    int? episode,
  }) async {
    return _stremioService.searchStreams(
      type: type,
      imdbId: imdbId,
      season: season,
      episode: episode,
    );
  }
}
