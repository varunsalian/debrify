import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:debrify/screens/video_player/services/player_now_playing.dart';
import 'package:debrify/features/player_launch/data/launch_tracking_policy.dart';
import 'package:debrify/features/player_launch/data/movie_resume_state.dart';
import 'package:debrify/features/player_launch/data/native_playback_debug.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_disclosure.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_player_launch.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/launch_router.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/webdav_player_notice.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/services/mdblist/mdblist_service.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter/material.dart';

export 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
export 'package:debrify/features/player_launch/presentation/legacy_launch/video_player_launch_widget.dart';

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
  }) => NativePlaybackDebug.debugNativePlaybackSession(
    args,
    updates,
    mdblistService: mdblistService,
    canContinue: canContinue,
  );

  /// The external app needs its own temporary grant for this exact document.
  /// Debrify's persisted folder/file permission is not shared across apps.
  static AndroidIntent androidExternalVideoIntent(String url) =>
      ExternalPlayerLaunch.androidExternalVideoIntent(url);

  /// Select the single URL handed to an external player.
  ///
  /// External-player intents, URL schemes, and generic commands cannot
  /// reliably attach [VideoPlayerLaunchArgs.audioUrl] on every platform. When
  /// the primary stream needs that separate audio track, prefer the muxed
  /// fallback so external playback is never silent.
  @visibleForTesting
  static String externalPlaybackUrlFor(VideoPlayerLaunchArgs args) =>
      ExternalPlayerLaunch.externalPlaybackUrlFor(args);

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
  }) => MovieResumeState.readMovieResumeState(
    entry: entry,
    imdbId: imdbId,
    fallbackTitle: fallbackTitle,
    policy: policy,
  );

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
  }) => LaunchTrackingPolicy.shouldEnableMdblistTracking(
    requested: requested,
    autoEligible: autoEligible,
    featureEnabled: featureEnabled,
    identityAvailable: identityAvailable,
    syncEnabled: syncEnabled,
    authenticated: authenticated,
  );

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
  ) => ExternalDisclosure.shouldExplainExternalPlayerFallback(
    args,
    defaultPlayerMode,
  );

  @visibleForTesting
  static Future<bool> showAuthenticatedWebDavPlayerNotice(
    BuildContext context,
  ) => WebdavPlayerNotice.showAuthenticatedWebDavPlayerNotice(context);

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
  }) {
    // What the lock screen shows for the in-app player this launch opens.
    PlayerNowPlaying.prepare(
      title: originalArgs.title,
      subtitle: originalArgs.subtitle,
    );
    return LaunchRouter.push(
      context,
      originalArgs,
      onQuickPlayNextEpisode: onQuickPlayNextEpisode,
      isTrailer: isTrailer,
      onPlayerHandoff: onPlayerHandoff,
      retainSourceSession: retainSourceSession,
      sourceOwner: sourceOwner,
      canContinue: canContinue,
    );
  }

  /// Whether playback should leave the app entirely, per the user's default
  /// player setting. Screens that build their own player route ask this before
  /// spending work on in-app-only setup.
  static Future<bool> isExternalPlayerDefault() =>
      ExternalPlayerLaunch.isExternalPlayerDefault();

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
  }) => ExternalPlayerLaunch.launchExternalIfConfigured(
    context,
    videoUrl: videoUrl,
    title: title,
  );
}
