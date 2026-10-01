import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/iptv_playlist_storage.dart';
import 'package:flutter/material.dart';

import '../models/iptv_playlist.dart';
import '../models/playlist_view_mode.dart';
import '../screens/iptv/xtream_series_detail.dart';
import '../models/iptv_cw_entry.dart';
import 'iptv_cw_history.dart';

import 'video_player_launcher.dart';

export '../models/iptv_cw_entry.dart';

/// Legacy presentation routing for IPTV continuation cards.
class IptvCwRouter {
  /// Load the IPTV Continue Watching entries, split into Movies and Series.
  ///
  /// [StorageService.getIptvContinueWatching] returns one entry per episode,
  /// most-recent-first; a series is collapsed here to a single row (its
  /// most-recent watched episode wins, matching the IPTV page's shelf).
  static Future<IptvCwRows> load() => IptvCwHistory(
    readHistory: IptvHistoryStorage.getIptvContinueWatching,
  ).load();

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
    final playlists = await IptvPlaylistStorage.getIptvPlaylists(
      forSettings: false,
    );
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
    await IptvHistoryStorage.recordIptvWatch(
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

  static String? _nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
}
