import 'package:collection/collection.dart';
import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/features/player_launch/data/entry_url_resolver.dart';
import 'package:debrify/features/player_launch/data/movie_resume_state.dart';
import 'package:debrify/features/player_launch/data/stream_redirect_resolver.dart';
import 'package:debrify/features/player_launch/models/android_tv_playback_item.dart';
import 'package:debrify/features/player_launch/models/launcher_entry.dart';
import 'package:debrify/features/player_launch/models/native_playback_state.dart';
import 'package:debrify/features/player_launch/models/playback_content_type.dart';
import 'package:debrify/features/player_launch/models/video_player_launch_args.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/movie_collection.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/services/movie_metadata_service.dart';
import 'package:debrify/services/storage/episode_resume_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/merged_episode_progress_storage.dart';
import 'package:debrify/services/storage/quick_play_storage.dart';
import 'package:debrify/services/storage/tracker_episode_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/utils/episode_progress_merge.dart';
import 'package:debrify/utils/movie_parser.dart';
import 'package:debrify/utils/series_parser.dart';
import 'package:flutter/foundation.dart';

// dart format off
class AndroidTvPlaybackPayloadBuilder {
  final VideoPlayerLaunchArgs args;

  final bool Function()? canContinue;
  const AndroidTvPlaybackPayloadBuilder(this.args, {this.canContinue});

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
    final perItemStates = await fetchPerItemPlaybackState(
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
        final resolved = await EntryUrlResolver.resolveEntryUrl(
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

  Future<List<PerItemState>> fetchPerItemPlaybackState(
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
            await MovieResumeState.readMovieResumeState(
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
    return MovieResumeState.resumeIdForEntry(
      entry,
      fallbackTitle: args.title,
    );
  }
}
// dart format on
