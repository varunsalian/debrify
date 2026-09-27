import '../../../models/stremio_addon.dart';

/// Read-only row membership; metadata descriptors keep their original identity.
class HomeWatchlist {
  const HomeWatchlist.empty() : movies = const [], series = const [];

  HomeWatchlist.fromItems(List<StremioMeta> items)
    : movies = List.unmodifiable([
        for (final item in items)
          if (item.type.toLowerCase() != 'series') item,
      ]),
      series = List.unmodifiable([
        for (final item in items)
          if (item.type.toLowerCase() == 'series') item,
      ]);

  final List<StremioMeta> movies;
  final List<StremioMeta> series;
}
