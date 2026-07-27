import 'package:flutter/material.dart';

import '../models/iptv_playlist.dart';
import '../models/playlist_view_mode.dart';
import '../screens/iptv/xtream_series_detail.dart';
import 'storage_service.dart';
import 'video_player_launcher.dart';

/// One row of the IPTV Continue Watching shelves on Home. A movie/VOD entry
/// resumes playback directly; a series entry opens the merged Xtream series
/// page (whose episode list / Resume does the playing).
///
/// This mirrors — but does NOT reuse — the routing inside `iptv_results_view`
/// (which is coupled to that widget's preview/re-arm/playlist state). Keeping a
/// standalone router means the Home shelves add no risk to the committed IPTV
/// page: the two just share the same public building blocks
/// ([StorageService.getIptvContinueWatching], [openXtreamSeries],
/// [VideoPlayerLauncher]).
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

class IptvCwRouter {
  /// Load the IPTV Continue Watching entries, split into Movies and Series.
  ///
  /// [StorageService.getIptvContinueWatching] returns one entry per episode,
  /// most-recent-first; a series is collapsed here to a single row (its
  /// most-recent watched episode wins, matching the IPTV page's shelf).
  static Future<IptvCwRows> load() async {
    final items = await StorageService.getIptvContinueWatching();
    if (items.isEmpty) return const IptvCwRows(movies: [], series: []);

    final movies = <IptvCwEntry>[];
    final series = <IptvCwEntry>[];
    final seenSeries = <String>{};

    for (final item in items) {
      final seriesId = item['seriesId'] as String?;
      final isSeries = seriesId != null && seriesId.isNotEmpty;
      final progress =
          ((item['progress'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0);

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
            title: _firstNonEmpty([
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
            raw: item,
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
            raw: item,
          ),
        );
      }
    }

    return IptvCwRows(movies: movies, series: series);
  }

  /// Open an entry: a series routes to the merged Xtream series page; a movie
  /// resumes playback (the player restores its own position by URL).
  static Future<void> open(
    BuildContext context,
    IptvCwEntry entry, {
    required bool isTelevision,
  }) async {
    if (entry.isSeries) {
      await _openSeries(context, entry, isTelevision: isTelevision);
    } else {
      await _playMovie(context, entry);
    }
  }

  static Future<void> _openSeries(
    BuildContext context,
    IptvCwEntry entry, {
    required bool isTelevision,
  }) async {
    final seriesId = (entry.raw['seriesId'] as String?) ?? '';
    final originId = (entry.raw['playlistId'] as String?) ?? '';
    if (seriesId.isEmpty) return;

    // Resolve the series' real Xtream provider from the stored origin id — the
    // shelf entry is provider-agnostic, so we can't assume any "selected"
    // playlist like the IPTV page can.
    final playlists = await StorageService.getIptvPlaylists();
    if (!context.mounted) return;
    IptvPlaylist? origin;
    for (final p in playlists) {
      if (p.id == originId && p.isXtreamCodes) {
        origin = p;
        break;
      }
    }
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This series' provider is no longer available"),
        ),
      );
      return;
    }

    final channel = IptvChannel(
      name: entry.title,
      // `openXtreamSeries` reads the id from the `series_id` attribute first
      // (the composite sentinel URL is only a fallback), so stamp it here.
      url: entry.routeKey,
      logoUrl: entry.posterUrl,
      group: entry.title,
      contentType: 'series',
      attributes: {
        'series_id': seriesId,
        if (originId.isNotEmpty) 'series_playlist_id': originId,
      },
    );

    await openXtreamSeries(
      context,
      playlist: origin,
      series: channel,
      isTelevision: isTelevision,
    );
  }

  static Future<void> _playMovie(
    BuildContext context,
    IptvCwEntry entry,
  ) async {
    final url = (entry.raw['url'] as String?) ?? '';
    if (url.isEmpty) return;

    final headers = _headersOf(entry.raw['httpHeaders']);
    final channel = IptvChannel(
      name: entry.title,
      url: url,
      logoUrl: entry.posterUrl,
      group: _nonEmpty(entry.raw['group'] as String?),
      contentType: 'vod',
      httpHeaders: headers ?? const {},
    );

    // Bump recency before launch — the player process can be killed outright on
    // TV, and re-recording keeps the shelf ordering right in that case (the
    // player also re-records its final position on a clean exit).
    await StorageService.recordIptvWatch(
      url,
      channelName: channel.name,
      logoUrl: channel.logoUrl,
      group: channel.group,
      playlistId: entry.raw['playlistId'] as String?,
      httpHeaders: headers,
    );
    if (!context.mounted) return;

    await VideoPlayerLauncher.push(
      context,
      VideoPlayerLaunchArgs(
        videoUrl: url,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: [channel],
        iptvStartIndex: 0,
        httpHeaders: channel.playbackHeaders,
      ),
    );
  }

  static Map<String, String>? _headersOf(Object? raw) {
    if (raw is! Map) return null;
    final out = <String, String>{};
    raw.forEach((k, v) {
      if (k is String && v != null) out[k] = v.toString();
    });
    return out.isEmpty ? null : out;
  }

  static String? _nonEmpty(String? s) =>
      (s == null || s.isEmpty) ? null : s;

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
