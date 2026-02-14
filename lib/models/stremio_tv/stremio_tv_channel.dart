import '../stremio_addon.dart';

/// Represents a Stremio TV "channel" — an addon catalog treated as a TV channel.
///
/// Each installed Stremio catalog addon provides one or more catalogs
/// (e.g., "Popular Movies", "Trending Series"). For catalogs that support
/// genre filtering, each genre becomes its own channel (e.g., "Popular Movies - Crime").
/// Catalogs without genre support remain as a single channel.
class StremioTvChannel {
  /// Deterministic ID: "{addonId}:{catalogId}:{catalogType}" or
  /// "{addonId}:{catalogId}:{catalogType}:{genre}" for genre-specific channels
  final String id;

  /// Display name: "{addonName}: {catalogName}" or
  /// "{addonName}: {catalogName} - {genre}" for genre-specific channels
  final String displayName;

  /// The addon providing this channel
  final StremioAddon addon;

  /// The specific catalog within the addon
  final StremioAddonCatalog catalog;

  /// Genre filter for this channel, or null for unfiltered catalogs
  final String? genre;

  /// Auto-assigned channel number (1-based)
  final int channelNumber;

  /// Whether this channel is favorited by the user
  bool isFavorite;

  /// Whether this channel is backed by a local JSON catalog (not a remote addon)
  final bool isLocal;

  /// Lazily loaded catalog items (cached)
  List<StremioMeta> items;

  /// When items were last fetched (for cache invalidation)
  DateTime? lastFetched;

  StremioTvChannel({
    required this.id,
    required this.displayName,
    required this.addon,
    required this.catalog,
    required this.channelNumber,
    this.genre,
    this.isFavorite = false,
    this.isLocal = false,
    this.items = const [],
    this.lastFetched,
  });

  /// Create from an addon + catalog pair with a channel number.
  /// If [genre] is provided, creates a genre-specific channel.
  factory StremioTvChannel.fromCatalog({
    required StremioAddon addon,
    required StremioAddonCatalog catalog,
    required int channelNumber,
    String? genre,
    bool isFavorite = false,
  }) {
    final baseId = '${addon.id}:${catalog.id}:${catalog.type}';
    final id = genre != null ? '$baseId:$genre' : baseId;
    final baseName = '${addon.name}: ${catalog.name}';
    final displayName = genre != null ? '$baseName - $genre' : baseName;

    return StremioTvChannel(
      id: id,
      displayName: displayName,
      addon: addon,
      catalog: catalog,
      channelNumber: channelNumber,
      genre: genre,
      isFavorite: isFavorite,
    );
  }

  /// Create a local channel from a user-imported JSON catalog.
  factory StremioTvChannel.local({
    required String catalogId,
    required String catalogName,
    required String catalogType,
    required int channelNumber,
    required List<StremioMeta> items,
    bool isFavorite = false,
  }) {
    final addon = StremioAddon(
      id: 'local',
      name: 'Local',
      manifestUrl: '',
      baseUrl: '',
    );
    final catalog = StremioAddonCatalog(
      id: catalogId,
      type: catalogType,
      name: catalogName,
    );
    return StremioTvChannel(
      id: 'local:$catalogId:$catalogType',
      displayName: 'Local: $catalogName',
      addon: addon,
      catalog: catalog,
      channelNumber: channelNumber,
      isLocal: true,
      isFavorite: isFavorite,
      items: items,
      lastFetched: DateTime.now(),
    );
  }

  /// Whether items have been loaded
  bool get hasItems => items.isNotEmpty;

  /// Whether the cache is stale (older than 30 minutes)
  bool get isCacheStale {
    if (lastFetched == null) return true;
    return DateTime.now().difference(lastFetched!).inMinutes >= 30;
  }

  /// Content type from the catalog (e.g., 'movie', 'series')
  String get type => catalog.type;

  @override
  String toString() =>
      'StremioTvChannel(#$channelNumber $displayName, items: ${items.length})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StremioTvChannel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
