import 'dart:async';

import 'package:debrify/features/sources/data/source_file_ordering.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/source_playlist_resolver.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/material.dart';

export 'package:debrify/services/video_player_launcher.dart'
    show VideoPlayerLaunchArgsWidget;

final class SourcePlayerArgs {
  const SourcePlayerArgs._();

  /// Shared meta → player-args plumbing. ONE place builds the content-identity
  /// fields for every push site — a field missed at a single site would
  /// silently break Continue Watching / scrobble / Next Episode for that entry
  /// path only.
  static VideoPlayerLaunchArgs playerArgs({
    required String videoUrl,
    required String title,
    String? subtitle,
    List<PlaylistEntry>? playlist,
    int? startIndex,
    List<Torrent>? stremioSources,
    int? stremioCurrentSourceIndex,
    SourcePlaylistResolve? resolveSourceToPlaylist,
    bool startupFailoverEnabled = false,
    String? startupResolverProvider,
    Future<void> Function(Torrent)? onStremioSourceCommitted,
    Future<void> Function()? onStartupSourcesExhausted,
    bool startupHasRemainingSavedSources = false,
    SeriesSourceFetcher? seriesSourceFetcher,
    PlaybackMeta? meta,
    String? rdTorrentId,
    int? torboxTorrentId,
    PlaylistViewMode? viewMode,
    Map<String, String>? httpHeaders,
  }) => VideoPlayerLaunchArgs(
    // External apps receive only the URL, not media-server session headers.
    // Continuous shuffle also needs the in-app episode-fetch/EOF callbacks.
    disableExternalPlayer:
        (meta?.initialContinuousShuffle ?? false) ||
        (httpHeaders?.keys.any((key) => key.toLowerCase() == 'x-emby-token') ??
            false),
    initialContinuousShuffle: meta?.initialContinuousShuffle ?? false,
    videoUrl: videoUrl,
    httpHeaders: httpHeaders,
    title: title,
    subtitle: subtitle,
    playlist: playlist,
    startIndex: startIndex,
    viewMode: viewMode,
    stremioSources: stremioSources,
    stremioCurrentSourceIndex: stremioCurrentSourceIndex,
    resolveSourceToPlaylist: resolveSourceToPlaylist,
    startupFailoverEnabled: startupFailoverEnabled,
    startupResolverProvider: startupResolverProvider,
    onStremioSourceCommitted: onStremioSourceCommitted,
    onStartupSourcesExhausted: onStartupSourcesExhausted,
    startupHasRemainingSavedSources: startupHasRemainingSavedSources,
    seriesSourceFetcher: seriesSourceFetcher,
    contentImdbId: meta?.progressIdentity,
    contentType: meta?.contentType,
    contentSeason: meta?.season,
    contentEpisode: meta?.episode,
    contentTitle: meta?.title,
    posterUrl: meta?.posterUrl,
    contentYear: meta?.year,
    addonId: meta?.addonId,
    suppressTrackerAutoSync: meta?.hasStremioEpisodeIdentity ?? false,
    traktScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.traktScrobble ?? false,
    traktProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.traktProgressPercent,
    simklScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.simklScrobble ?? false,
    simklProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.simklProgressPercent,
    mdblistScrobble: meta?.hasStremioEpisodeIdentity == true
        ? false
        : meta?.mdblistScrobble ?? false,
    mdblistProgressPercent: meta?.hasStremioEpisodeIdentity == true
        ? null
        : meta?.mdblistProgressPercent,
    resumePolicy: meta?.resumePolicy ?? PlaybackResumePolicy.sourceSpecific,
    // Debrid torrent ids let the player back-fill poster/IMDb onto a saved
    // Playlist-library entry and power the in-player "Fix Metadata" action
    // (matching Home). PikPak is intentionally omitted: the launcher wants a
    // collection/folder id, but _Resolved only carries a per-file id.
    rdTorrentId: rdTorrentId,
    torboxTorrentId: torboxTorrentId?.toString(),
  );

  @visibleForTesting
  static VideoPlayerLaunchArgs playerArgsForTesting(
    PlaybackMeta? meta, {
    Map<String, String>? httpHeaders,
  }) => playerArgs(
    videoUrl: 'video',
    title: 'Title',
    meta: meta,
    httpHeaders: httpHeaders,
  );

  // ── File pickers: largest file that looks like video ───────────────────────

  /// True when a resolved playlist's file names look like a TV series (multiple
  /// files parseable as season/episode), so it should play in series view mode.
  static bool isSeriesPlaylist(List<PlaylistEntry> entries) {
    if (entries.length <= 1) return false;
    final names = [for (final e in entries) sourceFileName(e.title)];
    return SeriesParser.isSeriesPlaylist(names);
  }
}
