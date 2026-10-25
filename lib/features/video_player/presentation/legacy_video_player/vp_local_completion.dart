import 'dart:async';
import 'package:debrify/services/storage/episode_completion_storage.dart';
import 'package:debrify/services/storage/local_completion_storage.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';

abstract interface class VpLocalCompletionHost {
  bool get mounted;
  bool get traktScrobble;
  bool get simklScrobble;
  bool get mdblistScrobble;
  List<Map<String, dynamic>>? get stremioTvChannels;
  String? get contentType;
  int? get contentSeason;
  int? get contentEpisode;
  String? get contentImdbId;
  String? get contentTitle;
  String get title;
  List<IptvChannel>? get effectiveIptvChannels;
  String? get effectiveContentImdbId;
  String? get effectiveContentType;
  SeriesPlaylist? get seriesPlaylist;
  List<PlaylistEntry>? get activePlaylist;
  int get currentIndex;
  Duration get position;
  Duration get duration;
  bool get validationGateActive;
  String get resumeKey;
}

class VpLocalCompletion {
  VpLocalCompletion(this._host);
  final VpLocalCompletionHost _host;

  bool currentEpisodeMarkedAsFinished = false;
  bool currentMovieMarkedAsFinished = false;
  bool currentMovieRewatchStarted = false;
  int movieCompletionThreshold =
      LocalCompletionStorage.defaultLocalCompletionThreshold;
  int episodeCompletionThreshold =
      LocalCompletionStorage.defaultLocalCompletionThreshold;

  Future<void> loadLocalCompletionThresholds() async {
    final values = await Future.wait<int>([
      LocalCompletionStorage.getMovieCompletionThreshold(),
      LocalCompletionStorage.getEpisodeCompletionThreshold(),
    ]);
    if (!_host.mounted) return;
    movieCompletionThreshold = values[0];
    episodeCompletionThreshold = values[1];
    // A seek can cross the default threshold before the preference read
    // finishes. Re-evaluate against the configured value once it arrives.
    checkAndApplyLocalCompletion();
  }

  bool get usesLocalCompletionTracking =>
      (forceLocalCompletionTracking ||
          (!_host.traktScrobble &&
              !_host.simklScrobble &&
              !_host.mdblistScrobble)) &&
      _host.stremioTvChannels == null &&
      _host.effectiveIptvChannels == null;

  bool forceLocalCompletionTracking = false;

  Future<void> loadTrackingPolicy() async {
    final policy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    if (!_host.mounted) return;
    forceLocalCompletionTracking = policy.usesLocalCompletionTracking(
      traktScrobble: _host.traktScrobble,
      simklScrobble: _host.simklScrobble,
      mdblistScrobble: _host.mdblistScrobble,
    );
    // A very short item can cross its completion threshold before this async
    // profile read returns. Re-evaluate immediately so This-device mode never
    // misses the forced-local rule merely because scrobbling is also enabled.
    checkAndApplyLocalCompletion();
  }

  String? get currentLocalMovieImdbId {
    if (_host.effectiveContentType != 'movie') return null;
    final imdbId = _host.effectiveContentImdbId?.trim();
    return imdbId == null || imdbId.isEmpty ? null : imdbId;
  }

  void resetLocalCompletionState() {
    currentEpisodeMarkedAsFinished = false;
    currentMovieMarkedAsFinished = false;
    currentMovieRewatchStarted = false;
  }

  /// Mark the current episode as finished if it's a series
  Future<void> markCurrentEpisodeAsFinished() async {
    final seriesPlaylist = _host.seriesPlaylist;
    // Single-file series playback: use widget params
    if ((seriesPlaylist == null || !seriesPlaylist.isSeries) &&
        _host.contentType == 'series' &&
        _host.contentSeason != null &&
        _host.contentEpisode != null &&
        _host.contentImdbId != null) {
      currentEpisodeMarkedAsFinished = true;
      try {
        await EpisodeCompletionStorage.markEpisodeAsFinished(
          seriesTitle: _host.contentTitle ?? _host.title,
          season: _host.contentSeason!,
          episode: _host.contentEpisode!,
          imdbId: _host.contentImdbId,
        );
      } catch (_) {}
      return;
    }
    if (seriesPlaylist == null ||
        !seriesPlaylist.isSeries ||
        seriesPlaylist.seriesTitle == null) {
      return;
    }
    currentEpisodeMarkedAsFinished = true;
    try {
      // Find the current episode info
      if (_host.currentIndex >= 0 &&
          _host.currentIndex < _host.activePlaylist!.length) {
        final currentEpisode = seriesPlaylist.allEpisodes.firstWhere(
          (episode) => episode.originalIndex == _host.currentIndex,
          orElse: () => seriesPlaylist.allEpisodes.first,
        );

        if (currentEpisode.seriesInfo.season != null &&
            currentEpisode.seriesInfo.episode != null) {
          await EpisodeCompletionStorage.markEpisodeAsFinished(
            seriesTitle: seriesPlaylist.seriesTitle!,
            season: currentEpisode.seriesInfo.season!,
            episode: currentEpisode.seriesInfo.episode!,
            imdbId: seriesPlaylist.imdbId ?? _host.contentImdbId,
          );
        }
      }
    } catch (e) {}
  }

  Future<void> markCurrentMovieAsFinished() async {
    final imdbId = currentLocalMovieImdbId;
    if (!usesLocalCompletionTracking ||
        currentMovieMarkedAsFinished ||
        imdbId == null) {
      return;
    }
    // Set this before the await: position events are frequent and completion
    // must perform one cleanup/write, not queue one per frame.
    currentMovieMarkedAsFinished = true;
    try {
      await Future.wait([
        MovieProgressStorage.markMovieAsFinished(imdbId),
        VideoResumeStorage.removeVideoResume(
          _host.resumeKey,
          playbackCheckpoint: true,
        ),
      ]);
    } catch (_) {
      // Playback remains usable if local storage is temporarily unavailable.
    }
  }

  /// Apply the local, user-configured completion rule. This is synchronous on
  /// purpose because it runs for every position update; actual writes stay
  /// unawaited and are guarded one-shot above/in [markCurrentEpisodeAsFinished].
  void checkAndApplyLocalCompletion() {
    if (_host.validationGateActive ||
        !usesLocalCompletionTracking ||
        _host.duration <= Duration.zero ||
        _host.position <= Duration.zero) {
      return;
    }

    final percent =
        _host.position.inMicroseconds * 100 / _host.duration.inMicroseconds;
    final movieImdbId = currentLocalMovieImdbId;
    if (movieImdbId != null) {
      if (!currentMovieRewatchStarted && percent < movieCompletionThreshold) {
        // The title was finished during an earlier session. A real new play
        // below its threshold is a rewatch, so restore it to normal local
        // Continue Watching behavior before the next resume save.
        currentMovieRewatchStarted = true;
        unawaited(MovieProgressStorage.unmarkMovieAsFinished(movieImdbId));
      }
      if (!currentMovieMarkedAsFinished &&
          percent >= movieCompletionThreshold) {
        unawaited(markCurrentMovieAsFinished());
      }
      return;
    }

    final isSeries =
        _host.effectiveContentType == 'series' ||
        _host.seriesPlaylist?.isSeries == true;
    if (!isSeries) return;
    if (currentEpisodeMarkedAsFinished ||
        percent < episodeCompletionThreshold) {
      return;
    }
    unawaited(markCurrentEpisodeAsFinished());
  }
}
