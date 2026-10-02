import 'dart:async';
import 'dart:math';
import 'package:debrify/features/player_launch/data/android_tv_payload_builder.dart';
import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/android_tv_playlist_resolver.dart';
import 'package:debrify/features/player_launch/data/entry_url_resolver.dart';
import 'package:debrify/features/player_launch/data/iptv_android_tv_launch.dart';
import 'package:debrify/features/player_launch/data/movie_resume_state.dart';
import 'package:debrify/features/player_launch/data/native_mdblist_session.dart';
import 'package:debrify/features/player_launch/data/native_metadata_push.dart';
import 'package:debrify/features/player_launch/data/native_progress_handler.dart';
import 'package:debrify/features/player_launch/data/native_scrobble_session.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/failed_saved_source.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/profiles/profile_playback_preparation.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/startup_recovery_sources.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/torrent_search_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/torrent_playback_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:debrify/utils/show_shuffle.dart';
import 'package:flutter/foundation.dart';

final class AndroidTvNativeLaunch {
  static Future<bool> launchOnAndroidTv(
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
      return IptvAndroidTvLaunch.launchIptvOnAndroidTv(args);
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
    AndroidTvPlaylistResolver? playbackResolver;
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
      final builder = AndroidTvPlaybackPayloadBuilder(
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
      await NativeMdblistSession.initializeNativeMdblist(result.payload);

      if (!sessionActive()) {
        unawaited(serverWatch.close());
        await NativeMdblistSession.closeNativeMdblist(result.payload);
        return false;
      }
      // TVMaze may discover a stable show id after native playback starts.
      // Resolver callbacks read this mutable payload value at invocation time
      // so source switches and dynamically fetched episodes inherit it.
      String? effectiveContentImdbId() => result.payload.imdbId ?? args.contentImdbId;

      final resolver = AndroidTvPlaylistResolver(
        entries: result.entries,
        resolveEntry: (entry, {canContinue}) {
          bool active() => sessionActive() && (canContinue?.call() ?? true);
          Future<String> resolve() =>
              EntryUrlResolver.resolveEntryUrl(entry, args, canContinue: active);
          return preparation == null ? resolve() : preparation.run(resolve);
        },
      );
      playbackResolver = resolver;

      // Generate a unique session ID for this playback launch
      // This prevents stale metadata from previous sessions being sent to new sessions
      final sessionId = '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
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
          bool active() => sessionActive() && resolver.isLatestSwitch(switchToken);
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
                  season: args.contentType == 'series' ? args.contentSeason : null,
                  episode: args.contentType == 'series' ? args.contentEpisode : null,
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
          final fullyClassified = classifiedAsSeries && episodes.length >= nonSampleCount;
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

          final stableSeriesTitle = args.contentTitle ?? seriesPlaylist?.seriesTitle ?? args.title;
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
              !isSeries && args.contentType != 'series' && playlistEntries.length == 1
              ? await MovieResumeState.readMovieResumeState(
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
            final localPositionMs = (localState?['positionMs'] as num?)?.toInt() ?? 0;
            final localDurationMs = (localState?['durationMs'] as num?)?.toInt() ?? 0;
            final resolvedLocal = resolveEpisodeLocalWatchState(
              locallyWatched: trackingPolicy.progressFrom(TrackingSource.local) && locallyWatched,
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
              if (trackerPercent != null) 'traktProgressPercent': trackerPercent,
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
        sourcePlaylistResolverForTv = (index, {automaticRecovery = false}) async {
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
        if (sourceCommit != null) await sourceCommit(currentStremioSources[sourceIndex]);
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
        moreSourcesProviderForTv = (String mode, {int? season, int? episode}) async {
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
            'stremioSources': currentStremioSources.map((t) => t.toJson()).toList(),
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
          (seriesFetcher.fetchAddonEpisodes != null || seriesFetcher.fetchEngine != null)) {
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
                  if (engine == null && fetched.any((t) => t.streamType == StreamType.torrent)) {
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
              final wantPacks = !seriesFetcher.isMovie && seriesFetcher.fetchAddonPacks != null;
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
      Future<Map<String, dynamic>?> Function(int season, int episode)? episodeFetchProviderForTv;
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
              return start != null && end != null && season >= start && season <= end;
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
              final localProgress = await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
                seriesTitle: stableSeriesTitle,
                imdbId: episodeImdbId,
              );
              final locallyFinished = await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
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
              final localPositionMs = (localState?['positionMs'] as num?)?.toInt() ?? 0;
              final localDurationMs = (localState?['durationMs'] as num?)?.toInt() ?? 0;
              final localWatched = locallyFinished[season.toString()]?.contains(episode) ?? false;
              final resolvedLocal = resolveEpisodeLocalWatchState(
                locallyWatched: trackingPolicy.progressFrom(TrackingSource.local) && localWatched,
                localPositionMs: trackingPolicy.progressFrom(TrackingSource.local)
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
              row['updatedAt'] = (localState?['updatedAt'] as num?)?.toInt() ?? 0;
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
              'stremioSources': currentStremioSources.map((t) => t.toJson()).toList(),
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
            for (var i = from; i < currentStremioSources.length && attempts < cap; i++) {
              final t = currentStremioSources[i];
              if (t.streamType == StreamType.externalUrl) continue;
              if (packsOnly) {
                if (t.streamType != StreamType.torrent) continue;
                if (t.coverageType != null && !packCoversSeason(t, season)) {
                  continue;
                }
              } else {
                final info = SeriesParser.parseFilename(t.displayTitle);
                final matches = info.season == season && info.episode == episode;
                final covers = t.streamType == StreamType.torrent && packCoversSeason(t, season);
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
        final newResolver = playbackResult['sourceResolver'] as Future<String?> Function(Torrent)?;
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
      payloadMap['startupHasRemainingSavedSources'] = args.startupHasRemainingSavedSources;
      payloadMap['useAddonTextFormatting'] = await TorrentSearchStorage.getUseAddonTextFormatting();
      payloadMap['showAddonLogos'] = await TorrentSearchStorage.getShowAddonLogos();
      payloadMap['initialContinuousShuffle'] = args.initialContinuousShuffle;
      final customInventory = seriesFetcher?.loadCustomEpisodeInventory;
      if (customInventory != null) {
        final episodes = await customInventory();
        payloadMap['customShuffleEpisodes'] = episodes
            .where((episode) => isShuffleEpisodeEligible(episode))
            .toList();
      }
      if (args.stremioTvChannels != null && args.stremioTvChannels!.isNotEmpty) {
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
        await NativeMdblistSession.closeNativeMdblist(result.payload);
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
          return NativeProgressHandler.handleProgressUpdate(result.payload, progress);
        },
        onFinished: () async {
          unawaited(serverWatch.close());
          await NativeProgressHandler.handlePlaybackFinished(result.payload);
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
        onRequestMovieMetadata: result.payload.contentType != PlaybackContentType.series
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
            : (index) => sourcePlaylistResolverForTv!(index, automaticRecovery: true),
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
        await NativeMdblistSession.closeNativeMdblist(result.payload);
        resolver.dispose();
        return false;
      }

      // Async TVMaze metadata fetch - don't block initial playback
      // This mirrors mobile video_player_screen.dart behavior
      // Pass sessionId to ensure stale metadata from previous sessions is discarded
      NativeMetadataPush.fetchAndPushMetadataAsync(
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
      if (builtPayload != null) await NativeMdblistSession.closeNativeMdblist(builtPayload);
      debugPrint('VideoPlayerLauncher: Android TV launch failed: $e');
      playbackResolver?.dispose();
      if (e is NativePlayerSettingsUnavailable) rethrow;
      return false;
    }
  }
}
