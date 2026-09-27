import '../../../models/stremio_addon.dart';

/// Home owns membership and channel identity, never the service's mutable cache.
/// Metadata descriptors are borrowed; Home only reads their final display fields.
class HomeStremioFavorite {
  HomeStremioFavorite({
    required this.id,
    required this.displayName,
    required this.type,
    required List<StremioMeta> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String displayName;
  final String type;
  final List<StremioMeta> items;
}

class HomeStremioFavorites {
  HomeStremioFavorites({
    required List<HomeStremioFavorite> channels,
    required this.rotationMinutes,
    required this.seriesRotationMinutes,
  }) : channels = List.unmodifiable(channels);

  const HomeStremioFavorites.empty()
    : channels = const [],
      rotationMinutes = 90,
      seriesRotationMinutes = 45;

  final List<HomeStremioFavorite> channels;
  final int rotationMinutes;
  final int seriesRotationMinutes;

  HomeStremioFavorites withoutChannels() => HomeStremioFavorites(
    channels: const [],
    rotationMinutes: rotationMinutes,
    seriesRotationMinutes: seriesRotationMinutes,
  );
}
