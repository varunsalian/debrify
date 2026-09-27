/// Stable IPTV continuation identity and display fields. The original routing
/// payload is retained for the legacy playback/removal bridge.
class IptvCwEntry {
  /// Stable identity for this row — the item URL for a movie, the collapsed
  /// `xtream-series://<originId>/<seriesId>` sentinel for a series. Used as the
  /// synthetic meta id (so Home's card/focus keying stays 1:1 with the row).
  final String routeKey;
  final String title;
  final String? posterUrl;

  /// 'IPTV' or the channel group — the small subtitle under the card.
  final String? subtitle;
  final bool isSeries;

  /// Watched fraction 0..1 (a finished-with-next series episode reads ~1.0).
  final double progress;

  /// 'S2 · E5' for a series row (null for movies / when unknown).
  final String? seLabel;

  /// The original Continue Watching map, kept for routing (origin provider id,
  /// headers, series id, etc.).
  final Map<String, dynamic> raw;

  const IptvCwEntry({
    required this.routeKey,
    required this.title,
    required this.posterUrl,
    required this.subtitle,
    required this.isSeries,
    required this.progress,
    required this.seLabel,
    required this.raw,
  });
}

/// The two IPTV Continue Watching shelves, split by content type.
class IptvCwRows {
  final List<IptvCwEntry> movies;
  final List<IptvCwEntry> series;
  const IptvCwRows({required this.movies, required this.series});

  bool get isEmpty => movies.isEmpty && series.isEmpty;
}
