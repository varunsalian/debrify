import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/native_scrobble_session.dart';
import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/android_tv_playback_item.dart';
import 'package:debrify/features/player_launch/models/launcher_entry.dart';
import 'package:debrify/features/player_launch/models/native_playback_state.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';
export 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
export 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/iptv_audio_storage.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/playlist_artwork_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/services/storage/torrent_search_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'profiles/profile_playback_preparation.dart';
import 'profiles/profile_session_memory.dart';
import '../utils/show_shuffle.dart';
import 'failed_saved_source.dart';
import 'torrent_playback_service.dart';
import 'direct_source_authorization.dart';
import 'media_server_watch_sync.dart';
import 'startup_recovery_sources.dart';
import 'dart:async';
import '../models/custom_series_identity.dart';
import 'source_selection_diagnostics.dart';
import '../utils/platform_util.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/video_player/player_pip_route.dart';
import '../models/movie_collection.dart';
import '../models/torrent.dart';
import '../services/external_player_service.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../screens/video_player_screen.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/debrid_service.dart';
import '../services/main_page_bridge.dart';
import '../services/next_episode_service.dart';
import '../services/analytics_service.dart';
import '../services/episode_tracker_snapshot_service.dart';
import '../services/local_playback_resume_resolver.dart';
import '../services/series_source_fetcher.dart';
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
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_scrobble_session.dart';
import '../services/mdblist/mdblist_service.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_policy_guard.dart';
import 'tracking_source_policy.dart';
























class VideoPlayerLauncher {
  @visibleForTesting
  static Future<List<int>> debugNativeResumePositions(
    VideoPlayerLaunchArgs args,
    List<PlaylistEntry> entries,
  ) async {
    final states = await _AndroidTvPlaybackPayloadBuilder(args)
        ._fetchPerItemPlaybackState(
          entries,
          contentType: args.contentType == 'series'
              ? PlaybackContentType.series
              : PlaybackContentType.single,
          seriesPlaylist: null,
        );
    return states.map((state) => state.positionMs).toList();
  }

  @visibleForTesting
  static Future<Map<String, dynamic>> debugNativePlaybackSession(
    VideoPlayerLaunchArgs args,
    List<Map<String, dynamic>> updates, {
    MdblistService? mdblistService,
    bool Function()? canContinue,
  }) async {
    final built = await _AndroidTvPlaybackPayloadBuilder(
      args,
      canContinue: canContinue,
    ).build();
    if (built == null) throw StateError('Native payload could not be built');
    final payload = built.payload;
    final initial = payload.toMap();
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.traktLastKnownProgress = 0;
    NativeScrobbleSession.traktLastKnownSeason = null;
    NativeScrobbleSession.traktLastKnownEpisode = null;
    try {
      await _initializeNativeMdblist(payload, service: mdblistService);
      for (final update in updates) {
        await _handleProgressUpdate(payload, update);
      }
    } finally {
      await _handlePlaybackFinished(payload);
      StreamRedirectResolver.clearResolvedStreams(built.entries.map((entry) => entry.resumeId));
    }
    return initial;
  }

  /// The external app needs its own temporary grant for this exact document.
  /// Debrify's persisted folder/file permission is not shared across apps.
  static AndroidIntent androidExternalVideoIntent(String url) => AndroidIntent(
    action: 'action_view',
    data: url,
    type: 'video/*',
    flags: Uri.tryParse(url)?.scheme == 'content'
        ? const [Flag.FLAG_GRANT_READ_URI_PERMISSION]
        : null,
  );

  /// Select the single URL handed to an external player.
  ///
  /// External-player intents, URL schemes, and generic commands cannot
  /// reliably attach [VideoPlayerLaunchArgs.audioUrl] on every platform. When
  /// the primary stream needs that separate audio track, prefer the muxed
  /// fallback so external playback is never silent.
  @visibleForTesting
  static String externalPlaybackUrlFor(VideoPlayerLaunchArgs args) {
    final hasSeparateAudio = args.audioUrl?.isNotEmpty ?? false;
    final muxedFallback = args.fallbackUrl;
    if (hasSeparateAudio && muxedFallback != null && muxedFallback.isNotEmpty) {
      return muxedFallback;
    }
    return args.videoUrl;
  }

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

  /// Local resume record for a NON-series entry.
  ///
  /// [resumeIdForEntry] keys movies by release filename (or by debrid file id),
  /// so watching via one source and relaunching via another — Quick Play
  /// auto-picking a different torrent, an unpinned binding, a startup failover
  /// landing on candidate 3 — misses the record and restarts from zero. The
  /// Flutter player already recovers from that by scanning for the IMDb id
  /// (see `_getEnhancedPlaybackState`); this is the native-TV counterpart, so
  /// both players resolve movie resume the same way.
  ///
  /// Generic playback remains exact-source-first. Catalog playback reverses
  /// that precedence so the newest record for the stable IMDb id wins even
  /// when the selected source has an older bookmark of its own.
  static Future<Map<String, dynamic>?> readMovieResumeState({
    required PlaylistEntry entry,
    required String? imdbId,
    String fallbackTitle = '',
    PlaybackResumePolicy policy = PlaybackResumePolicy.sourceSpecific,
  }) async {
    // A canonical record's duration belongs to the source that wrote it and
    // may differ for another cut. Both players validate the absolute position
    // against the live duration before seeking, so retain the existing ms-based
    // behavior rather than guessing a percentage here.
    return LocalPlaybackResumeResolver.movie(
      resumeId: resumeIdForEntry(entry, fallbackTitle: fallbackTitle),
      imdbId: imdbId,
      policy: policy,
    );
  }

  /// Refresh the replaceable Trakt snapshot used by every guide surface.
  ///
  /// Older builds also copied remote completion into local finished/resume
  /// stores here. That made a later Trakt rewatch impossible to represent and
  /// had no provenance for safe deletion. New launches never create that
  /// pollution; legacy values are neutralized non-destructively when snapshots
  /// are merged for display/resume.
  static Future<void> _refreshTraktEpisodeProgress(String imdbId) async {
    try {
      await EpisodeTrackerSnapshotService.refreshTrakt(imdbId);
    } catch (e) {
      debugPrint('VideoPlayerLauncher: Trakt snapshot refresh failed: $e');
    }
  }

  /// Refresh the replaceable Simkl snapshot. Like Trakt, it remains remote
  /// truth and is merged at display/resume time rather than copied locally.
  static Future<void> _seedSimklEpisodeProgress(String imdbId) async {
    await EpisodeTrackerSnapshotService.refreshSimkl(imdbId);
  }

  static Future<void> _seedMdblistEpisodeProgress(String imdbId) async {
    if (!kMdblistEnabled) return;
    await EpisodeTrackerSnapshotService.seedMdblistPlayback(imdbId);
  }

  /// Resolves the one MDBList ownership decision used by every playback
  /// surface. A launch originating from an MDBList row is still only a
  /// *request* to use MDBList: disabling playback/library sync or disconnecting
  /// the account must hand completion and Continue Watching back to Debrify.
  @visibleForTesting
  static bool shouldEnableMdblistTracking({
    required bool requested,
    required bool autoEligible,
    required bool featureEnabled,
    required bool identityAvailable,
    required bool syncEnabled,
    required bool authenticated,
  }) {
    return featureEnabled &&
        identityAvailable &&
        syncEnabled &&
        authenticated &&
        (requested || autoEligible);
  }

  @visibleForTesting
  static VideoPlayerLaunchArgs normalizeScrobbleFlags(
    VideoPlayerLaunchArgs args,
    TrackingSourcePolicy policy,
  ) {
    policy = policy.forContent(args.contentImdbId);
    return args.copyWith(
      traktScrobble: args.traktScrobble && policy.scrobbles(TrackingSource.trakt),
      simklScrobble: args.simklScrobble && policy.scrobbles(TrackingSource.simkl),
      mdblistScrobble:
          args.mdblistScrobble && policy.scrobbles(TrackingSource.mdblist),
    );
  }

  /// Whether a launch needs to explain why the user's external-player default
  /// cannot be honored. Authenticated server playback carries headers which
  /// can be consumed by Debrify's player but are not part
  /// of the URL handed to another app.
  static bool shouldExplainExternalPlayerFallback(
    VideoPlayerLaunchArgs args,
    String defaultPlayerMode,
  ) {
    final wantsExternal =
        defaultPlayerMode == 'external' ||
        (defaultPlayerMode == 'deovr' && Platform.isAndroid);
    final carriesAuthorization =
        args.httpHeaders?.keys.any(
          (key) => key.toLowerCase() == 'authorization' ||
              key.toLowerCase() == 'x-emby-token',
        ) ??
        false;
    return wantsExternal && args.disableExternalPlayer && carriesAuthorization;
  }

  @visibleForTesting
  static Future<bool> showAuthenticatedWebDavPlayerNotice(
    BuildContext context,
  ) async {
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: const Text('External player unavailable'),
            content: const Text(
              'This server requires authentication. Debrify cannot pass '
              'the required authorization headers to another app, so this video '
              'will open in the Debrify player.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Use Debrify player'),
              ),
            ],
          ),
        ) ??
        false;
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
    VoidCallback Function()? retainSourceSession,
    ProfileSessionOwner? sourceOwner,
    bool Function()? canContinue,
  }) async {
    // Exactly-once relay for [onPlayerHandoff]. _push fires one of these at
    // its launch points; the finally is the safety net so an exception mid
    // launch-prep can never strand the caller's loader.
    final preparation = sourceOwner == null
        ? null
        : ProfilePlaybackPreparation(
            owner: sourceOwner,
            canContinue: canContinue ?? () => true,
          );
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
      Future<void> launch() => _push(
        context,
        originalArgs,
        onQuickPlayNextEpisode: onQuickPlayNextEpisode,
        isTrailer: isTrailer,
        handoffNow: handoffNow,
        handoffWhenCovered: handoffWhenCovered,
        retainSourceSession: retainSourceSession,
        preparation: preparation,
      );
      if (preparation == null) {
        await launch();
      } else {
        await preparation.run(launch);
      }
    } on PlaybackPreparationRetired {
      // The original launch retired before acceptance; finally releases its loader.
    } on NativePlayerSettingsUnavailable catch (error) {
      // No player opened, so no return observer will balance the launch signal.
      // Clear sync's playback gate even if the route/loader has gone away.
      if (!isTrailer) MainPageBridge.notifyContentPlaybackStopped();
      handoffNow();
      if (context.mounted && (preparation?.isCurrent ?? true)) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(error.message.toString())));
      }
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
    VoidCallback Function()? retainSourceSession,
    ProfilePlaybackPreparation? preparation,
  }) async {
    // Apply the tracker master switches to catalog content with stable IDs.
    bool active() => context.mounted && (preparation?.isCurrent ?? true);
    Future<void> write(Future<void> Function() action) =>
        preparation?.write(action) ?? action();
    if (!active()) return;
    var args = originalArgs;
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      args.contentImdbId,
    );
    if (!active()) return;
    final defaultPlayerMode = await ExternalPlayerStorage.getDefaultPlayerMode();
    if (!context.mounted || !active()) return;
    if (shouldExplainExternalPlayerFallback(args, defaultPlayerMode)) {
      final useDebrifyPlayer = await showAuthenticatedWebDavPlayerNotice(
        context,
      );
      if (!context.mounted || !active() || !useDebrifyPlayer) return;
    }
    if (!args.traktScrobble &&
        !args.suppressTraktAutoSync &&
        args.contentImdbId != null &&
        args.stremioTvChannels == null) {
      final isAuth = await TraktService.instance.isAuthenticated();
      if (!active()) return;
      if (trackingPolicy.scrobbles(TrackingSource.trakt) && isAuth) {
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
          initialContinuousShuffle: args.initialContinuousShuffle,
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
          resumePolicy: args.resumePolicy,
          iptvChannels: args.iptvChannels,
          iptvStartIndex: args.iptvStartIndex,
          iptvCategories: args.iptvCategories,
          iptvSourceId: args.iptvSourceId,
          iptvSourceName: args.iptvSourceName,
          iptvSelectedCategory: args.iptvSelectedCategory,
          iptvContentType: args.iptvContentType,
          iptvSources: args.iptvSources,
          iptvLists: args.iptvLists,
          iptvBrowseProvider: args.iptvBrowseProvider,
          stremioSources: args.stremioSources,
          stremioCurrentSourceIndex: args.stremioCurrentSourceIndex,
          resolveStremioSource: args.resolveStremioSource,
          resolveSourceToPlaylist: args.resolveSourceToPlaylist,
          startupFailoverEnabled: args.startupFailoverEnabled,
          startupResolverProvider: args.startupResolverProvider,
          startupHasRemainingSavedSources: args.startupHasRemainingSavedSources,
          onStremioSourceCommitted: args.onStremioSourceCommitted,
          onStartupSourcesExhausted: args.onStartupSourcesExhausted,
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
          mdblistScrobble: args.mdblistScrobble,
          mdblistProgressPercent: args.mdblistProgressPercent,
          contentTitle: args.contentTitle,
          posterUrl: args.posterUrl,
          contentYear: args.contentYear,
          addonId: args.addonId,
          initialSubtitles: args.initialSubtitles,
        );
        // Clean up any existing local Continue Watching entry (Trakt tracks it now)
        if (!trackingPolicy.forcesLocalCompletion &&
            !trackingPolicy.nativeIdentity) {
          await write(
            () =>
                ContinueWatchingStorage.removeContinueWatchingItem(args.contentImdbId!),
          );
          if (!active()) return;
        }
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
      final isAuth = await SimklService.instance.isAuthenticated();
      if (!active()) return;
      if (trackingPolicy.scrobbles(TrackingSource.simkl) && isAuth) {
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
          initialContinuousShuffle: args.initialContinuousShuffle,
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
          resumePolicy: args.resumePolicy,
          iptvChannels: args.iptvChannels,
          iptvStartIndex: args.iptvStartIndex,
          iptvCategories: args.iptvCategories,
          iptvSourceId: args.iptvSourceId,
          iptvSourceName: args.iptvSourceName,
          iptvSelectedCategory: args.iptvSelectedCategory,
          iptvContentType: args.iptvContentType,
          iptvSources: args.iptvSources,
          iptvLists: args.iptvLists,
          iptvBrowseProvider: args.iptvBrowseProvider,
          stremioSources: args.stremioSources,
          stremioCurrentSourceIndex: args.stremioCurrentSourceIndex,
          resolveStremioSource: args.resolveStremioSource,
          resolveSourceToPlaylist: args.resolveSourceToPlaylist,
          startupFailoverEnabled: args.startupFailoverEnabled,
          startupResolverProvider: args.startupResolverProvider,
          startupHasRemainingSavedSources: args.startupHasRemainingSavedSources,
          onStremioSourceCommitted: args.onStremioSourceCommitted,
          onStartupSourcesExhausted: args.onStartupSourcesExhausted,
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
          mdblistScrobble: args.mdblistScrobble,
          mdblistProgressPercent: args.mdblistProgressPercent,
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
        if (!trackingPolicy.forcesLocalCompletion) {
          await write(
            () =>
                ContinueWatchingStorage.removeContinueWatchingItem(args.contentImdbId!),
          );
          if (!active()) return;
        }
      }
    }

    final mdblistRequested = args.mdblistScrobble;
    final mdblistIdentityAvailable =
        args.contentImdbId?.trim().isNotEmpty == true;
    final mdblistAutoEligible =
        !mdblistRequested &&
        !args.suppressTrackerAutoSync &&
        mdblistIdentityAvailable &&
        args.stremioTvChannels == null;
    var mdblistSyncEnabled = false;
    var mdblistAuthenticated = false;
    if (kMdblistEnabled &&
        mdblistIdentityAvailable &&
        (mdblistRequested || mdblistAutoEligible)) {
      final results = await Future.wait([
        Future<bool>.value(trackingPolicy.scrobbles(TrackingSource.mdblist)),
        MdblistService.instance.isAuthenticated(),
      ]);
      if (!active()) return;
      mdblistSyncEnabled = results[0];
      mdblistAuthenticated = results[1];
    }
    final effectiveMdblistTracking = shouldEnableMdblistTracking(
      requested: mdblistRequested,
      autoEligible: mdblistAutoEligible,
      featureEnabled: kMdblistEnabled,
      identityAvailable: mdblistIdentityAvailable,
      syncEnabled: mdblistSyncEnabled,
      authenticated: mdblistAuthenticated,
    );
    if (args.mdblistScrobble != effectiveMdblistTracking) {
      args = args.copyWith(mdblistScrobble: effectiveMdblistTracking);
    }

    if (kMdblistEnabled && args.contentImdbId != null) {
      debugPrint(
        '[MDBListDiag] launch candidate imdb=${args.contentImdbId} '
        'type=${args.contentType} requested=$mdblistRequested '
        'suppressAuto=${args.suppressTrackerAutoSync} '
        'stremioTv=${args.stremioTvChannels != null} '
        'scrobbleMaster=$mdblistSyncEnabled '
        'authenticated=$mdblistAuthenticated '
        'effective=$effectiveMdblistTracking',
      );
    }
    if (effectiveMdblistTracking && !mdblistRequested) {
      debugPrint(
        '[MDBListDiag] launch tracking enabled imdb=${args.contentImdbId}',
      );
      if (!trackingPolicy.forcesLocalCompletion &&
          !trackingPolicy.nativeIdentity) {
        await write(
          () => ContinueWatchingStorage.removeContinueWatchingItem(args.contentImdbId!),
        );
        if (!active()) return;
      }
    }

    // Tracker-row launches arrive with their flag already true and skip the
    // auto-enable branches above. Normalize once on the shared path before
    // native payload construction, external seeding, or in-app playback.
    args = normalizeScrobbleFlags(args, trackingPolicy);

    // Persist before launching playback so Android TV handoff cannot race the write.
    // Skip when a tracker already owns this title's Continue Watching entry —
    // Trakt (its own CW row) OR Simkl (its own CW row) — so it lives in exactly
    // one row instead of duplicating into local Continue Watching. Also skip
    // Stremio TV (channel rotation). This runs on the shared pre-launch path, so
    // it applies to both the native-TV and in-app players.
    if (args.contentImdbId != null &&
        args.contentType != null &&
        trackingPolicy.usesLocalCompletionTracking(
          traktScrobble: args.traktScrobble,
          simklScrobble: args.simklScrobble,
          mdblistScrobble: args.mdblistScrobble,
        ) &&
        args.stremioTvChannels == null) {
      await write(
        () => ContinueWatchingStorage.saveContinueWatchingItem(
          imdbId: args.contentImdbId!,
          title: args.contentTitle ?? args.title,
          contentType: args.contentType!,
          posterUrl: args.posterUrl,
          year: args.contentYear,
          addonId: args.addonId,
        ),
      );
      if (!active()) return;
    }

    // Starting a saved title graduates it from My Watchlist into whichever
    // Continue Watching owner applies above (local or a connected tracker). Keep
    // this on the shared pre-launch path so opening details alone changes
    // nothing and native Android TV playback follows the same rule.
    if (args.contentType != null && args.stremioTvChannels == null) {
      await write(
        () => WatchlistStorage.removeMyWatchlistItemForPlayback(
          imdbId: args.contentImdbId,
          contentType: args.contentType!,
          title: args.contentTitle ?? args.title,
          addonId: args.addonId,
        ),
      );
      if (!active()) return;
    }

    // Real packs retain the existing Trakt/Simkl launch-time snapshots because
    // their immediately visible rows need them. MDBList always renders its
    // cached snapshot first and refreshes in the background: even its compact
    // playback endpoint has a 20-second transport timeout and must never hold
    // the player handoff. Complete history follows asynchronously with the
    // guide.
    if (args.contentType != 'movie' &&
        args.contentImdbId != null &&
        (args.playlist?.length ?? 0) > 1) {
      await Future.wait([
        _refreshTraktEpisodeProgress(args.contentImdbId!),
        _seedSimklEpisodeProgress(args.contentImdbId!),
      ]);
      unawaited(_seedMdblistEpisodeProgress(args.contentImdbId!));
    } else if (args.contentType == 'series' && args.contentImdbId != null) {
      await _seedSimklEpisodeProgress(args.contentImdbId!);
      unawaited(_seedMdblistEpisodeProgress(args.contentImdbId!));
    }

    if (!context.mounted || !active()) return;
    AnalyticsService.trackInBackground('playback_started', <String, Object?>{
      'content_type': args.contentType ?? 'unknown',
      'provider': _analyticsProviderLabel(args),
      'has_playlist': args.playlist?.isNotEmpty ?? false,
      'trakt_scrobble': args.traktScrobble,
      'simkl_scrobble': args.simklScrobble,
      'mdblist_scrobble': args.mdblistScrobble,
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

    // Every external-activity launch below arms the playback-return signal
    // (content only): control comes straight back to Flutter without a route
    // ever being pushed, so RouteAware can't tell those screens when playback
    // actually ended. See [_notifyOnReturnFromExternalActivity].
    if (!args.disableExternalPlayer && defaultPlayerMode == 'external') {
      int? chosenSeason;
      int? chosenEpisode;
      final launched = await _launchWithExternalPlayer(
        context,
        args,
        preparation: preparation,
        onSeriesEntryChosen: (s, e) {
          chosenSeason = s;
          chosenEpisode = e;
        },
      );
      if (launched) {
        if (active()) await _commitExternalLaunchSource(args);
        if (active()) {
          unawaited(
            _seedTrackerContinueWatching(
              args,
              seasonOverride: chosenSeason,
              episodeOverride: chosenEpisode,
            ),
          );
        }
        handoffWhenCovered();
        if (!isTrailer) _notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If external player failed, fall through to in-app player
    } else if (!args.disableExternalPlayer &&
        defaultPlayerMode == 'deovr' &&
        Platform.isAndroid) {
      final launched = await _launchWithDeoVR(
        context,
        args,
        preparation: preparation,
      );
      if (launched) {
        if (active()) await _commitExternalLaunchSource(args);
        if (active()) unawaited(_seedTrackerContinueWatching(args));
        handoffWhenCovered();
        if (!isTrailer) _notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If DeoVR failed, fall through to in-app player
    }

    final isTv = await _isAndroidTv(args.isAndroidTvOverride);
    if (!active()) return;
    if (isTv) {
      final launched = await _launchOnAndroidTv(
        args,
        onQuickPlayNextEpisode: onQuickPlayNextEpisode,
        isTrailer: isTrailer,
        retainSourceSession: retainSourceSession,
        preparation: preparation,
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
    if (!context.mounted || !active()) return;
    handoffNow();
    // FrozenLegacyPageRoute: the player is an excluded surface, and this one
    // push serves every launcher call site — the route's LegacyThemeBoundary
    // keeps it (and every dialog/sheet it opens) on today's look under any
    // app theme.
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      videoPlayerRoute(builder: (_) => args.toWidget()),
    );

    if (result?['startupSourcesExhausted'] == true &&
        args.onStartupSourcesExhausted != null) {
      try {
        await args.onStartupSourcesExhausted!();
      } catch (error) {
        debugPrint(
          'VideoPlayerLauncher: startup recovery failed '
          '(${error.runtimeType})',
        );
      }
      return;
    }

    // Handle Quick Play next episode request from player
    if (result != null &&
        result['quickPlayNext'] == true &&
        onQuickPlayNextEpisode != null) {
      await onQuickPlayNextEpisode(result);
    }
  }

  /// External players have no decoder callback into Debrify, so a successful
  /// OS/app handoff is their commit boundary. Keep this separate from Android
  /// TV, whose native player reports its validated source after first frame.
  static Future<void> _commitExternalLaunchSource(
    VideoPlayerLaunchArgs args,
  ) async {
    final sources = args.stremioSources;
    final commit = args.onStremioSourceCommitted;
    if (sources == null || sources.isEmpty || commit == null) return;
    final index = (args.stremioCurrentSourceIndex ?? 0).clamp(
      0,
      sources.length - 1,
    );
    try {
      await commit(sources[index]);
    } catch (error) {
      debugPrint(
        'VideoPlayerLauncher: external source commit failed '
        '(${error.runtimeType})',
      );
    }
  }

  /// Seed the connected tracker's Continue Watching when playback leaves the
  /// app (external player / DeoVR).
  ///
  /// The shared pre-launch path already writes LOCAL Continue Watching for
  /// untracked titles, but deliberately skips it when a tracker owns the
  /// row — and an external player can never scrobble back, so without this
  /// the title lands in NO row at all. A ~1% scrobble is each tracker's own
  /// idiom for "started watching" — start→pause for Trakt and a bare pause for
  /// Simkl/MDBList (Simkl start would CLEAR an existing session) — and all keep
  /// sub-80% sessions as resumable playback, so the item appears in their CW.
  /// The existing CW row menus then let the user mark it watched on return,
  /// and if the external app scrobbles real progress itself (Infuse + Trakt),
  /// that simply overwrites the seed.
  ///
  /// Fail-soft and fire-and-forget: every service no-ops without credentials, and
  /// the handoff must never wait on tracker HTTP.
  static Future<void> _seedTrackerContinueWatching(
    VideoPlayerLaunchArgs args, {
    int? seasonOverride,
    int? episodeOverride,
  }) async {
    final imdbId = args.contentImdbId;
    if (imdbId == null || imdbId.isEmpty) return;
    // Channel rotation is not a watchable title; mirrors the local CW skip.
    if (args.stremioTvChannels != null) return;
    if (!args.traktScrobble && !args.simklScrobble && !args.mdblistScrobble) {
      return;
    }

    // A series seed needs BOTH season and episode — both scrobble services
    // refuse a lone half, and a series imdb id in a movie-shaped body would
    // be worse than no seed. A movie sends neither. The overrides are the
    // episode the external path actually CHOSE (resume/advance) and outrank
    // the launch-time metadata.
    int? season = (seasonOverride != null && episodeOverride != null)
        ? seasonOverride
        : args.contentSeason;
    int? episode = (seasonOverride != null && episodeOverride != null)
        ? episodeOverride
        : args.contentEpisode;
    final isSeries = args.contentType == 'series';
    if (isSeries && ((season ?? 0) <= 0 || (episode ?? 0) <= 0)) return;
    if (!isSeries) {
      season = null;
      episode = null;
    }

    // Just-started sentinel: comfortably under both trackers' ~80% "watched"
    // thresholds, so the session lands as resumable playback.
    const progress = 1.0;

    // Concurrent, not serialized: this runs while another app is taking the
    // foreground, and a suspension mid-sequence must not starve the second
    // tracker of its seed.
    final s = season;
    final e = episode;
    await Future.wait([
      if (args.traktScrobble)
        () async {
          try {
            // Trakt's documented idiom: start opens the session, pause
            // checkpoints it into the playback-progress (CW) list.
            await TraktService.instance.scrobbleStart(
              imdbId,
              progress,
              season: s,
              episode: e,
              contentType: args.contentType,
            );
            await TraktService.instance.scrobblePause(
              imdbId,
              progress,
              season: s,
              episode: e,
              contentType: args.contentType,
            );
          } catch (err) {
            debugPrint('ExternalPlayer: Trakt CW seed failed: $err');
          }
        }(),
      if (args.simklScrobble)
        () async {
          try {
            // PAUSE ONLY, deliberately: Simkl's start CLEARS an existing
            // paused playback (and its 20-second lock could then swallow the
            // follow-up), while a bare pause creates the resumable row on
            // its own — the pause-centric idiom the in-app player already
            // uses.
            await SimklService.instance.scrobblePause(
              imdbId,
              progress,
              season: s,
              episode: e,
            );
          } catch (err) {
            debugPrint('ExternalPlayer: Simkl CW seed failed: $err');
          }
        }(),
      if (args.mdblistScrobble)
        () async {
          try {
            final ids = MdblistMediaIds.forContent(imdbId);
            final target = isSeries
                ? MdblistScrobbleTarget.episode(ids, season: s!, episode: e!)
                : MdblistScrobbleTarget.movie(ids);
            await MdblistService.instance.scrobblePause(target, progress);
          } catch (err) {
            debugPrint('ExternalPlayer: MDBList CW seed failed: $err');
          }
        }(),
    ]);
  }

  /// Whether playback should leave the app entirely, per the user's default
  /// player setting. Screens that build their own player route ask this before
  /// spending work on in-app-only setup.
  static Future<bool> isExternalPlayerDefault() async {
    final mode = await ExternalPlayerStorage.getDefaultPlayerMode();
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

    final mode = await ExternalPlayerStorage.getDefaultPlayerMode();
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

    if (!launched) {
      MainPageBridge.notifyContentPlaybackStopped();
      return false;
    }

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
    VideoPlayerLaunchArgs args, {
    // Reports the series entry this path CHOSE — resume/advance can land on
    // a different episode than args.contentSeason/Episode describe, and the
    // tracker CW seed must tag the episode actually handed over.
    void Function(int season, int episode)? onSeriesEntryChosen,
    ProfilePlaybackPreparation? preparation,
  }) async {
    bool active() => context.mounted && (preparation?.isCurrent ?? true);
    if (!context.mounted || !active()) return false;
    if (!await ProfilePolicyGuard.allows(ProfileFeature.externalPlayers)) {
      if (context.mounted && active()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('External players are disabled for this profile.'),
          ),
        );
      }
      return false;
    }
    if (!context.mounted || !active()) return false;
    // Determine the correct URL to play (considering resume state for series)
    String url = externalPlaybackUrlFor(args);
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
          // Local last-played drives the episode choice only when the
          // Progress source admits this device — the chosen entry is seeded
          // to tracker Continue Watching, so a dedicated-tracker mode must
          // not replay stale local state (falls to first episode instead).
          final trackingPolicy = await TrackingSourcePolicy.load();
          if (!context.mounted || !active()) return false;
          final lastEpisode = trackingPolicy.progressFrom(TrackingSource.local)
              ? await EpisodeResumeStorage.getLastPlayedEpisode(
                  seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
                )
              : null;

          if (!context.mounted || !active()) return false;
          if (lastEpisode != null) {
            final lastSeason = lastEpisode['season'] as int;
            final lastEpisodeNum = lastEpisode['episode'] as int;
            final originalIndex = seriesPlaylist
                .findOriginalIndexBySeasonEpisode(lastSeason, lastEpisodeNum);
            if (originalIndex != -1) {
              startIndex = originalIndex;

              // Check if this episode is finished - if so, advance to next
              final isFinished = await EpisodeProgressStorage.isEpisodeFinished(
                seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
                season: lastSeason,
                episode: lastEpisodeNum,
              );

              if (!context.mounted || !active()) return false;
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
                    'ExternalPlayer: E$lastEpisodeNum finished, advancing to next at index $startIndex',
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
          final resolvedUrl = await _resolveEntryUrl(
            targetEntry,
            args,
            canContinue: active,
          );
          if (!context.mounted || !active()) return false;
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
                // BEFORE the storage write: a throw there is caught by the
                // outer catch while the launch proceeds with this URL — the
                // seed must still know which episode that was.
                onSeriesEntryChosen?.call(
                  episode.seriesInfo.season!,
                  episode.seriesInfo.episode!,
                );
                Future<void> markFinished() =>
                    EpisodeCompletionStorage.markEpisodeAsFinished(
                      seriesTitle:
                          seriesPlaylist.seriesTitle ?? 'Unknown Series',
                      season: episode.seriesInfo.season!,
                      episode: episode.seriesInfo.episode!,
                      imdbId: seriesPlaylist.imdbId,
                    );
                if (preparation == null) {
                  await markFinished();
                } else {
                  await preparation.write(markFinished);
                }
                if (!context.mounted || !active()) return false;
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

    if (!context.mounted || !active()) return false;
    if (_mayDiscloseCredential(url) &&
        !await _confirmExternalDisclosure(context)) {
      return false;
    }

    if (!context.mounted || !active()) return false;
    if (Platform.isMacOS) {
      // macOS: Use configured external player
      final result = await ExternalPlayerService.launchWithPreferredPlayer(
        url,
        title: title,
        canContinue: active,
      );

      if (result.success) {
        if (context.mounted && active()) {
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
        if (context.mounted && active()) {
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
        final intent = androidExternalVideoIntent(url);
        await intent.launch();
        return true;
      } catch (e) {
        debugPrint('Failed to launch external player on Android: $e');
        return false;
      }
    } else if (PlatformUtil.isIosMobile || PlatformUtil.isTvOS) {
      // iOS + Apple TV: URL scheme to launch the preferred external player
      // (same catalog and storage; tvOS offers only the players with real
      // Apple TV apps and opens through the Runner's UIApplication bridge).
      final result = await ExternalPlayerService.launchWithPreferredIOSPlayer(
        url,
        title: title,
        canContinue: active,
      );

      if (result.success) {
        if (context.mounted && active()) {
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
        if (context.mounted && active()) {
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
            canContinue: active,
          );

      if (result.success) {
        if (context.mounted && active()) {
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
        if (context.mounted && active()) {
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
            canContinue: active,
          );

      if (result.success) {
        if (context.mounted && active()) {
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
        if (context.mounted && active()) {
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
    VideoPlayerLaunchArgs args, {
    ProfilePlaybackPreparation? preparation,
  }) async {
    bool active() => context.mounted && (preparation?.isCurrent ?? true);
    if (!context.mounted || !active()) return false;
    final url = args.videoUrl;
    final title = args.title;

    if (!await ProfilePolicyGuard.allows(ProfileFeature.externalPlayers)) {
      return false;
    }
    if (!context.mounted || !active()) return false;
    if (_mayDiscloseCredential(url) &&
        !await _confirmExternalDisclosure(context)) {
      return false;
    }

    if (!context.mounted || !active()) return false;
    try {
      // Load VR settings
      final vrAutoDetectFormat =
          await QuickPlayStorage.getQuickPlayVrAutoDetectFormat();
      if (!context.mounted || !active()) return false;
      final vrShowDialog = await QuickPlayStorage.getQuickPlayVrShowDialog();
      if (!context.mounted || !active()) return false;
      final vrDefaultScreenType =
          await QuickPlayStorage.getQuickPlayVrDefaultScreenType();
      if (!context.mounted || !active()) return false;
      final vrDefaultStereoMode =
          await QuickPlayStorage.getQuickPlayVrDefaultStereoMode();

      if (!context.mounted || !active()) return false;
      // Detect or use default format
      String selectedScreenType = vrDefaultScreenType;
      String selectedStereoMode = vrDefaultStereoMode;

      if (vrAutoDetectFormat) {
        final detected = deovr.detectVRFormat(title);
        selectedScreenType = detected.screenType;
        selectedStereoMode = detected.stereoMode;
      }

      // Show format selection dialog if enabled
      if (vrShowDialog && active()) {
        final result = await _showDeoVRFormatDialog(
          context,
          title: title,
          initialScreenType: selectedScreenType,
          initialStereoMode: selectedStereoMode,
        );

        if (!active() || result == null) {
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

      if (!context.mounted || !active()) return false;
      // Upload JSON to jsonblob.com
      final response = await http.post(
        Uri.parse('https://jsonblob.com/api/jsonBlob'),
        headers: {'Content-Type': 'application/json'},
        body: jsonString,
      );

      if (!context.mounted || !active()) return false;
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

      if (context.mounted && active()) {
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
      if (context.mounted && active()) {
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

  static bool _mayDiscloseCredential(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) return true;
    if (uri.userInfo.isNotEmpty) return true;
    const sensitive = <String>{
      'token',
      'key',
      'api_key',
      'apikey',
      'auth',
      'authorization',
      'signature',
      'sig',
      'expires',
    };
    return uri.queryParameters.keys.any(
      (key) => sensitive.contains(key.toLowerCase()),
    );
  }

  static Future<bool> _confirmExternalDisclosure(BuildContext context) async {
    if (!context.mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Share stream with another app?'),
            content: const Text(
              'This stream address may contain a short-lived account token. '
              'The selected player will be able to read it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Use Debrify player'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        ) ??
        false;
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
      if (!observer.wasCovered) {
        finish(notify: false);
        MainPageBridge.notifyContentPlaybackStopped();
      }
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
    VoidCallback Function()? retainSourceSession,
    ProfilePlaybackPreparation? preparation,
  }) async {
    bool sessionActive() => preparation?.isCurrent ?? true;
    if (!sessionActive()) return false;
    // Route IPTV playlists to dedicated IPTV launcher
    if (args.iptvChannels != null && args.iptvChannels!.isNotEmpty) {
      return _launchIptvOnAndroidTv(args);
    }
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      args.contentImdbId,
    );

    if (!sessionActive()) return false;
    // Reset Trakt scrobble state for clean session
    NativeScrobbleSession.traktHeartbeatTimer?.cancel();
    NativeScrobbleSession.traktHeartbeatTimer = null;
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.traktLastKnownProgress = 0.0;
    NativeScrobbleSession.traktLastKnownSeason = null;
    NativeScrobbleSession.traktLastKnownEpisode = null;

    // Reset Simkl scrobble state for clean session
    NativeScrobbleSession.simklHeartbeatTimer?.cancel();
    NativeScrobbleSession.simklHeartbeatTimer = null;
    NativeScrobbleSession.simklLastScrobbleAction = null;
    NativeScrobbleSession.simklLastKnownProgress = 0.0;
    NativeScrobbleSession.simklLastKnownSeason = null;
    NativeScrobbleSession.simklLastKnownEpisode = null;

    AndroidTvPlaybackPayload? builtPayload;
    final serverWatch = MediaServerWatchController();
    _AndroidTvPlaylistResolver? playbackResolver;
    try {
      final initialSources = args.stremioSources;
      final initialSourceIndex = args.stremioCurrentSourceIndex ?? 0;
      if (initialSources != null &&
          initialSourceIndex >= 0 &&
          initialSourceIndex < initialSources.length) {
        await serverWatch.prepare(
          initialSources[initialSourceIndex],
          contentTitle: args.contentTitle ?? args.title,
        );
      }
      final builder = _AndroidTvPlaybackPayloadBuilder(
        args,
        canContinue: sessionActive,
      );
      if (!sessionActive()) {
        unawaited(serverWatch.close());
        return false;
      }
      final result = await builder.build();
      if (result == null || !sessionActive()) {
        unawaited(serverWatch.close());
        return false;
      }
      builtPayload = result.payload;
      await _initializeNativeMdblist(result.payload);

      if (!sessionActive()) {
        unawaited(serverWatch.close());
        await _closeNativeMdblist(result.payload);
        return false;
      }
      // TVMaze may discover a stable show id after native playback starts.
      // Resolver callbacks read this mutable payload value at invocation time
      // so source switches and dynamically fetched episodes inherit it.
      String? effectiveContentImdbId() =>
          result.payload.imdbId ?? args.contentImdbId;

      final resolver = _AndroidTvPlaylistResolver(
        entries: result.entries,
        resolveEntry: (entry, {canContinue}) {
          bool active() => sessionActive() && (canContinue?.call() ?? true);
          Future<String> resolve() =>
              _resolveEntryUrl(entry, args, canContinue: active);
          return preparation == null ? resolve() : preparation.run(resolve);
        },
      );
      playbackResolver = resolver;

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
      // Bumped whenever the holder is REPLACED (a Stremio TV channel switch),
      // as opposed to appended to. Fetch providers capture it before their
      // awaits and discard stale responses — a late merge from the previous
      // content must never contaminate the replacement list.
      var stremioSourcesGeneration = 0;
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
          await serverWatch.prepare(
            torrent,
            contentTitle: args.contentTitle ?? args.title,
          );
          debugPrint(
            'VideoPlayerLauncher: resolving stremio source $sourceIndex: ${torrent.displayTitle}',
          );
          return currentStremioResolver!(torrent);
        };
      }

      // Build playlist resolver for Android TV (if resolveSourceToPlaylist is available)
      final resolveSourceToPlaylist = args.resolveSourceToPlaylist;
      final recoveryPreflight = RecoveryDirectPreflight(
        budget: TorrentPlaybackService.directValidationBudgetForRules(null),
        isMovie: args.contentType == 'movie',
        shouldProbe: TorrentPlaybackService.shouldPreflightDirectStream,
      );
      var validateRecoveryDirectLinks = true;
      Future<List<Map<String, dynamic>>?> Function(
        int, {
        bool automaticRecovery,
      })?
      sourcePlaylistResolverForTv;
      if (currentStremioSources.isNotEmpty && resolveSourceToPlaylist != null) {
        sourcePlaylistResolverForTv = (int sourceIndex, {bool automaticRecovery = false}) async {
          if (!sessionActive()) return null;
          // Claim a switch token up front so a slower, superseded resolve can't
          // repoint the resolver at a stale source after a newer switch wins.
          final switchToken = resolver.beginSwitch();
          bool active() =>
              sessionActive() && resolver.isLatestSwitch(switchToken);
          if (!active()) return null;
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
          try {
            await DirectSourceAuthorization.authorize(torrent);
            if (!active()) return null;
            await serverWatch.prepare(
              torrent,
              contentTitle: args.contentTitle ?? args.title,
            );
          } catch (_) {
            return null;
          }
          if (!active()) return null;
          if (automaticRecovery &&
              !await recoveryPreflight.allows(
                torrent,
                enabled: validateRecoveryDirectLinks,
              ))
            return null;
          final playlistEntries = automaticRecovery
              ? await TorrentPlaybackService.resolveRecoverySource(
                  torrent,
                  provider: args.startupResolverProvider,
                  owner: preparation?.owner,
                  canContinue: active,
                  season: args.contentType == 'series'
                      ? args.contentSeason
                      : null,
                  episode: args.contentType == 'series'
                      ? args.contentEpisode
                      : null,
                )
              : await resolveSourceToPlaylist(torrent, canContinue: active);
          if (!active() || playlistEntries == null || playlistEntries.isEmpty) {
            return null;
          }

          // Use SeriesPlaylist to detect series and compute season/episode
          final seriesPlaylist = playlistEntries.length > 1
              ? SeriesPlaylist.fromPlaylistEntries(
                  playlistEntries,
                  collectionTitle: args.contentTitle ?? args.title,
                  forceSeries: args.contentType == 'series',
                )
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
          // Catalog-series source switches already have authoritative content
          // identity. Match the Dart player: keep them in series mode even
          // when a valid pack has a few unusually named entries. A singleton
          // direct stream is also still an episode even though there is no
          // multi-file playlist from which to infer its identity.
          final isSeries = args.contentType == 'series'
              ? playlistEntries.length == 1 || classifiedAsSeries
              : fullyClassified || mostlyClassified;

          // Fetch TVMaze metadata so items arrive pre-populated with artwork/descriptions
          if (isSeries && seriesPlaylist != null) {
            try {
              await seriesPlaylist.fetchEpisodeInfo(
                imdbId: effectiveContentImdbId(),
              );
              debugPrint(
                'VideoPlayerLauncher: TVMaze fetch complete for source playlist',
              );
            } catch (e) {
              debugPrint(
                'VideoPlayerLauncher: TVMaze fetch failed (non-fatal): $e',
              );
            }
          }

          if (!active()) return null;
          // Build originalIndex → episode lookup for correct matching
          // (allEpisodes is sorted by season/episode, not by original entry order)
          final episodeByIndex = <int, SeriesEpisode>{};
          if (isSeries && episodes != null) {
            for (final ep in episodes) {
              episodeByIndex[ep.originalIndex] = ep;
            }
          }

          final sourceImdbId = effectiveContentImdbId();
          final sourceTrackerMaps = sourceImdbId != null
              ? await Future.wait([
                  TrackerEpisodeProgressStorage.getEpisodeTraktProgress(imdbId: sourceImdbId),
                  TrackerEpisodeProgressStorage.getEpisodeSimklProgress(imdbId: sourceImdbId),
                  TrackerEpisodeProgressStorage.getConnectedEpisodeMdblistProgress(
                    imdbId: sourceImdbId,
                  ),
                ])
              : const <Map<String, double>>[];
          if (!active()) return null;
          final sourceTraktProgress = sourceTrackerMaps.isNotEmpty
              ? sourceTrackerMaps[0]
              : const <String, double>{};
          final sourceSimklProgress = sourceTrackerMaps.length > 1
              ? sourceTrackerMaps[1]
              : const <String, double>{};
          final sourceMdblistProgress = sourceTrackerMaps.length > 2
              ? sourceTrackerMaps[2]
              : const <String, double>{};

          final stableSeriesTitle =
              args.contentTitle ?? seriesPlaylist?.seriesTitle ?? args.title;
          final localSeriesProgress = isSeries
              ? await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
                  seriesTitle: stableSeriesTitle,
                  imdbId: sourceImdbId,
                )
              : const <String, Map<String, dynamic>>{};
          final localFinishedEpisodes = isSeries
              ? await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
                  seriesTitle: stableSeriesTitle,
                  imdbId: sourceImdbId,
                )
              : const <String, Set<int>>{};
          // A movie has no episode key, so the loop below finds nothing in
          // localSeriesProgress and every re-resolved item ships
          // resumePositionMs: 0 — a source switch or startup failover restarts
          // the film. Resolve its own record once, the same way the initial
          // payload does.
          //
          // `args.contentType` is redundant against today's `isSeries` (a lone
          // entry under a series launch always classifies as series above), but
          // it is stated because the id scan MUST NOT run for episodes: their
          // progress is mirrored into video records under the series imdbId,
          // so a scan would return an unrelated episode's position.
          final sourceMovieState =
              !isSeries &&
                  args.contentType != 'series' &&
                  playlistEntries.length == 1
              ? await readMovieResumeState(
                  entry: playlistEntries.first,
                  imdbId: sourceImdbId,
                  fallbackTitle: args.title,
                  policy: args.resumePolicy,
                )
              : null;

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
                    trackingPolicy.guideProgressFrom(
                      TrackingSource.trakt,
                      sourceTraktProgress[episodeKey],
                    ),
                    trackingPolicy.guideProgressFrom(
                      TrackingSource.simkl,
                      sourceSimklProgress[episodeKey],
                    ),
                    trackingPolicy.guideProgressFrom(
                      TrackingSource.mdblist,
                      sourceMdblistProgress[episodeKey],
                    ),
                  ])
                : null;
            final localState = episodeKey != null
                ? localSeriesProgress[episodeKey]
                : sourceMovieState;
            final locallyWatched = season != null && episodeNumber != null
                ? localFinishedEpisodes[season.toString()]?.contains(
                        episodeNumber,
                      ) ??
                      false
                : false;
            final localPositionMs =
                (localState?['positionMs'] as num?)?.toInt() ?? 0;
            final localDurationMs =
                (localState?['durationMs'] as num?)?.toInt() ?? 0;
            final resolvedLocal = resolveEpisodeLocalWatchState(
              locallyWatched:
                  trackingPolicy.progressFrom(TrackingSource.local) &&
                  locallyWatched,
              localPositionMs: trackingPolicy.progressFrom(TrackingSource.local)
                  ? localPositionMs
                  : 0,
              localDurationMs: localDurationMs,
              traktPercent: episodeKey == null
                  ? null
                  : trackingPolicy.guideProgressFrom(
                      TrackingSource.trakt,
                      sourceTraktProgress[episodeKey],
                    ),
              simklPercent: episodeKey == null
                  ? null
                  : trackingPolicy.guideProgressFrom(
                      TrackingSource.simkl,
                      sourceSimklProgress[episodeKey],
                    ),
              mdblistPercent: episodeKey == null
                  ? null
                  : trackingPolicy.guideProgressFrom(
                      TrackingSource.mdblist,
                      sourceMdblistProgress[episodeKey],
                    ),
            );
            items.add({
              'id': '${entry.title}_$i',
              // Mirror the resolver's own resumeId keying ('${title}_$i') so
              // post-switch lazy stream resolution can match by string id, not
              // positional index alone — the safety net the initial payload has.
              'resumeId': '${entry.title}_$i',
              'title': episode?.displayTitle ?? entry.title,
              'sourceTitle': entry.title,
              'url': entry.url,
              'httpHeaders': entry.httpHeaders ?? const <String, String>{},
              if (entry.hdVideoUrl != null) 'hdVideoUrl': entry.hdVideoUrl,
              if (entry.audioUrl != null) 'audioUrl': entry.audioUrl,
              'index': i,
              if (season != null) 'season': season,
              if (episodeNumber != null) 'episode': episodeNumber,
              if (epInfo?.poster != null) 'artwork': epInfo!.poster,
              if (epInfo?.plot != null) 'description': epInfo!.plot,
              if (epInfo?.rating != null) 'rating': epInfo!.rating,
              if (entry.sizeBytes != null) 'sizeBytes': entry.sizeBytes,
              'resumePositionMs': resolvedLocal.positionMs,
              'durationMs': localDurationMs,
              'updatedAt': (localState?['updatedAt'] as num?)?.toInt() ?? 0,
              if (entry.provider != null) 'provider': entry.provider,
              if (trackerPercent != null)
                'traktProgressPercent': trackerPercent,
              'watched': resolvedLocal.watched,
              'allowLocalProgressDisplay': trackingPolicy.progressFrom(
                TrackingSource.local,
              ),
            });
          }
          debugPrint(
            'VideoPlayerLauncher: resolved ${items.length} items for source playlist (isSeries=$isSeries)',
          );

          // Update the stream resolver so lazy loading works for the new
          // playlist — but only if this switch is still the latest one.
          if (!active()) {
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

      final unscopedPlaylistResolver = sourcePlaylistResolverForTv;
      if (preparation != null && unscopedPlaylistResolver != null) {
        sourcePlaylistResolverForTv =
            (index, {automaticRecovery = false}) async {
              if (!preparation.isCurrent) return null;
              return preparation.run(
                () => unscopedPlaylistResolver(
                  index,
                  automaticRecovery: automaticRecovery,
                ),
              );
            };
      }

      final sourceCommit = args.onStremioSourceCommitted;
      final sourceCommitterForTv = (int sourceIndex) async {
        if (sourceIndex < 0 || sourceIndex >= currentStremioSources.length) {
          return;
        }
        logSourceSelection(
          'player_source_committed',
          source: currentStremioSources[sourceIndex],
          index: sourceIndex,
          player: 'exo',
        );
        if (sourceCommit != null)
          await sourceCommit(currentStremioSources[sourceIndex]);
      };

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
              final generation = stremioSourcesGeneration;
              final automaticRecovery = mode.startsWith('startup:');
              var fetchMode = mode;
              String? recoveryNextMode;
              final recoveryRules = automaticRecovery
                  ? await QuickPlayStorage.getQuickPlayRules(
                      isMovie: seriesFetcher.isMovie,
                    )
                  : null;
              if (recoveryRules != null) {
                final stages = StartupRecoverySources.stages(
                  isMovie: seriesFetcher.isMovie,
                  rules: recoveryRules,
                  provider: args.startupResolverProvider,
                );
                final stageIndex = mode == 'startup:continue' ? 1 : 0;
                if (stageIndex >= stages.length) return null;
                fetchMode = stages[stageIndex];
                validateRecoveryDirectLinks = recoveryRules.validateDirectLinks;
                if (stageIndex + 1 < stages.length) {
                  recoveryNextMode = 'startup:continue';
                }
              }
              // season/episode = what the native player is CURRENTLY on (a pack
              // playlist auto-advances without relaunching); the fetcher falls
              // back to the launch episode when absent.
              final fetched = await seriesFetcher.fetch(
                fetchMode,
                season: season,
                episode: episode,
                automaticRecovery: automaticRecovery,
              );
              if (fetched == null && !automaticRecovery) return null;
              var automatic = fetched ?? <Torrent>[];
              if (recoveryRules != null) {
                final ladder = await TorrentPlaybackService.loadLadder(
                  includeSize: seriesFetcher.isMovie,
                  rules: recoveryRules,
                );
                automatic = await TorrentPlaybackService.prepareRecoverySources(
                  automatic,
                  rules: recoveryRules,
                  ladder: ladder,
                  provider: args.startupResolverProvider,
                );
              }
              // The holder was replaced mid-fetch (channel switch): these
              // results belong to the previous content — drop them.
              if (generation != stremioSourcesGeneration) return null;
              final merged = StartupRecoverySources.merge(
                existing: currentStremioSources,
                fetched: fetched ?? const <Torrent>[],
                automatic: automatic,
                replaceExistingAutomatic: automaticRecovery,
              );
              currentStremioSources = merged.sources;
              debugPrint(
                'VideoPlayerLauncher: load-more "$mode" → ${fetched?.length ?? 0} fetched, '
                '${currentStremioSources.length} total sources',
              );
              return {
                if (automaticRecovery) ...{
                  'recoveryCandidateCount': automatic.length,
                  'recoveryCandidateIndices': merged.automaticIndices,
                  'recoveryNextMode': recoveryNextMode,
                },
                'stremioSources': currentStremioSources
                    .map((t) => t.toJson())
                    .toList(),
                'packsFetched': seriesFetcher.packsFetched,
                'episodesFetched': seriesFetcher.episodesFetched,
                'movieFetched': seriesFetcher.movieFetched,
              };
            };
      }

      // Per-addon fetch for the source browser's placeholder groups.
      // 'episodes' fetches one addon's episode results, merges them
      // append-only, and reports whether they carried a torrent magnet
      // (probePacks) — the native side then makes the SECOND, lazy call with
      // 'packs'. Null (fetch failed) keeps the native Fetch row as a retry.
      Future<Map<String, dynamic>?> Function(
        List<String> addonIds,
        String mode, {
        int? season,
        int? episode,
      })?
      addonSourcesProviderForTv;
      if (seriesFetcher != null &&
          (seriesFetcher.fetchAddonEpisodes != null ||
              seriesFetcher.fetchEngine != null)) {
        addonSourcesProviderForTv =
            (
              List<String> addonIds,
              String mode, {
              int? season,
              int? episode,
            }) async {
              final generation = stremioSourcesGeneration;
              List<Map<String, dynamic>> serialized() =>
                  currentStremioSources.map((t) => t.toJson()).toList();
              // Stale = the holder was replaced (channel switch) while this
              // fetch ran; its results belong to the previous content.
              bool stale() => generation != stremioSourcesGeneration;
              if (mode == 'packs') {
                for (final addonId in addonIds) {
                  final packs = await seriesFetcher.fetchAddonPacks?.call(
                    addonId,
                    season ?? seriesFetcher.season,
                  );
                  if (stale()) return null;
                  if (packs != null && packs.isNotEmpty) {
                    currentStremioSources = SeriesSourceFetcher.mergeSources(
                      currentStremioSources,
                      packs,
                    );
                  }
                }
                // Best-effort: a failed probe still answers with the current
                // list so the native probing note simply clears.
                return {'stremioSources': serialized()};
              }
              // Every addon sharing the group's name; failed only when ALL
              // failed — a partial success is results the user asked for.
              // Only ids whose OWN results carried a magnet earn the pack
              // probe: a direct-only or empty sibling has no packs to find.
              List<Torrent>? episodes;
              final magnetIds = <String>[];
              for (final addonId in addonIds) {
                final engine = addonId.startsWith('engine::')
                    ? addonId.substring('engine::'.length)
                    : null;
                final fetched = engine == null
                    ? await seriesFetcher.fetchAddonEpisodes?.call(
                        addonId,
                        season ?? seriesFetcher.season,
                        episode ?? seriesFetcher.episode,
                      )
                    : await seriesFetcher.fetchEngine?.call(
                        engine,
                        season ?? seriesFetcher.season,
                        episode ?? seriesFetcher.episode,
                      );
                if (stale()) return null;
                if (fetched != null) {
                  (episodes ??= <Torrent>[]).addAll(fetched);
                  if (engine == null &&
                      fetched.any((t) => t.streamType == StreamType.torrent)) {
                    magnetIds.add(addonId);
                  }
                }
              }
              if (episodes == null) return null;
              if (episodes.isNotEmpty) {
                currentStremioSources = SeriesSourceFetcher.mergeSources(
                  currentStremioSources,
                  episodes,
                );
              }
              final wantPacks =
                  !seriesFetcher.isMovie &&
                  seriesFetcher.fetchAddonPacks != null;
              return {
                'stremioSources': serialized(),
                // The ids the native side should send back in its 'packs'
                // call; empty = no probe.
                'packAddonIds': wantPacks ? magnetIds : const <String>[],
              };
            };
      }

      // In-player fetch of an episode that isn't in the current playlist
      // (episode guide click / next-prev beyond the pack boundary): quick-play
      // semantics without finishing the activity. Candidate ladder mirrors the
      // Flutter player's _fetchAndPlayEpisode: existing sources (exact-episode
      // singles, packs covering the season) → episode-targeted fetch → pack
      // fetch. Candidates are pre-verified with a RAW resolve so a rejected
      // pack never disturbs the lazy-stream resolver; only the winner goes
      // through sourcePlaylistResolverForTv (which owns switch tokens and
      // entry replacement).
      Future<Map<String, dynamic>?> Function(int season, int episode)?
      episodeFetchProviderForTv;
      final resolvePlaylistForTv = sourcePlaylistResolverForTv;
      if (seriesFetcher != null &&
          !seriesFetcher.isMovie &&
          resolvePlaylistForTv != null &&
          resolveSourceToPlaylist != null &&
          args.stremioTvChannels == null) {
        bool packCoversSeason(Torrent t, int season) {
          switch (t.coverageType) {
            case 'completeSeries':
              final start = t.startSeason;
              final end = t.endSeason;
              if (start == null && end == null) return true;
              return season >= (start ?? 1) && season <= (end ?? season);
            case 'multiSeasonPack':
              final start = t.startSeason;
              final end = t.endSeason;
              return start != null &&
                  end != null &&
                  season >= start &&
                  season <= end;
            case 'seasonPack':
              return t.seasonNumber == season;
            default:
              return false;
          }
        }

        episodeFetchProviderForTv = (int season, int episode) async {
          final generation = stremioSourcesGeneration;
          bool stale() => generation != stremioSourcesGeneration;

          // Raw pre-verification: does this candidate actually contain the
          // target episode? (1-entry unparseable streams count — they get the
          // target identity stamped on.)
          Future<bool> candidateHasTarget(Torrent t) async {
            if (!await seriesFetcher.allowsCandidate(t)) return false;
            if (stale()) return false;
            List<PlaylistEntry>? entries;
            try {
              entries = await resolveSourceToPlaylist(
                t,
                canContinue: () => sessionActive() && !stale(),
              );
            } catch (_) {
              entries = null;
            }
            if (entries == null || entries.isEmpty) return false;
            if (entries.length == 1) {
              final info = SeriesParser.parseFilename(entries.first.title);
              if (info.season == null || info.episode == null) return true;
              return info.season == season && info.episode == episode;
            }
            final sp = SeriesPlaylist.fromPlaylistEntries(
              entries,
              collectionTitle: args.contentTitle ?? args.title,
              forceSeries: true,
            );
            return sp.findOriginalIndexBySeasonEpisode(season, episode) >= 0;
          }

          var preferredSourceMissing = false;
          Future<Map<String, dynamic>?> winWith(int i) async {
            final selectedSource = currentStremioSources[i];
            logSourceSelection(
              'next_episode_candidate',
              source: selectedSource,
              index: i,
              season: season,
              episode: episode,
              player: 'exo',
            );
            final items = await resolvePlaylistForTv(i);
            if (stale() || items == null || items.length < 2) {
              logSourceSelection(
                'next_episode_candidate_rejected',
                index: i,
                season: season,
                episode: episode,
                player: 'exo',
                reason: stale() ? 'superseded' : 'no_playlist',
              );
              return null;
            }
            logSourceSelection(
              'next_episode_candidate_resolved',
              source: selectedSource,
              index: i,
              season: season,
              episode: episode,
              player: 'exo',
            );
            // items[0] is the '__meta__' map; stamp the target identity onto
            // a lone stream so native lands on the right episode. The generic
            // source resolver cannot know the requested identity, so hydrate
            // its per-episode local/remote resume state here as well.
            if (items.length == 2) {
              final meta = Map<String, dynamic>.from(items[0]);
              meta['contentType'] = 'series';
              items[0] = meta;
              final row = Map<String, dynamic>.from(items[1]);
              row['season'] = season;
              row['episode'] = episode;

              final stableSeriesTitle = args.contentTitle ?? args.title;
              final episodeImdbId = effectiveContentImdbId();
              final localProgress =
                  await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
                    seriesTitle: stableSeriesTitle,
                    imdbId: episodeImdbId,
                  );
              final locallyFinished =
                  await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
                    seriesTitle: stableSeriesTitle,
                    imdbId: episodeImdbId,
                  );
              final trackerMaps = episodeImdbId != null
                  ? await Future.wait([
                      TrackerEpisodeProgressStorage.getEpisodeTraktProgress(
                        imdbId: episodeImdbId,
                      ),
                      TrackerEpisodeProgressStorage.getEpisodeSimklProgress(
                        imdbId: episodeImdbId,
                      ),
                      TrackerEpisodeProgressStorage.getConnectedEpisodeMdblistProgress(
                        imdbId: episodeImdbId,
                      ),
                    ])
                  : const <Map<String, double>>[];
              final episodeKey = '${season}_$episode';
              if (trackerMaps.isNotEmpty) {
                final trackerPercent = furthestEpisodeTrackerPercent([
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.trakt,
                    trackerMaps[0][episodeKey],
                  ),
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.simkl,
                    trackerMaps[1][episodeKey],
                  ),
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.mdblist,
                    trackerMaps[2][episodeKey],
                  ),
                ]);
                if (trackerPercent != null) {
                  row['traktProgressPercent'] = trackerPercent;
                }
              }
              final localState = localProgress[episodeKey];
              final localPositionMs =
                  (localState?['positionMs'] as num?)?.toInt() ?? 0;
              final localDurationMs =
                  (localState?['durationMs'] as num?)?.toInt() ?? 0;
              final localWatched =
                  locallyFinished[season.toString()]?.contains(episode) ??
                  false;
              final resolvedLocal = resolveEpisodeLocalWatchState(
                locallyWatched:
                    trackingPolicy.progressFrom(TrackingSource.local) &&
                    localWatched,
                localPositionMs:
                    trackingPolicy.progressFrom(TrackingSource.local)
                    ? localPositionMs
                    : 0,
                localDurationMs: localDurationMs,
                traktPercent: trackerMaps.isNotEmpty
                    ? trackingPolicy.guideProgressFrom(
                        TrackingSource.trakt,
                        trackerMaps[0][episodeKey],
                      )
                    : null,
                simklPercent: trackerMaps.length > 1
                    ? trackingPolicy.guideProgressFrom(
                        TrackingSource.simkl,
                        trackerMaps[1][episodeKey],
                      )
                    : null,
                mdblistPercent: trackerMaps.length > 2
                    ? trackingPolicy.guideProgressFrom(
                        TrackingSource.mdblist,
                        trackerMaps[2][episodeKey],
                      )
                    : null,
              );
              row['resumePositionMs'] = resolvedLocal.positionMs;
              row['durationMs'] = localDurationMs;
              row['updatedAt'] =
                  (localState?['updatedAt'] as num?)?.toInt() ?? 0;
              row['watched'] = resolvedLocal.watched;
              row['allowLocalProgressDisplay'] = trackingPolicy.progressFrom(
                TrackingSource.local,
              );
              items[1] = row;
            }
            final retained = SeriesSourceFetcher.retainForEpisode(
              currentStremioSources,
              season,
              episode,
            );
            var retainedIndex = retained.indexWhere(
              (source) => identical(source, selectedSource),
            );
            retainedIndex = retainedIndex >= 0
                ? retainedIndex
                : retained.indexWhere(
                    (source) =>
                        SeriesSourceFetcher.sourceKey(source) ==
                        SeriesSourceFetcher.sourceKey(selectedSource),
                  );
            if (retainedIndex < 0) return null;
            currentStremioSources = retained;
            // A late load-more/fetch response belongs to the previous episode.
            stremioSourcesGeneration++;
            return {
              'sourceIndex': retainedIndex,
              'preferredSourceMissing': preferredSourceMissing,
              'items': items,
              'targetSeason': season,
              'targetEpisode': episode,
              'stremioSources': currentStremioSources
                  .map((t) => t.toJson())
                  .toList(),
            };
          }

          final pinned = seriesFetcher.pinnedDirectCandidates;
          if (pinned != null) {
            await for (final candidate in pinned(
              season,
              episode,
              onPreferredMissing: () => preferredSourceMissing = true,
            )) {
              if (stale()) return null;
              if (!await candidateHasTarget(candidate)) continue;
              if (stale()) return null;
              final index = currentStremioSources.length;
              currentStremioSources = [...currentStremioSources, candidate];
              final result = await winWith(index);
              if (result != null) return result;
              if (stale()) return null;
            }
          }

          Future<Map<String, dynamic>?> tryRange(
            int from,
            int cap, {
            bool packsOnly = false,
          }) async {
            var attempts = 0;
            for (
              var i = from;
              i < currentStremioSources.length && attempts < cap;
              i++
            ) {
              final t = currentStremioSources[i];
              if (t.streamType == StreamType.externalUrl) continue;
              if (packsOnly) {
                if (t.streamType != StreamType.torrent) continue;
                if (t.coverageType != null && !packCoversSeason(t, season)) {
                  continue;
                }
              } else {
                final info = SeriesParser.parseFilename(t.displayTitle);
                final matches =
                    info.season == season && info.episode == episode;
                final covers =
                    t.streamType == StreamType.torrent &&
                    packCoversSeason(t, season);
                if (!matches && !covers) continue;
              }
              attempts++;
              if (!await candidateHasTarget(t)) {
                if (stale()) return null;
                continue;
              }
              if (stale()) return null;
              final win = await winWith(i);
              if (win != null || stale()) return win;
            }
            return null;
          }

          // 1. Existing sources.
          var result = await tryRange(0, 4);
          if (result != null || stale()) return result;

          // 2. Episode-targeted fetch.
          List<Torrent>? fetched;
          try {
            fetched = await seriesFetcher.fetch(
              SeriesSourceFetcher.modeEpisodes,
              season: season,
              episode: episode,
            );
          } catch (_) {
            fetched = null;
          }
          if (stale()) return null;
          if (fetched != null && fetched.isNotEmpty) {
            final from = currentStremioSources.length;
            currentStremioSources = SeriesSourceFetcher.mergeSources(
              currentStremioSources,
              fetched,
            );
            result = await tryRange(from, 5);
            if (result != null || stale()) return result;
          }

          // 3. Fresh pack search for that season.
          List<Torrent>? packs;
          try {
            packs = await seriesFetcher.fetch(
              SeriesSourceFetcher.modePacks,
              season: season,
              episode: episode,
            );
          } catch (_) {
            packs = null;
          }
          if (stale()) return null;
          if (packs != null && packs.isNotEmpty) {
            final from = currentStremioSources.length;
            currentStremioSources = SeriesSourceFetcher.mergeSources(
              currentStremioSources,
              packs,
            );
            result = await tryRange(from, 3, packsOnly: true);
            if (result != null || stale()) return result;
          }
          return null;
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
          // Wholesale replacement — invalidate every in-flight fetch so a
          // late response can't merge the previous content's sources in.
          stremioSourcesGeneration++;
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
      payloadMap['startupHasRemainingSavedSources'] =
          args.startupHasRemainingSavedSources;
      payloadMap['useAddonTextFormatting'] =
          await TorrentSearchStorage.getUseAddonTextFormatting();
      payloadMap['showAddonLogos'] = await TorrentSearchStorage.getShowAddonLogos();
      payloadMap['initialContinuousShuffle'] = args.initialContinuousShuffle;
      final customInventory = seriesFetcher?.loadCustomEpisodeInventory;
      if (customInventory != null) {
        final episodes = await customInventory();
        payloadMap['customShuffleEpisodes'] = episodes
            .where((episode) => isShuffleEpisodeEligible(episode))
            .toList();
      }
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
      // Every applicable addon, for the source browser's placeholder groups
      // (zero-result addons stay visible with a Fetch row). Best-effort: a
      // listing failure just means no placeholders this session.
      if (addonSourcesProviderForTv != null) {
        List<SourceAddonRef> addons = const [];
        List<SourceEngineRef> engines = const [];
        try {
          addons = await seriesFetcher!.listAddons?.call() ?? const [];
        } catch (e) {
          debugPrint('VideoPlayerLauncher: addon listing failed: $e');
        }
        try {
          engines = await seriesFetcher!.listEngines?.call() ?? const [];
        } catch (e) {
          debugPrint('VideoPlayerLauncher: engine listing failed: $e');
        }
        if (addons.isNotEmpty || engines.isNotEmpty) {
          payloadMap['sourceAddons'] = [
            for (final engine in engines)
              {
                'id': 'engine::${engine.id}',
                'name': engine.name,
                'sourceKey': engine.sourceKey,
              },
            for (final addon in addons)
              {
                'id': addon.requestKey,
                'name': addon.name,
                'sourceKey': addon.sourceKey,
              },
          ];
        }
      }

      if (!sessionActive()) {
        unawaited(serverWatch.close());
        await _closeNativeMdblist(result.payload);
        resolver.dispose();
        return false;
      }
      final launched = await AndroidTvPlayerBridge.launchTorrentPlayback(
        payload: payloadMap,
        retainSourceSession: retainSourceSession,
        sourceOwner: preparation?.owner,
        canContinue: sessionActive,
        onProgress: (progress) {
          final season = (progress['season'] as num?)?.toInt();
          final episode = (progress['episode'] as num?)?.toInt();
          final watchIndex = (progress['sourceIndex'] as num?)?.toInt();
          if (progress['isBuffering'] != true &&
              watchIndex != null &&
              watchIndex >= 0 &&
              watchIndex < currentStremioSources.length) {
            serverWatch.observe(
              currentStremioSources[watchIndex],
              positionMs: (progress['positionMs'] as num?)?.toInt() ?? 0,
              durationMs: (progress['durationMs'] as num?)?.toInt() ?? 0,
              playing: progress['isPlaying'] == true,
              completed: progress['completed'] == true,
              season: season,
              episode: episode,
            );
          }
          if (seriesFetcher != null &&
              season != null &&
              episode != null &&
              progress['isPlaying'] == true &&
              progress['isBuffering'] != true) {
            // Native URLs may have been redirect-resolved; source identity
            // must use the shared index, not equality with that final URL.
            final sourceIndex = (progress['sourceIndex'] as num?)?.toInt();
            if (sourceIndex != null &&
                sourceIndex >= 0 &&
                sourceIndex < currentStremioSources.length) {
              unawaited(
                seriesFetcher.prepareFromProgress(
                  source: currentStremioSources[sourceIndex],
                  season: season,
                  episode: episode,
                  positionMs: (progress['positionMs'] as num?)?.toInt() ?? 0,
                  durationMs: (progress['durationMs'] as num?)?.toInt() ?? 0,
                ),
              );
            }
          }
          return _handleProgressUpdate(result.payload, progress);
        },
        onFinished: () async {
          unawaited(serverWatch.close());
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
            result.payload.contentType != PlaybackContentType.series
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
        onResolveStartupSourcePlaylist: sourcePlaylistResolverForTv == null
            ? null
            : (index) =>
                  sourcePlaylistResolverForTv!(index, automaticRecovery: true),
        onCommitStremioSource: sourceCommitterForTv,
        onCommitPlaybackProgressSource: (sourceIndex) {
          if (sourceIndex >= 0 && sourceIndex < currentStremioSources.length) {
            serverWatch.commit(currentStremioSources[sourceIndex]);
          }
        },
        onStartupSourcesExhausted: args.onStartupSourcesExhausted,
        onRequestMoreSources: moreSourcesProviderForTv,
        onStartupSourceFailed: (index, reason) async {
          if (!sessionActive()) return;
          if (index < 0 || index >= currentStremioSources.length) return;
          Future<void> forget() => FailedSavedSource.forget(
            args.contentImdbId,
            currentStremioSources[index],
            reason: reason,
          );
          if (preparation == null) {
            await forget();
          } else {
            await preparation.write(forget);
          }
        },
        onRequestAddonSources: addonSourcesProviderForTv,
        onRequestEpisodeFetch: episodeFetchProviderForTv,
        onResolveAdjacentEpisode: seriesFetcher?.resolveAdjacentEpisode,
        onRequestStremioTvGuideData: args.stremioTvGuideDataProvider,
        onRequestStremioTvChannelSwitch: channelSwitchForTv,
        onRequestStremioTvNext: stremioTvNextForTv,
      );

      if (!launched) {
        unawaited(serverWatch.close());
        await _closeNativeMdblist(result.payload);
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
      unawaited(serverWatch.close());
      if (builtPayload != null) await _closeNativeMdblist(builtPayload);
      debugPrint('VideoPlayerLauncher: Android TV launch failed: $e');
      playbackResolver?.dispose();
      if (e is NativePlayerSettingsUnavailable) rethrow;
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
      final resumePositions = await IptvHistoryStorage.getIptvResumePositions([
        for (final c in channels)
          if (!c.isLive) c.url,
      ]);
      final favoriteUrls = await IptvFavoritesStorage.getIptvFavoriteChannelUrls();

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
        preferredAudioLang = await IptvAudioStorage.getIptvSeriesAudioLanguage(
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
        if (args.iptvLists != null) 'lists': args.iptvLists,
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
              if (c.attributes['tv_archive'] != null)
                'tvArchive': c.attributes['tv_archive'],
              if (int.tryParse(c.attributes['tv_archive_duration'] ?? '') !=
                  null)
                'tvArchiveDuration': int.parse(
                  c.attributes['tv_archive_duration']!,
                ),
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
      if (e is NativePlayerSettingsUnavailable) rethrow;
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

      await VideoResumeStorage.upsertVideoResume(url, {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': (progress['speed'] as num?)?.toDouble() ?? 1.0,
        'aspect': (progress['aspect'] as String?) ?? 'contain',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      }, sourceId: progress['sourceId'] as String?);
    } catch (e) {
      debugPrint('VideoPlayerLauncher: IPTV progress save failed: $e');
    }
  }

  /// Fetch TVMaze metadata asynchronously and push updates to native player
  /// This doesn't block initial playback - updates are pushed when available
  /// The sessionId parameter ensures stale metadata from previous sessions is discarded
  static void _fetchAndPushMetadataAsync(
    AndroidTvPlaybackPayload payload,
    List<LauncherEntry> entries,
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

    if (payload.contentType != PlaybackContentType.series) {
      debugPrint(
        'TVMazeAsync: SKIPPED - not series content (contentType=${payload.contentType})',
      );
      return;
    }

    // Create SeriesPlaylist for TVMaze lookup. Single-entry launches used to
    // be skipped entirely; with a catalog IMDb id they now run too, solely to
    // fetch the show's FULL episode list for the native episode guide (their
    // per-item decoration is skipped — a lone unparseable file would be
    // misattributed to S1E1).
    final playlistEntries = entries.map((e) => e.entry).toList();
    final singleEntryGuideOnly = playlistEntries.length < 2;
    if (singleEntryGuideOnly && contentImdbId == null) {
      debugPrint('TVMazeAsync: SKIPPED - less than 2 entries and no IMDb id');
      return;
    }

    debugPrint('TVMazeAsync: Starting background fetch...');

    // Run in background - don't await
    () async {
      try {
        final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(contentImdbId);
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
          await PlaylistMetadataStorage.updatePlaylistItemImdbId(
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

        // Metadata may decorate playback, but must not replace the identity
        // selected in the catalog with a title-search match for another show.
        final discoveredImdbId = contentImdbId ?? seriesPlaylist.imdbId;
        if (discoveredImdbId != null) payload.imdbId = discoveredImdbId;
        debugPrint(
          'TVMazeAsync: Playback tracking identity: $discoveredImdbId',
        );

        Future<
          ({
            List<Map<String, dynamic>> metadataUpdates,
            List<Map<String, dynamic>> guideEpisodes,
            int episodesWithInfo,
            int episodesWithoutInfo,
          })
        >
        buildUpdates() async {
          final localEpisodeProgress =
              await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
                seriesTitle: seriesPlaylist.seriesTitle ?? payload.title,
                imdbId: discoveredImdbId,
              );
          final locallyFinished =
              await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
                seriesTitle: seriesPlaylist.seriesTitle ?? payload.title,
                imdbId: discoveredImdbId,
              );
          final trackerMaps = discoveredImdbId != null
              ? await Future.wait([
                  TrackerEpisodeProgressStorage.getEpisodeTraktProgress(
                    imdbId: discoveredImdbId,
                  ),
                  TrackerEpisodeProgressStorage.getEpisodeSimklProgress(
                    imdbId: discoveredImdbId,
                  ),
                  TrackerEpisodeProgressStorage.getConnectedEpisodeMdblistProgress(
                    imdbId: discoveredImdbId,
                  ),
                ])
              : const <Map<String, double>>[];

          Map<String, dynamic> watchState(int season, int episode) {
            final episodeKey = '${season}_$episode';
            final local = localEpisodeProgress[episodeKey];
            final positionMs = (local?['positionMs'] as num?)?.toInt() ?? 0;
            final durationMs = (local?['durationMs'] as num?)?.toInt() ?? 0;
            final locallyWatched =
                locallyFinished[season.toString()]?.contains(episode) ?? false;
            final traktPercent = trackerMaps.isNotEmpty
                ? trackingPolicy.guideProgressFrom(
                    TrackingSource.trakt,
                    trackerMaps[0][episodeKey],
                  )
                : null;
            final simklPercent = trackerMaps.length > 1
                ? trackingPolicy.guideProgressFrom(
                    TrackingSource.simkl,
                    trackerMaps[1][episodeKey],
                  )
                : null;
            final mdblistPercent = trackerMaps.length > 2
                ? trackingPolicy.guideProgressFrom(
                    TrackingSource.mdblist,
                    trackerMaps[2][episodeKey],
                  )
                : null;
            final localState = resolveEpisodeLocalWatchState(
              locallyWatched:
                  trackingPolicy.progressFrom(TrackingSource.local) &&
                  locallyWatched,
              localPositionMs: trackingPolicy.progressFrom(TrackingSource.local)
                  ? positionMs
                  : 0,
              localDurationMs: durationMs,
              traktPercent: traktPercent,
              simklPercent: simklPercent,
              mdblistPercent: mdblistPercent,
            );
            final trackerPercent = furthestEpisodeTrackerPercent([
              traktPercent,
              simklPercent,
              mdblistPercent,
            ]);
            return {
              // Explicit zeros clear stale cached state on rows which are not
              // currently playing. Native protects the live row from a late
              // snapshot moving its position backwards.
              'resumePositionMs': localState.positionMs,
              'durationMs': durationMs,
              // Always send a tracker value so a successful refresh can clear
              // stale remote state already displayed by the native player.
              'trackerProgressPercent': trackerPercent ?? 0.0,
              // Explicit local completion differs from tracker 100%: remote
              // completion yields to a local partial during an active rewatch.
              'watched': localState.watched,
              'allowLocalProgressDisplay': trackingPolicy.progressFrom(
                TrackingSource.local,
              ),
            };
          }

          // Actual playlist rows need the same watch state as TVMaze-only
          // placeholders. Include every classified row even when TVMaze lacks
          // decorative metadata.
          final metadataUpdates = <Map<String, dynamic>>[];
          var episodesWithInfo = 0;
          var episodesWithoutInfo = 0;
          if (!singleEntryGuideOnly) {
            for (final episode in seriesPlaylist.allEpisodes) {
              final info = episode.episodeInfo;
              if (info == null) {
                episodesWithoutInfo++;
              } else {
                episodesWithInfo++;
              }
              final season = episode.seriesInfo.season;
              final number = episode.seriesInfo.episode;
              metadataUpdates.add({
                'originalIndex': episode.originalIndex,
                if (season != null) 'season': season,
                if (number != null) 'episode': number,
                if (info?.title != null) 'title': info!.title,
                if (info?.plot != null) 'description': info!.plot,
                if (info?.poster != null) 'artwork': info!.poster,
                if (info?.rating != null) 'rating': info!.rating,
                if (season != null && number != null)
                  ...watchState(season, number),
              });
            }
          } else {
            // The parser cannot safely infer a lone file's identity, but the
            // launch payload may already carry an authoritative catalog S/E.
            // Decorate and update that real row so it does not mask the richer
            // matching full-guide placeholder.
            for (var i = 0; i < payload.items.length; i++) {
              final item = payload.items[i];
              if (item.season == null || item.episode == null) continue;
              final rawInfo = seriesPlaylist.fullTvmazeEpisodes
                  .firstWhereOrNull(
                    (episode) =>
                        episode['season'] == item.season &&
                        episode['number'] == item.episode,
                  );
              final info = rawInfo == null
                  ? null
                  : EpisodeInfo.fromTVMaze(rawInfo);
              if (info == null) {
                episodesWithoutInfo++;
              } else {
                episodesWithInfo++;
              }
              metadataUpdates.add({
                'originalIndex': i,
                'season': item.season,
                'episode': item.episode,
                if (info?.title != null) 'title': info!.title,
                if (info?.plot != null) 'description': info!.plot,
                if (info?.poster != null) 'artwork': info!.poster,
                if (info?.rating != null) 'rating': info!.rating,
                ...watchState(item.season!, item.episode!),
              });
            }
          }

          // The show's FULL episode list for the native episode guide (every
          // episode, present in the pack or not).
          final guideEpisodes = <Map<String, dynamic>>[];
          for (final m in seriesPlaylist.fullTvmazeEpisodes) {
            final season = m['season'] as int?;
            final number = m['number'] as int?;
            if (season == null || number == null) continue;
            final info = EpisodeInfo.fromTVMaze(m);
            guideEpisodes.add({
              'season': season,
              'episode': number,
              'shuffleEligible': isShuffleEpisodeEligible(m),
              if (info.title != null) 'title': info.title,
              if (info.poster != null) 'artwork': info.poster,
              if (info.plot != null) 'description': info.plot,
              if (info.rating != null) 'rating': info.rating,
              if (info.runtime != null) 'runtime': info.runtime,
              ...watchState(season, number),
            });
          }
          return (
            metadataUpdates: metadataUpdates,
            guideEpisodes: guideEpisodes,
            episodesWithInfo: episodesWithInfo,
            episodesWithoutInfo: episodesWithoutInfo,
          );
        }

        var pushTail = Future<void>.value();
        Future<bool> pushUpdates({required String phase}) {
          final push = pushTail.then((_) async {
            final updates = await buildUpdates();
            debugPrint(
              'TVMazeAsync: $phase episodes with info='
              '${updates.episodesWithInfo}, without info='
              '${updates.episodesWithoutInfo}, guide='
              '${updates.guideEpisodes.length}, rows='
              '${updates.metadataUpdates.length}',
            );
            if (updates.metadataUpdates.isEmpty &&
                discoveredImdbId == null &&
                updates.guideEpisodes.isEmpty) {
              return false;
            }
            if (!AndroidTvPlayerBridge.isCurrentSession(sessionId)) {
              debugPrint(
                'TVMazeAsync: DISCARDED $phase - session $sessionId is stale',
              );
              return false;
            }
            AndroidTvPlayerBridge.storePendingMetadataUpdates(
              updates.metadataUpdates,
              sessionId: sessionId,
              imdbId: discoveredImdbId,
              guideEpisodes: updates.guideEpisodes,
              showName: seriesPlaylist.tvmazeShowName,
            );
            await AndroidTvPlayerBridge.updateEpisodeMetadata(
              updates.metadataUpdates,
              sessionId: sessionId,
              imdbId: discoveredImdbId,
              guideEpisodes: updates.guideEpisodes,
              showName: seriesPlaylist.tvmazeShowName,
            );
            return true;
          });
          pushTail = push.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          );
          return push;
        }

        // First push is cache-only and makes the complete TVMaze guide usable
        // immediately. Network histories refresh after that visible state.
        if (!await pushUpdates(phase: 'cached')) return;
        if (discoveredImdbId == null) return;

        final discoveredAfterLaunch = contentImdbId == null;
        final standardTrackerRefreshes = <Future<Map<String, double>?>>[
          if (singleEntryGuideOnly || discoveredAfterLaunch)
            EpisodeTrackerSnapshotService.refreshTrakt(discoveredImdbId),
          if (discoveredAfterLaunch)
            EpisodeTrackerSnapshotService.refreshSimkl(discoveredImdbId),
        ];

        // Publish the established trackers as one update, independently from
        // MDBList's larger history request. This avoids both provider coupling
        // and a redundant full-guide broadcast for each established tracker.
        final refreshGroups = <Future<void>>[
          if (standardTrackerRefreshes.isNotEmpty)
            () async {
              final refreshed = await Future.wait(standardTrackerRefreshes);
              if (refreshed.any((snapshot) => snapshot != null)) {
                await pushUpdates(phase: 'Trakt/Simkl refreshed');
              }
            }(),
          () async {
            final refreshed =
                await EpisodeTrackerSnapshotService.refreshMdblistHistory(
                  discoveredImdbId,
                );
            if (refreshed != null) {
              await pushUpdates(phase: 'MDBList refreshed');
            }
          }(),
        ];
        await Future.wait(refreshGroups);
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
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          rdTorrentId: rdTorrentId,
        );
      }
      if (torboxTorrentId != null && torboxTorrentId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          torboxTorrentId: torboxTorrentId,
        );
      }
      if (pikpakCollectionId != null && pikpakCollectionId.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
          posterUrl,
          pikpakCollectionId: pikpakCollectionId,
        );
      }
      if (webDavPath != null && webDavPath.isNotEmpty) {
        await PlaylistArtworkStorage.updatePlaylistItemPoster(
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
  static bool _simklSeriesSEUnresolved(
    AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) {
    if (payload.trackingContentType != 'series') return false;
    return progress['season'] == null || progress['episode'] == null;
  }

  static MdblistScrobbleTarget? _nativeMdblistTarget(
    AndroidTvPlaybackPayload payload, {
    int? season,
    int? episode,
  }) {
    final imdbId = payload.imdbId;
    if (imdbId == null || imdbId.isEmpty) return null;
    final ids = MdblistMediaIds.forContent(imdbId);
    if (payload.trackingContentType != 'series') {
      return MdblistScrobbleTarget.movie(ids);
    }
    if (season == null || episode == null) return null;
    return MdblistScrobbleTarget.episode(ids, season: season, episode: episode);
  }

  static Future<void> _initializeNativeMdblist(
    AndroidTvPlaybackPayload payload, {
    MdblistService? service,
  }) async {
    service ??= MdblistService.instance;
    if (!payload.mdblistScrobble || !service.networkEnabled) return;
    if (payload.items.isEmpty) return;
    // Capture authorization at launch even if episode coordinates arrive later.
    // Session creation then stays synchronous and bound to this playback account.
    final capability = await service.capturePlaybackCapability();
    final playbackService = service;
    payload.mdblistSessionFactory = (target) => MdblistScrobbleSession.forService(
      service: playbackService,
      target: target,
      capability: capability,
    );
    final index = payload.startIndex.clamp(0, payload.items.length - 1);
    final item = payload.items[index];
    final target = _nativeMdblistTarget(
      payload,
      season: item.season,
      episode: item.episode,
    );
    if (target != null) _ensureNativeMdblistSession(payload, target);
  }

  static MdblistScrobbleSession? _ensureNativeMdblistSession(
    AndroidTvPlaybackPayload payload,
    MdblistScrobbleTarget target,
  ) {
    if (payload.mdblistSession != null) return payload.mdblistSession;
    final create = payload.mdblistSessionFactory;
    if (create == null) return null;
    payload.mdblistSeason = target.season;
    payload.mdblistEpisode = target.episode;
    return payload.mdblistSession = create(target);
  }

  static Future<void> _closeNativeMdblist(
    AndroidTvPlaybackPayload payload,
  ) async {
    // A late frame must not create another session after playback has ended.
    payload.mdblistSessionFactory = null;
    final session = payload.mdblistSession;
    payload.mdblistSession = null;
    payload.mdblistSeason = null;
    payload.mdblistEpisode = null;
    await session?.close();
  }

  static Future<void> _handleProgressUpdate(
    AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) async {
    try {
      final positionMs = (progress['positionMs'] ?? 0) as int;
      final durationMs = (progress['durationMs'] ?? 0) as int;
      final speed = (progress['speed'] ?? 1.0) as double;
      final aspect = (progress['aspect'] ?? 'contain') as String;
      final completed = progress['completed'] == true;
      final localCompleted = progress['localCompleted'] == true;
      final resumeId = progress['resumeId'] as String?;
      final itemIndex = progress['itemIndex'] as int? ?? 0;
      final progressUrl = progress['url'] as String?;

      if (resumeId != null && progressUrl != null && progressUrl.isNotEmpty) {
        StreamRedirectResolver.cacheResolvedStream(resumeId, progressUrl);
      }

      // Native TV uses this one-shot signal for locally tracked catalog
      // movies. Complete before the generic resume writer runs, otherwise the
      // next native ping would immediately recreate Continue Watching after we
      // intentionally clear it.
      final locallyTrackedMovie =
          payload.localCompletionTracking &&
          payload.trackingContentType == 'movie' &&
          payload.contentType == PlaybackContentType.single &&
          payload.imdbId != null &&
          payload.imdbId!.isNotEmpty;
      if (locallyTrackedMovie && !payload.localMovieCompletionRecorded) {
        final movieProgress = durationMs > 0
            ? positionMs * 100 / durationMs
            : 0.0;
        if (!payload.localMovieRewatchStarted &&
            positionMs > 0 &&
            movieProgress < payload.movieCompletionThreshold) {
          await MovieProgressStorage.unmarkMovieAsFinished(payload.imdbId!);
          payload.localMovieRewatchStarted = true;
        }
        if (localCompleted ||
            completed ||
            progress['localCompletionEligible'] == true) {
          await Future.wait([
            MovieProgressStorage.markMovieAsFinished(payload.imdbId!),
            if (resumeId != null && resumeId.isNotEmpty)
              VideoResumeStorage.removeVideoResume(resumeId),
          ]);
          payload.localMovieCompletionRecorded = true;
        }
      }

      // Trakt scrobble for Android TV player (movies and series)
      if (payload.traktScrobble &&
          payload.imdbId != null &&
          durationMs > 0 &&
          TraktService.isScrobbleReady(
            contentType: payload.trackingContentType,
            season: progress['season'] as int?,
            episode: progress['episode'] as int?,
          )) {
        // Treat buffering as still playing — ExoPlayer sets isPlaying=false during buffer
        final isPlaying =
            progress['isPlaying'] == true || progress['isBuffering'] == true;
        final traktProgress = (positionMs / durationMs * 100).clamp(0.0, 100.0);
        final imdbId = payload.imdbId!;
        // For series, read season/episode from Kotlin progress update
        // For non-series, ignore parsed values — avoids filename false positives (e.g. "5.1" surround → S5E1)
        final season = payload.trackingContentType == 'series'
            ? progress['season'] as int?
            : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (NativeScrobbleSession.traktLastKnownSeason != null &&
            NativeScrobbleSession.traktLastKnownEpisode != null &&
            (season != NativeScrobbleSession.traktLastKnownSeason ||
                episode != NativeScrobbleSession.traktLastKnownEpisode) &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            NativeScrobbleSession.traktLastKnownProgress,
            season: NativeScrobbleSession.traktLastKnownSeason,
            episode: NativeScrobbleSession.traktLastKnownEpisode,
            contentType: payload.trackingContentType,
          );
          NativeScrobbleSession.traktLastScrobbleAction = 'stop';
        }

        NativeScrobbleSession.traktLastKnownProgress = traktProgress;
        NativeScrobbleSession.traktLastKnownSeason = season;
        NativeScrobbleSession.traktLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (NativeScrobbleSession.traktLastScrobbleAction == 'stop' &&
            isPlaying &&
            traktProgress <= 80 &&
            !completed) {
          NativeScrobbleSession.traktLastScrobbleAction = null;
        }
        if (completed && NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          NativeScrobbleSession.traktLastScrobbleAction = 'stop';
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          TraktService.instance.scrobbleStop(
            imdbId,
            traktProgress,
            season: season,
            episode: episode,
            contentType: payload.trackingContentType,
          );
        } else if (isPlaying &&
            NativeScrobbleSession.traktLastScrobbleAction != 'start' &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          // Trakt rejects start above 80% — send stop instead, no heartbeat needed
          if (traktProgress > 80) {
            NativeScrobbleSession.traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
          } else {
            NativeScrobbleSession.traktLastScrobbleAction = 'start';
            TraktService.instance.scrobbleStart(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
            // Start heartbeat timer to checkpoint progress every 2 minutes
            NativeScrobbleSession.traktHeartbeatTimer?.cancel();
            NativeScrobbleSession.traktHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              // Trakt rejects start/pause above 80% — send stop and end heartbeat
              if (NativeScrobbleSession.traktLastKnownProgress > 80) {
                NativeScrobbleSession.traktLastScrobbleAction = 'stop';
                TraktService.instance.scrobbleStop(
                  payload.imdbId!,
                  NativeScrobbleSession.traktLastKnownProgress,
                  season: NativeScrobbleSession.traktLastKnownSeason,
                  episode: NativeScrobbleSession.traktLastKnownEpisode,
                  contentType: payload.trackingContentType,
                );
                debugPrint(
                  'Trakt: Heartbeat stop at ${NativeScrobbleSession.traktLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                NativeScrobbleSession.traktHeartbeatTimer?.cancel();
                NativeScrobbleSession.traktHeartbeatTimer = null;
                return;
              }
              // Use latest known progress/season/episode
              NativeScrobbleSession.traktLastScrobbleAction = 'start';
              TraktService.instance.scrobbleStart(
                payload.imdbId!,
                NativeScrobbleSession.traktLastKnownProgress,
                season: NativeScrobbleSession.traktLastKnownSeason,
                episode: NativeScrobbleSession.traktLastKnownEpisode,
                contentType: payload.trackingContentType,
              );
              debugPrint(
                'Trakt: Heartbeat scrobble at ${NativeScrobbleSession.traktLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            NativeScrobbleSession.traktLastScrobbleAction != null &&
            NativeScrobbleSession.traktLastScrobbleAction != 'pause' &&
            NativeScrobbleSession.traktLastScrobbleAction != 'stop') {
          // Trakt rejects pause when progress > 80% — send stop instead
          NativeScrobbleSession.traktHeartbeatTimer?.cancel();
          NativeScrobbleSession.traktHeartbeatTimer = null;
          if (traktProgress > 80) {
            NativeScrobbleSession.traktLastScrobbleAction = 'stop';
            TraktService.instance.scrobbleStop(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
            );
          } else {
            NativeScrobbleSession.traktLastScrobbleAction = 'pause';
            TraktService.instance.scrobblePause(
              imdbId,
              traktProgress,
              season: season,
              episode: episode,
              contentType: payload.trackingContentType,
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
        final season = payload.trackingContentType == 'series'
            ? progress['season'] as int?
            : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;

        // Detect episode switch — scrobble stop for the old episode
        if (NativeScrobbleSession.simklLastKnownSeason != null &&
            NativeScrobbleSession.simklLastKnownEpisode != null &&
            (season != NativeScrobbleSession.simklLastKnownSeason ||
                episode != NativeScrobbleSession.simklLastKnownEpisode) &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            NativeScrobbleSession.simklLastKnownProgress,
            season: NativeScrobbleSession.simklLastKnownSeason,
            episode: NativeScrobbleSession.simklLastKnownEpisode,
          );
          NativeScrobbleSession.simklLastScrobbleAction = 'stop';
        }

        NativeScrobbleSession.simklLastKnownProgress = simklProgress;
        NativeScrobbleSession.simklLastKnownSeason = season;
        NativeScrobbleSession.simklLastKnownEpisode = episode;
        // Recover session if stopped at >80% and user sought back under 80%
        if (NativeScrobbleSession.simklLastScrobbleAction == 'stop' &&
            isPlaying &&
            simklProgress <= 80 &&
            !completed) {
          NativeScrobbleSession.simklLastScrobbleAction = null;
        }
        if (completed && NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklLastScrobbleAction = 'stop';
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          SimklService.instance.scrobbleStop(
            imdbId,
            simklProgress,
            season: season,
            episode: episode,
          );
        } else if (isPlaying &&
            NativeScrobbleSession.simklLastScrobbleAction != 'start' &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          // ≥80% would just finalize server-side — send stop, no heartbeat
          if (simklProgress > 80) {
            NativeScrobbleSession.simklLastScrobbleAction = 'stop';
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
            NativeScrobbleSession.simklLastScrobbleAction = 'start';
            // 2-minute checkpoint — comfortably above Simkl's 20s rate lock
            NativeScrobbleSession.simklHeartbeatTimer?.cancel();
            NativeScrobbleSession.simklHeartbeatTimer = Timer.periodic(const Duration(minutes: 2), (
              _,
            ) {
              if (payload.imdbId == null) return;
              if (NativeScrobbleSession.simklLastKnownProgress > 80) {
                NativeScrobbleSession.simklLastScrobbleAction = 'stop';
                SimklService.instance.scrobbleStop(
                  payload.imdbId!,
                  NativeScrobbleSession.simklLastKnownProgress,
                  season: NativeScrobbleSession.simklLastKnownSeason,
                  episode: NativeScrobbleSession.simklLastKnownEpisode,
                );
                debugPrint(
                  'Simkl: Heartbeat stop at ${NativeScrobbleSession.simklLastKnownProgress.toStringAsFixed(1)}% (>80%)',
                );
                NativeScrobbleSession.simklHeartbeatTimer?.cancel();
                NativeScrobbleSession.simklHeartbeatTimer = null;
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
              NativeScrobbleSession.simklLastScrobbleAction = 'start';
              SimklService.instance.scrobblePause(
                payload.imdbId!,
                NativeScrobbleSession.simklLastKnownProgress,
                season: NativeScrobbleSession.simklLastKnownSeason,
                episode: NativeScrobbleSession.simklLastKnownEpisode,
              );
              debugPrint(
                'Simkl: Heartbeat pause checkpoint at ${NativeScrobbleSession.simklLastKnownProgress.toStringAsFixed(1)}%',
              );
            });
          }
        } else if (!isPlaying &&
            !completed &&
            NativeScrobbleSession.simklLastScrobbleAction != null &&
            NativeScrobbleSession.simklLastScrobbleAction != 'pause' &&
            NativeScrobbleSession.simklLastScrobbleAction != 'stop') {
          NativeScrobbleSession.simklHeartbeatTimer?.cancel();
          NativeScrobbleSession.simklHeartbeatTimer = null;
          if (simklProgress > 80) {
            NativeScrobbleSession.simklLastScrobbleAction = 'stop';
            SimklService.instance.scrobbleStop(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          } else {
            NativeScrobbleSession.simklLastScrobbleAction = 'pause';
            SimklService.instance.scrobblePause(
              imdbId,
              simklProgress,
              season: season,
              episode: episode,
            );
          }
        }
      }

      if (durationMs > 0) {
        final isPlaying =
            progress['isPlaying'] == true || progress['isBuffering'] == true;
        final season = payload.trackingContentType == 'series'
            ? progress['season'] as int?
            : null;
        final episode = payload.trackingContentType == 'series'
            ? progress['episode'] as int?
            : null;
        final target = _nativeMdblistTarget(
          payload,
          season: season,
          episode: episode,
        );
        final mdblistSession = target == null
            ? null
            : _ensureNativeMdblistSession(payload, target);
        if (mdblistSession != null) {
          if (season != payload.mdblistSeason ||
              episode != payload.mdblistEpisode) {
            await mdblistSession.switchTarget(
              target!,
              position: Duration(milliseconds: positionMs),
              duration: Duration(milliseconds: durationMs),
            );
            payload.mdblistSeason = season;
            payload.mdblistEpisode = episode;
          } else {
            mdblistSession.seek(
              Duration(milliseconds: positionMs),
              Duration(milliseconds: durationMs),
            );
          }
          if (completed) {
            mdblistSession.complete();
          } else if (isPlaying) {
            mdblistSession.play();
          } else {
            mdblistSession.pause();
          }
        }
      }

      // Local completion suppresses resume persistence only. Remote trackers
      // must still receive the threshold frame and all later progress/exit data.
      if (locallyTrackedMovie && payload.localMovieCompletionRecorded) return;

      if (payload.contentType == PlaybackContentType.series) {
        final season = progress['season'] as int?;
        final episode = progress['episode'] as int?;
        final seriesTitle = payload.seriesTitle ?? payload.title;
        if (season != null && episode != null) {
          await SeriesProgressStorage.saveSeriesPlaybackState(
            seriesTitle: seriesTitle,
            season: season,
            episode: episode,
            positionMs: positionMs,
            durationMs: durationMs,
            speed: speed,
            aspect: aspect,
            imdbId: payload.imdbId,
          );

          if (completed ||
              (payload.localCompletionTracking && localCompleted)) {
            await EpisodeCompletionStorage.markEpisodeAsFinished(
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
              (resumeId != null ? StreamRedirectResolver.resolvedStreamCache[resumeId] : null) ??
              item.url;

          await VideoProgressStorage.saveVideoPlaybackState(
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
          (resumeId != null ? StreamRedirectResolver.resolvedStreamCache[resumeId] : null) ??
          item.url;

      await VideoProgressStorage.saveVideoPlaybackState(
        videoTitle: videoTitle,
        videoUrl: persistedUrl,
        positionMs: positionMs,
        durationMs: durationMs,
        speed: speed,
        aspect: aspect,
        imdbId: payload.imdbId,
      );

      if (payload.contentType == PlaybackContentType.single) {
        await VideoResumeStorage.upsertVideoResume(videoTitle, {
          'positionMs': positionMs,
          'durationMs': durationMs,
          'speed': speed,
          'aspect': aspect,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      // ALSO save in collection format for Android TV playlist progress tracking
      // This allows the playlist screen to display progress indicators for collections
      if (payload.contentType == PlaybackContentType.collection &&
          payload.seriesTitle != null) {
        debugPrint(
          '📺 AndroidTV Collection Save Check: seriesTitle="${payload.seriesTitle}", itemIndex=$fallbackIndex',
        );

        await SeriesProgressStorage.saveSeriesPlaybackState(
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
          await EpisodeCompletionStorage.markEpisodeAsFinished(
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
      rethrow;
    }
  }

  static Future<void> _handlePlaybackFinished(
    AndroidTvPlaybackPayload payload,
  ) async {
    debugPrint(
      'VideoPlayerLauncher: Android TV playback finished for "${payload.title}"',
    );
    // Final Trakt scrobble stop on playback exit
    // Skip if last action was 'stop' (already stopped) or 'pause' (pause already
    // created the playback entry — sending stop would create a duplicate)
    NativeScrobbleSession.traktHeartbeatTimer?.cancel();
    NativeScrobbleSession.traktHeartbeatTimer = null;
    if (payload.traktScrobble &&
        payload.imdbId != null &&
        NativeScrobbleSession.traktLastScrobbleAction != 'stop' &&
        NativeScrobbleSession.traktLastScrobbleAction != 'pause') {
      TraktService.instance.scrobbleStop(
        payload.imdbId!,
        NativeScrobbleSession.traktLastKnownProgress,
        season: NativeScrobbleSession.traktLastKnownSeason,
        episode: NativeScrobbleSession.traktLastKnownEpisode,
        contentType: payload.trackingContentType,
      );
    }
    NativeScrobbleSession.traktLastScrobbleAction = null;
    NativeScrobbleSession.traktLastKnownProgress = 0.0;
    NativeScrobbleSession.traktLastKnownSeason = null;
    NativeScrobbleSession.traktLastKnownEpisode = null;

    // Final Simkl scrobble stop on playback exit — parallel to the Trakt
    // cleanup above, including the same skip-after-pause nuance (a pause
    // already created Simkl's playback entry; stop would duplicate it).
    // The extra series-S/E guard: unlike the per-frame block, this direct
    // stop isn't gated by _simklSeriesSEUnresolved, so a series whose S/E
    // never resolved (every frame was skipped, last-known stays null) would
    // otherwise be finalized as a bogus movie. Skip it in that case.
    NativeScrobbleSession.simklHeartbeatTimer?.cancel();
    NativeScrobbleSession.simklHeartbeatTimer = null;
    final simklSeriesUnresolved =
        payload.trackingContentType == 'series' &&
        (NativeScrobbleSession.simklLastKnownSeason == null || NativeScrobbleSession.simklLastKnownEpisode == null);
    if (payload.simklScrobble &&
        payload.imdbId != null &&
        NativeScrobbleSession.simklLastScrobbleAction != 'stop' &&
        NativeScrobbleSession.simklLastScrobbleAction != 'pause' &&
        !simklSeriesUnresolved) {
      SimklService.instance.scrobbleStop(
        payload.imdbId!,
        NativeScrobbleSession.simklLastKnownProgress,
        season: NativeScrobbleSession.simklLastKnownSeason,
        episode: NativeScrobbleSession.simklLastKnownEpisode,
      );
    }
    NativeScrobbleSession.simklLastScrobbleAction = null;
    NativeScrobbleSession.simklLastKnownProgress = 0.0;
    NativeScrobbleSession.simklLastKnownSeason = null;
    NativeScrobbleSession.simklLastKnownEpisode = null;
    await _closeNativeMdblist(payload);
  }

  static Future<String> _resolveEntryUrl(
    PlaylistEntry entry,
    VideoPlayerLaunchArgs args, {
    bool Function()? canContinue,
  }) async {
    void checkCurrent() {
      if (canContinue?.call() == false) {
        throw const PlaybackPreparationRetired();
      }
    }

    checkCurrent();
    if (entry.url.isNotEmpty) {
      // Keep protected URLs attached to their declared headers and origin.
      // The player handles redirects; the legacy URL-only resolver cannot.
      if ((entry.httpHeaders ?? args.httpHeaders)?.isNotEmpty == true) {
        return entry.url;
      }
      // For direct stream URLs, resolve redirects to get final URL
      // (needed for HLS streams behind short URL redirects like USATV)
      return await StreamRedirectResolver.resolveRedirectUrl(entry.url, canContinue: canContinue);
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
      final apiKey = await TorboxStorage.getTorboxApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
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
          canContinue: canContinue,
        );
      }
      checkCurrent();
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
      final fileData = await pikpak.getFileDetails(
        fileId,
        canContinue: canContinue,
      );
      checkCurrent();
      final url = pikpak.getStreamingUrl(fileData);
      if (url == null || url.isEmpty) {
        throw Exception('PikPak returned an empty stream URL');
      }
      return url;
    }

    // Premiumize cloud-browser lazy resolution: re-fetch a fresh direct link by
    // cloud item id (items saved from the cloud browser have no infohash).
    if (entry.premiumizeItemId != null && entry.premiumizeItemId!.isNotEmpty) {
      final apiKey = await PremiumizeStorage.getPremiumizeApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Premiumize API key');
      }
      final file = await PremiumizeService.resolveItemById(
        apiKey,
        entry.premiumizeItemId!,
      );
      checkCurrent();
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
        final apiKey = await PremiumizeStorage.getPremiumizeApiKey(
          canContinue: canContinue,
        );
        checkCurrent();
        if (apiKey == null || apiKey.isEmpty) {
          throw Exception('Missing Premiumize API key');
        }
        final files = await PremiumizeService.resolveFilesByHash(apiKey, hash);
        checkCurrent();
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
      final apiKey = await RealDebridStorage.getApiKey(canContinue: canContinue);
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing Real Debrid API key');
      }
      final unrestrictResult = await DebridService.unrestrictLink(
        apiKey,
        entry.restrictedLink!,
        canContinue: canContinue,
      );
      checkCurrent();
      final url = unrestrictResult['download']?.toString() ?? '';
      checkCurrent();
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
      final apiKey = await AllDebridStorage.getAllDebridApiKey(
        canContinue: canContinue,
      );
      checkCurrent();
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('Missing AllDebrid API key');
      }
      final url = await AllDebridService.unlockLink(
        apiKey,
        lockedLink,
        canContinue: canContinue,
      );
      checkCurrent();
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

















class _AndroidTvPlaylistResolver {
  List<LauncherEntry> entries;
  final Future<String> Function(
    PlaylistEntry entry, {
    bool Function()? canContinue,
  })
  resolveEntry;

  // Monotonic token for in-flight source switches. The native side already
  // discards stale playlist RESULTS via its own resolution token, but the Dart
  // `replaceEntries` side effect was ungated: tap B then C quickly and, if B's
  // torrent resolves slower, B's `replaceEntries` could run LAST and leave the
  // lazy stream resolver pointing at B while the player shows C — wrong-torrent
  // lazy resolution. Each switch captures a token via [beginSwitch]; a late
  // [replaceEntries] whose token is no longer current is ignored.
  int _switchSeq = 0;
  bool _disposed = false;
  int beginSwitch() => ++_switchSeq;
  bool isLatestSwitch(int token) => !_disposed && token == _switchSeq;

  _AndroidTvPlaylistResolver({
    required this.entries,
    required this.resolveEntry,
  });

  /// Replace entries with a new playlist (used during source switching).
  /// Pass the [switchToken] from [beginSwitch] so a stale (superseded) switch
  /// that resolves late is skipped instead of overwriting a newer source.
  void replaceEntries(List<PlaylistEntry> playlistEntries, {int? switchToken}) {
    if (_disposed || (switchToken != null && switchToken != _switchSeq)) {
      debugPrint(
        'AndroidTvPlaylistResolver: skipping stale replaceEntries '
        '(token $switchToken != current $_switchSeq)',
      );
      return;
    }
    // Clear cached URLs for old entries before replacing
    StreamRedirectResolver.clearResolvedStreams(entries.map((e) => e.resumeId));

    entries = playlistEntries.asMap().entries.map((e) {
      final i = e.key;
      final entry = e.value;
      return LauncherEntry(
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
    final token = _switchSeq;
    bool active() => isLatestSwitch(token);
    if (!active()) return null;
    debugPrint(
      'AndroidTvPlaylistResolver: handleRequest called with: $request',
    );
    debugPrint('AndroidTvPlaylistResolver: total entries: ${entries.length}');

    LauncherEntry? target;
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
    final url = await resolveEntry(target.entry, canContinue: active);
    if (!active()) return null;
    debugPrint(
      'AndroidTvPlaylistResolver: resolved URL: ${url.isNotEmpty ? url.substring(0, min(50, url.length)) : "EMPTY"}',
    );

    if (url.isEmpty) {
      debugPrint('AndroidTvPlaylistResolver: ERROR - resolved URL is empty!');
      return null;
    }

    StreamRedirectResolver.cacheResolvedStream(target.resumeId, url);
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
    _disposed = true;
    StreamRedirectResolver.clearResolvedStreams(entries.map((e) => e.resumeId));
  }
}

class _AndroidTvPlaybackPayloadBuilder {
  final VideoPlayerLaunchArgs args;

  final bool Function()? canContinue;
  const _AndroidTvPlaybackPayloadBuilder(this.args, {this.canContinue});

  Future<AndroidTvPlaybackPayloadResult?> build() async {
    if (canContinue?.call() == false) return null;
    final playlistEntries = _normalizePlaylist();
    final seriesPlaylist = await _buildSeriesPlaylist(playlistEntries);
    if (canContinue?.call() == false) return null;
    final contentType = _determineContentType(seriesPlaylist, playlistEntries);
    final startupRules =
        args.startupFailoverEnabled && args.stremioSources?.isNotEmpty == true
        ? await QuickPlayStorage.getQuickPlayRules(
            isMovie: contentType != PlaybackContentType.series,
          )
        : null;
    if (canContinue?.call() == false) return null;
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      args.contentImdbId,
    );
    if (canContinue?.call() == false) return null;
    final localCompletionTracking =
        trackingPolicy.usesLocalCompletionTracking(
          traktScrobble: args.traktScrobble,
          simklScrobble: args.simklScrobble,
          mdblistScrobble: args.mdblistScrobble,
        ) &&
        args.stremioTvChannels == null &&
        args.iptvChannels == null;
    final completionThresholds = localCompletionTracking
        ? await Future.wait<int>([
            LocalCompletionStorage.getMovieCompletionThreshold(),
            LocalCompletionStorage.getEpisodeCompletionThreshold(),
          ])
        : const <int>[
            LocalCompletionStorage.defaultLocalCompletionThreshold,
            LocalCompletionStorage.defaultLocalCompletionThreshold,
          ];
    if (canContinue?.call() == false) return null;
    final perItemStates = await _fetchPerItemPlaybackState(
      playlistEntries,
      contentType: contentType,
      seriesPlaylist: seriesPlaylist,
    );
    if (canContinue?.call() == false) return null;
    final stableSeriesTitle =
        args.contentTitle ?? seriesPlaylist?.seriesTitle ?? args.title;
    final locallyFinished = contentType == PlaybackContentType.series
        ? await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
            seriesTitle: stableSeriesTitle,
            imdbId: args.contentImdbId,
          )
        : const <String, Set<int>>{};
    // Cross-device per-episode progress ("season_episode" → 0-100) for playlist
    // bars and in-session episode resume. The native payload retains its legacy
    // `traktProgressPercent` field name, but each value is the furthest of
    // Trakt, Simkl, and MDBList.
    if (canContinue?.call() == false) return null;
    final trackerProgressMaps = args.contentImdbId != null
        ? await Future.wait([
            TrackerEpisodeProgressStorage.getEpisodeTraktProgress(imdbId: args.contentImdbId!),
            TrackerEpisodeProgressStorage.getEpisodeSimklProgress(imdbId: args.contentImdbId!),
            TrackerEpisodeProgressStorage.getConnectedEpisodeMdblistProgress(
              imdbId: args.contentImdbId!,
            ),
          ])
        : const <Map<String, double>>[];
    if (canContinue?.call() == false) return null;
    final traktProgress = trackerProgressMaps.isNotEmpty
        ? trackerProgressMaps[0]
        : const <String, double>{};
    final simklProgress = trackerProgressMaps.length > 1
        ? trackerProgressMaps[1]
        : const <String, double>{};
    final mdblistProgress = trackerProgressMaps.length > 2
        ? trackerProgressMaps[2]
        : const <String, double>{};
    final startIndex = await _determineStartIndex(
      contentType,
      seriesPlaylist,
      playlistEntries,
      perItemStates,
      trackingPolicy,
    );

    if (canContinue?.call() == false) return null;
    final preparedEntries = await _prepareEntries(playlistEntries, startIndex);
    if (canContinue?.call() == false) return null;
    final seasons = _buildSeriesSeasons(seriesPlaylist);

    final launcherEntries = <LauncherEntry>[];
    final items = <AndroidTvPlaybackItem>[];

    for (int i = 0; i < preparedEntries.length; i++) {
      final entry = preparedEntries[i];
      final resumeId = _resumeIdForEntry(entry);
      launcherEntries.add(
        LauncherEntry(entry: entry, resumeId: resumeId, index: i),
      );

      final resumeInfo = i < perItemStates.length
          ? perItemStates[i]
          : const PerItemState();

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

      // Use TVMaze episode title if available, otherwise fallback to entry
      // title. Catalog singles (Quick Play / Sources tap) never get TVMaze
      // enrichment, so prefer the clean content title over the release name.
      // Stremio TV is excluded: there entry.title is the current program
      // title while contentTitle is the generic catalog name.
      final displayTitle = episodeInfo.episodeInfo?.title?.isNotEmpty == true
          ? episodeInfo.episodeInfo!.title!
          : (preparedEntries.length == 1 &&
                    args.stremioTvChannels == null &&
                    (args.contentTitle?.isNotEmpty ?? false)
                ? args.contentTitle!
                : entry.title);
      final season = episodeInfo.seriesInfo.season;
      final episode = episodeInfo.seriesInfo.episode;
      final episodeKey = season != null && episode != null
          ? '${season}_$episode'
          : null;
      final locallyWatched = episodeKey != null
          ? locallyFinished[season.toString()]?.contains(episode) ?? false
          : false;
      final resolvedLocal = resolveEpisodeLocalWatchState(
        locallyWatched:
            trackingPolicy.progressFrom(TrackingSource.local) && locallyWatched,
        localPositionMs: trackingPolicy.progressFrom(TrackingSource.local)
            ? resumeInfo.positionMs
            : 0,
        localDurationMs: resumeInfo.durationMs,
        traktPercent: episodeKey == null
            ? null
            : trackingPolicy.guideProgressFrom(
                TrackingSource.trakt,
                traktProgress[episodeKey],
              ),
        simklPercent: episodeKey == null
            ? null
            : trackingPolicy.guideProgressFrom(
                TrackingSource.simkl,
                simklProgress[episodeKey],
              ),
        mdblistPercent: episodeKey == null
            ? null
            : trackingPolicy.guideProgressFrom(
                TrackingSource.mdblist,
                mdblistProgress[episodeKey],
              ),
      );

      items.add(
        AndroidTvPlaybackItem(
          id: entry.url.isNotEmpty ? entry.url : '${entry.title}_$i',
          title: displayTitle,
          url: entry.url,
          httpHeaders: entry.httpHeaders ?? args.httpHeaders,
          hdVideoUrl: entry.hdVideoUrl,
          audioUrl: entry.audioUrl,
          index: i,
          season: season,
          episode: episode,
          artwork: episodeInfo.episodeInfo?.poster,
          description: episodeInfo.episodeInfo?.plot,
          sizeBytes: entry.sizeBytes,
          resumePositionMs: resolvedLocal.positionMs,
          durationMs: resumeInfo.durationMs,
          updatedAt: resumeInfo.updatedAt,
          resumeId: resumeId,
          provider: entry.provider,
          watched: resolvedLocal.watched,
          allowLocalProgressDisplay: trackingPolicy.progressFrom(
            TrackingSource.local,
          ),
          traktProgressPercent: episodeKey != null
              ? furthestEpisodeTrackerPercent([
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.trakt,
                    traktProgress[episodeKey],
                  ),
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.simkl,
                    simklProgress[episodeKey],
                  ),
                  trackingPolicy.guideProgressFrom(
                    TrackingSource.mdblist,
                    mdblistProgress[episodeKey],
                  ),
                ])
              : null,
        ),
      );
    }

    // Build navigation maps based on SeriesPlaylist.allEpisodes ordering
    // This mirrors mobile video_player_screen.dart's navigation exactly
    final navigationMaps = _buildNavigationMaps(seriesPlaylist, items);

    // Build collection groups for movie collections
    List<AndroidTvCollectionGroup>? collectionGroups;
    if (contentType == PlaybackContentType.collection &&
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
            (group) => AndroidTvCollectionGroup(
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
    if (effectiveImdbId == null && contentType != PlaybackContentType.series) {
      effectiveImdbId = await _fetchMovieImdbId(items, startIndex);
    }

    if (canContinue?.call() == false) return null;
    for (final entry in launcherEntries) {
      if (entry.entry.url.isNotEmpty) {
        StreamRedirectResolver.cacheResolvedStream(entry.resumeId, entry.entry.url);
      }
    }
    final payload = AndroidTvPlaybackPayload(
      contentType: contentType,
      declaredContentType: args.contentType,
      title: args.title,
      subtitle: args.subtitle,
      items: items,
      startIndex: startIndex,
      // Always carry the stable catalog title for series so local writes use
      // the same key regardless of which release wins Quick Play or a switch.
      seriesTitle: contentType == PlaybackContentType.series
          ? stableSeriesTitle
          : seriesPlaylist?.seriesTitle,
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
      hasAdjacentEpisodeResolver:
          args.seriesSourceFetcher?.resolveAdjacentEpisode != null,
      startupTryNextOnFailure: startupRules?.tryNextOnFailure ?? false,
      startupMaxAttempts: startupRules?.maxAttempts ?? 1,
      startupResolverProvider: args.startupResolverProvider,
      startupRecoveryAvailable: args.onStartupSourcesExhausted != null,
      traktScrobble: args.traktScrobble,
      traktProgressPercent: trackingPolicy.progressFrom(TrackingSource.trakt)
          ? args.traktProgressPercent
          : null,
      simklScrobble: args.simklScrobble,
      simklProgressPercent: trackingPolicy.progressFrom(TrackingSource.simkl)
          ? args.simklProgressPercent
          : null,
      mdblistScrobble: args.mdblistScrobble,
      mdblistProgressPercent:
          trackingPolicy.progressFrom(TrackingSource.mdblist)
          ? args.mdblistProgressPercent
          : null,
      localCompletionTracking: localCompletionTracking,
      movieCompletionThreshold: completionThresholds[0],
      episodeCompletionThreshold: completionThresholds[1],
      initialSubtitles: args.initialSubtitles,
    );

    debugPrint(
      '[StartupFailover] event=native_payload platform=flutter '
      'contentType=${contentType.name} sourceCount=${args.stremioSources?.length ?? 0} '
      'selectedIndex=${args.stremioCurrentSourceIndex ?? 0} '
      'tryNext=${startupRules?.tryNextOnFailure ?? false} '
      'maxAttempts=${startupRules?.maxAttempts ?? 1} '
      'playlistResolver=${args.resolveSourceToPlaylist != null}',
    );

    return AndroidTvPlaybackPayloadResult(
      payload: payload,
      entries: launcherEntries,
    );
  }

  /// Fetch movie IMDB ID from Cinemeta for Android TV playback
  /// Returns IMDB ID if found, null otherwise
  Future<String?> _fetchMovieImdbId(
    List<AndroidTvPlaybackItem> items,
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
  NavigationMaps _buildNavigationMaps(
    SeriesPlaylist? seriesPlaylist,
    List<AndroidTvPlaybackItem> items,
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
      return NavigationMaps(nextMap: nextMap, prevMap: prevMap);
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
    return NavigationMaps(nextMap: nextMap, prevMap: prevMap);
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
          canContinue: canContinue,
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
              httpHeaders: entry.httpHeaders,
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

  Future<List<PerItemState>> _fetchPerItemPlaybackState(
    List<PlaylistEntry> entries, {
    required PlaybackContentType contentType,
    required SeriesPlaylist? seriesPlaylist,
  }) async {
    final stableSeriesTitle =
        args.contentTitle ?? seriesPlaylist?.seriesTitle ?? args.title;
    final seriesProgress = contentType == PlaybackContentType.series
        ? await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
            seriesTitle: stableSeriesTitle,
            imdbId: args.contentImdbId,
          )
        : const <String, Map<String, dynamic>>{};
    final result = <PerItemState>[];
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      SeriesEpisode? parsedEpisode;
      if (seriesPlaylist != null) {
        for (final episode in seriesPlaylist.allEpisodes) {
          if (episode.originalIndex == i) {
            parsedEpisode = episode;
            break;
          }
        }
      }
      final season =
          parsedEpisode?.seriesInfo.season ??
          (entries.length == 1 ? args.contentSeason : null);
      final episode =
          parsedEpisode?.seriesInfo.episode ??
          (entries.length == 1 ? args.contentEpisode : null);
      final seriesState = season != null && episode != null
          ? seriesProgress['${season}_$episode']
          : null;
      if (seriesState != null) {
        result.add(
          PerItemState(
            positionMs: (seriesState['positionMs'] as num?)?.toInt() ?? 0,
            durationMs: (seriesState['durationMs'] as num?)?.toInt() ?? 0,
            updatedAt: (seriesState['updatedAt'] as num?)?.toInt() ?? 0,
          ),
        );
        continue;
      }
      // A lone single-content entry IS the movie, so an IMDb-keyed record
      // describes THIS content and recovers a resume the source-specific key
      // missed. Deliberately narrow:
      //  - collection (a pack) would seed every file from one id;
      //  - `contentType == 'series'` is excluded even when the classifier fell
      //    through to `single` (an episode launched without season/episode).
      //    Episode progress is ALSO mirrored into a `type: 'video'` record
      //    carrying the SERIES imdbId (see the series branch of
      //    `_handleProgressUpdate`), so scanning by id there would hand back
      //    whichever episode was watched most recently.
      if (contentType == PlaybackContentType.single &&
          args.contentType != 'series' &&
          entries.length == 1) {
        result.add(
          _stateFromRecord(
            await VideoPlayerLauncher.readMovieResumeState(
              entry: entry,
              imdbId: args.contentImdbId,
              fallbackTitle: args.title,
              policy: args.resumePolicy,
            ),
          ),
        );
        continue;
      }
      final resumeId = _resumeIdForEntry(entry);
      result.add((CustomSeriesIdentity.isCustom(args.contentImdbId) ||
              (args.contentImdbId?.startsWith('medialibrary:') ?? false))
          ? const PerItemState() : await _readVideoState(resumeId));
    }
    return result;
  }

  static PerItemState _stateFromRecord(Map<String, dynamic>? data) {
    if (data == null) {
      return const PerItemState();
    }
    return PerItemState(
      positionMs: (data['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (data['durationMs'] as num?)?.toInt() ?? 0,
      updatedAt: (data['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Future<PerItemState> _readVideoState(String resumeId) async {
    return _stateFromRecord(
      await VideoProgressStorage.getVideoPlaybackState(videoTitle: resumeId),
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

  PlaybackContentType _determineContentType(
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
  ) {
    if (seriesPlaylist != null && seriesPlaylist.isSeries) {
      return PlaybackContentType.series;
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
      return PlaybackContentType.series;
    }
    if (entries.length > 1) {
      return PlaybackContentType.collection;
    }
    return PlaybackContentType.single;
  }

  Future<int> _determineStartIndex(
    PlaybackContentType contentType,
    SeriesPlaylist? seriesPlaylist,
    List<PlaylistEntry> entries,
    List<PerItemState> perItemState,
    TrackingSourcePolicy trackingPolicy,
  ) async {
    switch (contentType) {
      case PlaybackContentType.series:
        return await _determineSeriesStartIndex(seriesPlaylist, trackingPolicy);
      case PlaybackContentType.collection:
        if (!trackingPolicy.progressFrom(TrackingSource.local)) {
          return args.startIndex ?? 0;
        }
        return _determineCollectionStartIndex(entries, perItemState);
      case PlaybackContentType.single:
        return args.startIndex ?? 0;
    }
  }

  Future<int> _determineSeriesStartIndex(
    SeriesPlaylist? playlist,
    TrackingSourcePolicy trackingPolicy,
  ) async {
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
    final lastEpisode =
        hadExplicitTarget || !trackingPolicy.progressFrom(TrackingSource.local)
        ? null
        : trackingPolicy.nativeIdentity && args.contentImdbId != null
        ? await EpisodeResumeStorage.getLastPlayedEpisodeByImdbId(args.contentImdbId!)
        : await EpisodeResumeStorage.getLastPlayedEpisode(
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
    List<PerItemState> perItemState,
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

  List<AndroidTvSeriesSeason> _buildSeriesSeasons(SeriesPlaylist? playlist) {
    if (playlist == null) {
      return const [];
    }
    final seasons = <AndroidTvSeriesSeason>[];
    for (final season in playlist.seasons) {
      final episodes = season.episodes.map((episode) {
        return AndroidTvSeriesEpisode(
          title: episode.displayTitle,
          season: episode.seriesInfo.season,
          episode: episode.seriesInfo.episode,
          description: episode.episodeInfo?.plot,
          artwork: episode.episodeInfo?.poster,
        );
      }).toList();
      seasons.add(
        AndroidTvSeriesSeason(
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
