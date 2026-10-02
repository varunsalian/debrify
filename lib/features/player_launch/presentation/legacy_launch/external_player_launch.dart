import 'package:debrify/models/playlist_view_mode.dart';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:collection/collection.dart';
import 'package:debrify/features/player_launch/data/entry_url_resolver.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/deovr_launch.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_activity_lifecycle.dart';
import 'package:debrify/features/player_launch/presentation/legacy_launch/external_disclosure.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/external_player_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/profiles/profile_policy_guard.dart';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/episode_progress_storage.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/external_player_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';

final class ExternalPlayerLaunch {
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

  static String externalPlaybackUrlFor(VideoPlayerLaunchArgs args) {
    final hasSeparateAudio = args.audioUrl?.isNotEmpty ?? false;
    final muxedFallback = args.fallbackUrl;
    if (hasSeparateAudio && muxedFallback != null && muxedFallback.isNotEmpty) {
      return muxedFallback;
    }
    return args.videoUrl;
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
        ? await DeovrLaunch.launchWithDeoVR(context, args)
        : await ExternalPlayerLaunch.launchWithExternalPlayer(context, args);

    if (!launched) {
      MainPageBridge.notifyContentPlaybackStopped();
      return false;
    }

    // Control returns to Flutter without a route ever being pushed, so
    // RouteAware can't tell screens when playback ended — same signal the
    // launcher's own external path arms. See [push].
    ExternalActivityLifecycle.notifyOnReturnFromExternalActivity();
    MainPageBridge.notifyExternalPlayerLaunched();
    return true;
  }

  // dart format off
  /// Launch video with external player based on platform
  /// Returns true if successfully launched, false if should fall back to in-app player
  static Future<bool> launchWithExternalPlayer(
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
    String url = ExternalPlayerLaunch.externalPlaybackUrlFor(args);
    String title = args.title;

    final playlist = args.playlist;
    if (playlist != null && playlist.length > 1) {
      try {
        // Build SeriesPlaylist to check if it's a series
        final seriesPlaylist = SeriesPlaylist.fromPlaylistEntries(
          playlist,
          collectionTitle: args.title,
          forceSeries: args.viewMode?.toForceSeries() ?? (args.contentType == 'series'),
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
            final originalIndex = seriesPlaylist.findOriginalIndexBySeasonEpisode(
              lastSeason,
              lastEpisodeNum
            );
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
                  final nextEpisode = seriesPlaylist.allEpisodes[currentEpisodeIdx + 1];
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
                Future<void> markFinished() => EpisodeCompletionStorage.markEpisodeAsFinished(
                  seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
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
    if (ExternalDisclosure.mayDiscloseCredential(url) &&
        !await ExternalDisclosure.confirmExternalDisclosure(context)) {
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
        final intent = ExternalPlayerLaunch.androidExternalVideoIntent(url);
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
      final result = await LinuxExternalPlayerServiceExtension.launchWithPreferredLinuxPlayer(
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
      final result = await WindowsExternalPlayerServiceExtension.launchWithPreferredWindowsPlayer(
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
  // dart format on
}
