import 'package:debrify/features/player_launch/data/android_tv_native_launch.dart';
import 'package:debrify/features/player_launch/data/entry_url_resolver.dart';
import 'package:debrify/features/player_launch/data/launch_tracking_policy.dart';
import 'package:debrify/features/player_launch/data/movie_resume_state.dart';
import 'package:debrify/features/player_launch/data/native_playback_debug.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';
export 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
export 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'profiles/profile_playback_preparation.dart';
import 'profiles/profile_session_memory.dart';
import 'dart:async';
import '../utils/platform_util.dart';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../screens/video_player/player_pip_route.dart';
import '../services/external_player_service.dart';
import '../utils/deovr_utils.dart' as deovr;
import '../models/playlist_view_mode.dart';
import '../models/series_playlist.dart';
import '../screens/video_player_screen.dart';
import '../services/android_native_downloader.dart';
import '../services/android_tv_player_bridge.dart';
import '../services/main_page_bridge.dart';
import '../services/analytics_service.dart';
import '../services/episode_tracker_snapshot_service.dart';
import '../services/local_playback_resume_resolver.dart';
import '../services/trakt/trakt_service.dart';
import '../services/simkl/simkl_service.dart';
import '../services/mdblist/mdblist_models.dart';
import '../services/mdblist/mdblist_service.dart';
import '../models/profiles/profile_policy.dart';
import 'profiles/profile_policy_guard.dart';
import 'tracking_source_policy.dart';
























class VideoPlayerLauncher {
  @visibleForTesting
  static Future<List<int>> debugNativeResumePositions(
    VideoPlayerLaunchArgs args,
    List<PlaylistEntry> entries,
  ) => NativePlaybackDebug.debugNativeResumePositions(args, entries);

  @visibleForTesting
  static Future<Map<String, dynamic>> debugNativePlaybackSession(
    VideoPlayerLaunchArgs args,
    List<Map<String, dynamic>> updates, {
    MdblistService? mdblistService,
    bool Function()? canContinue,
  }) => NativePlaybackDebug.debugNativePlaybackSession(args, updates, mdblistService: mdblistService, canContinue: canContinue);

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
  }) => MovieResumeState.resumeIdForEntry(entry, fallbackTitle: fallbackTitle);

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
  }) => MovieResumeState.readMovieResumeState(entry: entry, imdbId: imdbId, fallbackTitle: fallbackTitle, policy: policy);

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
  }) => LaunchTrackingPolicy.shouldEnableMdblistTracking(requested: requested, autoEligible: autoEligible, featureEnabled: featureEnabled, identityAvailable: identityAvailable, syncEnabled: syncEnabled, authenticated: authenticated);

  @visibleForTesting
  static VideoPlayerLaunchArgs normalizeScrobbleFlags(
    VideoPlayerLaunchArgs args,
    TrackingSourcePolicy policy,
  ) => LaunchTrackingPolicy.normalizeScrobbleFlags(args, policy);

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
    final effectiveMdblistTracking = LaunchTrackingPolicy.shouldEnableMdblistTracking(
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
    args = LaunchTrackingPolicy.normalizeScrobbleFlags(args, trackingPolicy);

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
      final launched = await AndroidTvNativeLaunch.launchOnAndroidTv(
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
          final resolvedUrl = await EntryUrlResolver.resolveEntryUrl(
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
