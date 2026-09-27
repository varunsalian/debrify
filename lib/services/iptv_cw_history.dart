import '../models/iptv_cw_entry.dart';

/// Reads recency-ordered watch history and collapses series to their newest
/// episode. Pure data access: no navigation, playback, writes, cache or retry.
class IptvCwHistory {
  const IptvCwHistory({
    required Future<List<Map<String, dynamic>>> Function() readHistory,
  }) : _readHistory = readHistory;

  final Future<List<Map<String, dynamic>>> Function() _readHistory;

  Future<IptvCwRows> load() async {
    final items = await _readHistory();
    if (items.isEmpty) return const IptvCwRows(movies: [], series: []);

    final movies = <IptvCwEntry>[];
    final series = <IptvCwEntry>[];
    final seenSeries = <String>{};

    for (final item in items) {
      // Detach the routing fields and headers read by the legacy bridge.
      final raw = Map<String, dynamic>.unmodifiable({
        ...item,
        if (item['httpHeaders'] case final Map headers)
          'httpHeaders': Map.unmodifiable(headers),
      });
      final seriesId = item['seriesId'] as String?;
      final isSeries = seriesId != null && seriesId.isNotEmpty;
      final progress = ((item['progress'] as num?)?.toDouble() ?? 0.0).clamp(
        0.0,
        1.0,
      );

      if (isSeries) {
        final originId = (item['playlistId'] as String?) ?? '';
        final seriesKey =
            (item['_seriesKey'] as String?) ?? '$originId::$seriesId';
        // The list is already most-recent-first, so the first episode we see
        // for a series is the one to resume.
        if (!seenSeries.add(seriesKey)) continue;
        series.add(
          IptvCwEntry(
            routeKey: 'xtream-series://$originId/$seriesId',
            title:
                _firstNonEmpty([
                  item['seriesName'] as String?,
                  item['group'] as String?,
                  item['name'] as String?,
                ]) ??
                'Series',
            posterUrl: _nonEmpty(item['logoUrl'] as String?),
            subtitle: 'IPTV',
            isSeries: true,
            progress: progress,
            seLabel: _seLabel(item['season'], item['episode']),
            raw: raw,
          ),
        );
      } else {
        movies.add(
          IptvCwEntry(
            routeKey: (item['url'] as String?) ?? '',
            title: _nonEmpty(item['name'] as String?) ?? 'IPTV',
            posterUrl: _nonEmpty(item['logoUrl'] as String?),
            subtitle: _nonEmpty(item['group'] as String?) ?? 'IPTV',
            isSeries: false,
            progress: progress,
            seLabel: null,
            raw: raw,
          ),
        );
      }
    }

    return IptvCwRows(
      movies: List.unmodifiable(movies),
      series: List.unmodifiable(series),
    );
  }

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      if (c != null && c.isNotEmpty) return c;
    }
    return null;
  }

  static String? _seLabel(Object? season, Object? episode) {
    final s = (season as num?)?.toInt();
    final e = (episode as num?)?.toInt();
    if (s == null && e == null) return null;
    final parts = <String>[];
    if (s != null) parts.add('S$s');
    if (e != null) parts.add('E$e');
    return parts.join(' · ');
  }
}
