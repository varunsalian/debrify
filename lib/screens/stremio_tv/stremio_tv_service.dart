import 'package:flutter/foundation.dart';

import '../../models/stremio_addon.dart';
import '../../models/stremio_tv/stremio_tv_channel.dart';
import '../../models/stremio_tv/stremio_tv_now_playing.dart';
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

      // Block series for now (needs season/episode selection)
      const blockedTypes = {'series'};

      for (final addon in addons) {
        // Skip entire addon if disabled
        if (disabled.contains(addon.id)) continue;

        for (final catalog in addon.catalogs) {
          if (blockedTypes.contains(catalog.type.toLowerCase())) continue;

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

      return channels;
    } catch (e) {
      debugPrint('StremioTvService: Error discovering channels: $e');
      return [];
    }
  }

  /// Get the raw addon→catalog→genre tree for the filter UI.
  /// Returns all addons with their catalogs (excluding series type).
  Future<List<({StremioAddon addon, List<StremioAddonCatalog> catalogs})>>
      getFilterTree() async {
    final addons = await _stremioService.getCatalogAddons();
    const blockedTypes = {'series'};

    return addons.map((addon) {
      final catalogs = addon.catalogs
          .where((c) => !blockedTypes.contains(c.type.toLowerCase()))
          .toList();
      return (addon: addon, catalogs: catalogs);
    }).where((entry) => entry.catalogs.isNotEmpty).toList();
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
    if (!channel.isCacheStale) return;

    try {
      // Pick a deterministic page based on channel ID
      final pageHash = _djb2('page:${channel.id}');
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
