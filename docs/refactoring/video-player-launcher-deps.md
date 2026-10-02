# VideoPlayerLauncher dependency and ownership report

Original: `204b1011:lib/services/video_player_launcher.dart` (6,594 physical lines). The current application source is identical to that revision. Dart AST inventory: **154 ownership leaves**; split classes are `VideoPlayerLauncher` and `VideoPlayerLaunchArgs`. Whole classes retain all their members. The table below also lists every nested member for dependency review.

Every manifest row has one destination and step. Members crossing files become public by dropping the leading underscore, or use their single static owner. The only additional member rename is `_AndroidTvPlaybackPayloadBuilder._fetchPerItemPlaybackState` → `fetchPerItemPlaybackState`, used by the debug resume harness. `_stateFromRecord` stays inside the whole builder: extracting it would violate the explicit prohibition on splitting the builder.

## Layer decisions

`presentation/legacy_launch/` owns context, dialogs, widgets, lifecycle observers, route pushes and their legacy action orchestration. Its exit milestone is to move service calls behind data contracts and dissolve the bridge folder. `data/` owns storage, tracker sessions, redirects, native bridges and payload behavior; it uses foundation for diagnostics/annotations and direct model imports for playlist entries and resume policy, never the screen re-export. `models/` holds argument/value types. No application/Riverpod state or DI is introduced.

`VideoPlayerLaunchArgs` retains its borrowed callbacks and `SeriesSourceFetcher` handle; it never owns or mutates the handle. The fetcher remains a legacy service dependency until its session state gets a contract in a later migration. The payload and payload-result types are in `data/` because `imdbId`, MDBList session/factory/season/episode and completion guards are mutable session identity. Immutable item/season/group/episode declarations move whole into models.

## Declaration destinations and referenced import contracts

Imports below identify the original contracts used by each declaration. Imports/qualifiers are the permitted wiring changes; model contracts replace screen re-exports. Comments and bodies remain verbatim. A member with no external identifier needs only Dart core and its owning declaration/feature references.

| Original declaration | Destination (under `lib/features/player_launch/`) | Owner | Step / layer | Referenced import contracts |
| --- | --- | --- | --- | --- |
| `_traktLastScrobbleAction` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_traktLastKnownProgress` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_traktLastKnownSeason` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_traktLastKnownEpisode` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_traktHeartbeatTimer` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | `dart:async` |
| `_simklLastScrobbleAction` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_simklLastKnownProgress` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_simklLastKnownSeason` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_simklLastKnownEpisode` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | Dart core / owning type / feature owners |
| `_simklHeartbeatTimer` | `data/native_scrobble_session.dart` | `NativeScrobbleSession` | 1 / data | `dart:async` |
| `_resolvedStreamCache` | `data/stream_redirect_resolver.dart` | `StreamRedirectResolver` | 1 / data | Dart core / owning type / feature owners |
| `_redirectCache` | `data/stream_redirect_resolver.dart` | `StreamRedirectResolver` | 1 / data | Dart core / owning type / feature owners |
| `_cacheResolvedStream` | `data/stream_redirect_resolver.dart` | `StreamRedirectResolver` | 1 / data | Dart core / owning type / feature owners |
| `_resolveRedirectUrl` | `data/stream_redirect_resolver.dart` | `StreamRedirectResolver` | 1 / data | `package:flutter/foundation.dart`; `package:http/http.dart` |
| `_clearResolvedStreams` | `data/stream_redirect_resolver.dart` | `StreamRedirectResolver` | 1 / data | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.videoUrl` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.audioUrl` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.fallbackUrl` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.title` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.subtitle` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.playlist` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/playlist_entry.dart` |
| `VideoPlayerLaunchArgs.startIndex` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.rdTorrentId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.torboxTorrentId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.pikpakCollectionId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.webDavServerId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.webDavBaseUrl` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.webDavPath` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.requestMagicNext` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.requestNextChannel` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.initialContinuousShuffle` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.startFromRandom` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.randomStartMaxPercent` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.startAtPercent` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.hideSeekbar` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.showChannelName` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.channelName` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.channelNumber` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.showVideoTitle` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.hideOptions` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.hideBackButton` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.httpHeaders` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.disableExternalPlayer` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.isAndroidTvOverride` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.disableAutoResume` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.viewMode` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/playlist_view_mode.dart` |
| `VideoPlayerLaunchArgs.contentImdbId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.contentType` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.contentSeason` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.contentEpisode` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.resumePolicy` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/playback_resume_policy.dart` |
| `VideoPlayerLaunchArgs.iptvChannels` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/iptv_playlist.dart` |
| `VideoPlayerLaunchArgs.iptvStartIndex` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvCategories` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvSourceId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvSourceName` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvSelectedCategory` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvContentType` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvSources` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvLists` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.iptvBrowseProvider` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioSources` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/torrent.dart` |
| `VideoPlayerLaunchArgs.stremioCurrentSourceIndex` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.resolveStremioSource` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/torrent.dart` |
| `VideoPlayerLaunchArgs.resolveSourceToPlaylist` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/source_playlist_resolver.dart` |
| `VideoPlayerLaunchArgs.startupFailoverEnabled` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.startupResolverProvider` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.onStremioSourceCommitted` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/torrent.dart` |
| `VideoPlayerLaunchArgs.onStartupSourcesExhausted` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.startupHasRemainingSavedSources` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.seriesSourceFetcher` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/services/series_source_fetcher.dart` |
| `VideoPlayerLaunchArgs.stremioTvChannels` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvCurrentChannelId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvRotationMinutes` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvSeriesRotationMinutes` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvMixSalt` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvGuideDataProvider` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvChannelSwitchProvider` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.stremioTvNextProvider` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.traktScrobble` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.suppressTrackerAutoSync` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.suppressTraktAutoSync` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.traktProgressPercent` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.simklScrobble` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.simklProgressPercent` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.mdblistScrobble` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.mdblistProgressPercent` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.contentTitle` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.posterUrl` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.contentYear` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.addonId` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.initialSubtitles` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/stremio_subtitle.dart` |
| `VideoPlayerLaunchArgs.VideoPlayerLaunchArgs` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | `package:debrify/models/playback_resume_policy.dart` |
| `VideoPlayerLaunchArgs.copyWith` | `models/video_player_launch_args.dart` | `VideoPlayerLaunchArgs` | 1 / models | Dart core / owning type / feature owners |
| `VideoPlayerLaunchArgs.toWidget` | `presentation/legacy_launch/video_player_launch_widget.dart` | `VideoPlayerLaunchArgsWidget` | 1 / presentation | `package:debrify/screens/video_player_screen.dart` |
| `VideoPlayerLauncher.debugNativeResumePositions` | `data/native_playback_debug.dart` | `NativePlaybackDebug` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.debugNativePlaybackSession` | `data/native_playback_debug.dart` | `NativePlaybackDebug` | 2 / data | `package:debrify/services/mdblist/mdblist_service.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.androidExternalVideoIntent` | `presentation/legacy_launch/external_player_launch.dart` | `ExternalPlayerLaunch` | 4 / presentation | `package:android_intent_plus/android_intent.dart`; `package:android_intent_plus/flag.dart` |
| `VideoPlayerLauncher.externalPlaybackUrlFor` | `presentation/legacy_launch/external_player_launch.dart` | `ExternalPlayerLaunch` | 4 / presentation | `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.resumeIdForEntry` | `data/movie_resume_state.dart` | `MovieResumeState` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `VideoPlayerLauncher.readMovieResumeState` | `data/movie_resume_state.dart` | `MovieResumeState` | 2 / data | `package:debrify/models/playback_resume_policy.dart`; `package:debrify/models/playlist_entry.dart`; `package:debrify/services/local_playback_resume_resolver.dart` |
| `VideoPlayerLauncher._refreshTraktEpisodeProgress` | `presentation/legacy_launch/tracker_progress_seeding.dart` | `TrackerProgressSeeding` | 4 / presentation | `package:debrify/services/episode_tracker_snapshot_service.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._seedSimklEpisodeProgress` | `presentation/legacy_launch/tracker_progress_seeding.dart` | `TrackerProgressSeeding` | 4 / presentation | `package:debrify/services/episode_tracker_snapshot_service.dart` |
| `VideoPlayerLauncher._seedMdblistEpisodeProgress` | `presentation/legacy_launch/tracker_progress_seeding.dart` | `TrackerProgressSeeding` | 4 / presentation | `package:debrify/services/episode_tracker_snapshot_service.dart`; `package:debrify/services/mdblist/mdblist_service.dart` |
| `VideoPlayerLauncher.shouldEnableMdblistTracking` | `data/launch_tracking_policy.dart` | `LaunchTrackingPolicy` | 2 / data | `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.normalizeScrobbleFlags` | `data/launch_tracking_policy.dart` | `LaunchTrackingPolicy` | 2 / data | `package:debrify/services/tracking_source_policy.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.shouldExplainExternalPlayerFallback` | `presentation/legacy_launch/external_disclosure.dart` | `ExternalDisclosure` | 4 / presentation | `dart:io` |
| `VideoPlayerLauncher.showAuthenticatedWebDavPlayerNotice` | `presentation/legacy_launch/webdav_player_notice.dart` | `WebdavPlayerNotice` | 4 / presentation | `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher.push` | `presentation/legacy_launch/launch_router.dart` | `LaunchRouter` | 4 / presentation | `package:debrify/services/android_tv_player_bridge.dart`; `package:debrify/services/main_page_bridge.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/profiles/profile_session_memory.dart`; `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._push` | `presentation/legacy_launch/launch_router.dart` | `LaunchRouter` | 4 / presentation | `dart:async`; `dart:io`; `package:debrify/services/analytics_service.dart`; `package:debrify/services/main_page_bridge.dart`; `package:debrify/services/mdblist/mdblist_service.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/simkl/simkl_service.dart`; `package:debrify/services/storage/continue_watching_storage.dart`; `package:debrify/services/storage/external_player_storage.dart`; `package:debrify/services/storage/watchlist_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/services/trakt/trakt_service.dart`; `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._commitExternalLaunchSource` | `presentation/legacy_launch/external_launch_commit.dart` | `ExternalLaunchCommit` | 4 / presentation | `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._seedTrackerContinueWatching` | `presentation/legacy_launch/external_launch_commit.dart` | `ExternalLaunchCommit` | 4 / presentation | `package:debrify/services/mdblist/mdblist_models.dart`; `package:debrify/services/mdblist/mdblist_service.dart`; `package:debrify/services/simkl/simkl_service.dart`; `package:debrify/services/trakt/trakt_service.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher.isExternalPlayerDefault` | `presentation/legacy_launch/external_player_launch.dart` | `ExternalPlayerLaunch` | 4 / presentation | `dart:io`; `package:debrify/services/storage/external_player_storage.dart` |
| `VideoPlayerLauncher.launchExternalIfConfigured` | `presentation/legacy_launch/external_player_launch.dart` | `ExternalPlayerLaunch` | 4 / presentation | `dart:io`; `package:debrify/services/main_page_bridge.dart`; `package:debrify/services/storage/external_player_storage.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._launchWithExternalPlayer` | `presentation/legacy_launch/external_player_launch.dart` | `ExternalPlayerLaunch` | 4 / presentation | `dart:io`; `package:collection/collection.dart`; `package:debrify/models/profiles/profile_policy.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/external_player_service.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/profiles/profile_policy_guard.dart`; `package:debrify/services/storage/episode_completion_storage.dart`; `package:debrify/services/storage/episode_progress_storage.dart`; `package:debrify/services/storage/episode_resume_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/utils/platform_util.dart`; `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._launchWithDeoVR` | `presentation/legacy_launch/deovr_launch.dart` | `DeovrLaunch` | 4 / presentation | `dart:convert`; `package:android_intent_plus/android_intent.dart`; `package:debrify/models/profiles/profile_policy.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/profiles/profile_policy_guard.dart`; `package:debrify/services/storage/quick_play_storage.dart`; `package:debrify/utils/deovr_utils.dart`; `package:flutter/foundation.dart`; `package:flutter/material.dart`; `package:http/http.dart` |
| `VideoPlayerLauncher._mayDiscloseCredential` | `presentation/legacy_launch/external_disclosure.dart` | `ExternalDisclosure` | 4 / presentation | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._confirmExternalDisclosure` | `presentation/legacy_launch/external_disclosure.dart` | `ExternalDisclosure` | 4 / presentation | `package:flutter/material.dart` |
| `VideoPlayerLauncher._showDeoVRFormatDialog` | `presentation/legacy_launch/deovr_launch.dart` | `DeovrLaunch` | 4 / presentation | `dart:math`; `package:debrify/utils/deovr_utils.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._isAndroidTv` | `presentation/legacy_launch/launch_router.dart` | `LaunchRouter` | 4 / presentation | `package:debrify/services/android_native_downloader.dart` |
| `VideoPlayerLauncher._runWhenCoveredByExternalActivity` | `presentation/legacy_launch/external_activity_lifecycle.dart` | `ExternalActivityLifecycle` | 4 / presentation | `dart:async`; `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._externalReturnArmTimeout` | `presentation/legacy_launch/external_activity_lifecycle.dart` | `ExternalActivityLifecycle` | 4 / presentation | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._armedReturnObserver` | `presentation/legacy_launch/external_activity_lifecycle.dart` | `ExternalActivityLifecycle` | 4 / presentation | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._notifyOnReturnFromExternalActivity` | `presentation/legacy_launch/external_activity_lifecycle.dart` | `ExternalActivityLifecycle` | 4 / presentation | `dart:async`; `package:debrify/services/main_page_bridge.dart`; `package:flutter/material.dart` |
| `VideoPlayerLauncher._analyticsProviderLabel` | `presentation/legacy_launch/launch_analytics.dart` | `LaunchAnalytics` | 4 / presentation | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._analyticsPlaylistProviderLabel` | `presentation/legacy_launch/launch_analytics.dart` | `LaunchAnalytics` | 4 / presentation | `package:debrify/models/playlist_entry.dart` |
| `VideoPlayerLauncher._analyticsUrlProviderLabel` | `presentation/legacy_launch/launch_analytics.dart` | `LaunchAnalytics` | 4 / presentation | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._launchOnAndroidTv` | `data/android_tv_native_launch.dart` | `AndroidTvNativeLaunch` | 3 / data | `dart:async`; `dart:math`; `package:debrify/models/playlist_entry.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/models/torrent.dart`; `package:debrify/services/android_tv_player_bridge.dart`; `package:debrify/services/direct_source_authorization.dart`; `package:debrify/services/failed_saved_source.dart`; `package:debrify/services/main_page_bridge.dart`; `package:debrify/services/media_server_watch_sync.dart`; `package:debrify/services/movie_metadata_service.dart`; `package:debrify/services/next_episode_service.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/series_source_fetcher.dart`; `package:debrify/services/source_selection_diagnostics.dart`; `package:debrify/services/startup_recovery_sources.dart`; `package:debrify/services/storage/merged_episode_progress_storage.dart`; `package:debrify/services/storage/quick_play_storage.dart`; `package:debrify/services/storage/torrent_search_storage.dart`; `package:debrify/services/storage/tracker_episode_progress_storage.dart`; `package:debrify/services/torrent_playback_service.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/utils/episode_progress_merge.dart`; `package:debrify/utils/movie_parser.dart`; `package:debrify/utils/series_parser.dart`; `package:debrify/utils/show_shuffle.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._launchIptvOnAndroidTv` | `data/iptv_android_tv_launch.dart` | `IptvAndroidTvLaunch` | 3 / data | `package:debrify/services/android_tv_player_bridge.dart`; `package:debrify/services/main_page_bridge.dart`; `package:debrify/services/storage/iptv_audio_storage.dart`; `package:debrify/services/storage/iptv_favorites_storage.dart`; `package:debrify/services/storage/iptv_history_storage.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._handleIptvProgressUpdate` | `data/iptv_android_tv_launch.dart` | `IptvAndroidTvLaunch` | 3 / data | `package:debrify/services/storage/video_resume_storage.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._fetchAndPushMetadataAsync` | `data/native_metadata_push.dart` | `NativeMetadataPush` | 2 / data | `package:collection/collection.dart`; `package:debrify/models/playlist_view_mode.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/android_tv_player_bridge.dart`; `package:debrify/services/episode_tracker_snapshot_service.dart`; `package:debrify/services/storage/merged_episode_progress_storage.dart`; `package:debrify/services/storage/playlist_metadata_storage.dart`; `package:debrify/services/storage/tracker_episode_progress_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/utils/episode_progress_merge.dart`; `package:debrify/utils/show_shuffle.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._saveSeriesPosterToPlaylist` | `data/series_poster_persistence.dart` | `SeriesPosterPersistence` | 2 / data | `package:debrify/models/series_playlist.dart`; `package:debrify/services/storage/playlist_artwork_storage.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._simklSeriesSEUnresolved` | `data/native_mdblist_session.dart` | `NativeMdblistSession` | 2 / data | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._nativeMdblistTarget` | `data/native_mdblist_session.dart` | `NativeMdblistSession` | 2 / data | `package:debrify/services/mdblist/mdblist_models.dart` |
| `VideoPlayerLauncher._initializeNativeMdblist` | `data/native_mdblist_session.dart` | `NativeMdblistSession` | 2 / data | `package:debrify/services/mdblist/mdblist_scrobble_session.dart`; `package:debrify/services/mdblist/mdblist_service.dart` |
| `VideoPlayerLauncher._ensureNativeMdblistSession` | `data/native_mdblist_session.dart` | `NativeMdblistSession` | 2 / data | `package:debrify/services/mdblist/mdblist_models.dart`; `package:debrify/services/mdblist/mdblist_scrobble_session.dart` |
| `VideoPlayerLauncher._closeNativeMdblist` | `data/native_mdblist_session.dart` | `NativeMdblistSession` | 2 / data | Dart core / owning type / feature owners |
| `VideoPlayerLauncher._handleProgressUpdate` | `data/native_progress_handler.dart` | `NativeProgressHandler` | 2 / data | `dart:async`; `package:debrify/services/simkl/simkl_service.dart`; `package:debrify/services/storage/episode_completion_storage.dart`; `package:debrify/services/storage/movie_progress_storage.dart`; `package:debrify/services/storage/series_progress_storage.dart`; `package:debrify/services/storage/video_progress_storage.dart`; `package:debrify/services/storage/video_resume_storage.dart`; `package:debrify/services/trakt/trakt_service.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._handlePlaybackFinished` | `data/native_progress_handler.dart` | `NativeProgressHandler` | 2 / data | `package:debrify/services/simkl/simkl_service.dart`; `package:debrify/services/trakt/trakt_service.dart`; `package:flutter/foundation.dart` |
| `VideoPlayerLauncher._resolveEntryUrl` | `data/entry_url_resolver.dart` | `EntryUrlResolver` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:debrify/services/alldebrid_service.dart`; `package:debrify/services/debrid_service.dart`; `package:debrify/services/pikpak_api_service.dart`; `package:debrify/services/premiumize_service.dart`; `package:debrify/services/profiles/profile_playback_preparation.dart`; `package:debrify/services/storage/alldebrid_storage.dart`; `package:debrify/services/storage/premiumize_storage.dart`; `package:debrify/services/storage/real_debrid_storage.dart`; `package:debrify/services/storage/torbox_storage.dart`; `package:debrify/services/torbox_service.dart` |
| `_PlaybackContentType` | `models/playback_content_type.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | `package:debrify/models/stremio_subtitle.dart`; `package:debrify/services/mdblist/mdblist_models.dart`; `package:debrify/services/mdblist/mdblist_scrobble_session.dart`; `package:debrify/services/storage/local_completion_storage.dart` |
| `_AndroidTvPlaybackPayload.contentType` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.declaredContentType` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.trackingContentType` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.title` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.subtitle` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.items` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startIndex` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.seriesTitle` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.seasons` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.nextEpisodeMap` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.prevEpisodeMap` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.collectionGroups` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.imdbId` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.httpHeaders` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startAtPercent` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.stremioSources` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.stremioCurrentSourceIndex` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.hasPlaylistResolver` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.hasAdjacentEpisodeResolver` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startupTryNextOnFailure` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startupMaxAttempts` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startupResolverProvider` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.startupRecoveryAvailable` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.traktScrobble` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.traktProgressPercent` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.simklScrobble` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.simklProgressPercent` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.mdblistScrobble` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.mdblistProgressPercent` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.mdblistSession` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | `package:debrify/services/mdblist/mdblist_scrobble_session.dart` |
| `_AndroidTvPlaybackPayload.mdblistSessionFactory` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | `package:debrify/services/mdblist/mdblist_models.dart`; `package:debrify/services/mdblist/mdblist_scrobble_session.dart` |
| `_AndroidTvPlaybackPayload.mdblistSeason` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.mdblistEpisode` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.localCompletionTracking` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.movieCompletionThreshold` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.episodeCompletionThreshold` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.localMovieCompletionRecorded` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.localMovieRewatchStarted` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.initialSubtitles` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | `package:debrify/models/stremio_subtitle.dart` |
| `_AndroidTvPlaybackPayload._AndroidTvPlaybackPayload` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | `package:debrify/services/storage/local_completion_storage.dart` |
| `_AndroidTvPlaybackPayload._effectiveLaunchPercent` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayload.toMap` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.id` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.title` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.url` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.httpHeaders` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.hdVideoUrl` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.audioUrl` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.index` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.season` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.episode` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.artwork` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.description` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.sizeBytes` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.resumePositionMs` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.durationMs` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.updatedAt` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.resumeId` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.provider` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.traktProgressPercent` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.watched` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.allowLocalProgressDisplay` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem._AndroidTvPlaybackItem` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackItem.toMap` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesSeason` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesSeason.seasonNumber` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesSeason.episodes` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesSeason._AndroidTvSeriesSeason` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesSeason.toMap` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvCollectionGroup` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvCollectionGroup.name` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvCollectionGroup.fileIndices` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvCollectionGroup._AndroidTvCollectionGroup` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvCollectionGroup.toMap` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.title` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.season` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.episode` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.description` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.artwork` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode._AndroidTvSeriesEpisode` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvSeriesEpisode.toMap` | `models/android_tv_playback_item.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadResult` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadResult.payload` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadResult.entries` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadResult._AndroidTvPlaybackPayloadResult` | `data/android_tv_playback_payload.dart` | `top level` | 1 / data | Dart core / owning type / feature owners |
| `_LauncherEntry` | `models/launcher_entry.dart` | `top level` | 1 / models | `package:debrify/models/playlist_entry.dart` |
| `_LauncherEntry.entry` | `models/launcher_entry.dart` | `top level` | 1 / models | `package:debrify/models/playlist_entry.dart` |
| `_LauncherEntry.resumeId` | `models/launcher_entry.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_LauncherEntry.index` | `models/launcher_entry.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_LauncherEntry._LauncherEntry` | `models/launcher_entry.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | `dart:math`; `package:collection/collection.dart`; `package:debrify/models/playlist_entry.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaylistResolver.entries` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver.resolveEntry` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `_AndroidTvPlaylistResolver._switchSeq` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver._disposed` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver.beginSwitch` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver.isLatestSwitch` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver._AndroidTvPlaylistResolver` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaylistResolver.replaceEntries` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaylistResolver.handleRequest` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | `dart:math`; `package:collection/collection.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaylistResolver.dispose` | `data/android_tv_playlist_resolver.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadBuilder` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:collection/collection.dart`; `package:debrify/models/custom_series_identity.dart`; `package:debrify/models/movie_collection.dart`; `package:debrify/models/playlist_entry.dart`; `package:debrify/models/playlist_view_mode.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/movie_metadata_service.dart`; `package:debrify/services/storage/episode_resume_storage.dart`; `package:debrify/services/storage/local_completion_storage.dart`; `package:debrify/services/storage/merged_episode_progress_storage.dart`; `package:debrify/services/storage/quick_play_storage.dart`; `package:debrify/services/storage/tracker_episode_progress_storage.dart`; `package:debrify/services/storage/video_progress_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/utils/episode_progress_merge.dart`; `package:debrify/utils/movie_parser.dart`; `package:debrify/utils/series_parser.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder.args` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadBuilder.canContinue` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadBuilder._AndroidTvPlaybackPayloadBuilder` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadBuilder.build` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:collection/collection.dart`; `package:debrify/models/movie_collection.dart`; `package:debrify/models/playlist_view_mode.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/storage/local_completion_storage.dart`; `package:debrify/services/storage/merged_episode_progress_storage.dart`; `package:debrify/services/storage/quick_play_storage.dart`; `package:debrify/services/storage/tracker_episode_progress_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:debrify/utils/episode_progress_merge.dart`; `package:debrify/utils/series_parser.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder._fetchMovieImdbId` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/services/movie_metadata_service.dart`; `package:debrify/utils/movie_parser.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder._buildNavigationMaps` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/series_playlist.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder._normalizePlaylist` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `_AndroidTvPlaybackPayloadBuilder._prepareEntries` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `_AndroidTvPlaybackPayloadBuilder._fetchPerItemPlaybackState` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/custom_series_identity.dart`; `package:debrify/models/playlist_entry.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/storage/merged_episode_progress_storage.dart` |
| `_AndroidTvPlaybackPayloadBuilder._stateFromRecord` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | Dart core / owning type / feature owners |
| `_AndroidTvPlaybackPayloadBuilder._readVideoState` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/services/storage/video_progress_storage.dart` |
| `_AndroidTvPlaybackPayloadBuilder._buildSeriesPlaylist` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:debrify/models/series_playlist.dart` |
| `_AndroidTvPlaybackPayloadBuilder._determineContentType` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:debrify/models/series_playlist.dart` |
| `_AndroidTvPlaybackPayloadBuilder._determineStartIndex` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:debrify/models/series_playlist.dart`; `package:debrify/services/tracking_source_policy.dart` |
| `_AndroidTvPlaybackPayloadBuilder._determineSeriesStartIndex` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/series_playlist.dart`; `package:debrify/services/storage/episode_resume_storage.dart`; `package:debrify/services/tracking_source_policy.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder._determineCollectionStartIndex` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart`; `package:debrify/models/playlist_view_mode.dart`; `package:flutter/foundation.dart` |
| `_AndroidTvPlaybackPayloadBuilder._buildSeriesSeasons` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/series_playlist.dart` |
| `_AndroidTvPlaybackPayloadBuilder._getMainGroupIndices` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `_AndroidTvPlaybackPayloadBuilder._resumeIdForEntry` | `data/android_tv_payload_builder.dart` | `top level` | 2 / data | `package:debrify/models/playlist_entry.dart` |
| `_PerItemState` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_PerItemState.positionMs` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_PerItemState.durationMs` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_PerItemState.updatedAt` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_PerItemState._PerItemState` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_NavigationMaps` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_NavigationMaps.nextMap` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_NavigationMaps.prevMap` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_NavigationMaps._NavigationMaps` | `models/native_playback_state.dart` | `top level` | 1 / models | Dart core / owning type / feature owners |
| `_AppCoverObserver` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `_AppCoverObserver._AppCoverObserver` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | Dart core / owning type / feature owners |
| `_AppCoverObserver.onCovered` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/foundation.dart` |
| `_AppCoverObserver.didChangeAppLifecycleState` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/material.dart` |
| `_AppReturnObserver` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/foundation.dart`; `package:flutter/material.dart` |
| `_AppReturnObserver._AppReturnObserver` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | Dart core / owning type / feature owners |
| `_AppReturnObserver.onReturned` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/foundation.dart` |
| `_AppReturnObserver.wasCovered` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | Dart core / owning type / feature owners |
| `_AppReturnObserver.didChangeAppLifecycleState` | `presentation/legacy_launch/external_return_observers.dart` | `top level` | 4 / presentation | `package:flutter/material.dart` |

## Private cross-file references

Every listed edge uses the renamed declaration or its destination static owner. Private members used only inside a whole class remain private. No data/model edge calls back through the facade.

| Private declaration | Used by original declarations (different destination) | Shared as |
| --- | --- | --- |
| `_traktLastScrobbleAction` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeScrobbleSession.traktLastScrobbleAction` |
| `_traktLastKnownProgress` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeScrobbleSession.traktLastKnownProgress` |
| `_traktLastKnownSeason` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeScrobbleSession.traktLastKnownSeason` |
| `_traktLastKnownEpisode` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeScrobbleSession.traktLastKnownEpisode` |
| `_traktHeartbeatTimer` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.traktHeartbeatTimer` |
| `_simklLastScrobbleAction` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.simklLastScrobbleAction` |
| `_simklLastKnownProgress` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.simklLastKnownProgress` |
| `_simklLastKnownSeason` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.simklLastKnownSeason` |
| `_simklLastKnownEpisode` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.simklLastKnownEpisode` |
| `_simklHeartbeatTimer` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeScrobbleSession.simklHeartbeatTimer` |
| `_resolvedStreamCache` | `VideoPlayerLauncher._handleProgressUpdate` | `StreamRedirectResolver.resolvedStreamCache` |
| `_cacheResolvedStream` | `VideoPlayerLauncher._handleProgressUpdate`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder.build`, `_AndroidTvPlaylistResolver`, `_AndroidTvPlaylistResolver.handleRequest` | `StreamRedirectResolver.cacheResolvedStream` |
| `_resolveRedirectUrl` | `VideoPlayerLauncher._resolveEntryUrl` | `StreamRedirectResolver.resolveRedirectUrl` |
| `_clearResolvedStreams` | `VideoPlayerLauncher.debugNativePlaybackSession`, `_AndroidTvPlaylistResolver`, `_AndroidTvPlaylistResolver.dispose`, `_AndroidTvPlaylistResolver.replaceEntries` | `StreamRedirectResolver.clearResolvedStreams` |
| `_refreshTraktEpisodeProgress` | `VideoPlayerLauncher._push` | `TrackerProgressSeeding.refreshTraktEpisodeProgress` |
| `_seedSimklEpisodeProgress` | `VideoPlayerLauncher._push` | `TrackerProgressSeeding.seedSimklEpisodeProgress` |
| `_seedMdblistEpisodeProgress` | `VideoPlayerLauncher._push` | `TrackerProgressSeeding.seedMdblistEpisodeProgress` |
| `_push` | `VideoPlayerLauncher.push` | `LaunchRouter.push` |
| `_commitExternalLaunchSource` | `VideoPlayerLauncher._push` | `ExternalLaunchCommit.commitExternalLaunchSource` |
| `_seedTrackerContinueWatching` | `VideoPlayerLauncher._push` | `ExternalLaunchCommit.seedTrackerContinueWatching` |
| `_launchWithExternalPlayer` | `VideoPlayerLauncher._push` | `ExternalPlayerLaunch.launchWithExternalPlayer` |
| `_launchWithDeoVR` | `VideoPlayerLauncher._push`, `VideoPlayerLauncher.launchExternalIfConfigured` | `DeovrLaunch.launchWithDeoVR` |
| `_mayDiscloseCredential` | `VideoPlayerLauncher._launchWithDeoVR`, `VideoPlayerLauncher._launchWithExternalPlayer` | `ExternalDisclosure.mayDiscloseCredential` |
| `_confirmExternalDisclosure` | `VideoPlayerLauncher._launchWithDeoVR`, `VideoPlayerLauncher._launchWithExternalPlayer` | `ExternalDisclosure.confirmExternalDisclosure` |
| `_runWhenCoveredByExternalActivity` | `VideoPlayerLauncher.push` | `ExternalActivityLifecycle.runWhenCoveredByExternalActivity` |
| `_notifyOnReturnFromExternalActivity` | `VideoPlayerLauncher._push`, `VideoPlayerLauncher.launchExternalIfConfigured` | `ExternalActivityLifecycle.notifyOnReturnFromExternalActivity` |
| `_analyticsProviderLabel` | `VideoPlayerLauncher._push` | `LaunchAnalytics.analyticsProviderLabel` |
| `_launchOnAndroidTv` | `VideoPlayerLauncher._push` | `AndroidTvNativeLaunch.launchOnAndroidTv` |
| `_launchIptvOnAndroidTv` | `VideoPlayerLauncher._launchOnAndroidTv` | `IptvAndroidTvLaunch.launchIptvOnAndroidTv` |
| `_fetchAndPushMetadataAsync` | `VideoPlayerLauncher._launchOnAndroidTv` | `NativeMetadataPush.fetchAndPushMetadataAsync` |
| `_saveSeriesPosterToPlaylist` | `VideoPlayerLauncher._fetchAndPushMetadataAsync` | `SeriesPosterPersistence.saveSeriesPosterToPlaylist` |
| `_simklSeriesSEUnresolved` | `VideoPlayerLauncher._handleProgressUpdate` | `NativeMdblistSession.simklSeriesSEUnresolved` |
| `_nativeMdblistTarget` | `VideoPlayerLauncher._handleProgressUpdate` | `NativeMdblistSession.nativeMdblistTarget` |
| `_initializeNativeMdblist` | `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeMdblistSession.initializeNativeMdblist` |
| `_ensureNativeMdblistSession` | `VideoPlayerLauncher._handleProgressUpdate` | `NativeMdblistSession.ensureNativeMdblistSession` |
| `_closeNativeMdblist` | `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._launchOnAndroidTv` | `NativeMdblistSession.closeNativeMdblist` |
| `_handleProgressUpdate` | `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeProgressHandler.handleProgressUpdate` |
| `_handlePlaybackFinished` | `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession` | `NativeProgressHandler.handlePlaybackFinished` |
| `_resolveEntryUrl` | `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher._launchWithExternalPlayer`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._prepareEntries` | `EntryUrlResolver.resolveEntryUrl` |
| `_PlaybackContentType` | `VideoPlayerLauncher._fetchAndPushMetadataAsync`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativeResumePositions`, `_AndroidTvPlaybackPayload`, `_AndroidTvPlaybackPayload.contentType`, `_AndroidTvPlaybackPayload.trackingContentType`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._determineContentType`, `_AndroidTvPlaybackPayloadBuilder._determineStartIndex`, `_AndroidTvPlaybackPayloadBuilder._fetchPerItemPlaybackState`, `_AndroidTvPlaybackPayloadBuilder.build` | `PlaybackContentType` |
| `_AndroidTvPlaybackPayload` | `VideoPlayerLauncher._closeNativeMdblist`, `VideoPlayerLauncher._ensureNativeMdblistSession`, `VideoPlayerLauncher._fetchAndPushMetadataAsync`, `VideoPlayerLauncher._handlePlaybackFinished`, `VideoPlayerLauncher._handleProgressUpdate`, `VideoPlayerLauncher._initializeNativeMdblist`, `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher._nativeMdblistTarget`, `VideoPlayerLauncher._simklSeriesSEUnresolved`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder.build` | `AndroidTvPlaybackPayload` |
| `_AndroidTvPlaybackItem` | `_AndroidTvPlaybackPayload`, `_AndroidTvPlaybackPayload.items`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._buildNavigationMaps`, `_AndroidTvPlaybackPayloadBuilder._fetchMovieImdbId`, `_AndroidTvPlaybackPayloadBuilder.build` | `AndroidTvPlaybackItem` |
| `_AndroidTvSeriesSeason` | `_AndroidTvPlaybackPayload`, `_AndroidTvPlaybackPayload.seasons`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._buildSeriesSeasons` | `AndroidTvSeriesSeason` |
| `_AndroidTvCollectionGroup` | `_AndroidTvPlaybackPayload`, `_AndroidTvPlaybackPayload.collectionGroups`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder.build` | `AndroidTvCollectionGroup` |
| `_AndroidTvSeriesEpisode` | `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._buildSeriesSeasons` | `AndroidTvSeriesEpisode` |
| `_AndroidTvPlaybackPayloadResult` | `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder.build` | `AndroidTvPlaybackPayloadResult` |
| `_LauncherEntry` | `VideoPlayerLauncher._fetchAndPushMetadataAsync`, `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder.build`, `_AndroidTvPlaybackPayloadResult`, `_AndroidTvPlaybackPayloadResult.entries`, `_AndroidTvPlaylistResolver`, `_AndroidTvPlaylistResolver.entries`, `_AndroidTvPlaylistResolver.handleRequest`, `_AndroidTvPlaylistResolver.replaceEntries` | `LauncherEntry` |
| `_AndroidTvPlaylistResolver` | `VideoPlayerLauncher._launchOnAndroidTv` | `AndroidTvPlaylistResolver` |
| `_AndroidTvPlaybackPayloadBuilder` | `VideoPlayerLauncher._launchOnAndroidTv`, `VideoPlayerLauncher.debugNativePlaybackSession`, `VideoPlayerLauncher.debugNativeResumePositions` | `AndroidTvPlaybackPayloadBuilder` |
| `_PerItemState` | `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._determineCollectionStartIndex`, `_AndroidTvPlaybackPayloadBuilder._determineStartIndex`, `_AndroidTvPlaybackPayloadBuilder._fetchPerItemPlaybackState`, `_AndroidTvPlaybackPayloadBuilder._readVideoState`, `_AndroidTvPlaybackPayloadBuilder._stateFromRecord`, `_AndroidTvPlaybackPayloadBuilder.build` | `PerItemState` |
| `_NavigationMaps` | `_AndroidTvPlaybackPayloadBuilder`, `_AndroidTvPlaybackPayloadBuilder._buildNavigationMaps` | `NavigationMaps` |
| `_AppCoverObserver` | `VideoPlayerLauncher._runWhenCoveredByExternalActivity` | `AppCoverObserver` |
| `_AppReturnObserver` | `VideoPlayerLauncher._armedReturnObserver`, `VideoPlayerLauncher._notifyOnReturnFromExternalActivity` | `AppReturnObserver` |

| Private member retained in a whole class | Cross-file use | Shared as |
| --- | --- | --- |
| `_AndroidTvPlaybackPayloadBuilder._fetchPerItemPlaybackState` | `VideoPlayerLauncher.debugNativeResumePositions` | `AndroidTvPlaybackPayloadBuilder.fetchPerItemPlaybackState` |

## Public facade and static dispatch

All 13 original public launcher methods retain signatures, annotations, defaults and argument order in forwarding methods; the ownership checker verifies these independently. The facade exports `VideoPlayerLaunchArgs` and `VideoPlayerLaunchArgsWidget`. Repository search found no `extends VideoPlayerLaunchArgs` / `implements VideoPlayerLaunchArgs`, and no method tear-offs: all eight `.toWidget` references in `lib/` and `test/` are calls (seven test calls and the production router call). Extension static dispatch is therefore compatible.

## Enum stringification audit

All full-enum interpolations are logs: original lines 3883 and 3891 in `_fetchAndPushMetadataAsync` interpolate `payload.contentType`; line 5889 in builder `build` interpolates `contentType`. No full-enum `toString()` call exists. Original lines 5311 (payload map) and 5998 (diagnostic) use `contentType.name`; comparisons/switches use enum values. No full-enum text reaches persistence, a payload, comparison or native call. Accepted exception to unchanged logs: `_PlaybackContentType.*` becomes `PlaybackContentType.*` in those three log messages only.

## Approved annotation amendment

The user approved removing `@visibleForTesting` from exactly six moved
implementations on 2026-10-02: `debugNativeResumePositions`,
`debugNativePlaybackSession`, `externalPlaybackUrlFor`,
`shouldEnableMdblistTracking`, `normalizeScrobbleFlags`, and
`showAuthenticatedWebDavPlayerNotice`. Their facade annotations stay intact.
Without the amendment, splitting libraries introduces analyzer warnings at
unchanged production/facade calls. The checker verifies each exact removal
and the retained facade annotation, with positive and negative fixtures.

## Approved DeoVR bridge amendment and router grouping

The user approved the exact HTTP import in `presentation/legacy_launch/deovr_launch.dart`
on 2026-10-02. The existing `_launchWithDeoVR` combines UI and a JSON upload;
its whole body remains verbatim. The guard allows only that path/URI pair.
Exit: move the upload behind a data contract in a later control-flow change.
Step 0 listed this import but missed its conflict with the bridge prohibition;
the conflict was reported and approval obtained before the bridge move.

`VideoPlayerLauncher.push` and `_push` share `LaunchRouter`. The public action
calls `_push`, which can dispatch the public action for a next episode; separate
files would form a circular import. `_push` retains its underscore within this
single owner. The manifest/report are updated before step 4; no method is split.

## Exact expected differences

In addition to imports, registered owner qualifiers and dropping a leading underscore: static ownership of the ten session fields, two caches and cache functions; `toWidget` becomes an extension with identical signature/body; builder debug helper becomes public; the progress warning at 4849 removes only the proven-true null condition (the similar condition at 4879 remains); resolver warnings at 5599 replace the proven-true log comparison by `true` and remove `?.` in the same log interpolation. Each is recorded in `vpl_manifest.tsv` and the checker compares its exact expected baseline substitution.

## Source and behavior verification boundary

`vpl_source_text.txt` inventories all source readers, their positive/negative scope and port steps. `vpl_affected_tests.txt` includes all launcher importers plus indirect `toWidget` consumers and source readers. Host debug tests cover the initial payload/resume projection. Android TV launch enrichment, finish/disposal and next-episode ordering remain pending on a real device. Heartbeat timer coverage is assessed through existing handlers without changing production code.

## Oversized declarations and retention

Until each step, the original launcher temporarily retains the remaining source responsibilities; it shrinks at steps 1–4 and is capped at 300 at step 5. Whole native launch, payload builder, progress handler and router retain named measured size exceptions, with exit milestone: split their method/class during a later control-flow change. No other extracted source gets a size exception.

No unresolved declaration, cross-file private symbol or layer decision remains.
