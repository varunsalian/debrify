import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'dart:async';
import 'dart:io';
import 'package:debrify/features/player_launch/data/android_tv_native_launch.dart';
import 'package:debrify/features/player_launch/data/launch_tracking_policy.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/deovr_launch.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_activity_lifecycle.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_disclosure.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_launch_commit.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_player_launch.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/launch_analytics.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/tracker_progress_seeding.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/webdav_player_notice.dart';
import 'package:debrify/services/analytics_service.dart';
import 'package:debrify/services/android_native_downloader.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/simkl/simkl_service.dart';
import 'package:debrify/services/storage/continue_watching_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/storage/watchlist_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_service.dart';
import 'package:flutter/material.dart';

final class LaunchRouter {
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
      if (callback != null) ExternalActivityLifecycle.runWhenCoveredByExternalActivity(callback);
    }

    try {
      Future<void> launch() => LaunchRouter._push(
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
    Future<void> write(Future<void> Function() action) => preparation?.write(action) ?? action();
    if (!active()) return;
    var args = originalArgs;
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      args.contentImdbId,
    );
    if (!active()) return;
    final defaultPlayerMode = await ExternalPlayerStorage.getDefaultPlayerMode();
    if (!context.mounted || !active()) return;
    if (ExternalDisclosure.shouldExplainExternalPlayerFallback(args, defaultPlayerMode)) {
      final useDebrifyPlayer = await WebdavPlayerNotice.showAuthenticatedWebDavPlayerNotice(
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
        if (!trackingPolicy.forcesLocalCompletion && !trackingPolicy.nativeIdentity) {
          await write(
            () => ContinueWatchingStorage.removeContinueWatchingItem(args.contentImdbId!),
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
            () => ContinueWatchingStorage.removeContinueWatchingItem(args.contentImdbId!),
          );
          if (!active()) return;
        }
      }
    }

    final mdblistRequested = args.mdblistScrobble;
    final mdblistIdentityAvailable = args.contentImdbId?.trim().isNotEmpty == true;
    final mdblistAutoEligible =
        !mdblistRequested &&
        !args.suppressTrackerAutoSync &&
        mdblistIdentityAvailable &&
        args.stremioTvChannels == null;
    var mdblistSyncEnabled = false;
    var mdblistAuthenticated = false;
    if (kMdblistEnabled && mdblistIdentityAvailable && (mdblistRequested || mdblistAutoEligible)) {
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
      if (!trackingPolicy.forcesLocalCompletion && !trackingPolicy.nativeIdentity) {
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
        TrackerProgressSeeding.refreshTraktEpisodeProgress(args.contentImdbId!),
        TrackerProgressSeeding.seedSimklEpisodeProgress(args.contentImdbId!),
      ]);
      unawaited(TrackerProgressSeeding.seedMdblistEpisodeProgress(args.contentImdbId!));
    } else if (args.contentType == 'series' && args.contentImdbId != null) {
      await TrackerProgressSeeding.seedSimklEpisodeProgress(args.contentImdbId!);
      unawaited(TrackerProgressSeeding.seedMdblistEpisodeProgress(args.contentImdbId!));
    }

    if (!context.mounted || !active()) return;
    AnalyticsService.trackInBackground('playback_started', <String, Object?>{
      'content_type': args.contentType ?? 'unknown',
      'provider': LaunchAnalytics.analyticsProviderLabel(args),
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
    // actually ended. See [ExternalActivityLifecycle.notifyOnReturnFromExternalActivity].
    if (!args.disableExternalPlayer && defaultPlayerMode == 'external') {
      int? chosenSeason;
      int? chosenEpisode;
      final launched = await ExternalPlayerLaunch.launchWithExternalPlayer(
        context,
        args,
        preparation: preparation,
        onSeriesEntryChosen: (s, e) {
          chosenSeason = s;
          chosenEpisode = e;
        },
      );
      if (launched) {
        if (active()) await ExternalLaunchCommit.commitExternalLaunchSource(args);
        if (active()) {
          unawaited(
            ExternalLaunchCommit.seedTrackerContinueWatching(
              args,
              seasonOverride: chosenSeason,
              episodeOverride: chosenEpisode,
            ),
          );
        }
        handoffWhenCovered();
        if (!isTrailer) ExternalActivityLifecycle.notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If external player failed, fall through to in-app player
    } else if (!args.disableExternalPlayer && defaultPlayerMode == 'deovr' && Platform.isAndroid) {
      final launched = await DeovrLaunch.launchWithDeoVR(
        context,
        args,
        preparation: preparation,
      );
      if (launched) {
        if (active()) await ExternalLaunchCommit.commitExternalLaunchSource(args);
        if (active()) unawaited(ExternalLaunchCommit.seedTrackerContinueWatching(args));
        handoffWhenCovered();
        if (!isTrailer) ExternalActivityLifecycle.notifyOnReturnFromExternalActivity();
        MainPageBridge.notifyExternalPlayerLaunched();
        return;
      }
      // If DeoVR failed, fall through to in-app player
    }

    final isTv = await LaunchRouter.isAndroidTv(args.isAndroidTvOverride);
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
        if (!isTrailer) ExternalActivityLifecycle.notifyOnReturnFromExternalActivity();
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

    if (result?['startupSourcesExhausted'] == true && args.onStartupSourcesExhausted != null) {
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
    if (result != null && result['quickPlayNext'] == true && onQuickPlayNextEpisode != null) {
      await onQuickPlayNextEpisode(result);
    }
  }

  static Future<bool> isAndroidTv(bool Function()? override) async {
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
}
