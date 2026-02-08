import 'package:flutter/foundation.dart';

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

      final channels = <StremioTvChannel>[];
      int channelNumber = 1;

      // TODO: Add 'series' support later (needs season/episode selection)
      const allowedTypes = {'movie'};

      for (final addon in addons) {
        for (final catalog in addon.catalogs) {
          if (!allowedTypes.contains(catalog.type.toLowerCase())) continue;
          final genres = catalog.genreOptions;

          if (genres.isNotEmpty) {
            // Expand each genre into its own channel
            for (final genre in genres) {
              final id = '${addon.id}:${catalog.id}:${catalog.type}:$genre';
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
            final id = '${addon.id}:${catalog.id}:${catalog.type}';
            channels.add(StremioTvChannel.fromCatalog(
              addon: addon,
              catalog: catalog,
              channelNumber: channelNumber++,
              isFavorite: favoriteIds.contains(id),
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

  // ============================================================================
  // Item Loading
  // ============================================================================

  /// Load items for a single channel from its addon catalog.
  /// Passes the channel's genre filter if set. Caches results for 30 minutes.
  Future<void> loadChannelItems(StremioTvChannel channel) async {
    if (channel.hasItems && !channel.isCacheStale) return;

    try {
      final items = await _stremioService.fetchCatalog(
        channel.addon,
        channel.catalog,
        genre: channel.genre,
      );
      // Only keep items with valid IMDb IDs (needed for stream search)
      channel.items = items.where((m) => m.hasValidImdbId).toList();
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
    int rotationMinutes = 60,
  }) {
    if (channel.items.isEmpty) return null;

    final now = DateTime.now();
    final slotDurationMs = rotationMinutes * 60 * 1000;
    final offset = _channelOffsetMs(channel.id, slotDurationMs);
    final adjusted = now.millisecondsSinceEpoch - offset;
    final slotNumber = adjusted ~/ slotDurationMs;

    final seed = '${channel.id}:$slotNumber';
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

  /// Get the next slot's item (for "Up Next" / skip).
  StremioTvNowPlaying? getNextPlaying(
    StremioTvChannel channel, {
    int rotationMinutes = 60,
  }) {
    if (channel.items.isEmpty) return null;

    final now = DateTime.now();
    final slotDurationMs = rotationMinutes * 60 * 1000;
    final offset = _channelOffsetMs(channel.id, slotDurationMs);
    final adjusted = now.millisecondsSinceEpoch - offset;
    final currentSlotNumber = adjusted ~/ slotDurationMs;
    final nextSlotNumber = currentSlotNumber + 1;

    final seed = '${channel.id}:$nextSlotNumber';
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
