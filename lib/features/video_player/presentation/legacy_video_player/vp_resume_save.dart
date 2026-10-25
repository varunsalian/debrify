import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/models/playback_resume_policy.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/utils/series_parser.dart';

abstract interface class VpResumeSaveHost {
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  IptvChannel? get currentIptvChannel;
  String? get currentStreamUrl;
  String? get currentStremioTvContentTitle;
  Duration get duration;
  int? get effectiveContentEpisode;
  String? get effectiveContentImdbId;
  int? get effectiveContentSeason;
  String? get effectiveContentTitle;
  String? get effectiveContentType;
  List<IptvChannel>? get effectiveIptvChannels;
  IptvGuideContext? get iptvGuideContextOverride;
  bool get isManualEpisodeSelection;
  bool get isPlaying;
  bool get isReady;
  bool get isTransitioning;
  Torrent? get openedWatchSource;
  Duration get position;
  Lock get resumeSaveLock;
  ResumeWriteGuard get resumeWriteGuard;
  SeriesPlaylist? get seriesPlaylist;
  MediaServerWatchController get serverWatch;
  bool get validationGateActive;
  ({int? season, int? episode}) traktSeasonEpisode();
  String resumeIdForEntry(PlaylistEntry entry);
  String get resumeKey;
  String get title;
  String get videoUrl;
  String? get contentImdbId;
  String? get iptvSourceId;
  PlaybackResumePolicy get resumePolicy;
  String? get currentLocalMovieImdbId;
  bool get currentMovieMarkedAsFinished;
  double get playbackSpeed;
  AspectMode get aspectMode;
  double? get speedBeforeHold;
}

class VpResumeSave {
  VpResumeSave(this._host);
  final VpResumeSaveHost _host;

  /// Get enhanced playback state for current content
  Future<Map<String, dynamic>?> getEnhancedPlaybackState() async {
    try {
      final seriesPlaylist = _host.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series, get the current episode info
        if (_host.currentIndex >= 0 &&
            _host.currentIndex < _host.activePlaylist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _host.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            // Catalog series follow IMDb + S/E across release-title aliases;
            // generic packs keep their exact title-keyed record.
            return LocalPlaybackResumeResolver.episode(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
              imdbId: seriesPlaylist.imdbId ?? _host.effectiveContentImdbId,
              policy: _host.resumePolicy,
            );
          }
        }
      }

      PlaylistEntry? currentEntry;
      final activePlaylist = _host.activePlaylist;
      if (activePlaylist != null &&
          _host.currentIndex >= 0 &&
          _host.currentIndex < activePlaylist.length) {
        currentEntry = activePlaylist[_host.currentIndex];
      }

      // A lone series stream has no SeriesPlaylist, but its catalog S/E is
      // authoritative. Prefer the canonical episode record for catalog play;
      // generic playback retains its exact video/source lookup first.
      if (_host.effectiveContentType == 'series') {
        if (CustomSeriesIdentity.isCustom(_host.effectiveContentImdbId) ||
            (_host.effectiveContentImdbId?.startsWith('medialibrary:') ??
                false)) {
          if (_host.effectiveContentSeason == null ||
              _host.effectiveContentEpisode == null) {
            return null;
          }
          return LocalPlaybackResumeResolver.episode(
            seriesTitle: _host.effectiveContentTitle ?? _host.title,
            season: _host.effectiveContentSeason!,
            episode: _host.effectiveContentEpisode!,
            imdbId: _host.effectiveContentImdbId,
            policy: _host.resumePolicy,
          );
        }
        if (_host.resumePolicy == PlaybackResumePolicy.sourceSpecific &&
            currentEntry != null) {
          final exactVideo = await VideoProgressStorage.getVideoPlaybackState(
            videoTitle: _host.resumeIdForEntry(currentEntry),
          );
          if (exactVideo != null) return exactVideo;
        }

        if (_host.effectiveContentSeason != null &&
            _host.effectiveContentEpisode != null) {
          final episodeState = await LocalPlaybackResumeResolver.episode(
            seriesTitle: _host.effectiveContentTitle ?? _host.title,
            season: _host.effectiveContentSeason!,
            episode: _host.effectiveContentEpisode!,
            imdbId: _host.effectiveContentImdbId,
            policy: _host.resumePolicy,
          );
          if (episodeState != null) return episodeState;
        }

        // Legacy single-episode launches may only have the mirrored video row.
        if (currentEntry != null) {
          return VideoProgressStorage.getVideoPlaybackState(
            videoTitle: _host.resumeIdForEntry(currentEntry),
          );
        }
        final legacyTitle = _host.title.isNotEmpty
            ? _host.title
            : 'Unknown Video';
        return VideoProgressStorage.getVideoPlaybackState(
          videoTitle: legacyTitle,
        );
      }

      final resumeId = currentEntry != null
          ? _host.resumeIdForEntry(currentEntry)
          : ((_host.currentStremioTvContentTitle ?? _host.title).isNotEmpty
                ? (_host.currentStremioTvContentTitle ?? _host.title)
                : 'Unknown Video');
      // A multi-file movie/collection must keep an existing per-file bookmark
      // ahead of the one catalog IMDb bookmark. ExoPlayer already restricts
      // canonical movie resume to `_PlaybackContentType.single`; mirror that
      // boundary here while retaining the legacy IMDb fallback for unseen files.
      final isSingleLogicalMovie =
          activePlaylist == null || activePlaylist.length <= 1;
      final moviePolicy =
          _host.resumePolicy == PlaybackResumePolicy.catalogCanonical &&
              isSingleLogicalMovie
          ? PlaybackResumePolicy.catalogCanonical
          : PlaybackResumePolicy.sourceSpecific;
      debugPrint(
        'Resume Load: fetching state for resumeId=$resumeId '
        'policy=${moviePolicy.name}',
      );
      final videoState = await LocalPlaybackResumeResolver.movie(
        resumeId: resumeId,
        imdbId: _host.effectiveContentImdbId,
        policy: moviePolicy,
      );
      if (videoState != null) {
        debugPrint(
          'Resume Load: found state for resumeId=$resumeId '
          'updatedAt=${videoState['updatedAt']}',
        );
      }
      return videoState;
    } catch (e) {}
    return null;
  }

  bool resumeSaveBlocked(bool debounced) {
    if (_host.validationGateActive || !_host.isReady) return true;
    // An IPTV zap flips _currentIptvIndex — and therefore _resumeKey — before
    // the incoming stream opens, while _position/_duration still describe the
    // OUTGOING one (_isReady is never cleared for the gap). A tick landing in
    // that window would file the old movie's position under the new channel's
    // key, which the Continue-watching shelf would then show as real progress.
    // Nothing is lost by skipping: the next tick saves once the switch lands.
    if (_host.effectiveIptvChannels != null && _host.isTransitioning) {
      return true;
    }

    // If this is a manual episode selection and it's been less than 30 seconds, skip saving
    // This gives the user time to seek to where they want
    if (_host.isManualEpisodeSelection && debounced) {
      return true;
    }
    return false;
  }

  void observeServerWatch({bool completed = false}) {
    if (!_host.serverWatch.isActive ||
        _host.validationGateActive ||
        !_host.isReady ||
        _host.isTransitioning ||
        _host.resumeWriteGuard.heldTargetIfBlocked(
              _host.position.inMilliseconds,
            ) !=
            null) {
      return;
    }
    // This resolver follows the current playlist entry after episode advance;
    // launch metadata alone still describes the originally opened episode.
    final currentEpisode = _host.traktSeasonEpisode();
    _host.serverWatch.observe(
      _host.openedWatchSource,
      positionMs: _host.position.inMilliseconds,
      durationMs: _host.duration.inMilliseconds,
      playing: _host.isPlaying,
      completed: completed,
      season: currentEpisode.season,
      episode: currentEpisode.episode,
    );
  }

  Future<void> saveResume({
    bool debounced = false,
    Duration? positionOverride,
  }) {
    // Check both when requested and after queueing. A save requested inside a
    // transition/validation guard must not become valid merely because an
    // older write kept it queued until the guard ended; conversely, a newly
    // started transition must suppress work which was waiting on the lock.
    if (resumeSaveBlocked(debounced)) return Future<void>.value();
    observeServerWatch();
    // A periodic tick carries no unique intent. If any newer/older save owns
    // the lock, drop this tick instead of building an unbounded timer backlog.
    if (debounced && _host.resumeSaveLock.locked) return Future<void>.value();
    return _host.resumeSaveLock.synchronized(
      () => saveResumeLocked(
        debounced: debounced,
        positionOverride: positionOverride,
      ),
    );
  }

  Future<void> saveResumeLocked({
    required bool debounced,
    Duration? positionOverride,
  }) async {
    if (resumeSaveBlocked(debounced)) return;

    var pos = positionOverride ?? _host.position;
    final dur = _host.duration;
    if (dur <= Duration.zero) {
      return;
    }

    // A resume seek was requested and playback is still nowhere near it: the
    // seek did not land, so the live position describes a stream that
    // restarted at the beginning. Filing it would destroy the very bookmark we
    // tried to resume from — persist the REQUESTED target instead, which keeps
    // the bookmark where it was while still recording speed/aspect changes
    // made in the window (this is their only persistence route). The guard
    // self-releases once the seek lands, the user seeks, or they have watched
    // from here long enough for it to be their real position.
    if (!_host.resumeWriteGuard.allowsPersist(pos.inMilliseconds)) {
      // allowsPersist(false) implies an armed target.
      final heldTarget = _host.resumeWriteGuard.pendingTargetMs!;
      if (heldTarget >= dur.inMilliseconds) {
        // _duration mirrors mpv live and can briefly read short on a fresh
        // remote stream. Writing the target against that duration would store
        // a ≥100% (finished-looking) position, so skip this tick entirely —
        // including speed/aspect, which the next tick (or exit save) persists
        // once the duration settles. Deliberate trade: a rare few-second delay
        // beats a bookmark that reads as watched.
        return;
      }
      pos = Duration(milliseconds: heldTarget);
    }

    // Completion clears local movie resume/CW state. Do not let the autosave
    // tick immediately recreate that state while end credits keep playing.
    if (_host.currentMovieMarkedAsFinished &&
        _host.currentLocalMovieImdbId != null) {
      return;
    }

    final aspectStr = AspectModeUtils.aspectModeToString(_host.aspectMode);
    // While the user is holding for temporary 2x boost, persist the prior speed
    // so a kill/dispose mid-hold doesn't strand 2x as the resume value.
    final persistedSpeed = _host.speedBeforeHold ?? _host.playbackSpeed;

    // Save to enhanced playback state system
    try {
      final seriesPlaylist = _host.seriesPlaylist;
      if (seriesPlaylist != null && seriesPlaylist.isSeries) {
        // For series content
        if (_host.currentIndex >= 0 &&
            _host.currentIndex < _host.activePlaylist!.length) {
          final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
            (episode) => episode.originalIndex == _host.currentIndex,
            orElse: () => seriesPlaylist.allEpisodes.first,
          );

          if (currentEpisode.seriesInfo.season != null &&
              currentEpisode.seriesInfo.episode != null) {
            await SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: seriesPlaylist.seriesTitle ?? 'Unknown Series',
              season: currentEpisode.seriesInfo.season!,
              episode: currentEpisode.seriesInfo.episode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: seriesPlaylist.imdbId ?? _host.contentImdbId,
            );
          }
        }
      } else {
        // For non-series content
        if (_host.activePlaylist != null && _host.activePlaylist!.isNotEmpty) {
          PlaylistEntry? currentEntry;
          if (_host.currentIndex >= 0 &&
              _host.currentIndex < _host.activePlaylist!.length) {
            currentEntry = _host.activePlaylist![_host.currentIndex];
          }

          if (currentEntry != null) {
            final resumeId = _host.resumeIdForEntry(currentEntry);
            debugPrint(
              'Resume Save: storing state resumeId=$resumeId pos=${pos.inMilliseconds} dur=${dur.inMilliseconds}',
            );
            String currentVideoUrl = '';
            if (_host.currentStreamUrl != null &&
                _host.currentStreamUrl!.isNotEmpty) {
              currentVideoUrl = _host.currentStreamUrl!;
            } else if (currentEntry.url.isNotEmpty) {
              currentVideoUrl = currentEntry.url;
            } else if (_host.videoUrl.isNotEmpty) {
              currentVideoUrl = _host.videoUrl;
            }

            await VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: resumeId,
              videoUrl: currentVideoUrl,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: _host.contentImdbId,
            );

            // ALSO save in collection format for playlist progress tracking
            // This allows the playlist screen to display progress indicators
            debugPrint(
              '💾 Collection Save Check: seriesPlaylist=${seriesPlaylist != null}, seriesTitle="${seriesPlaylist?.seriesTitle}", isSeries=${seriesPlaylist?.isSeries}',
            );
            if (seriesPlaylist != null && seriesPlaylist.seriesTitle != null) {
              // Parse season/episode from filename for consistent progress tracking across view modes
              final seriesInfo = SeriesParser.parseFilename(currentEntry.title);
              final season = seriesInfo.season ?? 0;
              final episode = seriesInfo.episode ?? (_host.currentIndex + 1);

              await SeriesProgressStorage.saveSeriesPlaybackState(
                seriesTitle: seriesPlaylist.seriesTitle!,
                season: season, // Parsed from filename, fallback to 0
                episode: episode, // Parsed from filename, fallback to index
                positionMs: pos.inMilliseconds,
                durationMs: dur.inMilliseconds,
                speed: persistedSpeed,
                aspect: aspectStr,
                imdbId: seriesPlaylist.imdbId ?? _host.contentImdbId,
              );
              debugPrint(
                '✅ Collection Save: title="${seriesPlaylist.seriesTitle}" S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')} (index=${_host.currentIndex}) filename="${currentEntry.title}"',
              );
            } else {
              debugPrint(
                '❌ Collection Save SKIPPED: seriesPlaylist is null or has no title',
              );
            }
          }
        } else {
          // Single video file (no playlist)
          // If it's a series episode (from Quick Play next episode), save as series state
          if (_host.effectiveContentType == 'series' &&
              _host.effectiveContentSeason != null &&
              _host.effectiveContentEpisode != null) {
            await SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: _host.effectiveContentTitle ?? _host.title,
              season: _host.effectiveContentSeason!,
              episode: _host.effectiveContentEpisode!,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: _host.effectiveContentImdbId,
            );
          } else {
            final currentUrl =
                (_host.currentStreamUrl != null &&
                    _host.currentStreamUrl!.isNotEmpty)
                ? _host.currentStreamUrl!
                : _host.videoUrl;
            final title = _host.currentStremioTvContentTitle ?? _host.title;
            final videoTitle = title.isNotEmpty ? title : 'Unknown Video';

            await VideoProgressStorage.saveVideoPlaybackState(
              videoTitle: videoTitle,
              videoUrl: currentUrl,
              positionMs: pos.inMilliseconds,
              durationMs: dur.inMilliseconds,
              speed: persistedSpeed,
              aspect: aspectStr,
              imdbId: _host.effectiveContentImdbId,
            );
          }
        }
      }
    } catch (e) {}

    // Also save to legacy system for backward compatibility
    if (!CustomSeriesIdentity.isCustom(_host.effectiveContentImdbId)) {
      await VideoResumeStorage.upsertVideoResume(
        _host.resumeKey,
        {
          'positionMs': pos.inMilliseconds,
          'speed': persistedSpeed,
          'aspect': aspectStr,
          'durationMs': dur.inMilliseconds,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        sourceId:
            _host.currentIptvChannel?.attributes['series_playlist_id'] ??
            _host.currentIptvChannel?.attributes['source_playlist_id'] ??
            _host.iptvGuideContextOverride?.sourceId ??
            _host.iptvSourceId,
      );
    }

    // Explicit checkpoints (pause, settled seek, exit-adjacent saves) are the
    // handoff moments another device would resume from — let sync flush now
    // instead of waiting out the playback coalescing window. The 6s autosave
    // tick stays on the throttled path.
    if (!debounced) {
      MainPageBridge.notifyPlaybackCheckpoint();
    }
  }
}
