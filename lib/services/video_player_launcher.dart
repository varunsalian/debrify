import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/iptv_playlist.dart';
import '../models/movie_collection.dart';
import '../models/torrent.dart';
import '../services/external_player_service.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../models/stremio_subtitle.dart';
import '../screens/video_player_screen.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/debrid_service.dart';
import '../services/main_page_bridge.dart';
import '../services/next_episode_service.dart';
import '../services/analytics_service.dart';
import '../services/series_source_fetcher.dart';
import '../services/storage_service.dart';
import '../services/torbox_service.dart';
import '../services/pikpak_api_service.dart';
import '../services/premiumize_service.dart';
import '../services/alldebrid_service.dart';
import '../utils/episode_progress_merge.dart';
import '../utils/series_parser.dart';
import '../utils/movie_parser.dart';
import '../services/movie_metadata_service.dart';
import '../services/trakt/trakt_service.dart';
import '../services/simkl/simkl_service.dart';

/// Trakt scrobble dedup guard for Android TV player (mirrors _traktLastScrobbleAction in VideoPlayerScreen)
String? _traktLastScrobbleAction;
double _traktLastKnownProgress = 0.0;
int? _traktLastKnownSeason;
int? _traktLastKnownEpisode;
Timer? _traktHeartbeatTimer;

/// Simkl scrobble state — fully parallel mirror of the Trakt vars above
/// (independent dedup guard + heartbeat; the two trackers never share state).
String? _simklLastScrobbleAction;
double _simklLastKnownProgress = 0.0;
int? _simklLastKnownSeason;
int? _simklLastKnownEpisode;
Timer? _simklHeartbeatTimer;

final Map<String, String> _resolvedStreamCache = <String, String>{};
final Map<String, String> _redirectCache = <String, String>{};

void _cacheResolvedStream(String? resumeId, String url) {
  if (resumeId == null) return;
  if (url.isEmpty) return;
  _resolvedStreamCache[resumeId] = url;
}

/// Resolve redirects for a URL (for TV player HLS streams).
/// Returns the final URL after following redirects, or original URL if no redirect.
/// Only resolves URLs that look like they might be short redirect URLs.
Future<String> _resolveRedirectUrl(String url) async {
  debugPrint('[RedirectResolver] Input URL: $url');

  // Check cache first
  if (_redirectCache.containsKey(url)) {
    final cached = _redirectCache[url]!;
    debugPrint('[RedirectResolver] Cache HIT: $url -> $cached');
    return cached;
  }
  debugPrint('[RedirectResolver] Cache MISS, checking URL...');

  // Skip resolution for URLs that are unlikely to be redirects:
  // - Already have media extensions
  // - Known debrid CDN domains
  final uri = Uri.tryParse(url);
  if (uri == null) {
    debugPrint('[RedirectResolver] SKIP: Invalid URL, using original');
    return url;
  }

  final path = uri.path.toLowerCase();
  final host = uri.host.toLowerCase();
  debugPrint('[RedirectResolver] Host: $host, Path: $path');

  // Skip if already has a media extension
  if (path.endsWith('.m3u8') ||
      path.endsWith('.mp4') ||
      path.endsWith('.mkv') ||
      path.endsWith('.ts') ||
      path.endsWith('.mpd')) {
    debugPrint('[RedirectResolver] SKIP: Has media extension, using original');
    return url;
  }

  // Skip known debrid CDN domains (they don't redirect)
  if (host.contains('real-debrid') ||
      host.contains('torbox') ||
      host.contains('pikpak') ||
      host.contains('1fichier') ||
      host.contains('rapidgator')) {
    debugPrint(
      '[RedirectResolver] SKIP: Known debrid CDN domain, using original',
    );
    return url;
  }

  debugPrint(
    '[RedirectResolver] Attempting HEAD request to resolve redirects...',
  );

  try {
    // Use a client that doesn't follow redirects automatically
    final client = http.Client();
    try {
      final request = http.Request('HEAD', uri);
      request.followRedirects = false;
      request.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 5));

      debugPrint('[RedirectResolver] Response status: ${response.statusCode}');
      debugPrint('[RedirectResolver] Response headers: ${response.headers}');

      // Check if it's a redirect
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        debugPrint('[RedirectResolver] Redirect detected! Location: $location');

        if (location != null && location.isNotEmpty) {
          // Handle relative URLs
          final resolvedUri = uri.resolve(location);
          final resolvedUrl = resolvedUri.toString();
          debugPrint(
            '[RedirectResolver] SUCCESS: Resolved $url -> $resolvedUrl',
          );

          // Cache the result
          _redirectCache[url] = resolvedUrl;
          return resolvedUrl;
        } else {
          debugPrint(
            '[RedirectResolver] WARNING: Redirect but no Location header',
          );
        }
      } else {
        debugPrint(
          '[RedirectResolver] No redirect (status ${response.statusCode}), using original',
        );
      }
    } finally {
      client.close();
    }
  } catch (e) {
    debugPrint('[RedirectResolver] ERROR: $e');
    debugPrint('[RedirectResolver] Falling back to original URL');
  }

  // No redirect or error - use original URL
  _redirectCache[url] = url;
  debugPrint('[RedirectResolver] Final URL (no change): $url');
  return url;
}

void _clearResolvedStreams(Iterable<String?> resumeIds) {
  for (final id in resumeIds) {
    if (id == null) continue;
    _resolvedStreamCache.remove(id);
  }
}

class VideoPlayerLaunchArgs {
  final String videoUrl;

  /// Optional separate audio track to play alongside [videoUrl] (used for
  /// high-res YouTube, where video and audio are served as separate streams).
  final String? audioUrl;

  /// Optional muxed stream (already has audio) used as a never-silent fallback
  /// on Android TV, where [videoUrl] may be a video-only HD track.
  final String? fallbackUrl;
  final String title;
  final String? subtitle;
  final List<PlaylistEntry>? playlist;
  final int? startIndex;
  final String? rdTorrentId;
  final String? torboxTorrentId;
  final String? pikpakCollectionId;
  final String? webDavServerId;
  final String? webDavBaseUrl;
  final String? webDavPath;
  final Future<Map<String, String>?> Function()? requestMagicNext;
  final Future<Map<String, dynamic>?> Function()? requestNextChannel;
  final bool startFromRandom;
  final int randomStartMaxPercent;
  final double? startAtPercent;
  final bool hideSeekbar;
  final bool showChannelName;
  final String? channelName;
  final int? channelNumber;
  final bool showVideoTitle;
  final bool hideOptions;
  final bool hideBackButton;
  final Map<String, String>? httpHeaders;
  final bool disableExternalPlayer;
  final bool Function()? isAndroidTvOverride;
  final bool disableAutoResume;
  final PlaylistViewMode? viewMode;
  // Content metadata for fetching external subtitles from Stremio addons
  final String? contentImdbId;
  final String? contentType; // 'movie' or 'series'
  final int? contentSeason;
  final int? contentEpisode;
  // IPTV channel list for in-player channel switching
  final List<IptvChannel>? iptvChannels;
  final int? iptvStartIndex;

  /// The source's FULL category list, in provider order. Without it the player
  /// derived categories from the windowed (~1500) channel list, so the picker
  /// only ever showed the handful of groups in that window.
  final List<String>? iptvCategories;
  final String? iptvSourceId;
  final String? iptvSourceName;
  final String? iptvSelectedCategory;
  final String? iptvContentType;
  final List<Map<String, dynamic>>? iptvSources;
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic>)?
  iptvBrowseProvider;
  // Stremio sources for in-player source switching
  final List<Torrent>? stremioSources;
  final int? stremioCurrentSourceIndex;
  final Future<String?> Function(Torrent)? resolveStremioSource;
  // Torrent search source switching: resolves a Torrent to a full playlist
  final Future<List<PlaylistEntry>?> Function(Torrent)? resolveSourceToPlaylist;
  // Series source tabs: on-demand "Load more sources" fetcher for the
  // pack/episode split. Non-null only for series plays with a searchable id.
  final SeriesSourceFetcher? seriesSourceFetcher;
  // Stremio TV in-player channel guide
  final List<Map<String, dynamic>>? stremioTvChannels;
  final String? stremioTvCurrentChannelId;
  final int? stremioTvRotationMinutes;
  final int? stremioTvSeriesRotationMinutes;
  final int? stremioTvMixSalt;
  final Future<Map<String, dynamic>?> Function(List<String>)?
  stremioTvGuideDataProvider;
  final Future<Map<String, dynamic>?> Function(String)?
  stremioTvChannelSwitchProvider;
  final Future<Map<String, dynamic>?> Function(String)? stremioTvNextProvider;
  // Trakt scrobble: send playback progress to Trakt
  final bool traktScrobble;
  // Prevent launcher-level Trakt auto-sync upgrade for playlist-origin playback.
  // Context-scoped, not Trakt-specific: contexts that suppress Trakt auto-sync
  // (playlists, Stremio TV) suppress the Simkl auto-sync upgrade too.
  final bool suppressTraktAutoSync;
  // Trakt progress: resume fallback when no local resume exists (0-100)
  final double? traktProgressPercent;
  // Simkl scrobble/progress — fully parallel to the Trakt pair above.
  final bool simklScrobble;
  final double? simklProgressPercent;
  // Continue watching metadata (for home screen section)
  final String? contentTitle; // Clean display name (IMDB title)
  final String? posterUrl;
  final String? contentYear;
  final String? addonId; // Stremio addon used for playback

  /// Subtitle tracks known at launch time, surfaced in the player's subtitle
  /// menu as a pre-loaded provider group (no addon fetch needed). Used for
  /// sources that carry their own captions — e.g. YouTube closed captions —
  /// where the IMDb-keyed addon fetch never runs.
  final List<StremioSubtitle>? initialSubtitles;

  const VideoPlayerLaunchArgs({
    required this.videoUrl,
    this.audioUrl,
    this.fallbackUrl,
    required this.title,
    this.subtitle,
    this.playlist,
    this.startIndex,
    this.rdTorrentId,
    this.torboxTorrentId,
    this.pikpakCollectionId,
    this.webDavServerId,
    this.webDavBaseUrl,
    this.webDavPath,
    this.requestMagicNext,
    this.requestNextChannel,
    this.startFromRandom = false,
    this.randomStartMaxPercent = 40,
    this.startAtPercent,
    this.hideSeekbar = false,
    this.showChannelName = false,
    this.channelName,
    this.channelNumber,
    this.showVideoTitle = true,
    this.hideOptions = false,
    this.hideBackButton = false,
    this.httpHeaders,
    this.disableExternalPlayer = false,
    this.isAndroidTvOverride,
    this.disableAutoResume = false,
    this.viewMode,
    this.contentImdbId,
    this.contentType,
    this.contentSeason,
    this.contentEpisode,
    this.iptvChannels,
    this.iptvStartIndex,
    this.iptvCategories,
    this.iptvSourceId,
    this.iptvSourceName,
    this.iptvSelectedCategory,
    this.iptvContentType,
    this.iptvSources,
    this.iptvBrowseProvider,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.resolveStremioSource,
    this.resolveSourceToPlaylist,
    this.seriesSourceFetcher,
    this.stremioTvChannels,
    this.stremioTvCurrentChannelId,
    this.stremioTvRotationMinutes,
    this.stremioTvSeriesRotationMinutes,
    this.stremioTvMixSalt,
    this.stremioTvGuideDataProvider,
    this.stremioTvChannelSwitchProvider,
    this.stremioTvNextProvider,
    this.traktScrobble = false,
    this.suppressTraktAutoSync = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.contentTitle,
    this.posterUrl,
    this.contentYear,
    this.addonId,
    this.initialSubtitles,
  });

  VideoPlayerScreen toWidget() {
    return VideoPlayerScreen(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      title: title,
      subtitle: subtitle,
      playlist: playlist,
      startIndex: startIndex,
      rdTorrentId: rdTorrentId,
      torboxTorrentId: torboxTorrentId,
      pikpakCollectionId: pikpakCollectionId,
      requestMagicNext: requestMagicNext,
      requestNextChannel: requestNextChannel,
      startFromRandom: startFromRandom,
      randomStartMaxPercent: randomStartMaxPercent,
      startAtPercent: startAtPercent,
      hideSeekbar: hideSeekbar,
      showChannelName: showChannelName,
      channelName: channelName,
      channelNumber: channelNumber,
      showVideoTitle: showVideoTitle,
      hideOptions: hideOptions,
      hideBackButton: hideBackButton,
      httpHeaders: httpHeaders,
      disableAutoResume: disableAutoResume,
      viewMode: viewMode,
      contentImdbId: contentImdbId,
      contentType: contentType,
      contentSeason: contentSeason,
      contentEpisode: contentEpisode,
      contentTitle: contentTitle,
      iptvChannels: iptvChannels,
      iptvStartIndex: iptvStartIndex,
      stremioSources: stremioSources,
      stremioCurrentSourceIndex: stremioCurrentSourceIndex,
      resolveStremioSource: resolveStremioSource,
      resolveSourceToPlaylist: resolveSourceToPlaylist,
      seriesSourceFetcher: seriesSourceFetcher,
      stremioTvChannels: stremioTvChannels,
      stremioTvCurrentChannelId: stremioTvCurrentChannelId,
      stremioTvGuideDataProvider: stremioTvGuideDataProvider,
      stremioTvChannelSwitchProvider: stremioTvChannelSwitchProvider,
      stremioTvNextProvider: stremioTvNextProvider,
      traktScrobble: traktScrobble,
      traktProgressPercent: traktProgressPercent,
      simklScrobble: simklScrobble,
      simklProgressPercent: simklProgressPercent,
      initialSubtitles: initialSubtitles,
    );
  }
}

class VideoPlayerLauncher {
  /// Generate a resume key for a playlist entry.
  /// Used to pre-populate playback state (e.g., from Trakt progress).
  static String resumeIdForEntry(
    PlaylistEntry entry, {
    String fallbackTitle = '',
  }) {
    final provider = entry.provider?.toLowerCase();
    // Torbox
    if (provider == 'torbox') {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (webDownloadId != null && fileId != null) {
        return 'torbox_web_${webDownloadId}_$fileId';
      }
      if (torrentId != null && fileId != null) {
        return 'torbox_${torrentId}_$fileId';
      }
    }
    // PikPak
    if (provider == 'pikpak') {
      final fileId = entry.pikpakFileId;
      if (fileId != null && fileId.isNotEmpty) {
        return 'pikpak_$fileId';
      }
    }
    // Fallback: filename hash
    final name = entry.title.isNotEmpty ? entry.title : fallbackTitle;
    final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]*$'), '');
    return nameWithoutExt.hashCode.toString();
  }

  /// Seed the local finished-episodes store from Trakt watched history so the
  /// in-player playlist (SeriesBrowser, which reads local playback state) shows
  /// Trakt-watched episodes. Runs on every series launch that has an IMDb id;
  /// a no-op when Trakt isn't connected or has nothing for the show. Only fully
  /// watched (>=95%) episodes are written — partial progress is left to the
  /// per-episode `traktProgressPercent` resume so we never store a fake
  /// position/duration. Best-effort: any failure is swallowed.
  static Future<void> _seedTraktWatchedEpisodes(
    List<PlaylistEntry> playlist,
    String imdbId,
    String fallbackTitle,
  ) async {
    try {
      final trakt = TraktService.instance;
      if (!await trakt.isAuthenticated()) return;

      final results = await Future.wait([
        trakt.fetchWatchedShowEpisodes(imdbId),
        trakt.fetchEpisodePlaybackProgress(imdbId),
      ]);
      final watchedSet = results[0] as Set<String>; // "season-episode" keys
      final playbackMap = results[1] as Map<String, double>; // key → 0-100

      final merged = <String, double>{};
      for (final key in watchedSet) {
        merged[key] = 100.0;
      }
      for (final entry in playbackMap.entries) {
        if (entry.value > 0) merged[entry.key] = entry.value;
      }

      final filenames = playlist.map((e) => e.title).toList();
      // Title used only for the title-keyed sibling stores below (finished-
      // episode badges + season bars). The per-episode Trakt store is now keyed
      // by IMDb id (see saveEpisodeTraktProgress below), so it no longer depends
      // on this derivation matching the readers'.
      final effectiveTitle =
          SeriesParser.extractCommonSeriesTitle(filenames) ?? fallbackTitle;

      // The complete per-episode Trakt truth for the show ("season_episode" →
      // 0-100), for the playlist bars + cross-device resume. Kept in a dedicated
      // store apart from the ms-based resume state (the players convert % → ms at
      // play time), so partial progress never seeds a fake position. Built from
      // ALL Trakt episodes (every season, not just this playlist) so a show split
      // across torrents keeps each season's bars; written whole (replace) so
      // un-watched episodes clear — including the empty case below.
      final traktPercents = <String, double>{};
      merged.forEach((key, pct) {
        // Trakt keys are "season-episode"; store as "season_episode".
        final dash = key.indexOf('-');
        if (dash > 0) {
          traktPercents['${key.substring(0, dash)}_${key.substring(dash + 1)}'] =
              pct;
        }
      });
      await StorageService.saveEpisodeTraktProgress(
        imdbId: imdbId,
        percents: traktPercents,
      );

      if (merged.isEmpty) return;

      final parsed = SeriesParser.parsePlaylist(filenames);

      for (var i = 0; i < parsed.length; i++) {
        final info = parsed[i];
        if (info.season == null || info.episode == null) continue;
        final traktPercent = merged['${info.season}-${info.episode}'];
        if (traktPercent == null || traktPercent <= 0) continue;

        // Fully-watched: also mark finished (badge) + seed native watched state.
        if (traktPercent < 95) continue;

        // Writes to 'finishedEpisodes' (badges) + 'seasons' (bars), preserving
        // any existing local progress.
        await StorageService.markEpisodeAsFinished(
          seriesTitle: effectiveTitle,
          season: info.season!,
          episode: info.episode!,
          imdbId: imdbId,
        );

        // Video format (Kotlin Android TV player) — only if no local state, so
        // we never clobber a real resume position.
        final resumeId = resumeIdForEntry(
          playlist[i],
          fallbackTitle: effectiveTitle,
        );
        final existingState = await StorageService.getVideoPlaybackState(
          videoTitle: resumeId,
        );
        if (existingState == null) {
          await StorageService.saveVideoPlaybackState(
            videoTitle: resumeId,
            videoUrl: '',
            positionMs: 100,
            durationMs: 100,
          );
        }
      }
    } catch (e) {
      debugPrint('VideoPlayerLauncher: Trakt watched seed failed: $e');
    }
  }

  /// Refresh the player-only Simkl episode snapshot for [imdbId]. Unlike the
  /// legacy Trakt seed above, this never writes remote completion into local
  /// finished/resume state: every player surface reads this dedicated snapshot
  /// and merges it with local + Trakt at display/resume time.
  static Future<void> _seedSimklEpisodeProgress(String imdbId) async {
    try {
      final simkl = SimklService.instance;
      if (!await simkl.isAuthenticated()) {
        await StorageService.saveEpisodeSimklProgress(
          imdbId: imdbId,
          percents: const {},
        );
        return;
      }

      final results = await Future.wait([
        simkl.fetchWatchedShowEpisodes(imdbId),
        simkl.fetchEpisodePlaybackProgress(imdbId),
      ]);
      final watchedSet = results[0] as Set<String>;
      final playbackMap = results[1] as Map<String, double>;

      final percents = buildEpisodeTrackerSnapshot(
        watched: watchedSet,
        playback: playbackMap,
      );
      await StorageService.saveEpisodeSimklProgress(
        imdbId: imdbId,
        percents: percents,
      );
    } catch (e) {
      // A failed refresh should not show a stale remote tick from an older
      // launch. Local and Trakt state remain available.
      await StorageService.saveEpisodeSimklProgress(
        imdbId: imdbId,
        percents: const {},
      );
      debugPrint('VideoPlayerLauncher: Simkl episode seed failed: $e');
    }
  }

  /// [onPlayerHandoff] (optional) fires exactly once, at the moment a player
  /// surface actually takes over the screen: synchronously before the in-app
  /// player route is pushed, or — for external activities (Android TV native
  /// player, DeoVR, external apps) — once that activity covers the app
  /// (bounded by a timeout). It also fires if the launch dies, so a play-flow
  /// loading overlay handed here can stay up through the launch prep yet can
  /// never be left covering the app.
  static Future<void> push(
    BuildContext context,
    VideoPlayerLaunchArgs originalArgs, {
    Future<void> Function(Map<String, dynamic> result)? onQuickPlayNextEpisode,
    bool isTrailer = false,
    VoidCallback? onPlayerHandoff,
  }) async {
    // Exactly-once relay for [onPlayerHandoff]. _push fires one of these at
    // its launch points; the finally is the safety net so an exception mid
    // launch-prep can never strand the caller's loader.
    var handedOff = false;
    void handoffNow() {
      if (handedOff) return;
      handedOff = true;
      onPlayerHandoff?.call();
    }

    // External-activity launches return control immediately while the
    // activity is still opening. Firing the handoff right away would drop the
    // caller's loader and flash the underlying screen for the length of the
    // launch transition — so wait until the activity actually covers the app.
    void handoffWhenCovered() {
      if (handedOff) return;
      handedOff = true;
      final callback = onPlayerHandoff;
      if (callback != null) _runWhenCoveredByExternalActivity(callback);
    }

    try {
      await _push(
        context,
        originalArgs,
        onQuickPlayNextEpisode: onQuickPlayNextEpisode,
        isTrailer: isTrailer,
        handoffNow: handoffNow,
        handoffWhenCovered: handoffWhenCovered,
      );
    } finally {
      handoffNow();
    }
  }

  static Future<void> _push(
    BuildContext context,
    VideoPlayerLaunchArgs originalArgs, {
    Future<void> Function(Map<String, dynamic> result)? onQuickPlayNextEpisode,
    bool isTrailer = false,
    required VoidCallback handoffNow,
    required VoidCallback handoffWhenCovered,
  }) async {
    // If "Sync Catalog Items" is enabled and content has IMDB ID, enable scrobble
    var args = originalArgs;
    if (!args.traktScrobble &&
        !args.suppressTraktAutoSync &&
        args.contentImdbId != null &&
        args.stremioTvChannels == null) {
      final results = await Future.wait([
        StorageService.getTraktSyncCatalogItems(),
        TraktService.instance.isAuthenticated(),
      ]);
      final syncCatalog = results[0] as bool;
      final isAuth = results[1] as bool;
      if (syncCatalog && isAuth) {
        args = VideoPlayerLaunchArgs(
          videoUrl: args.videoUrl,
          audioUrl: args.audioUrl,
          fallbackUrl: args.fallbackUrl,
          title: args.title,
          subtitle: args.subtitle,
          playlist: args.playlist,
          startIndex: args.startIndex,
          rdTorrentId: args.rdTorrentId,
          torboxTorrentId: args.torboxTorrentId,
          pikpakCollectionId: args.pikpakCollectionId,
          webDavServerId: args.webDavServerId,
          webDavBaseUrl: args.webDavBaseUrl,
          webDavPath: args.webDavPath,
          requestMagicNext: args.requestMagicNext,
          requestNextChannel: args.requestNextChannel,
          startFromRandom: args.startFromRandom,
          randomStartMaxPercent: args.randomStartMaxPercent,
          startAtPercent: args.startAtPercent,
          hideSeekbar: args.hideSeekbar,
          showChannelName: args.showChannelName,
          channelName: args.channelName,
          channelNumber: args.channelNumber,
          showVideoTitle: args.showVideoTitle,
          hideOptions: args.hideOptions,
          hideBackButton: args.hideBackButton,
          httpHeaders: args.httpHeaders,
          disableExternalPlayer: args.disableExternalPlayer,
          isAndroidTvOverride: args.isAndroidTvOverride,
          disableAutoResume: args.disableAutoResume,
          viewMode: args.viewMode,
          contentImdbId: args.contentImdbId,
          contentType: args.contentType,
          contentSeason: args.contentSeason,
          contentEpisode: args.contentEpisode,
          iptvChannels: args.iptvChannels,
          iptvStartIndex: args.iptvStartIndex,
          iptvCategories: args.iptvCategories,
          iptvSourceId: args.iptvSourceId,
          iptvSourceName: args.iptvSourceName,
          iptvSelectedCategory: args.iptvSelectedCategory,
          iptvContentType: args.iptvContentType,
          iptvSources: args.iptvSources,
          iptvBrowseProvider: args.iptvBrowseProvider,
          stremioSources: args.stremioSources,
          stremioCurrentSourceIndex: args.stremioCurrentSourceIndex,
          resolveStremioSource: args.resolveStremioSource,
          resolveSourceToPlaylist: args.resolveSourceToPlaylist,
          seriesSourceFetcher: args.seriesSourceFetcher,
          stremioTvChannels: args.stremioTvChannels,
          stremioTvCurrentChannelId: args.stremioTvCurrentChannelId,
          stremioTvRotationMinutes: args.stremioTvRotationMinutes,
          stremioTvSeriesRotationMinutes: args.stremioTvSeriesRotationMinutes,
          stremioTvMixSalt: args.stremioTvMixSalt,
          stremioTvGuideDataProvider: args.stremioTvGuideDataProvider,
          stremioTvChannelSwitchProvider: args.stremioTvChannelSwitchProvider,
          stremioTvNextProvider: args.stremioTvNextProvider,
          traktScrobble: true,
          suppressTraktAutoSync: args.suppressTraktAutoSync,
          traktProgressPercent: args.traktProgressPercent,
          simklScrobble: args.simklScrobble,
          simklProgressPercent: args.simklProgressPercent,
          contentTitle: args.contentTitle,
          posterUrl: args.posterUrl,
          contentYear: args.contentYear,
          addonId: args.addonId,
          initialSubtitles: args.initialSubtitles,
        );
        // Clean up any existing local Continue Watching entry (Trakt tracks it now)
        await StorageService.removeContinueWatchingItem(args.contentImdbId!);
      }
    }

    // Simkl auto-enable — parallel to the Trakt upgrade above, same context
    // exclusions (suppressTraktAutoSync is context-scoped, not Trakt-specific).
    // Now that a Simkl Continue Watching row exists, this mirrors the Trakt
    // branch: the title lives in the Simkl CW row, so the stale local entry is
    // removed below (and the write-guard at the persist step skips creating a
    // new one) — otherwise it would show in BOTH the local and Simkl rows.
    if (!args.simklScrobble &&
        !args.suppressTraktAutoSync &&
        args.contentImdbId != null &&
        args.stremioTvChannels == null) {
      final results = await Future.wait([
        StorageService.getSimklSyncCatalogItems(),
        SimklService.instance.isAuthenticated(),
      ]);
      final syncCatalog = results[0];
      final isAuth = results[1];
      if (syncCatalog && isAuth) {
        args = VideoPlayerLaunchArgs(
          videoUrl: args.videoUrl,
          audioUrl: args.audioUrl,
          fallbackUrl: args.fallbackUrl,
          title: args.title,
          subtitle: args.subtitle,
          playlist: args.playlist,
          startIndex: args.startIndex,
          rdTorrentId: args.rdTorrentId,
          torboxTorrentId: args.torboxTorrentId,
          pikpakCollectionId: args.pikpakCollectionId,
          webDavServerId: args.webDavServerId,
          webDavBaseUrl: args.webDavBaseUrl,
          webDavPath: args.webDavPath,
          requestMagicNext: args.requestMagicNext,
          requestNextChannel: args.requestNextChannel,
          startFromRandom: args.startFromRandom,
          randomStartMaxPercent: args.randomStartMaxPercent,
          startAtPercent: args.startAtPercent,
          hideSeekbar: args.hideSeekbar,
          showChannelName: args.showChannelName,
          channelName: args.channelName,
          channelNumber: args.channelNumber,
          showVideoTitle: args.showVideoTitle,
          hideOptions: args.hideOptions,
          hideBackButton: args.hideBackButton,
          httpHeaders: args.httpHeaders,
          disableExternalPlayer: args.disableExternalPlayer,
          isAndroidTvOverride: args.isAndroidTvOverride,
          disableAutoResume: args.disableAutoResume,
          viewMode: args.viewMode,
          contentImdbId: args.contentImdbId,
          contentType: args.contentType,
          contentSeason: args.contentSeason,
          contentEpisode: args.contentEpisode,
          iptvChannels: args.iptvChannels,
          iptvStartIndex: args.iptvStartIndex,
          iptvCategories: args.iptvCategories,
          iptvSourceId: args.iptvSourceId,
          iptvSourceName: args.iptvSourceName,
          iptvSelectedCategory: args.iptvSelectedCategory,
          iptvContentType: args.iptvContentType,
          iptvSources: args.iptvSources,
          iptvBrowseProvider: args.iptvBrowseProvider,
          stremioSources: args.stremioSources,
          stremioCurrentSourceIndex: args.stremioCurrentSourceIndex,
          resolveStremioSource: args.resolveStremioSource,
          resolveSourceToPlaylist: args.resolveSourceToPlaylist,
          seriesSourceFetcher: args.seriesSourceFetcher,
          stremioTvChannels: args.stremioTvChannels,
          stremioTvCurrentChannelId: args.stremioTvCurrentChannelId,
          stremioTvRotationMinutes: args.stremioTvRotationMinutes,
          stremioTvSeriesRotationMinutes: args.stremioTvSeriesRotationMinutes,
          stremioTvMixSalt: args.stremioTvMixSalt,
          stremioTvGuideDataProvider: args.stremioTvGuideDataProvider,
          stremioTvChannelSwitchProvider: args.stremioTvChannelSwitchProvider,
          stremioTvNextProvider: args.stremioTvNextProvider,
          traktScrobble: args.traktScrobble,
          suppressTraktAutoSync: args.suppressTraktAutoSync,
          traktProgressPercent: args.traktProgressPercent,
          simklScrobble: true,
          simklProgressPercent: args.simklProgressPercent,
          contentTitle: args.contentTitle,
          posterUrl: args.posterUrl,
          contentYear: args.contentYear,
          addonId: args.addonId,
          initialSubtitles: args.initialSubtitles,
        );
        // Clean up any pre-existing local Continue Watching entry (from before
        // Simkl was connected, or a prior non-Simkl play) — Simkl's own CW row
        // tracks it now, so leaving the local entry would duplicate it. Mirrors
        // the Trakt branch above.
        await StorageService.removeContinueWatchingItem(args.contentImdbId!);
      }
    }

    // Persist before launching playback so Android TV handoff cannot race the write.
    // Skip when a tracker already owns this title's Continue Watching entry —
    // Trakt (its own CW row) OR Simkl (its own CW row) — so it lives in exactly
    // one row instead of duplicating into local Continue Watching. Also skip
    // Stremio TV (channel rotation). This runs on the shared pre-launch path, so
    // it applies to both the native-TV and in-app players.
    if (args.contentImdbId != null &&
        args.contentType != null &&
        !args.traktScrobble &&
        !args.simklScrobble &&
        args.stremioTvChannels == null) {
      await StorageService.saveContinueWatchingItem(
        imdbId: args.contentImdbId!,
        title: args.contentTitle ?? args.title,
        contentType: args.contentType!,
        posterUrl: args.posterUrl,
        year: args.contentYear,
        addonId: args.addonId,
      );
    }

    // Refresh both trackers' per-episode snapshots before either player is
    // launched. Trakt retains its legacy local-finished seed; Simkl stays in a
    // dedicated replaceable store so remote "unwatched" changes cannot leave
    // stale local completion behind.
    if (args.contentType != 'movie' &&
        args.contentImdbId != null &&
        (args.playlist?.length ?? 0) > 1) {
      await Future.wait([
        _seedTraktWatchedEpisodes(
          args.playlist!,
          args.contentImdbId!,
          args.contentTitle ?? args.title,
        ),
        _seedSimklEpisodeProgress(args.contentImdbId!),
      ]);
    } else if (args.contentType == 'series' && args.contentImdbId != null) {
      // Single-episode launches may grow into a pack through source switching,
      // so have the Simkl snapshot ready for that in-session playlist too.
      await _seedSimklEpisodeProgress(args.contentImdbId!);
    }

    AnalyticsService.trackInBackground('playback_started', <String, Object?>{
      'content_type': args.contentType ?? 'unknown',
      'provider': _analyticsProviderLabel(args),
      'has_playlist': args.playlist?.isNotEmpty ?? false,
      'trakt_scrobble': args.traktScrobble,
      'platform': AnalyticsService.currentPlatformLabel(),
    });

    MainPageBridge.notifyPlayerLaunching(isTrailer: isTrailer);

    // Log playlist entries to trace relativePath
    if (args.playlist != null && args.playlist!.isNotEmpty) {
      debugPrint(
        '🚀 VideoPlayerLauncher.push: Launching with ${args.playlist!.length} entries',
      );
      for (int i = 0; i < args.playlist!.length && i < 5; i++) {
        final entry = args.playlist![i];
        debugPrint(
          '  Entry[$i]: title="${entry.title}", relativePath="${entry.relativePath}"',
        );
      }
    }

    // Check default player mode
    final defaultPlayerMode = await StorageService.getDefaultPlayerMode();

    // Every external-activity launch below arms the playback-return signal
    // (content only): control comes straight back to Flutter without a route
    // ever being pushed, so RouteAware can't tell those screens when playback
    // actually ended. See [_notifyOnReturnFromExternalActivity].
    if (!args.disableExternalPlayer && defaultPlayerMode == 'external') {
      final launched = await _launchWithExternalPlayer(context, args);
      if (launched) {
        handoffWhenCovered();
        if (!isTrailer) _notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If external player failed, fall through to in-app player
    } else if (!args.disableExternalPlayer &&
        defaultPlayerMode == 'deovr' &&
        Platform.isAndroid) {
      final launched = await _launchWithDeoVR(context, args);
      if (launched) {
        handoffWhenCovered();
        if (!isTrailer) _notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If DeoVR failed, fall through to in-app player
    }

    final isTv = await _isAndroidTv(args.isAndroidTvOverride);
    if (isTv) {
      final launched = await _launchOnAndroidTv(
        args,
        onQuickPlayNextEpisode: onQuickPlayNextEpisode,
        isTrailer: isTrailer,
      );
      if (launched) {
        handoffWhenCovered();
        if (!isTrailer) _notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
    }

    // In-app player: pop the loader and push the player in the same frame, so
    // there's no between-screens gap and the loader never sits under the
    // player route.
    handoffNow();
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(builder: (_) => args.toWidget()),
    );

    // Handle Quick Play next episode request from player
    if (result != null &&
        result['quickPlayNext'] == true &&
        onQuickPlayNextEpisode != null) {
      await onQuickPlayNextEpisode(result);
    }
  }

  /// Whether playback should leave the app entirely, per the user's default
  /// player setting. Screens that build their own player route ask this before
  /// spending work on in-app-only setup.
  static Future<bool> isExternalPlayerDefault() async {
    final mode = await StorageService.getDefaultPlayerMode();
    return mode == 'external' || (mode == 'deovr' && Platform.isAndroid);
  }

  /// Hand a single already-resolved stream to the user's configured external
  /// player, if — and only if — they set one as their default.
  ///
  /// This is the entry point for flows that build their own player route
  /// instead of going through [push] (Debrify TV, which drives channel
  /// rotation from its own screen state). Returns false when the default is
  /// the in-app player, when the platform launch fails, or when the caller
  /// passes an empty URL — the caller then continues to its own player exactly
  /// as before, so this is always safe to call first.
  ///
  /// Only the URL and title travel to the other app: playlists, resume state
  /// and "play next" callbacks are meaningless once playback leaves Debrify.
  static Future<bool> launchExternalIfConfigured(
    BuildContext context, {
    required String videoUrl,
    required String title,
  }) async {
    if (videoUrl.isEmpty) return false;

    final mode = await StorageService.getDefaultPlayerMode();
    final bool wantsDeoVR = mode == 'deovr' && Platform.isAndroid;
    if (mode != 'external' && !wantsDeoVR) return false;
    if (!context.mounted) return false;

    final args = VideoPlayerLaunchArgs(videoUrl: videoUrl, title: title);

    // Same pre-launch beat the in-app path uses: drop the auto-launch overlay
    // before another activity comes to the front.
    MainPageBridge.notifyPlayerLaunching();

    final launched = wantsDeoVR
        ? await _launchWithDeoVR(context, args)
        : await _launchWithExternalPlayer(context, args);

    if (!launched) return false;

    // Control returns to Flutter without a route ever being pushed, so
    // RouteAware can't tell screens when playback ended — same signal the
    // launcher's own external path arms. See [push].
    _notifyOnReturnFromExternalActivity();
    MainPageBridge.notifyExternalPlayerLaunched();
    return true;
  }

  /// Launch video with external player based on platform
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> _launchWithExternalPlayer(
    BuildContext context,
    VideoPlayerLaunchArgs args,
  ) async {
    // Determine the correct URL to play (considering resume state for series)
    String url = args.videoUrl;
    String title = args.title;

    final playlist = args.playlist;
    if (playlist != null && playlist.length > 1) {
      try {
        // Build SeriesPlaylist to check if it's a series
        final seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          playlist,
          collectionTitle: args.title,
          forceSeries:
              args.viewMode?.toForceSeries() ?? (args.contentType == 'series'),
        );

        int startIndex = 0;
        if (seriesPlaylist.isSeries && seriesPlaylist.allEpisodes.isNotEmpty) {
          // Get last played episode for resume
          final lastEpisode = await StorageService.getLastPlayedEpisode(
            seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
          );

          if (lastEpisode != null) {
            final lastSeason = lastEpisode['season'] as int;
            final lastEpisodeNum = lastEpisode['episode'] as int;
            final originalIndex = seriesPlaylist
                .findOriginalIndexBySeasonEpisode(lastSeason, lastEpisodeNum);
            if (originalIndex != -1) {
              startIndex = originalIndex;

              // Check if this episode is finished - if so, advance to next
              final isFinished = await StorageService.isEpisodeFinished(
                seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
                season: lastSeason,
                episode: lastEpisodeNum,
              );

              if (isFinished) {
                // Find next episode in allEpisodes (already sorted by season/episode)
                final currentEpisodeIdx = seriesPlaylist.allEpisodes.indexWhere(
                  (ep) => ep.originalIndex == originalIndex,
                );
                if (currentEpisodeIdx != -1 &&
                    currentEpisodeIdx + 1 < seriesPlaylist.allEpisodes.length) {
                  final nextEpisode =
                      seriesPlaylist.allEpisodes[currentEpisodeIdx + 1];
                  startIndex = nextEpisode.originalIndex;
                  debugPrint(
                    'ExternalPlayer: E${lastEpisodeNum} finished, advancing to next at index $startIndex',
                  );
                }
              } else {
                debugPrint(
                  'ExternalPlayer: Resuming series at index $startIndex',
                );
              }
            }
          } else {
            // First time - start at first episode
            final firstIndex = seriesPlaylist.getFirstEpisodeOriginalIndex();
            if (firstIndex != -1) {
              startIndex = firstIndex;
            }
          }
        }

        // Resolve the URL for the target entry
        if (startIndex >= 0 && startIndex < playlist.length) {
          final targetEntry = playlist[startIndex];
          final resolvedUrl = await _resolveEntryUrl(targetEntry, args);
          if (resolvedUrl.isNotEmpty) {
            url = resolvedUrl;
            title = targetEntry.title;
            debugPrint(
              'ExternalPlayer: Using entry $startIndex - ${targetEntry.title}',
            );

            // Mark episode as watched (external player doesn't provide progress feedback)
            if (seriesPlaylist.isSeries) {
              final episode = seriesPlaylist.allEpisodes.firstWhereOrNull(
                (ep) => ep.originalIndex == startIndex,
              );
              if (episode != null &&
                  episode.seriesInfo.season != null &&
                  episode.seriesInfo.episode != null) {
                await StorageService.markEpisodeAsFinished(
                  seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
                  season: episode.seriesInfo.season!,
                  episode: episode.seriesInfo.episode!,
                  imdbId: seriesPlaylist.imdbId,
                );
                debugPrint(
                  'ExternalPlayer: Marked S${episode.seriesInfo.season}E${episode.seriesInfo.episode} as watched',
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint(
          'ExternalPlayer: Failed to determine start index, using default: $e',
        );
      }
    }

    if (Platform.isMacOS) {
      // macOS: Use configured external player
      final result = await ExternalPlayerService.launchWithPreferredPlayer(
        url,
        title: title,
      );

      if (result.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opening with ${result.usedPlayer?.displayName ?? "external player"}...',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        // Show error but fall back to in-app player
        debugPrint('External player failed: ${result.errorMessage}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Failed to open external player',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
    } else if (Platform.isAndroid) {
      // Android: Show Intent chooser for video player apps
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: url,
          type: 'video/*',
        );
        await intent.launch();
        return true;
      } catch (e) {
        debugPrint('Failed to launch external player on Android: $e');
        return false;
      }
    } else if (Platform.isIOS) {
      // iOS: Use URL scheme to launch preferred external player
      final result = await ExternalPlayerService.launchWithPreferredIOSPlayer(
        url,
        title: title,
      );

      if (result.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opening with ${result.usedPlayer?.displayName ?? "external player"}...',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        // Show error but fall back to in-app player
        debugPrint('iOS External player failed: ${result.errorMessage}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Failed to open external player',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
    } else if (Platform.isLinux) {
      // Linux: Use command line to launch preferred external player
      final result =
          await LinuxExternalPlayerServiceExtension.launchWithPreferredLinuxPlayer(
            url,
            title: title,
          );

      if (result.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opening with ${result.usedPlayer?.displayName ?? "external player"}...',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        // Show error but fall back to in-app player
        debugPrint('Linux External player failed: ${result.errorMessage}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Failed to open external player',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
    } else if (Platform.isWindows) {
      // Windows: Use command line to launch preferred external player
      final result =
          await WindowsExternalPlayerServiceExtension.launchWithPreferredWindowsPlayer(
            url,
            title: title,
          );

      if (result.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Opening with ${result.usedPlayer?.displayName ?? "external player"}...',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return true;
      } else {
        // Show error but fall back to in-app player
        debugPrint('Windows External player failed: ${result.errorMessage}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.errorMessage ?? 'Failed to open external player',
              ),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
    }

    // Other platforms: not supported, use in-app player
    return false;
  }

  /// Launch video with DeoVR player (Android only)
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> _launchWithDeoVR(
    BuildContext context,
    VideoPlayerLaunchArgs args,
  ) async {
    final url = args.videoUrl;
    final title = args.title;

    try {
      // Load VR settings
      final vrAutoDetectFormat =
          await StorageService.getQuickPlayVrAutoDetectFormat();
      final vrShowDialog = await StorageService.getQuickPlayVrShowDialog();
      final vrDefaultScreenType =
          await StorageService.getQuickPlayVrDefaultScreenType();
      final vrDefaultStereoMode =
          await StorageService.getQuickPlayVrDefaultStereoMode();

      // Detect or use default format
      String selectedScreenType = vrDefaultScreenType;
      String selectedStereoMode = vrDefaultStereoMode;

      if (vrAutoDetectFormat) {
        final detected = deovr.detectVRFormat(title);
        selectedScreenType = detected.screenType;
        selectedStereoMode = detected.stereoMode;
      }

      // Show format selection dialog if enabled
      if (vrShowDialog && context.mounted) {
        final result = await _showDeoVRFormatDialog(
          context,
          title: title,
          initialScreenType: selectedScreenType,
          initialStereoMode: selectedStereoMode,
        );

        if (result == null) {
          // User cancelled
          return false;
        }

        selectedScreenType = result.screenType;
        selectedStereoMode = result.stereoMode;
      }

      // Generate DeoVR JSON
      final json = deovr.generateDeoVRJson(
        videoUrl: url,
        title: title,
        screenType: selectedScreenType,
        stereoMode: selectedStereoMode,
      );
      final jsonString = jsonEncode(json);

      debugPrint('DeoVR JSON content: $jsonString');

      // Upload JSON to jsonblob.com
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonString,
      );

      if (response.statusCode != 201) {
        throw Exception('Failed to upload JSON: ${response.statusCode}');
      }

      final location = response.headers['location'];
      if (location == null) {
        throw Exception('No location header in response');
      }

      final jsonUrl = 'https://jsonblob.com$location';
      debugPrint('DeoVR JSON uploaded to: $jsonUrl');

      // Launch DeoVR with the public URL
      final deOvrUri = 'deovr://$jsonUrl';
      debugPrint('Launching DeoVR with URI: $deOvrUri');

      final intent = AndroidIntent(action: 'action_view', data: deOvrUri);
      await intent.launch();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Launching DeoVR...'),
            duration: Duration(seconds: 2),
          ),
        );
      }

      return true;
    } catch (e) {
      debugPrint('Failed to launch DeoVR: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to open DeoVR: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
  }

  /// Show DeoVR format selection dialog
  static Future<({String screenType, String stereoMode})?>
  _showDeoVRFormatDialog(
    BuildContext context, {
    required String title,
    required String initialScreenType,
    required String initialStereoMode,
  }) async {
    String selectedScreenType = initialScreenType;
    String selectedStereoMode = initialStereoMode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('DeoVR Format'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              const Text(
                'Screen Type',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedScreenType,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: deovr.screenTypeLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedScreenType = value);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Stereo Mode',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedStereoMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: deovr.stereoModeLabels.entries
                    .map(
                      (e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedStereoMode = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
      ),
    );

    if (result != true) {
      return null;
    }

    return (screenType: selectedScreenType, stereoMode: selectedStereoMode);
  }

  static Future<bool> _isAndroidTv(bool Function()? override) async {
    if (override != null) {
      try {
        return override();
      } catch (_) {}
    }
    try {
      return await AndroidNativeDownloader.isTelevision();
    } catch (_) {
      return false;
    }
  }

  /// Runs [action] once another activity takes the foreground (first
  /// lifecycle state away from resumed), or after a short timeout if that
  /// never happens. Lets a play-flow loading overlay stay up through an
  /// external-activity launch transition, dismissed only while it's hidden —
  /// the timeout guarantees a launch that silently dies can't strand it.
  static void _runWhenCoveredByExternalActivity(VoidCallback action) {
    final binding = WidgetsBinding.instance;
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      action();
      return;
    }
    var done = false;
    Timer? fallback;
    late final _AppCoverObserver observer;
    void finish() {
      if (done) return;
      done = true;
      fallback?.cancel();
      binding.removeObserver(observer);
      action();
    }

    observer = _AppCoverObserver(onCovered: finish);
    binding.addObserver(observer);
    fallback = Timer(const Duration(seconds: 4), finish);
  }

  /// How long to wait for the launched activity to actually cover the app
  /// before giving up on ever seeing it return (see
  /// [_notifyOnReturnFromExternalActivity]).
  static const Duration _externalReturnArmTimeout = Duration(seconds: 30);

  /// Arms the one-shot "the player activity gave the screen back" signal.
  ///
  /// [_runWhenCoveredByExternalActivity] answers *"the player took over"*;
  /// this answers *"the player finished"* — the moment watch progress is final
  /// and every resume label / episode tick / Continue Watching row on screen is
  /// stale. External-activity launches push no Flutter route, so this is the
  /// only signal those screens can hang a refresh off (see
  /// [MainPageBridge.notifyPlaybackReturned]).
  ///
  /// Only fires on a cover→resume PAIR, so a launch that silently died (app
  /// never left the foreground) can't be mistaken for a finished playback. If
  /// the cover never comes within [_externalReturnArmTimeout] the observer is
  /// dropped, so it can't leak or fire on some unrelated later resume.
  static _AppReturnObserver? _armedReturnObserver;

  static void _notifyOnReturnFromExternalActivity() {
    // Already armed — a launch issued while the player activity still owns the
    // screen (Debrify TV moving to the next channel, a playlist advancing)
    // must not stack a second observer: they'd both fire on the one resume and
    // every listener would refresh twice.
    if (_armedReturnObserver != null) return;

    final binding = WidgetsBinding.instance;
    var done = false;
    late final _AppReturnObserver observer;
    void finish({required bool notify}) {
      if (done) return;
      done = true;
      binding.removeObserver(observer);
      if (identical(_armedReturnObserver, observer)) {
        _armedReturnObserver = null;
      }
      if (notify) MainPageBridge.notifyPlaybackReturned();
    }

    observer = _AppReturnObserver(onReturned: () => finish(notify: true));
    // Launch prep can await across the activity transition, so the player may
    // ALREADY be covering us by the time we arm. Seed from the live state —
    // otherwise the only lifecycle event left is the resume, which an unseeded
    // observer would discard as "never covered" and the refresh would be lost.
    observer.wasCovered = binding.lifecycleState != AppLifecycleState.resumed;
    _armedReturnObserver = observer;
    binding.addObserver(observer);
    Timer(_externalReturnArmTimeout, () {
      if (!observer.wasCovered) finish(notify: false);
    });
  }

  static String _analyticsProviderLabel(VideoPlayerLaunchArgs args) {
    if (args.rdTorrentId != null && args.rdTorrentId!.isNotEmpty) {
      return 'real_debrid';
    }
    if (args.torboxTorrentId != null && args.torboxTorrentId!.isNotEmpty) {
      return 'torbox';
    }
    if (args.pikpakCollectionId != null &&
        args.pikpakCollectionId!.isNotEmpty) {
      return 'pikpak';
    }
    if (args.stremioTvChannels != null) {
      return 'stremio_tv';
    }
    if (args.iptvChannels != null) {
      return 'iptv';
    }
    if (args.stremioSources != null && args.stremioSources!.isNotEmpty) {
      return 'stremio';
    }
    final playlistProvider = _analyticsPlaylistProviderLabel(args.playlist);
    if (playlistProvider != null) {
      return playlistProvider;
    }
    final urlProvider = _analyticsUrlProviderLabel(args.videoUrl);
    if (urlProvider != null) {
      return urlProvider;
    }
    return 'direct';
  }

  static String? _analyticsPlaylistProviderLabel(
    List<PlaylistEntry>? playlist,
  ) {
    if (playlist == null || playlist.isEmpty) return null;

    for (final entry in playlist) {
      final explicitProvider = entry.provider?.trim().toLowerCase();
      if (explicitProvider == 'torbox') return 'torbox';
      if (explicitProvider == 'pikpak') return 'pikpak';
      if (explicitProvider == 'realdebrid' ||
          explicitProvider == 'real_debrid' ||
          explicitProvider == 'real debrid') {
        return 'real_debrid';
      }

      if (entry.torboxTorrentId != null ||
          entry.torboxWebDownloadId != null ||
          entry.torboxFileId != null) {
        return 'torbox';
      }
      if (entry.pikpakFileId != null) {
        return 'pikpak';
      }
      if (entry.rdTorrentId != null && entry.rdTorrentId!.isNotEmpty) {
        return 'real_debrid';
      }
    }

    return null;
  }

  static String? _analyticsUrlProviderLabel(String videoUrl) {
    final uri = Uri.tryParse(videoUrl);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return null;

    if (host.contains('real-debrid')) {
      return 'real_debrid';
    }
    if (host.contains('mypikpak') || host.contains('pikpak')) {
      return 'pikpak';
    }
    if (host.contains('torbox') || host.contains('tb-cdn.')) {
      return 'torbox';
    }

    return null;
  }

  static Future<bool> _launchOnAndroidTv(
    VideoPlayerLaunchArgs args, {
    Future<void> Function(Map<String, dynamic> result)? onQuickPlayNextEpisode,
    bool isTrailer = false,
  }) async {
    // Route IPTV playlists to dedicated IPTV launcher
    if (args.iptvChannels != null && args.iptvChannels!.isNotEmpty) {
      return _launchIptvOnAndroidTv(args);
    }

    // Reset Trakt scrobble state for clean session
    _traktHeartbeatTimer?.cancel();
    _traktHeartbeatTimer = null;
    _traktLastScrobbleAction = null;
    _traktLastKnownProgress = 0.0;
    _traktLastKnownSeason = null;
    _traktLastKnownEpisode = null;

    // Reset Simkl scrobble state for clean session
    _simklHeartbeatTimer?.cancel();
    _simklHeartbeatTimer = null;
    _simklLastScrobbleAction = null;
    _simklLastKnownProgress = 0.0;
    _simklLastKnownSeason = null;
    _simklLastKnownEpisode = null;

    try {
      final builder = _AndroidTvPlaybackPayloadBuilder(args);
      final result = await builder.build();
      if (result == null) {
        return false;
      }

      final resolver = _AndroidTvPlaylistResolver(
        entries: result.entries,
        resolveEntry: (entry) => _resolveEntryUrl(entry, args),
      );

      // Generate a unique session ID for this playback launch
      // This prevents stale metadata from previous sessions being sent to new sessions
      final sessionId =
          '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      AndroidTvPlayerBridge.setCurrentSessionId(sessionId);
      debugPrint('VideoPlayerLauncher: Generated session ID: $sessionId');

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching(isTrailer: isTrailer);

      // Build stremio source resolver for Android TV (if stremio sources are available)
      // Uses a mutable sources holder so channel switches can update the source list
      var currentStremioSources = List<Torrent>.from(args.stremioSources ?? []);
      var currentStremioResolver = args.resolveStremioSource;
      Future<String?> Function(int)? stremioSourceResolverForTv;
      if (currentStremioSources.isNotEmpty && currentStremioResolver != null) {
        stremioSourceResolverForTv = (int sourceIndex) async {
          if (sourceIndex < 0 || sourceIndex >= currentStremioSources.length) {
            debugPrint(
              'VideoPlayerLauncher: stremio source index out of range: $sourceIndex',
            );
            return null;
          }
          final torrent = currentStremioSources[sourceIndex];
          debugPrint(
            'VideoPlayerLauncher: resolving stremio source $sourceIndex: ${torrent.displayTitle}',
          );
          return currentStremioResolver!(torrent);
        };
      }

      // Build playlist resolver for Android TV (if resolveSourceToPlaylist is available)
      final resolveSourceToPlaylist = args.resolveSourceToPlaylist;
      Future<List<Map<String, dynamic>>?> Function(int)?
      sourcePlaylistResolverForTv;
      if (currentStremioSources.isNotEmpty && resolveSourceToPlaylist != null) {
        sourcePlaylistResolverForTv = (int sourceIndex) async {
          // Claim a switch token up front so a slower, superseded resolve can't
          // repoint the resolver at a stale source after a newer switch wins.
          final switchToken = resolver.beginSwitch();
          if (sourceIndex < 0 || sourceIndex >= currentStremioSources.length) {
            debugPrint(
              'VideoPlayerLauncher: source playlist index out of range: $sourceIndex',
            );
            return null;
          }
          final torrent = currentStremioSources[sourceIndex];
          debugPrint(
            'VideoPlayerLauncher: resolving source playlist $sourceIndex: ${torrent.displayTitle}',
          );
          final playlistEntries = await resolveSourceToPlaylist(torrent);
          if (playlistEntries == null || playlistEntries.isEmpty) return null;

          // Use SeriesPlaylist to detect series and compute season/episode
          final seriesPlaylist = playlistEntries.length > 1
              ? SeriesPlaylist.fromPlaylistEntries(playlistEntries)
              : null;
          final episodes = seriesPlaylist?.allEpisodes;
          // Compare against non-sample count (fromPlaylistEntries excludes samples).
          final nonSampleCount = playlistEntries
              .where((e) => !SeriesParser.isSampleFile(e.title))
              .length;
          // Classify as a series in two cases:
          //  (1) EVERY non-sample file classified — the original, strict rule,
          //      kept verbatim so this change can't regress anything that
          //      already worked.
          //  (2) NEW, bounded relaxation: a large pack where the vast majority
          //      classified but a few stray files didn't (a recap, a
          //      "Superfan.Extended" cut, an oddly named release). Previously
          //      one such file demoted the WHOLE season pack to a flat
          //      collection, dropping season/episode off every item and
          //      breaking "resume the same episode" on a source switch. The
          //      index mapping is NOT at risk: items are built by iterating ALL
          //      entries and looking up episodeByIndex[i], so entry[i].url
          //      always pairs with entry[i]'s season/episode whether or not it
          //      classified. The >=3 floor + 70% ratio keeps small movie
          //      boxsets (e.g. 2 movies, one with a stray "E01" token) from
          //      tipping into "series".
          final classifiedAsSeries =
              seriesPlaylist != null &&
              seriesPlaylist.isSeries &&
              episodes != null &&
              episodes.isNotEmpty;
          final fullyClassified =
              classifiedAsSeries && episodes.length >= nonSampleCount;
          final mostlyClassified =
              classifiedAsSeries &&
              episodes.length >= 3 &&
              episodes.length * 10 >= nonSampleCount * 7;
          final isSeries = fullyClassified || mostlyClassified;

          // Fetch TVMaze metadata so items arrive pre-populated with artwork/descriptions
          if (isSeries) {
            try {
              await seriesPlaylist.fetchEpisodeInfo();
              debugPrint(
                'VideoPlayerLauncher: TVMaze fetch complete for source playlist',
              );
            } catch (e) {
              debugPrint(
                'VideoPlayerLauncher: TVMaze fetch failed (non-fatal): $e',
              );
            }
          }

          // Build originalIndex → episode lookup for correct matching
          // (allEpisodes is sorted by season/episode, not by original entry order)
          final episodeByIndex = <int, SeriesEpisode>{};
          if (isSeries) {
            for (final ep in episodes) {
              episodeByIndex[ep.originalIndex] = ep;
            }
          }

          final sourceTrackerMaps = args.contentImdbId != null
              ? await Future.wait([
                  StorageService.getEpisodeTraktProgress(
                    imdbId: args.contentImdbId!,
                  ),
                  StorageService.getEpisodeSimklProgress(
                    imdbId: args.contentImdbId!,
                  ),
                ])
              : const <Map<String, double>>[];
          final sourceTraktProgress = sourceTrackerMaps.isNotEmpty
              ? sourceTrackerMaps[0]
              : const <String, double>{};
          final sourceSimklProgress = sourceTrackerMaps.length > 1
              ? sourceTrackerMaps[1]
              : const <String, double>{};

          // Convert PlaylistEntry list to Android TV PlaybackItem maps
          final items = <Map<String, dynamic>>[];
          for (int i = 0; i < playlistEntries.length; i++) {
            final entry = playlistEntries[i];
            // Match by originalIndex to handle reordering
            final episode = episodeByIndex[i];
            final epInfo = episode?.episodeInfo;
            final season = episode?.seriesInfo.season;
            final episodeNumber = episode?.seriesInfo.episode;
            final episodeKey = season != null && episodeNumber != null
                ? '${season}_$episodeNumber'
                : null;
            final trackerPercent = episodeKey != null
                ? furthestEpisodeTrackerPercent([
                    sourceTraktProgress[episodeKey],
                    sourceSimklProgress[episodeKey],
                  ])
                : null;
            items.add({
              'id': '${entry.title}_$i',
              // Mirror the resolver's own resumeId keying ('${title}_$i') so
              // post-switch lazy stream resolution can match by string id, not
              // positional index alone — the safety net the initial payload has.
              'resumeId': '${entry.title}_$i',
              'title': episode?.displayTitle ?? entry.title,
              'url': entry.url,
              if (entry.hdVideoUrl != null) 'hdVideoUrl': entry.hdVideoUrl,
              if (entry.audioUrl != null) 'audioUrl': entry.audioUrl,
              'index': i,
              if (season != null) 'season': season,
              if (episodeNumber != null) 'episode': episodeNumber,
              if (epInfo?.poster != null) 'artwork': epInfo!.poster,
              if (epInfo?.plot != null) 'description': epInfo!.plot,
              if (epInfo?.rating != null) 'rating': epInfo!.rating,
              if (entry.sizeBytes != null) 'sizeBytes': entry.sizeBytes,
              'resumePositionMs': 0,
              'durationMs': 0,
              'updatedAt': 0,
              if (entry.provider != null) 'provider': entry.provider,
              if (trackerPercent != null)
                'traktProgressPercent': trackerPercent,
            });
          }
          debugPrint(
            'VideoPlayerLauncher: resolved ${items.length} items for source playlist (isSeries=$isSeries)',
          );

          // Update the stream resolver so lazy loading works for the new
          // playlist — but only if this switch is still the latest one.
          if (!resolver.isLatestSwitch(switchToken)) {
            debugPrint(
              'VideoPlayerLauncher: source playlist $sourceIndex superseded '
              'before apply — discarding stale resolve',
            );
            return null;
          }
          resolver.replaceEntries(playlistEntries, switchToken: switchToken);

          // Add metadata as the first entry with key '__meta__'
          // This tells Kotlin what content type to use for the new playlist
          final meta = <String, dynamic>{
            '__meta__': true,
            'contentType': isSeries ? 'series' : 'collection',
          };
          return [meta, ...items];
        };
      }

      // "Load more sources" for the series source tabs: run the missing
      // category's search (packs/episodes), APPEND the deduped results onto
      // the mutable sources holder — never re-order; the native side and the
      // resolvers above couple a source to its list index — and hand the full
      // list back. Returning null (search failed) keeps the native button up
      // for a retry.
      final seriesFetcher = args.seriesSourceFetcher;
      Future<Map<String, dynamic>?> Function(
        String, {
        int? season,
        int? episode,
      })?
      moreSourcesProviderForTv;
      if (seriesFetcher != null && currentStremioSources.isNotEmpty) {
        moreSourcesProviderForTv =
            (String mode, {int? season, int? episode}) async {
              // season/episode = what the native player is CURRENTLY on (a pack
              // playlist auto-advances without relaunching); the fetcher falls
              // back to the launch episode when absent.
              final fetched = await seriesFetcher.fetch(
                mode,
                season: season,
                episode: episode,
              );
              if (fetched == null) return null;
              currentStremioSources = SeriesSourceFetcher.mergeSources(
                currentStremioSources,
                fetched,
              );
              debugPrint(
                'VideoPlayerLauncher: load-more "$mode" → ${fetched.length} fetched, '
                '${currentStremioSources.length} total sources',
              );
              return {
                'stremioSources': currentStremioSources
                    .map((t) => t.toJson())
                    .toList(),
                'packsFetched': seriesFetcher.packsFetched,
                'episodesFetched': seriesFetcher.episodesFetched,
                'movieFetched': seriesFetcher.movieFetched,
              };
            };
      }

      // Build Stremio TV channel switch wrapper that updates mutable sources holder
      Map<String, dynamic>? prepareStremioTvPlaybackResult(
        Map<String, dynamic>? playbackResult,
      ) {
        if (playbackResult == null) return null;

        // Update mutable sources holder with the new item's sources.
        final newSourcesList = playbackResult['stremioSources'] as List?;
        final newResolver =
            playbackResult['sourceResolver']
                as Future<String?> Function(Torrent)?;
        if (newSourcesList != null) {
          currentStremioSources = newSourcesList
              .map((s) => Torrent.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList();
        }
        if (newResolver != null) {
          currentStremioResolver = newResolver;
        }

        // Remove the sourceResolver from the result (it's a function, not serializable)
        final resultMap = Map<String, dynamic>.from(playbackResult);
        resultMap.remove('sourceResolver');
        return resultMap;
      }

      final channelSwitchProvider = args.stremioTvChannelSwitchProvider;
      Future<Map<String, dynamic>?> Function(String)? channelSwitchForTv;
      if (channelSwitchProvider != null) {
        channelSwitchForTv = (String channelId) async {
          final switchResult = await channelSwitchProvider(channelId);
          return prepareStremioTvPlaybackResult(switchResult);
        };
      }

      final stremioTvNextProvider = args.stremioTvNextProvider;
      Future<Map<String, dynamic>?> Function(String)? stremioTvNextForTv;
      if (stremioTvNextProvider != null) {
        stremioTvNextForTv = (String channelId) async {
          final nextResult = await stremioTvNextProvider(channelId);
          return prepareStremioTvPlaybackResult(nextResult);
        };
      }

      // Build payload with Stremio TV guide data
      final payloadMap = result.payload.toMap();
      if (args.stremioTvChannels != null &&
          args.stremioTvChannels!.isNotEmpty) {
        payloadMap['stremioTvGuide'] = {
          'channels': args.stremioTvChannels,
          'currentChannelId': args.stremioTvCurrentChannelId,
          'rotationMinutes': args.stremioTvRotationMinutes,
          'seriesRotationMinutes': args.stremioTvSeriesRotationMinutes,
          'mixSalt': args.stremioTvMixSalt,
        };
      }
      // "Load more sources" flags: series plays get the pack/episode tab
      // split; movie plays keep the flat picker with one Load more row on
      // the Torrent tab.
      if (moreSourcesProviderForTv != null) {
        if (seriesFetcher!.isMovie) {
          payloadMap['movieMoreSources'] = true;
          payloadMap['movieSourcesFetched'] = seriesFetcher.movieFetched;
        } else {
          payloadMap['seriesSourceTabs'] = true;
          payloadMap['seriesPacksFetched'] = seriesFetcher.packsFetched;
          payloadMap['seriesEpisodesFetched'] = seriesFetcher.episodesFetched;
        }
      }

      final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
        payload: payloadMap,
        onProgress: (progress) =>
            _handleProgressUpdate(result.payload, progress),
        onFinished: () async {
          await _handlePlaybackFinished(result.payload);
          resolver.dispose();
          // The native player may have requested a Quick Play next episode
          // right before it called finish(). The bridge handler only stores
          // the raw request (imdbId + current season/episode) — the async
          // NextEpisode lookup happens here so it doesn't race the Activity's
          // finish() → onFinished flow.
          final pending = AndroidTvPlayerBridge.consumeQuickPlayNextResult();
          if (pending != null && onQuickPlayNextEpisode != null) {
            final imdbId = pending['imdbId'] as String?;
            final curSeason = pending['currentSeason'] as int?;
            final curEpisode = pending['currentEpisode'] as int?;
            if (imdbId != null && curSeason != null && curEpisode != null) {
              final nextEp = await NextEpisodeService.findNextEpisode(
                imdbId,
                curSeason,
                curEpisode,
              );
              if (nextEp != null) {
                debugPrint(
                  'VideoPlayerLauncher: Quick Play next → S${nextEp.season}E${nextEp.episode}',
                );
                await onQuickPlayNextEpisode({
                  'quickPlayNext': true,
                  'imdbId': imdbId,
                  'season': nextEp.season,
                  'episode': nextEp.episode,
                });
              } else {
                debugPrint(
                  'VideoPlayerLauncher: No next episode found after S${curSeason}E$curEpisode',
                );
              }
            }
          }
        },
        onRequestStream: resolver.handleRequest,
        onRequestMovieMetadata:
            result.payload.contentType != _PlaybackContentType.series
            ? (index, filename) async {
                debugPrint(
                  'MovieMetadataCallback: index=$index, filename=$filename',
                );
                final movieInfo = MovieParser.parseFilename(filename);
                if (!movieInfo.hasYear || movieInfo.title == null) {
                  debugPrint(
                    'MovieMetadataCallback: No year pattern in filename',
                  );
                  return null;
                }
                final metadata = await MovieMetadataService.lookupMovie(
                  movieInfo.title!,
                  movieInfo.year,
                );
                debugPrint(
                  'MovieMetadataCallback: Lookup result imdbId=${metadata?.imdbId}',
                );
                return metadata?.imdbId;
              }
            : null,
        onResolveStremioSource: stremioSourceResolverForTv,
        onResolveSourcePlaylist: sourcePlaylistResolverForTv,
        onRequestMoreSources: moreSourcesProviderForTv,
        onRequestStremioTvGuideData: args.stremioTvGuideDataProvider,
        onRequestStremioTvChannelSwitch: channelSwitchForTv,
        onRequestStremioTvNext: stremioTvNextForTv,
      );

      if (!launched) {
        resolver.dispose();
        return false;
      }

      // Async TVMaze metadata fetch - don't block initial playback
      // This mirrors mobile video_player_screen.dart behavior
      // Pass sessionId to ensure stale metadata from previous sessions is discarded
      _fetchAndPushMetadataAsync(
        result.payload,
        result.entries,
        sessionId,
        args.viewMode,
        rdTorrentId: args.rdTorrentId,
        torboxTorrentId: args.torboxTorrentId,
        pikpakCollectionId: args.pikpakCollectionId,
        webDavServerId: args.webDavServerId,
        webDavBaseUrl: args.webDavBaseUrl,
        webDavPath: args.webDavPath,
        contentImdbId: args.contentImdbId,
        contentType: args.contentType,
      );

      return true;
    } catch (e) {
      debugPrint('VideoPlayerLauncher: Android TV launch failed: $e');
      return false;
    }
  }

  /// Launch IPTV playlist on Android TV using existing launchTorrentPlayback bridge
  static Future<bool> _launchIptvOnAndroidTv(VideoPlayerLaunchArgs args) async {
    try {
      final channels = args.iptvChannels!;
      final startIndex = args.iptvStartIndex ?? 0;

      // The source's FULL category list (provider order). Only fall back to
      // deriving from the windowed channels when the caller didn't supply it —
      // deriving only ever saw the ~1500-channel window, so the picker showed a
      // truncated set of categories.
      var categories = args.iptvCategories ?? const <String>[];
      if (categories.isEmpty) {
        final categorySet = <String>{};
        for (final c in channels) {
          if (c.group != null && c.group!.isNotEmpty) {
            categorySet.add(c.group!);
          }
        }
        categories = categorySet.toList()..sort();
      }

      // Saved positions for the on-demand items in this payload, so a movie
      // picks up where it was left off — and so does one the user zaps to
      // from the in-player guide. Attached alongside each channel rather than
      // baked into IptvChannel.toJson(): a resume point is session state, not
      // a property of the channel.
      final resumePositions = await StorageService.getIptvResumePositions([
        for (final c in channels)
          if (!c.isLive) c.url,
      ]);
      final favoriteUrls = await StorageService.getIptvFavoriteChannelUrls();

      // Per-series audio memory: Xtream series episodes carry a series identity
      // (series_id + series_playlist_id) in their attributes. The native player
      // has no per-series audio store of its own — resolve the remembered
      // language here and hand it the same `<playlistId>::<seriesId>` key so a
      // native audio pick round-trips back to the shared store.
      String? seriesAudioKey;
      String? preferredAudioLang;
      for (final c in channels) {
        final sid = c.attributes['series_id'];
        if (sid != null && sid.isNotEmpty) {
          final pid = c.attributes['series_playlist_id'] ?? '';
          seriesAudioKey = '$pid::$sid';
          break;
        }
      }
      if (seriesAudioKey != null) {
        preferredAudioLang = await StorageService.getIptvSeriesAudioLanguage(
          seriesAudioKey,
        );
      }

      final activeChannel = channels.isEmpty
          ? null
          : channels[startIndex.clamp(0, channels.length - 1)];
      final inferredContentType = activeChannel == null
          ? 'live'
          : activeChannel.attributes['series_id']?.isNotEmpty == true
          ? 'episodes'
          : activeChannel.isLive
          ? 'live'
          : 'vod';

      final payload = <String, dynamic>{
        'mode': 'iptv',
        'initialUrl': args.videoUrl,
        'title': args.title,
        'subtitle': args.subtitle ?? 'IPTV',
        'startIndex': startIndex,
        if (args.iptvSourceId != null) 'sourceId': args.iptvSourceId,
        if (args.iptvSourceName != null) 'sourceName': args.iptvSourceName,
        if (args.iptvSelectedCategory != null)
          'selectedCategory': args.iptvSelectedCategory,
        'contentType': args.iptvContentType ?? inferredContentType,
        if (args.iptvSources != null) 'sources': args.iptvSources,
        'channels': [
          for (final c in channels)
            {
              ...c.toJson(),
              if (c.attributes['source_playlist_id']?.isNotEmpty == true)
                'sourceId': c.attributes['source_playlist_id']
              else if (c.attributes['series_playlist_id']?.isNotEmpty == true)
                'sourceId': c.attributes['series_playlist_id'],
              if (c.attributes['series_id']?.isNotEmpty == true)
                'seriesId': c.attributes['series_id'],
              if (c.attributes['series_name']?.isNotEmpty == true)
                'seriesName': c.attributes['series_name'],
              if (int.tryParse(c.attributes['season'] ?? '') != null)
                'season': int.parse(c.attributes['season']!),
              if (int.tryParse(c.attributes['episode'] ?? '') != null)
                'episode': int.parse(c.attributes['episode']!),
              if (c.attributes['has_next_episode'] != null)
                'hasNextEpisode': c.attributes['has_next_episode'] == 'true',
              'isFavorite': favoriteUrls.contains(c.url),
              if ((resumePositions[c.url] ?? 0) > 0)
                'resumePositionMs': resumePositions[c.url],
            },
        ],
        'categories': categories,
        if (seriesAudioKey != null) 'seriesAudioKey': seriesAudioKey,
        if (preferredAudioLang != null)
          'preferredAudioLang': preferredAudioLang,
      };

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
        payload: payload,
        onProgress: _handleIptvProgressUpdate,
        onFinished: () async {
          debugPrint('VideoPlayerLauncher: IPTV Android TV playback finished');
        },
        onRequestIptvBrowse: args.iptvBrowseProvider,
      );

      return launched;
    } catch (e) {
      debugPrint('VideoPlayerLauncher: IPTV Android TV launch failed: $e');
      return false;
    }
  }

  /// Persist the native TV player's position for an on-demand IPTV item.
  ///
  /// Writes to the same `video_resume_v1` store, under the same key (the
  /// stream URL), that the in-app player already uses for IPTV — so a movie
  /// started on the phone and finished on the TV is one entry, not two.
  ///
  /// Live channels are ignored: the Kotlin side reports an unset duration for
  /// them, and a resume point on a live stream is meaningless anyway.
  static Future<void> _handleIptvProgressUpdate(
    Map<String, dynamic> progress,
  ) async {
    try {
      final url = progress['url'] as String?;
      if (url == null || url.isEmpty) return;

      final positionMs = (progress['positionMs'] as num?)?.toInt() ?? 0;
      final durationMs = (progress['durationMs'] as num?)?.toInt() ?? 0;
      if (durationMs <= 0 || positionMs <= 0) return;

      await StorageService.upsertVideoResume(url, {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': (progress['speed'] as num?)?.toDouble() ?? 1.0,
        'aspect': (progress['aspect'] as String?) ?? 'contain',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('VideoPlayerLauncher: IPTV progress save failed: $e');
    }
  }

  /// Fetch TVMaze metadata asynchronously and push updates to native player
  /// This doesn't block initial playback - updates are pushed when available
  /// The sessionId parameter ensures stale metadata from previous sessions is discarded
  static void _fetchAndPushMetadataAsync(
    _AndroidTvPlaybackPayload payload,
    List<_LauncherEntry> entries,
    String sessionId,
    PlaylistViewMode? viewMode, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
    String? contentImdbId,
    String? contentType,
  }) {
    debugPrint('TVMazeAsync: _fetchAndPushMetadataAsync CALLED');
    debugPrint(
      'TVMazeAsync: contentType=${payload.contentType}, title=${payload.title}',
    );
    debugPrint(
      'TVMazeAsync: entries.length=${entries.length}, viewMode=$viewMode, imdbId=$contentImdbId',
    );

    if (payload.contentType != _PlaybackContentType.series) {
      debugPrint(
        'TVMazeAsync: SKIPPED - not series content (contentType=${payload.contentType})',
      );
      return;
    }

    // Create SeriesPlaylist for TVMaze lookup
    final playlistEntries = entries.map((e) => e.entry).toList();
    if (playlistEntries.length < 2) {
      debugPrint(
        'TVMazeAsync: SKIPPED - less than 2 entries (${playlistEntries.length})',
      );
      return;
    }

    debugPrint('TVMazeAsync: Starting background fetch...');

    // Run in background - don't await
    () async {
      try {
        // Determine forceSeries: prefer viewMode, then use contentType from catalog
        bool? forceSeries = viewMode?.toForceSeries();
        if (forceSeries == null && contentType != null) {
          forceSeries = contentType == 'series';
        }

        debugPrint(
          'TVMazeAsync: Creating SeriesPlaylist from ${playlistEntries.length} entries',
        );
        final seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          playlistEntries,
          collectionTitle: payload.title,
          forceSeries: forceSeries,
        );

        debugPrint(
          'TVMazeAsync: SeriesPlaylist created - isSeries=${seriesPlaylist.isSeries}, seriesTitle=${seriesPlaylist.seriesTitle}',
        );
        debugPrint(
          'TVMazeAsync: allEpisodes.length=${seriesPlaylist.allEpisodes.length}',
        );

        if (!seriesPlaylist.isSeries) {
          // For non-series content, try to fetch movie metadata to get IMDB ID
          debugPrint(
            'MovieAsync: Not a series, attempting movie metadata fetch',
          );
          await seriesPlaylist.fetchMovieMetadata();

          final discoveredImdbId = seriesPlaylist.imdbId;
          if (discoveredImdbId != null) {
            debugPrint(
              'MovieAsync: Found IMDB ID $discoveredImdbId, pushing to native player',
            );

            // Check if this session is still current
            if (!AndroidTvPlayerBridge.isCurrentSession(sessionId)) {
              debugPrint(
                'MovieAsync: DISCARDED - session $sessionId is no longer current',
              );
              return;
            }

            // Store and push IMDB ID to native player (no episode metadata for movies)
            AndroidTvPlayerBridge.storePendingMetadataUpdates(
              [],
              sessionId: sessionId,
              imdbId: discoveredImdbId,
            );

            await AndroidTvPlayerBridge.updateEpisodeMetadata(
              [],
              sessionId: sessionId,
              imdbId: discoveredImdbId,
            );
            debugPrint('MovieAsync: IMDB ID pushed to native player');
          } else {
            debugPrint(
              'MovieAsync: No IMDB ID discovered, cannot fetch subtitles',
            );
          }
          return;
        }

        debugPrint(
          'TVMazeAsync: Calling fetchEpisodeInfo() with imdbId=$contentImdbId',
        );
        await seriesPlaylist.fetchEpisodeInfo(imdbId: contentImdbId);
        debugPrint('TVMazeAsync: fetchEpisodeInfo() completed');

        // Save discovered IMDB ID back to playlist item for future direct plays
        final seriesImdbId = seriesPlaylist.imdbId;
        if (seriesImdbId != null &&
            seriesImdbId.startsWith('tt') &&
            contentImdbId == null) {
          await StorageService.updatePlaylistItemImdbId(
            seriesImdbId,
            rdTorrentId: rdTorrentId,
            torboxTorrentId: torboxTorrentId,
            pikpakCollectionId: pikpakCollectionId,
          );
        }

        // Save series poster to playlist item (if we have series info)
        await _saveSeriesPosterToPlaylist(
          seriesPlaylist,
          rdTorrentId: rdTorrentId,
          torboxTorrentId: torboxTorrentId,
          pikpakCollectionId: pikpakCollectionId,
          webDavServerId: webDavServerId,
          webDavBaseUrl: webDavBaseUrl,
          webDavPath: webDavPath,
        );

        // Build metadata updates for each item
        final metadataUpdates = <Map<String, dynamic>>[];
        int episodesWithInfo = 0;
        int episodesWithoutInfo = 0;
        for (final episode in seriesPlaylist.allEpisodes) {
          if (episode.episodeInfo == null) {
            episodesWithoutInfo++;
            continue;
          }
          episodesWithInfo++;

          final info = episode.episodeInfo!;
          metadataUpdates.add({
            'originalIndex': episode.originalIndex,
            'title': info.title,
            'description': info.plot,
            'artwork': info.poster,
            'rating': info.rating,
          });
        }

        debugPrint(
          'TVMazeAsync: Episodes with info=$episodesWithInfo, without info=$episodesWithoutInfo',
        );

        // Get discovered IMDB ID from TVMaze (may have been extracted from externals)
        final discoveredImdbId = seriesPlaylist.imdbId;
        debugPrint(
          'TVMazeAsync: Discovered IMDB ID from TVMaze: $discoveredImdbId',
        );

        if (metadataUpdates.isEmpty && discoveredImdbId == null) {
          debugPrint(
            'TVMazeAsync: SKIPPED push - no metadata updates and no IMDB ID',
          );
          return;
        }

        // Check if this session is still current before sending metadata
        // This prevents stale metadata from Series A being sent to Series B
        if (!AndroidTvPlayerBridge.isCurrentSession(sessionId)) {
          debugPrint(
            'TVMazeAsync: DISCARDED - session $sessionId is no longer current (current: ${AndroidTvPlayerBridge.currentSessionId})',
          );
          return;
        }

        // Store pending updates for fallback (in case broadcast arrives before receiver is registered)
        // AND push directly to native player
        debugPrint(
          'TVMazeAsync: Storing ${metadataUpdates.length} pending metadata updates for fallback (imdbId=$discoveredImdbId)',
        );
        AndroidTvPlayerBridge.storePendingMetadataUpdates(
          metadataUpdates,
          sessionId: sessionId,
          imdbId: discoveredImdbId,
        );

        // Push metadata updates directly to native player (don't wait for request)
        // Include discovered IMDB ID for Stremio subtitle fetching
        debugPrint(
          'TVMazeAsync: Pushing ${metadataUpdates.length} metadata updates to native player (imdbId=$discoveredImdbId)',
        );
        await AndroidTvPlayerBridge.updateEpisodeMetadata(
          metadataUpdates,
          sessionId: sessionId,
          imdbId: discoveredImdbId,
        );
        debugPrint('TVMazeAsync: Metadata push complete');
      } catch (e, stack) {
        debugPrint('TVMazeAsync: ERROR - $e');
        debugPrint('TVMazeAsync: Stack - $stack');
      }
    }();
  }

  /// Save series poster URL to playlist item (Android TV flow)
  static Future<void> _saveSeriesPosterToPlaylist(
    SeriesPlaylist seriesPlaylist, {
    String? rdTorrentId,
    String? torboxTorrentId,
    String? pikpakCollectionId,
    String? webDavServerId,
    String? webDavBaseUrl,
    String? webDavPath,
  }) async {
    final posterUrl = seriesPlaylist.showPosterUrl;
    if (posterUrl == null || posterUrl.isEmpty) return;

    if ((rdTorrentId == null || rdTorrentId.isEmpty) &&
        (torboxTorrentId == null || torboxTorrentId.isEmpty) &&
        (pikpakCollectionId == null || pikpakCollectionId.isEmpty) &&
        (webDavPath == null || webDavPath.isEmpty)) {
      return;
    }

    try {
      if (rdTorrentId != null && rdTorrentId.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
      if (webDavPath != null && webDavPath.isNotEmpty) {
        await StorageService.updatePlaylistItemPoster(
          posterUrl,
          webDavServerId: webDavServerId,
          webDavBaseUrl: webDavBaseUrl,
          webDavPath: webDavPath,
        );
      }
    } catch (e) {
      debugPrint('Error saving poster: $e');
    }
  }

  /// A series frame whose season/episode hasn't been populated yet must not be
  /// scrobbled to Simkl — [SimklService._scrobble] would send the show id in a
  /// movie-shaped body, recording a bogus movie on the account. A movie
  /// legitimately reports (null, null), so this only blocks the series case.
  /// (Trakt has the same latent gap; guard is Simkl-only per the no-touch-Trakt
  /// convention.)
  static bool _simklSeriesSEUnresolved(
    _AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) {
    if (payload.contentType != _PlaybackContentType.series) return false;
    return progress['season'] == null || progress['episode'] == null;
  }

  static Future<void> _handleProgressUpdate(
    _AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) async {
    try {
      final positionMs = (progress['positionMs'] ?? 0) as int;
      final durationMs = (progress['durationMs'] ?? 0) as int;
      final speed = (progress['speed'] ?? 1.0) as double;
      final aspect = (progress['aspect'] ?? 'contain') as String;
      final completed = progress['completed'] == true;
      final resumeId = progress['resumeId'] as String?;
      final itemIndex = progress['itemIndex'] as int? ?? 0;
      final progressUrl = progress['url'] as String?;

      if (resumeId != null && progressUrl != null && progressUrl.isNotEmpty) {
        _cacheResolvedStream(resumeId, progressUrl);
      }

      // Trakt scrobble for Android TV player (movies and series)
      if (payload.traktScrobble && payload.imdbId != null && durationMs > 0) {
        // Treat buffering as still playing — ExoPlayer sets isPlaying=false during buffer
        final isPlaying =
            progress['isPlaying'] == true || progress['isBuffering'] == true;
        final traktProgress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
        final imdbId = payload.imdbId!;
        // For series, read season/episode from Kotlin progress update
        // For non-series, ignore parsed values — avoids filename false positives (e.g. "5.1" surround → S5E1)
        final season = payload.contentType == _PlaybackContentType.series
            ? progress['season'] as int?
            : null;
        final episode = payload.contentType == _PlaybackContentType.series
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (_traktLastKnownSeason != null &&
            _traktLastKnownEpisode != null &&
            (season != _traktLastKnownSeason ||
                episode != _traktLastKnownEpisode) &&
            _traktLastScrobbleAction != 'stop') {
          _traktHeartbeatTimer?.cancel();
          _traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            _traktLastKnownProgress,
            season: _traktLastKnownSeason,
            episode: _traktLastKnownEpisode,
          );
          _traktLastScrobbleAction = 'stop';
        }

        _traktLastKnownProgress = traktProgress;
        _traktLastKnownSeason = season;
        _traktLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (_traktLastScrobbleAction == 'stop' &&
            isPlaying &&
            traktProgress <= 80 &&
            !completed) {
          _traktLastScrobbleAction = null;
        }
        if (completed && _traktLastScrobbleAction != 'stop') {
          _traktLastScrobbleAction = 'stop';
          _traktHeartbeatTimer?.cancel();
          _traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            traktProgress,
            season: season,
            episode: episode,
          );
        } else if (isPlaying &&
            _traktLastScrobbleAction != 'start' &&
            _traktLastScrobbleAction != 'stop') {
          // Trakt rejects start above 80% — send stop instead, no heartbeat needed
          if (traktProgress > 80) {
            _traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
            );
          } else {
            _traktLastScrobbleAction = 'start';
            TraktService.instance.scrobbleStart(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
            );
            // Start heartbeat timer to checkpoint progress every 2 minutes
            _traktHeartbeatTimer?.cancel();
            _traktHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              // Trakt rejects start/pause above 80% — send stop and end heartbeat
              if (_traktLastKnownProgress > 80) {
                _traktLastScrobbleAction = 'stop';
                TraktService.instance.scrobbleStop(
                  payload.imdbId!,
                  _traktLastKnownProgress,
                  season: _traktLastKnownSeason,
                  episode: _traktLastKnownEpisode,
                );
                debugPrint(
                  'Trakt: Heartbeat stop at ${_traktLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                _traktHeartbeatTimer?.cancel();
                _traktHeartbeatTimer = null;
                return;
              }
              // Use latest known progress/season/episode
              _traktLastScrobbleAction = 'start';
              TraktService.instance.scrobbleStart(
                payload.imdbId!,
                _traktLastKnownProgress,
                season: _traktLastKnownSeason,
                episode: _traktLastKnownEpisode,
              );
              debugPrint(
                'Trakt: Heartbeat scrobble at ${_traktLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            _traktLastScrobbleAction != null &&
            _traktLastScrobbleAction != 'pause' &&
            _traktLastScrobbleAction != 'stop') {
          // Trakt rejects pause when progress > 80% — send stop instead
          _traktHeartbeatTimer?.cancel();
          _traktHeartbeatTimer = null;
          if (traktProgress > 80) {
            _traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
            );
          } else {
            _traktLastScrobbleAction = 'pause';
            TraktService.instance.scrobblePause(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
            );
          }
        }
      }

      // Simkl scrobble for Android TV player — fully parallel mirror of the
      // Trakt block above (own state vars/heartbeat, same event stream, same
      // 80% rule — Simkl also finalizes watched server-side at ≥80% on stop).
      // Skips a series frame with unresolved S/E so it can't be recorded as a
      // movie (see _simklSeriesSEUnresolved).
      if (payload.simklScrobble &&
          payload.imdbId != null &&
          durationMs > 0 &&
          !_simklSeriesSEUnresolved(payload, progress)) {
        final isPlaying =
            progress['isPlaying'] == true || progress['isBuffering'] == true;
        final simklProgress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
        final imdbId = payload.imdbId!;
        final season = payload.contentType == _PlaybackContentType.series
            ? progress['season'] as int?
            : null;
        final episode = payload.contentType == _PlaybackContentType.series
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (_simklLastKnownSeason != null &&
            _simklLastKnownEpisode != null &&
            (season != _simklLastKnownSeason ||
                episode != _simklLastKnownEpisode) &&
            _simklLastScrobbleAction != 'stop') {
          _simklHeartbeatTimer?.cancel();
          _simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            _simklLastKnownProgress,
            season: _simklLastKnownSeason,
            episode: _simklLastKnownEpisode,
          );
          _simklLastScrobbleAction = 'stop';
        }

        _simklLastKnownProgress = simklProgress;
        _simklLastKnownSeason = season;
        _simklLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (_simklLastScrobbleAction == 'stop' &&
            isPlaying &&
            simklProgress <= 80 &&
            !completed) {
          _simklLastScrobbleAction = null;
        }
        if (completed && _simklLastScrobbleAction != 'stop') {
          _simklLastScrobbleAction = 'stop';
          _simklHeartbeatTimer?.cancel();
          _simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            simklProgress,
            season: season,
            episode: episode,
          );
        } else if (isPlaying &&
            _simklLastScrobbleAction != 'start' &&
            _simklLastScrobbleAction != 'stop') {
          // ≥80% would just finalize server-side — send stop, no heartbeat
          if (simklProgress > 80) {
            _simklLastScrobbleAction = 'stop';
            SimklService.instance.scrobbleStop(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          } else {
            // Pause-centric: do NOT scrobble 'start' to Simkl — it persists
            // nothing (id:0) AND wipes the existing /sync/playback resume point.
            // Leave the resume point intact; the pause-based heartbeat below
            // checkpoints it. 'start' is kept only as an in-play state marker
            // (no POST sent) so this isPlaying branch doesn't re-enter on every
            // progress tick.
            _simklLastScrobbleAction = 'start';
            // 2-minute checkpoint — comfortably above Simkl's 20s rate lock
            _simklHeartbeatTimer?.cancel();
            _simklHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              if (_simklLastKnownProgress > 80) {
                _simklLastScrobbleAction = 'stop';
                SimklService.instance.scrobbleStop(
                  payload.imdbId!,
                  _simklLastKnownProgress,
                  season: _simklLastKnownSeason,
                  episode: _simklLastKnownEpisode,
                );
                debugPrint(
                  'Simkl: Heartbeat stop at ${_simklLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                _simklHeartbeatTimer?.cancel();
                _simklHeartbeatTimer = null;
                return;
              }
              // Checkpoint a RESUMABLE position via pause. Simkl's /scrobble/start
              // saves nothing (returns id:0) AND wipes any existing /sync/playback
              // entry, so start-based heartbeats never survived a hard kill. Pause
              // is the only call that persists a resume point.
              // Keep _simklLastScrobbleAction as 'start' (do NOT set 'pause'): the
              // native player re-runs this scrobble block on every progress event,
              // and a 'pause' value would re-enter the isPlaying start-branch above
              // on the next tick, re-sending start and wiping the position we just
              // saved. 'start' keeps that branch inert while pause refreshes the
              // resume point each interval.
              _simklLastScrobbleAction = 'start';
              SimklService.instance.scrobblePause(
                payload.imdbId!,
                _simklLastKnownProgress,
                season: _simklLastKnownSeason,
                episode: _simklLastKnownEpisode,
              );
              debugPrint(
                'Simkl: Heartbeat pause checkpoint at ${_simklLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            _simklLastScrobbleAction != null &&
            _simklLastScrobbleAction != 'pause' &&
            _simklLastScrobbleAction != 'stop') {
          _simklHeartbeatTimer?.cancel();
          _simklHeartbeatTimer = null;
          if (simklProgress > 80) {
            _simklLastScrobbleAction = 'stop';
            SimklService.instance.scrobbleStop(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          } else {
            _simklLastScrobbleAction = 'pause';
            SimklService.instance.scrobblePause(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          }
        }
      }

      if (payload.contentType == _PlaybackContentType.series) {
        final season = progress['season'] as int?;
        final episode = progress['episode'] as int?;
        final seriesTitle = payload.seriesTitle ?? payload.title;
        if (season != null && episode != null) {
          await StorageService.saveSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
            imdbId: payload.imdbId,
          );

          if (completed) {
            await StorageService.markEpisodeAsFinished(
              seriesTitle: seriesTitle,
              season: season,
              episode: episode,
              imdbId: payload.imdbId,
            );
          }
        }

        if (resumeId != null && payload.items.isNotEmpty) {
          final fallbackIndex = itemIndex
              .clamp(0, payload.items.length - 1)
              .toInt();
          final item = payload.items.firstWhere(
            (i) => i.resumeId == resumeId,
            orElse: () => payload.items[fallbackIndex],
          );
          final persistedUrl =
              progressUrl ??
              (resumeId != null ? _resolvedStreamCache[resumeId] : null) ??
              item.url;

          await StorageService.saveVideoPlaybackState(
            videoTitle: resumeId,
            videoUrl: persistedUrl,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
            imdbId: payload.imdbId,
          );
        }

        return;
      }

      final items = payload.items;
      if (items.isEmpty) return;
      final fallbackIndex = itemIndex.clamp(0, items.length - 1).toInt();
      final item = resumeId != null
          ? items.firstWhere(
              (i) => i.resumeId == resumeId,
              orElse: () => items[fallbackIndex],
            )
          : items[fallbackIndex];

      final videoTitle = item.resumeId ?? item.title;
      final persistedUrl =
          progressUrl ??
          (resumeId != null ? _resolvedStreamCache[resumeId] : null) ??
          item.url;

      await StorageService.saveVideoPlaybackState(
        videoTitle: videoTitle,
        videoUrl: persistedUrl,
        positionMs: positionMs,
        durationMs: durationMs,
        speed: speed,
        aspect: aspect,
        imdbId: payload.imdbId,
      );

      if (payload.contentType == _PlaybackContentType.single) {
        await StorageService.upsertVideoResume(videoTitle, {
          'positionMs': positionMs,
          'durationMs': durationMs,
          'speed': speed,
          'aspect': aspect,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // ALSO save in collection format for Android TV playlist progress tracking
      // This allows the playlist screen to display progress indicators for collections
      if (payload.contentType == _PlaybackContentType.collection &&
          payload.seriesTitle != null) {
        debugPrint(
          '📺 AndroidTV Collection Save Check: seriesTitle="${payload.seriesTitle}", itemIndex=$fallbackIndex',
        );

        await StorageService.saveSeriesPlaybackState(
          seriesTitle: payload.seriesTitle!,
          season: 0, // Use season 0 for non-series collections
          episode: fallbackIndex + 1, // Use 1-based index as episode number
          positionMs: positionMs,
          durationMs: durationMs,
          speed: speed,
          aspect: aspect,
          imdbId: payload.imdbId,
        );

        debugPrint(
          '✅ AndroidTV Collection Save: title="${payload.seriesTitle}" S0E${fallbackIndex + 1} pos=${positionMs}ms',
        );

        // Mark as finished if completed
        if (completed) {
          await StorageService.markEpisodeAsFinished(
            seriesTitle: payload.seriesTitle!,
            season: 0,
            episode: fallbackIndex + 1,
            imdbId: payload.imdbId,
          );
          debugPrint(
            '✅ AndroidTV Collection: Marked S0E${fallbackIndex + 1} as finished',
          );
        }
      }
    } catch (e) {
      debugPrint('VideoPlayerLauncher: failed to persist progress: $e');
    }
  }

  static Future<void> _handlePlaybackFinished(
    _AndroidTvPlaybackPayload payload,
  ) async {
    debugPrint(
      'VideoPlayerLauncher: Android TV playback finished for "${payload.title}"',
    );
    // Final Trakt scrobble stop on playback exit
    // Skip if last action was 'stop' (already stopped) or 'pause' (pause already
    // created the playback entry — sending stop would create a duplicate)
    _traktHeartbeatTimer?.cancel();
    _traktHeartbeatTimer = null;
    if (payload.traktScrobble &&
        payload.imdbId != null &&
        _traktLastScrobbleAction != 'stop' &&
        _traktLastScrobbleAction != 'pause') {
      TraktService.instance.scrobbleStop(
        payload.imdbId!,
        _traktLastKnownProgress,
        season: _traktLastKnownSeason,
        episode: _traktLastKnownEpisode,
      );
    }
    _traktLastScrobbleAction = null;
    _traktLastKnownProgress = 0.0;
    _traktLastKnownSeason = null;
    _traktLastKnownEpisode = null;

    // Final Simkl scrobble stop on playback exit — parallel to the Trakt
    // cleanup above, including the same skip-after-pause nuance (a pause
    // already created Simkl's playback entry; stop would duplicate it).
    // The extra series-S/E guard: unlike the per-frame block, this direct
    // stop isn't gated by _simklSeriesSEUnresolved, so a series whose S/E
    // never resolved (every frame was skipped, last-known stays null) would
    // otherwise be finalized as a bogus movie. Skip it in that case.
    _simklHeartbeatTimer?.cancel();
    _simklHeartbeatTimer = null;
    final simklSeriesUnresolved =
        payload.contentType == _PlaybackContentType.series &&
        (_simklLastKnownSeason == null || _simklLastKnownEpisode == null);
    if (payload.simklScrobble &&
        payload.imdbId != null &&
        _simklLastScrobbleAction != 'stop' &&
        _simklLastScrobbleAction != 'pause' &&
        !simklSeriesUnresolved) {
      SimklService.instance.scrobbleStop(
        payload.imdbId!,
        _simklLastKnownProgress,
        season: _simklLastKnownSeason,
        episode: _simklLastKnownEpisode,
      );
    }
    _simklLastScrobbleAction = null;
    _simklLastKnownProgress = 0.0;
    _simklLastKnownSeason = null;
    _simklLastKnownEpisode = null;
  }

  static Future<String> _resolveEntryUrl(
    PlaylistEntry entry,
    VideoPlayerLaunchArgs args,
  ) async {
    if (entry.url.isNotEmpty) {
      // For direct stream URLs, resolve redirects to get final URL
      // (needed for HLS streams behind short URL redirects like USATV)
      return await _resolveRedirectUrl(entry.url);
    }

    final provider = entry.provider?.toLowerCase();
    final hasTorboxMetadata =
        entry.torboxTorrentId != null && entry.torboxFileId != null;
    final hasTorboxWebDownloadMetadata =
        entry.torboxWebDownloadId != null && entry.torboxFileId != null;

    if (provider == 'torbox' ||
        hasTorboxMetadata ||
        hasTorboxWebDownloadMetadata) {
      final torrentId = entry.torboxTorrentId;
      final webDownloadId = entry.torboxWebDownloadId;
      final fileId = entry.torboxFileId;
      if (fileId == null || (torrentId == null && webDownloadId == null)) {
        throw Exception('Torbox file metadata missing');
      }
      final apiKey = await StorageService.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Torbox API key');
      }
      String url;
      if (webDownloadId != null) {
        // Web download - use web download API
        url = await TorboxService.requestWebDownloadFileLink(
          apiKey: apiKey,
          webId: webDownloadId,
          fileId: fileId,
        );
      } else {
        // Torrent - use torrent API
        url = await TorboxService.requestFileDownloadLink(
          apiKey: apiKey,
          torrentId: torrentId!,
          fileId: fileId,
        );
      }
      if (url.isEmpty) {
        throw Exception('Torbox returned an empty stream URL');
      }
      return url;
    }

    // PikPak lazy resolution
    final hasPikPakMetadata = entry.pikpakFileId != null;
    if (provider == 'pikpak' || hasPikPakMetadata) {
      final fileId = entry.pikpakFileId;
      if (fileId == null) {
        throw Exception('PikPak file metadata missing');
      }
      final pikpak = PikPakApiService.instance;
      final fileData = await pikpak.getFileDetails(fileId);
      final url = pikpak.getStreamingUrl(fileData);
      if (url == null || url.isEmpty) {
        throw Exception('PikPak returned an empty stream URL');
      }
      return url;
    }

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await StorageService.getPremiumizeApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      final file = await PremiumizeService.resolveItemById(
        apiKey,
        entry.premiumizeItemId!,
      );
      if (file == null || file.link.isEmpty) {
        throw Exception('File not found in Premiumize cloud');
      }
      return file.link;
    }

    // Premiumize lazy resolution: re-fetch direct links by infohash and match
    // the file by its stored path (Premiumize direct links eventually expire).
    final hasPremiumizeMetadata =
        entry.premiumizeHash != null && entry.premiumizePath != null;
    if (provider == 'premiumize' || hasPremiumizeMetadata) {
      final hash = entry.premiumizeHash;
      final path = entry.premiumizePath;
      if (hash != null && hash.isNotEmpty && path != null && path.isNotEmpty) {
        final apiKey = await StorageService.getPremiumizeApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('Missing Premiumize API key');
        }
        final files = await PremiumizeService.resolveFilesByHash(apiKey, hash);
        final match = files.firstWhere(
          (f) => f.path == path,
          orElse: () => throw Exception('File not found in Premiumize cloud'),
        );
        if (match.link.isEmpty) {
          throw Exception('Premiumize returned an empty stream URL');
        }
        return match.link;
      }
    }

    if (entry.restrictedLink != null && entry.restrictedLink!.isNotEmpty) {
      final apiKey = await StorageService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        entry.restrictedLink!,
      );
      final url = unrestrictResult['download']?.toString() ?? '';
      if (url.isEmpty) {
        throw Exception('Real Debrid returned an empty stream URL');
      }
      return url;
    }

    // AllDebrid lazy resolution: unlock the stored locked link on demand.
    if (provider == 'alldebrid' ||
        (entry.allDebridLink != null && entry.allDebridLink!.isNotEmpty)) {
      final lockedLink = entry.allDebridLink;
      if (lockedLink == null || lockedLink.isEmpty) {
        throw Exception('AllDebrid link metadata missing');
      }
      final apiKey = await StorageService.getAllDebridApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing AllDebrid API key');
      }
      final url = await AllDebridService.unlockLink(apiKey, lockedLink);
      if (url.isEmpty) {
        throw Exception('AllDebrid returned an empty stream URL');
      }
      return url;
    }

    if (args.videoUrl.isNotEmpty) {
      return args.videoUrl;
    }

    throw Exception('No URL metadata available for this entry');
  }
}

enum _PlaybackContentType { single, collection, series }

class _AndroidTvPlaybackPayload {
  final _PlaybackContentType contentType;
  final String title;
  final String? subtitle;
  final List<_AndroidTvPlaybackItem> items;
  final int startIndex;
  final String? seriesTitle;
  final List<_AndroidTvSeriesSeason> seasons;
  final Map<int, int> nextEpisodeMap;
  final Map<int, int> prevEpisodeMap;
  final List<_AndroidTvCollectionGroup>? collectionGroups;
  final String? imdbId;
  final Map<String, String>? httpHeaders;

  final double? startAtPercent;
  final List<Map<String, dynamic>>? stremioSources;
  final int? stremioCurrentSourceIndex;
  final bool hasPlaylistResolver;
  final bool traktScrobble;
  final double? traktProgressPercent;
  // Simkl parallel pair. Only the scrobble flag matters Dart-side (the
  // progress percent folds into the native resume seed via toMap below).
  final bool simklScrobble;
  final double? simklProgressPercent;
  // Subtitle tracks known at launch (e.g. YouTube captions), surfaced natively
  // as a pre-loaded provider group without an addon fetch.
  final List<StremioSubtitle>? initialSubtitles;

  const _AndroidTvPlaybackPayload({
    required this.contentType,
    required this.title,
    required this.subtitle,
    required this.items,
    required this.startIndex,
    required this.seriesTitle,
    required this.seasons,
    this.nextEpisodeMap = const {},
    this.prevEpisodeMap = const {},
    this.collectionGroups,
    this.imdbId,
    this.httpHeaders,
    this.startAtPercent,
    this.stremioSources,
    this.stremioCurrentSourceIndex,
    this.hasPlaylistResolver = false,
    this.traktScrobble = false,
    this.traktProgressPercent,
    this.simklScrobble = false,
    this.simklProgressPercent,
    this.initialSubtitles,
  });

  /// The effective cross-tracker launch resume percent: the FURTHEST of the
  /// Trakt and Simkl promises (each 0-100, exclusive). The native player only
  /// knows one launch-resume input (`traktProgressPercent` in the map below),
  /// so the three-way merge happens here — native then reconciles this
  /// explicit percent against its local position as before.
  double? get _effectiveLaunchPercent {
    double? best;
    for (final pct in [traktProgressPercent, simklProgressPercent]) {
      if (pct == null || pct <= 0 || pct >= 100) continue;
      if (best == null || pct > best) best = pct;
    }
    return best;
  }

  Map<String, dynamic> toMap() {
    return {
      'version': 1,
      'title': title,
      'subtitle': subtitle,
      'contentType': contentType.name,
      'startIndex': startIndex,
      'seriesTitle': seriesTitle,
      'items': items.map((e) => e.toMap()).toList(),
      'seasons': seasons.map((e) => e.toMap()).toList(),
      'nextEpisodeMap': nextEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'prevEpisodeMap': prevEpisodeMap.map((k, v) => MapEntry(k.toString(), v)),
      'collectionGroups': collectionGroups?.map((e) => e.toMap()).toList(),
      'imdbId': imdbId,
      if (httpHeaders != null && httpHeaders!.isNotEmpty)
        'httpHeaders': httpHeaders,
      if (startAtPercent != null && startAtPercent! > 0)
        'startAtPercent': startAtPercent,
      if (stremioSources != null && stremioSources!.isNotEmpty)
        'stremioSources': stremioSources,
      if (stremioCurrentSourceIndex != null)
        'stremioCurrentSourceIndex': stremioCurrentSourceIndex,
      if (hasPlaylistResolver) 'hasPlaylistResolver': true,
      // Keyed 'traktProgressPercent' for the native side's existing resume
      // input, but carries the furthest of the Trakt/Simkl launch percents.
      if (_effectiveLaunchPercent != null)
        'traktProgressPercent': _effectiveLaunchPercent,
      if (initialSubtitles != null && initialSubtitles!.isNotEmpty)
        'initialSubtitles': [
          for (final s in initialSubtitles!)
            {
              'id': s.id,
              'url': s.url,
              'lang': s.lang,
              if (s.label != null) 'label': s.label,
              'source': s.source,
            },
        ],
    };
  }
}

class _AndroidTvPlaybackItem {
  final String id;
  final String title;
  final String url;
  final String? hdVideoUrl;
  final String? audioUrl;
  final int index;
  final int? season;
  final int? episode;
  final String? artwork;
  final String? description;
  final int? sizeBytes;
  final int resumePositionMs;
  final int durationMs;
  final int updatedAt;
  final String? resumeId;
  final String? provider;
  // Cross-device progress for this episode (0-100), or null. The legacy field
  // name is retained for the Kotlin payload, but the value is the furthest of
  // Trakt and Simkl.
  final double? traktProgressPercent;

  const _AndroidTvPlaybackItem({
    required this.id,
    required this.title,
    required this.url,
    this.hdVideoUrl,
    this.audioUrl,
    required this.index,
    required this.season,
    required this.episode,
    required this.artwork,
    required this.description,
    required this.sizeBytes,
    required this.resumePositionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.resumeId,
    required this.provider,
    this.traktProgressPercent,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      if (hdVideoUrl != null) 'hdVideoUrl': hdVideoUrl,
      if (audioUrl != null) 'audioUrl': audioUrl,
      'index': index,
      'season': season,
      'episode': episode,
      'artwork': artwork,
      'description': description,
      'sizeBytes': sizeBytes,
      'resumePositionMs': resumePositionMs,
      'durationMs': durationMs,
      'updatedAt': updatedAt,
      'resumeId': resumeId,
      'provider': provider,
      if (traktProgressPercent != null)
        'traktProgressPercent': traktProgressPercent,
    };
  }
}

class _AndroidTvSeriesSeason {
  final int seasonNumber;
  final List<_AndroidTvSeriesEpisode> episodes;

  const _AndroidTvSeriesSeason({
    required this.seasonNumber,
    required this.episodes,
  });

  Map<String, dynamic> toMap() {
    return {
      'seasonNumber': seasonNumber,
      'episodes': episodes.map((e) => e.toMap()).toList(),
    };
  }
}

class _AndroidTvCollectionGroup {
  final String name;
  final List<int> fileIndices;

  const _AndroidTvCollectionGroup({
    required this.name,
    required this.fileIndices,
  });

  Map<String, dynamic> toMap() {
    return {'name': name, 'fileIndices': fileIndices};
  }
}

class _AndroidTvSeriesEpisode {
  final String title;
  final int? season;
  final int? episode;
  final String? description;
  final String? artwork;

  const _AndroidTvSeriesEpisode({
    required this.title,
    required this.season,
    required this.episode,
    required this.description,
    required this.artwork,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'season': season,
      'episode': episode,
      'description': description,
      'artwork': artwork,
    };
  }
}

class _AndroidTvPlaybackPayloadResult {
  final _AndroidTvPlaybackPayload payload;
  final List<_LauncherEntry> entries;

  const _AndroidTvPlaybackPayloadResult({
    required this.payload,
    required this.entries,
  });
}

class _LauncherEntry {
  final PlaylistEntry entry;
  final String resumeId;
  final int index;

  const _LauncherEntry({
    required this.entry,
    required this.resumeId,
    required this.index,
  });
}

class _AndroidTvPlaylistResolver {
  List<_LauncherEntry> entries;
  final Future<String> Function(PlaylistEntry entry) resolveEntry;

  // Monotonic token for in-flight source switches. The native side already
  // discards stale playlist RESULTS via its own resolution token, but the Dart
  // `replaceEntries` side effect was ungated: tap B then C quickly and, if B's
  // torrent resolves slower, B's `replaceEntries` could run LAST and leave the
  // lazy stream resolver pointing at B while the player shows C — wrong-torrent
  // lazy resolution. Each switch captures a token via [beginSwitch]; a late
  // [replaceEntries] whose token is no longer current is ignored.
  int _switchSeq = 0;
  int beginSwitch() => ++_switchSeq;
  bool isLatestSwitch(int token) => token == _switchSeq;

  _AndroidTvPlaylistResolver({
    required this.entries,
    required this.resolveEntry,
  });

  /// Replace entries with a new playlist (used during source switching).
  /// Pass the [switchToken] from [beginSwitch] so a stale (superseded) switch
  /// that resolves late is skipped instead of overwriting a newer source.
  void replaceEntries(List<PlaylistEntry> playlistEntries, {int? switchToken}) {
    if (switchToken != null && switchToken != _switchSeq) {
      debugPrint(
        'AndroidTvPlaylistResolver: skipping stale replaceEntries '
        '(token $switchToken != current $_switchSeq)',
      );
      return;
    }
    // Clear cached URLs for old entries before replacing
    _clearResolvedStreams(entries.map((e) => e.resumeId));

    entries = playlistEntries.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      return _LauncherEntry(
        entry: entry,
        index: i,
        resumeId: '${entry.title}_$i',
      );
    }).toList();
    debugPrint(
      'AndroidTvPlaylistResolver: replaced entries with ${entries.length} new entries',
    );
  }

  Future<Map<String, dynamic>?> handleRequest(
    Map<String, dynamic> request,
  ) async {
    debugPrint(
      'AndroidTvPlaylistResolver: handleRequest called with: $request',
    );
    debugPrint('AndroidTvPlaylistResolver: total entries: ${entries.length}');

    _LauncherEntry? target;
    final resumeId = request['resumeId'] as String?;
    final index = request['index'] as int?;

    debugPrint(
      'AndroidTvPlaylistResolver: looking for - resumeId: $resumeId, index: $index',
    );

    if (resumeId != null) {
      target = entries.firstWhereOrNull((entry) => entry.resumeId == resumeId);
      debugPrint(
        'AndroidTvPlaylistResolver: found by resumeId: ${target != null}',
      );
    }
    if (target == null &&
        index != null &&
        index >= 0 &&
        index < entries.length) {
      target = entries[index];
      debugPrint(
        'AndroidTvPlaylistResolver: found by index: ${target != null}, entry: ${target?.entry.title}',
      );
    }
    if (target == null) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - target not found!');
      debugPrint('AndroidTvPlaylistResolver: Available entries:');
      for (int i = 0; i < entries.length; i++) {
        debugPrint(
          '  [$i] resumeId=${entries[i].resumeId}, title=${entries[i].entry.title}',
        );
      }
      return null;
    }

    debugPrint(
      'AndroidTvPlaylistResolver: resolving entry for: ${target.entry.title}',
    );
    final url = await resolveEntry(target.entry);
    debugPrint(
      'AndroidTvPlaylistResolver: resolved URL: ${url.isNotEmpty ? url.substring(0, min(50, url.length)) : "EMPTY"}',
    );

    if (url.isEmpty) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - resolved URL is empty!');
      return null;
    }

    _cacheResolvedStream(target.resumeId, url);
    debugPrint(
      'AndroidTvPlaylistResolver: returning success - url length: ${url.length}',
    );
    return {
      'url': url,
      'resumeId': target.resumeId,
      'index': target.index,
      'provider': target.entry.provider,
    };
  }

  void dispose() {
    _clearResolvedStreams(entries.map((e) => e.resumeId));
  }
}

class _AndroidTvPlaybackPayloadBuilder {
  final VideoPlayerLaunchArgs args;

  const _AndroidTvPlaybackPayloadBuilder(this.args);

  Future<_AndroidTvPlaybackPayloadResult?> build() async {
    final playlistEntries = _normalizePlaylist();
    final seriesPlaylist = await _buildSeriesPlaylist(playlistEntries);
    final contentType = _determineContentType(seriesPlaylist, playlistEntries);
    final perItemStates = await _fetchPerItemPlaybackState(playlistEntries);
    // Cross-device per-episode progress ("season_episode" → 0-100) for playlist
    // bars and in-session episode resume. The native payload retains its legacy
    // `traktProgressPercent` field name, but each value is the furthest of Trakt
    // and Simkl.
    final trackerProgressMaps = args.contentImdbId != null
        ? await Future.wait([
            StorageService.getEpisodeTraktProgress(imdbId: args.contentImdbId!),
            StorageService.getEpisodeSimklProgress(imdbId: args.contentImdbId!),
          ])
        : const <Map<String, double>>[];
    final traktProgress = trackerProgressMaps.isNotEmpty
        ? trackerProgressMaps[0]
        : const <String, double>{};
    final simklProgress = trackerProgressMaps.length > 1
        ? trackerProgressMaps[1]
        : const <String, double>{};
    final startIndex = await _determineStartIndex(
      contentType,
      seriesPlaylist,
      playlistEntries,
      perItemStates,
    );

    final preparedEntries = await _prepareEntries(playlistEntries, startIndex);
    final seasons = _buildSeriesSeasons(seriesPlaylist);

    final launcherEntries = <_LauncherEntry>[];
    final items = <_AndroidTvPlaybackItem>[];

    for (int i = 0; i < preparedEntries.length; i++) {
      final entry = preparedEntries[i];
      final resumeId = _resumeIdForEntry(entry);
      if (entry.url.isNotEmpty) {
        _cacheResolvedStream(resumeId, entry.url);
      }
      launcherEntries.add(
        _LauncherEntry(entry: entry, resumeId: resumeId, index: i),
      );

      final resumeInfo = i < perItemStates.length
          ? perItemStates[i]
          : const _PerItemState();

      SeriesEpisode? episodeInfo;
      if (seriesPlaylist != null) {
        episodeInfo = seriesPlaylist.allEpisodes.firstWhereOrNull(
          (episode) => episode.originalIndex == i,
        );
      }
      if (episodeInfo == null) {
        var fallbackInfo = SeriesParser.parseFilename(entry.title);
        // Single stream whose title has no parseable S##E## (e.g. an addon
        // stream named "Torrentio 1080p"): fall back to the episode identity
        // the caller provided. Without it the TV player's item has null
        // season/episode and can never hand back a Next Episode request
        // (AndroidTvTorrentPlayerActivity.playNext requires both) — the
        // Flutter player has the same fallback via widget.contentSeason.
        if (preparedEntries.length == 1 &&
            (fallbackInfo.season == null || fallbackInfo.episode == null) &&
            args.contentSeason != null &&
            args.contentEpisode != null) {
          fallbackInfo = fallbackInfo.copyWith(
            season: args.contentSeason,
            episode: args.contentEpisode,
          );
        }
        episodeInfo = SeriesEpisode(
          url: entry.url,
          title: entry.title,
          filename: entry.title,
          seriesInfo: fallbackInfo,
          originalIndex: i,
        );
      }

      // Use TVMaze episode title if available, otherwise fallback to entry title
      final displayTitle = episodeInfo.episodeInfo?.title?.isNotEmpty == true
          ? episodeInfo.episodeInfo!.title!
          : entry.title;

      items.add(
        _AndroidTvPlaybackItem(
          id: entry.url.isNotEmpty ? entry.url : '${entry.title}_$i',
          title: displayTitle,
          url: entry.url,
          hdVideoUrl: entry.hdVideoUrl,
          audioUrl: entry.audioUrl,
          index: i,
          season: episodeInfo.seriesInfo.season,
          episode: episodeInfo.seriesInfo.episode,
          artwork: episodeInfo.episodeInfo?.poster,
          description: episodeInfo.episodeInfo?.plot,
          sizeBytes: entry.sizeBytes,
          resumePositionMs: resumeInfo.positionMs,
          durationMs: resumeInfo.durationMs,
          updatedAt: resumeInfo.updatedAt,
          resumeId: resumeId,
          provider: entry.provider,
          traktProgressPercent:
              (episodeInfo.seriesInfo.season != null &&
                  episodeInfo.seriesInfo.episode != null)
              ? furthestEpisodeTrackerPercent([
                  traktProgress['${episodeInfo.seriesInfo.season}_${episodeInfo.seriesInfo.episode}'],
                  simklProgress['${episodeInfo.seriesInfo.season}_${episodeInfo.seriesInfo.episode}'],
                ])
              : null,
        ),
      );
    }

    // Build navigation maps based on SeriesPlaylist.allEpisodes ordering
    // This mirrors mobile video_player_screen.dart's navigation exactly
    final navigationMaps = _buildNavigationMaps(seriesPlaylist, items);

    // Build collection groups for movie collections
    List<_AndroidTvCollectionGroup>? collectionGroups;
    if (contentType == _PlaybackContentType.collection &&
        launcherEntries.isNotEmpty) {
      // Extract PlaylistEntry objects from _LauncherEntry wrappers
      final playlistEntries = launcherEntries.map((e) => e.entry).toList();

      // Create MovieCollection based on view mode:
      // - Raw: Preserve folder structure as-is
      // - Sorted: Files are already sorted A-Z in playlist, create single group
      // - Series/Other: Use Main/Extras grouping (40% threshold)
      debugPrint(
        '🎬 MovieCollection: viewMode=${args.viewMode}, contentType=$contentType',
      );
      final MovieCollection movieCollection;
      if (args.viewMode == PlaylistViewMode.raw) {
        debugPrint('🎬 Using fromFolderStructure (Raw mode)');
        movieCollection = MovieCollection.fromFolderStructure(
          playlist: playlistEntries,
          title: args.title,
        );
      } else if (args.viewMode == PlaylistViewMode.sorted) {
        debugPrint('🎬 Using fromSortedPlaylist (Sort A-Z mode)');
        movieCollection = MovieCollection.fromSortedPlaylist(
          playlist: playlistEntries,
          title: args.title,
        );
      } else {
        debugPrint(
          '🎬 Using fromPlaylistWithMainExtras (Main/Extras mode) - viewMode is ${args.viewMode}',
        );
        movieCollection = MovieCollection.fromPlaylistWithMainExtras(
          playlist: playlistEntries,
          title: args.title,
        );
      }

      // Convert to Android TV collection groups
      collectionGroups = movieCollection.groups
          .where(
            (group) => group.fileIndices.isNotEmpty,
          ) // Only include non-empty groups
          .map(
            (group) => _AndroidTvCollectionGroup(
              name: group.name,
              fileIndices: group.fileIndices,
            ),
          )
          .toList();

      debugPrint(
        'VideoPlayerLauncher: Created ${collectionGroups.length} collection groups for Android TV',
      );
      for (final group in collectionGroups) {
        debugPrint('  - ${group.name}: ${group.fileIndices.length} files');
      }
    }

    // For non-series content without IMDB ID, try to fetch from Cinemeta
    String? effectiveImdbId = args.contentImdbId;
    if (effectiveImdbId == null && contentType != _PlaybackContentType.series) {
      effectiveImdbId = await _fetchMovieImdbId(items, startIndex);
    }

    final payload = _AndroidTvPlaybackPayload(
      contentType: contentType,
      title: args.title,
      subtitle: args.subtitle,
      items: items,
      startIndex: startIndex,
      seriesTitle: seriesPlaylist?.seriesTitle,
      seasons: seasons,
      nextEpisodeMap: navigationMaps.nextMap,
      prevEpisodeMap: navigationMaps.prevMap,
      collectionGroups: collectionGroups,
      imdbId: effectiveImdbId,
      httpHeaders: args.httpHeaders?.isNotEmpty == true
          ? Map<String, String>.from(args.httpHeaders!)
          : null,
      startAtPercent: args.startAtPercent,
      stremioSources: args.stremioSources?.map((t) => t.toJson()).toList(),
      stremioCurrentSourceIndex: args.stremioCurrentSourceIndex,
      hasPlaylistResolver: args.resolveSourceToPlaylist != null,
      traktScrobble: args.traktScrobble,
      traktProgressPercent: args.traktProgressPercent,
      simklScrobble: args.simklScrobble,
      simklProgressPercent: args.simklProgressPercent,
      initialSubtitles: args.initialSubtitles,
    );

    return _AndroidTvPlaybackPayloadResult(
      payload: payload,
      entries: launcherEntries,
    );
  }

  /// Fetch movie IMDB ID from Cinemeta for Android TV playback
  /// Returns IMDB ID if found, null otherwise
  Future<String?> _fetchMovieImdbId(
    List<_AndroidTvPlaybackItem> items,
    int startIndex,
  ) async {
    // Get the title to parse - prefer the starting item, fall back to args.title
    String titleToParse;
    if (startIndex >= 0 && startIndex < items.length) {
      titleToParse = items[startIndex].title;
    } else if (items.isNotEmpty) {
      titleToParse = items.first.title;
    } else {
      titleToParse = args.title;
    }

    debugPrint('AndroidTV MovieMetadata: Checking title "$titleToParse"');

    // Parse the title for movie info
    final movieInfo = MovieParser.parseFilename(titleToParse);

    if (!movieInfo.hasYear) {
      debugPrint('AndroidTV MovieMetadata: No year pattern, skipping lookup');
      return null;
    }

    if (movieInfo.title == null || movieInfo.title!.isEmpty) {
      debugPrint('AndroidTV MovieMetadata: Could not extract title');
      return null;
    }

    debugPrint(
      'AndroidTV MovieMetadata: Parsed title="${movieInfo.title}", year=${movieInfo.year}',
    );

    try {
      final metadata = await MovieMetadataService.lookupMovie(
        movieInfo.title!,
        movieInfo.year,
      );

      if (metadata != null) {
        debugPrint(
          'AndroidTV MovieMetadata: Found IMDB ID "${metadata.imdbId}"',
        );
        return metadata.imdbId;
      } else {
        debugPrint('AndroidTV MovieMetadata: No match found in Cinemeta');
        return null;
      }
    } catch (e) {
      debugPrint('AndroidTV MovieMetadata: Error during lookup: $e');
      return null;
    }
  }

  /// Build navigation maps based on SeriesPlaylist.allEpisodes ordering
  /// Maps originalIndex -> nextOriginalIndex and originalIndex -> prevOriginalIndex
  /// This mirrors exactly how mobile video_player_screen.dart navigates episodes
  _NavigationMaps _buildNavigationMaps(
    SeriesPlaylist? seriesPlaylist,
    List<_AndroidTvPlaybackItem> items,
  ) {
    final nextMap = <int, int>{};
    final prevMap = <int, int>{};

    if (seriesPlaylist == null || !seriesPlaylist.isSeries) {
      // For non-series content, use simple sequential navigation
      for (int i = 0; i < items.length; i++) {
        if (i + 1 < items.length) {
          nextMap[i] = i + 1;
        }
        if (i > 0) {
          prevMap[i] = i - 1;
        }
      }
      return _NavigationMaps(nextMap: nextMap, prevMap: prevMap);
    }

    // For series content, use SeriesPlaylist.allEpisodes ordering
    // allEpisodes is already sorted by season/episode in SeriesPlaylist.fromPlaylistEntries
    final allEpisodes = seriesPlaylist.allEpisodes;

    for (int i = 0; i < allEpisodes.length; i++) {
      final currentOriginalIndex = allEpisodes[i].originalIndex;

      if (i + 1 < allEpisodes.length) {
        final nextOriginalIndex = allEpisodes[i + 1].originalIndex;
        nextMap[currentOriginalIndex] = nextOriginalIndex;
      }

      if (i > 0) {
        final prevOriginalIndex = allEpisodes[i - 1].originalIndex;
        prevMap[currentOriginalIndex] = prevOriginalIndex;
      }
    }

    debugPrint(
      'VideoPlayerLauncher: Built navigation maps - next: ${nextMap.length}, prev: ${prevMap.length}',
    );
    return _NavigationMaps(nextMap: nextMap, prevMap: prevMap);
  }

  List<PlaylistEntry> _normalizePlaylist() {
    final playlist = args.playlist;
    if (playlist != null && playlist.isNotEmpty) {
      return playlist;
    }
    // For high-res YouTube, [videoUrl] is a video-only HD track and [audioUrl]
    // its audio. Use the muxed [fallbackUrl] as the base (never-silent) url and
    // carry the HD video/audio pair for ExoPlayer to merge.
    if (args.audioUrl != null && args.audioUrl!.isNotEmpty) {
      return [
        PlaylistEntry(
          url: (args.fallbackUrl != null && args.fallbackUrl!.isNotEmpty)
              ? args.fallbackUrl!
              : args.videoUrl,
          hdVideoUrl: args.videoUrl,
          audioUrl: args.audioUrl,
          title: args.title,
        ),
      ];
    }
    return [PlaylistEntry(url: args.videoUrl, title: args.title)];
  }

  Future<List<PlaylistEntry>> _prepareEntries(
    List<PlaylistEntry> entries,
    int startIndex,
  ) async {
    final prepared = <PlaylistEntry>[];
    for (int i = 0; i < entries.length; i++) {
      final entry = entries[i];

      // For start index entry, always resolve (handles redirects for direct streams)
      if (i == startIndex) {
        final resolved = await VideoPlayerLauncher._resolveEntryUrl(
          entry,
          args,
        );
        if (resolved.isEmpty) {
          throw Exception('Failed to resolve initial stream');
        }
        // Only create new entry if URL changed
        if (resolved != entry.url) {
          prepared.add(
            PlaylistEntry(
              url: resolved,
              title: entry.title,
              hdVideoUrl: entry.hdVideoUrl,
              audioUrl: entry.audioUrl,
              relativePath: entry.relativePath,
              restrictedLink: entry.restrictedLink,
              torrentHash: entry.torrentHash,
              sizeBytes: entry.sizeBytes,
              provider: entry.provider,
              torboxTorrentId: entry.torboxTorrentId,
              torboxWebDownloadId: entry.torboxWebDownloadId,
              torboxFileId: entry.torboxFileId,
              pikpakFileId: entry.pikpakFileId,
              rdTorrentId: entry.rdTorrentId,
              rdLinkIndex: entry.rdLinkIndex,
              premiumizeHash: entry.premiumizeHash,
              premiumizePath: entry.premiumizePath,
              premiumizeItemId: entry.premiumizeItemId,
              allDebridLink: entry.allDebridLink,
            ),
          );
        } else {
          prepared.add(entry);
        }
        continue;
      }

      // Non-start entries are added as-is (will be resolved lazily if needed)
      prepared.add(entry);
    }
    return prepared;
  }

  Future<List<_PerItemState>> _fetchPerItemPlaybackState(
    List<PlaylistEntry> entries,
  ) async {
    final result = <_PerItemState>[];
    for (final entry in entries) {
      final resumeId = _resumeIdForEntry(entry);
      result.add(await _readVideoState(resumeId));
    }
    return result;
  }

  Future<_PerItemState> _readVideoState(String resumeId) async {
    final data = await StorageService.getVideoPlaybackState(
      videoTitle: resumeId,
    );
    if (data == null) {
      return const _PerItemState();
    }
    return _PerItemState(
      positionMs: (data['positionMs'] ?? 0) as int,
      durationMs: (data['durationMs'] ?? 0) as int,
      updatedAt: (data['updatedAt'] ?? 0) as int,
    );
  }

  Future<SeriesPlaylist?> _buildSeriesPlaylist(
    List<PlaylistEntry> entries,
  ) async {
    if (entries.length < 2) {
      return null;
    }
    try {
      // Determine forceSeries: prefer viewMode, then use contentType from catalog
      bool? forceSeries = args.viewMode?.toForceSeries();
      if (forceSeries == null && args.contentType != null) {
        // Use catalog content type: 'series' -> force series, 'movie' -> force not series
        forceSeries = args.contentType == 'series';
      }

      final playlist = SeriesPlaylist.fromPlaylistEntries(
        entries,
        collectionTitle:
            args.title, // Pass collection/torrent title as fallback
        forceSeries: forceSeries,
      );
      // DO NOT await fetchEpisodeInfo() here - TVMaze loading is now async
      // Metadata will be fetched and pushed separately after playback launches
      // This mirrors mobile behavior where TVMaze doesn't block initial playback
      return playlist;
    } catch (_) {
      return null;
    }
  }

  _PlaybackContentType _determineContentType(
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
  ) {
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      return _PlaybackContentType.series;
    }
    // Caller explicitly declared a series episode with full context
    // (imdbId + season + episode). Quick Play from TorrentSearchScreen hits
    // this path: one torrent, but we already know the show IMDb ID and S/E,
    // so the native player needs series mode to enable Trakt scrobble,
    // next-episode navigation, and series-aware subtitle fetching.
    if (args.contentType == 'series' &&
        args.contentImdbId != null &&
        args.contentSeason != null &&
        args.contentEpisode != null) {
      return _PlaybackContentType.series;
    }
    if (entries.length > 1) {
      return _PlaybackContentType.collection;
    }
    return _PlaybackContentType.single;
  }

  Future<int> _determineStartIndex(
    _PlaybackContentType contentType,
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
    List<_PerItemState> perItemState,
  ) async {
    switch (contentType) {
      case _PlaybackContentType.series:
        return await _determineSeriesStartIndex(seriesPlaylist);
      case _PlaybackContentType.collection:
        return _determineCollectionStartIndex(entries, perItemState);
      case _PlaybackContentType.single:
        return args.startIndex ?? 0;
    }
  }

  Future<int> _determineSeriesStartIndex(SeriesPlaylist? playlist) async {
    // If auto-resume is disabled, use startIndex directly
    if (args.disableAutoResume) {
      debugPrint(
        'AndroidTV: auto-resume disabled, using startIndex=${args.startIndex ?? 0}',
      );
      return args.startIndex ?? 0;
    }

    if (playlist == null || playlist.allEpisodes.isEmpty) {
      return args.startIndex ?? 0;
    }

    // Target episode override (e.g. Trakt Quick Play next episode)
    final hadExplicitTarget =
        args.contentSeason != null && args.contentEpisode != null;
    if (hadExplicitTarget) {
      final targetIndex = playlist.findOriginalIndexBySeasonEpisode(
        args.contentSeason!,
        args.contentEpisode!,
      );
      if (targetIndex != -1) {
        debugPrint(
          'AndroidTV: target episode S${args.contentSeason}E${args.contentEpisode} → index=$targetIndex',
        );
        return targetIndex;
      }
    }

    // Only resume from last-played when NO explicit episode was requested. When
    // a target WAS requested but isn't in this pack, falling back to last-played
    // would replay the just-finished episode (the "Next replays the same
    // episode" bug), so skip straight to the first episode below.
    final lastEpisode = hadExplicitTarget
        ? null
        : await StorageService.getLastPlayedEpisode(
            seriesTitle: playlist.seriesTitle ?? 'Unknown Series',
          );
    if (lastEpisode == null) {
      final candidate = playlist.getFirstEpisodeOriginalIndex();
      if (candidate == -1) {
        return args.startIndex ?? 0;
      }
      final maxIndex = playlist.allEpisodes.length - 1;
      return candidate.clamp(0, maxIndex).toInt();
    }
    final originalIndex = playlist.findOriginalIndexBySeasonEpisode(
      lastEpisode['season'] as int,
      lastEpisode['episode'] as int,
    );
    if (originalIndex != -1) {
      return originalIndex;
    }
    final fallback = playlist.getFirstEpisodeOriginalIndex();
    if (fallback == -1) {
      return args.startIndex ?? 0;
    }
    final maxIndex = playlist.allEpisodes.isEmpty
        ? 0
        : (playlist.allEpisodes.length - 1);
    return (fallback.clamp(0, maxIndex) as num).toInt();
  }

  int _determineCollectionStartIndex(
    List<PlaylistEntry> entries,
    List<_PerItemState> perItemState,
  ) {
    // If auto-resume is disabled, use explicit start index
    if (args.disableAutoResume) {
      debugPrint(
        'AndroidTV: auto-resume disabled for collection, using startIndex=${args.startIndex ?? 0}',
      );
      return args.startIndex ?? 0;
    }

    // Find most recently watched item
    int bestIndex = -1;
    int bestUpdatedAt = -1;
    for (int i = 0; i < entries.length; i++) {
      final state = perItemState[i];
      if (state.updatedAt > bestUpdatedAt && state.updatedAt > 0) {
        bestUpdatedAt = state.updatedAt;
        bestIndex = i;
      }
    }
    if (bestIndex != -1) {
      return bestIndex;
    }

    // Raw mode: start at first file (index 0)
    if (args.viewMode == PlaylistViewMode.raw) {
      return 0;
    }

    // Sorted/collection mode: start at first Main group file
    final indices = _getMainGroupIndices(entries);
    if (indices.isNotEmpty) {
      return indices.first;
    }

    return args.startIndex ?? 0;
  }

  List<_AndroidTvSeriesSeason> _buildSeriesSeasons(SeriesPlaylist? playlist) {
    if (playlist == null) {
      return const [];
    }
    final seasons = <_AndroidTvSeriesSeason>[];
    for (final season in playlist.seasons) {
      final episodes = season.episodes.map((episode) {
        return _AndroidTvSeriesEpisode(
          title: episode.displayTitle,
          season: episode.seriesInfo.season,
          episode: episode.seriesInfo.episode,
          description: episode.episodeInfo?.plot,
          artwork: episode.episodeInfo?.poster,
        );
      }).toList();
      seasons.add(
        _AndroidTvSeriesSeason(
          seasonNumber: season.seasonNumber,
          episodes: episodes,
        ),
      );
    }
    return seasons;
  }

  List<int> _getMainGroupIndices(List<PlaylistEntry> entries) {
    int maxSize = -1;
    for (final e in entries) {
      final s = e.sizeBytes ?? -1;
      if (s > maxSize) maxSize = s;
    }
    final double threshold = maxSize > 0 ? maxSize * 0.40 : -1;
    final main = <int>[];
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isSmall =
          threshold > 0 && (e.sizeBytes != null && e.sizeBytes! < threshold);
      if (!isSmall) main.add(i);
    }
    int sizeOf(int idx) => entries[idx].sizeBytes ?? -1;
    int? yearOf(int idx) {
      final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(entries[idx].title);
      if (m != null) return int.tryParse(m.group(0)!);
      return null;
    }

    main.sort((a, b) {
      final yearA = yearOf(a);
      final yearB = yearOf(b);
      if (yearA != null && yearB != null) {
        return yearA.compareTo(yearB);
      }
      return sizeOf(b).compareTo(sizeOf(a));
    });

    if (main.isEmpty) {
      return List<int>.generate(entries.length, (i) => i);
    }
    return main;
  }

  /// Generate resume ID for a playlist entry - MUST match mobile video_player_screen.dart
  /// This ensures Android TV and mobile share the same resume state
  String _resumeIdForEntry(PlaylistEntry entry) {
    return VideoPlayerLauncher.resumeIdForEntry(
      entry,
      fallbackTitle: args.title,
    );
  }
}

class _PerItemState {
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  const _PerItemState({
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAt = 0,
  });
}

/// Navigation maps for series playback
/// Maps originalIndex -> next/prev originalIndex based on SeriesPlaylist.allEpisodes order
class _NavigationMaps {
  final Map<int, int> nextMap;
  final Map<int, int> prevMap;

  const _NavigationMaps({required this.nextMap, required this.prevMap});
}

/// Fires [onCovered] on the first lifecycle change away from resumed — i.e.
/// when the launched activity (native TV player / external app) takes the
/// foreground. One-shot; the caller removes it via the callback.
class _AppCoverObserver with WidgetsBindingObserver {
  _AppCoverObserver({required this.onCovered});
  final VoidCallback onCovered;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) onCovered();
  }
}

/// Fires [onReturned] on the first resume AFTER the app was covered — i.e. the
/// launched activity finished and handed the screen back. The cover→resume
/// pairing is the point: a resume without a preceding cover means the launch
/// never happened, not that playback ended. One-shot; the caller removes it.
class _AppReturnObserver with WidgetsBindingObserver {
  _AppReturnObserver({required this.onReturned});
  final VoidCallback onReturned;

  /// Whether the launched activity ever actually took the foreground — read by
  /// the arm timeout to tell "still launching" from "launch died".
  bool wasCovered = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      wasCovered = true;
      return;
    }
    if (wasCovered) onReturned();
  }
}
