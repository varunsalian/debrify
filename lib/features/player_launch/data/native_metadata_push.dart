import 'package:collection/collection.dart';
import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/series_poster_persistence.dart';
import 'package:debrify/features/player_launch/models/launcher_entry.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/episode_tracker_snapshot_service.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/playlist_metadata_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/show_shuffle.dart';
import 'package:flutter/foundation.dart';

final class NativeMetadataPush {
  /// Fetch TVMaze metadata asynchronously and push updates to native player
  /// This doesn't block initial playback - updates are pushed when available
  /// The sessionId parameter ensures stale metadata from previous sessions is discarded
  static void fetchAndPushMetadataAsync(
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
        if (seriesImdbId != null && seriesImdbId.startsWith('tt') && contentImdbId == null) {
          await PlaylistMetadataStorage.updatePlaylistItemImdbId(
            seriesImdbId,
            rdTorrentId: rdTorrentId,
            torboxTorrentId: torboxTorrentId,
            pikpakCollectionId: pikpakCollectionId,
          );
        }

        // Save series poster to playlist item (if we have series info)
        await SeriesPosterPersistence.saveSeriesPosterToPlaylist(
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
          final localEpisodeProgress = await MergedEpisodeProgressStorage.getMergedEpisodeProgress(
            seriesTitle: seriesPlaylist.seriesTitle ?? payload.title,
            imdbId: discoveredImdbId,
          );
          final locallyFinished = await MergedEpisodeProgressStorage.getMergedFinishedEpisodes(
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
            final locallyWatched = locallyFinished[season.toString()]?.contains(episode) ?? false;
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
              locallyWatched: trackingPolicy.progressFrom(TrackingSource.local) && locallyWatched,
              localPositionMs: trackingPolicy.progressFrom(TrackingSource.local) ? positionMs : 0,
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
                if (season != null && number != null) ...watchState(season, number),
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
              final rawInfo = seriesPlaylist.fullTvmazeEpisodes.firstWhereOrNull(
                (episode) => episode['season'] == item.season && episode['number'] == item.episode,
              );
              final info = rawInfo == null ? null : EpisodeInfo.fromTVMaze(rawInfo);
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
          if (discoveredAfterLaunch) EpisodeTrackerSnapshotService.refreshSimkl(discoveredImdbId),
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
            final refreshed = await EpisodeTrackerSnapshotService.refreshMdblistHistory(
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
}
