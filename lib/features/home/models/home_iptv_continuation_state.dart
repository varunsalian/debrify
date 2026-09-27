import '../../../models/iptv_cw_entry.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/continue_watching_presentation.dart';

/// Typed Home projection. Route descriptors retain legacy identity and payloads;
/// progress, episode and remaining-time lookups have no raw-map dependency in UI.
class HomeIptvContinuationState {
  const HomeIptvContinuationState.empty()
    : movies = const [],
      series = const [],
      progress = const {},
      episode = const {},
      remainingMinutes = const {},
      byKey = const {};

  HomeIptvContinuationState.fromRows(IptvCwRows rows)
    : movies = List.unmodifiable(rows.movies.map(_meta)),
      series = List.unmodifiable(rows.series.map(_meta)),
      progress = Map.unmodifiable({
        for (final entry in [...rows.movies, ...rows.series])
          entry.routeKey: entry.progress,
      }),
      episode = Map.unmodifiable({
        for (final entry in [...rows.movies, ...rows.series])
          if (entry.seLabel != null) entry.routeKey: entry.seLabel!,
      }),
      byKey = Map.unmodifiable({
        for (final entry in [...rows.movies, ...rows.series])
          entry.routeKey: entry,
      }),
      remainingMinutes = Map.unmodifiable({
        for (final entry in [...rows.movies, ...rows.series])
          entry.routeKey: continueWatchingMinutesLeft(
            positionMs: (entry.raw['positionMs'] as num?)?.toInt() ?? 0,
            durationMs: (entry.raw['durationMs'] as num?)?.toInt() ?? 0,
          ),
      });

  final List<StremioMeta> movies;
  final List<StremioMeta> series;
  final Map<String, double> progress;
  final Map<String, String> episode;
  final Map<String, int?> remainingMinutes;
  final Map<String, IptvCwEntry> byKey;

  static StremioMeta _meta(IptvCwEntry entry) => StremioMeta(
    id: entry.routeKey,
    type: entry.isSeries ? 'series' : 'movie',
    name: entry.title,
    poster: entry.posterUrl,
  );
}
