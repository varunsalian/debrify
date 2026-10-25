import 'dart:async';

import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/services/next_episode_service.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpEpisodeNextHost {
  Map<String, String>? get activeHttpHeaders;
  List<PlaylistEntry>? get activePlaylist;
  bool get continuousShuffleEnabled;
  int get currentIndex;
  set currentStreamUrl(String? v);
  Duration get duration;
  set dynamicTitle(String v);
  bool get hasStremioTvNext;
  set isTransitioning(bool v);
  int get pikPakRetryId;
  set pikPakRetryId(int v);
  mk.Player get player;
  bool get seriesNextDispatched;
  set seriesNextDispatched(bool v);
  SeriesPlaylist? get seriesPlaylist;
  set singleFileImdbFetched(bool v);
  set singleFileImdbId(String? v);
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  set tvStaticMessage(String v);
  set tvStaticSubtext(String v);
  void clearBufferingIndicator();
  void startTransitionOverlay();
  void tvAbandonScrub();
  void resetSubtitleState();
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  Duration? randomStartOffset(Duration total);
  Duration? percentStartOffset(Duration total);
  Future<bool> playShowShuffle({bool autoAdvance = false});
  int? pickShuffleIndex();
  Future<bool> loadPlaylistIndex(
    int index, {
    bool autoplay = false,
    EpisodePlaybackRequest? request,
    bool skipInitialSave = false,
    bool preferLocalResume = false,
    bool suppressResume = false,
    Torrent? manualValidationSource,
    int? manualValidationSourceIndex,
  });
  int findNextEpisodeIndex();
  Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false});
  void setManualSelectionMode({bool allowResume = false});
  Future<bool> playPikPakVideoWithRetry(
    String videoUrl, {
    String? overrideProvider,
    String? overridePikPakFileId,
    bool isDebrifyTV = false,
    bool showFailure = true,
    EpisodePlaybackRequest? request,
  });
  Future<void> waitForVideoReady();
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  Future<Map<String, String>?> Function()? get requestMagicNext;
  bool get startFromRandom;
  double? get startAtPercent;
  String? get contentType;
  String? get contentImdbId;
  int? get contentSeason;
  int? get contentEpisode;
  String? get contentTitle;
  String get title;
  SeriesSourceFetcher? get seriesSourceFetcher;
  void resetLocalCompletionState();
  Future<bool> goToNextStremioTvSlot({bool resumeCurrentOnFailure = true});
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
  PlayerPipSession? get iosPipSession;
}

class VpEpisodeNext {
  VpEpisodeNext(this._host);
  final VpEpisodeNextHost _host;

  /// Navigate to next episode
  Future<void> goToNextEpisode() async {
    // Check if widget is still mounted before any state changes
    if (!_host.mounted) return;

    // Show black screen during transition to hide previous frame
    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
    });

    // Only show transition overlay for Debrify TV content (when requestMagicNext is available)
    final isDebrifyTV = _host.requestMagicNext != null;
    if (isDebrifyTV) {
      _host.startTransitionOverlay();
    }
    try {
      await _host.player.pause();
    } catch (_) {}
    if (_host.continuousShuffleEnabled) {
      if (await _host.playShowShuffle()) return;
      final shuffleIndex = _host.pickShuffleIndex();
      if (shuffleIndex != null) {
        _host.setManualSelectionMode();
        await _host.loadPlaylistIndex(shuffleIndex, autoplay: true);
        return;
      }
    }

    final nextIndex = _host.findNextEpisodeIndex();
    if (nextIndex != -1) {
      // Mark this as a manual episode selection
      _host.setManualSelectionMode();
      await _host.loadPlaylistIndex(nextIndex, autoplay: true);
      return;
    }

    if (_host.hasStremioTvNext) {
      final handled = await _host.goToNextStremioTvSlot();
      if (handled) return;
    }

    // Series content beyond the pack: fetch the next episode IN-PLAYER when
    // possible (no relaunch), falling back to the pop-and-quick-play handoff.
    if (await _host.fetchNextEpisodeInPlayer()) return;

    // Series content without season pack: find next episode and trigger Quick Play
    if (_host.requestMagicNext == null) {
      final handled = await handleSeriesNextEpisode();
      if (handled) return;
    }

    // If there is no playlist-based next item and Debrify TV provider is present, use it
    if (_host.requestMagicNext != null) {
      debugPrint('Player: MagicTV next requested.');
      try {
        final result = await _host.requestMagicNext!();
        final url = result != null ? (result['url'] ?? '') : '';
        final title = result != null ? (result['title'] ?? '') : '';
        final provider = result != null ? (result['provider'] ?? '') : '';
        final pikpakFileId = result != null
            ? (result['pikpakFileId'] ?? '')
            : '';

        if (url.isNotEmpty) {
          debugPrint(
            'Player: MagicTV next success. Opening new URL (provider: $provider, pikpakFileId: $pikpakFileId).',
          );

          // Clear subtitle, IMDB, and local completion state when switching content
          _host.resetSubtitleState();
          _host.singleFileImdbId = null;
          _host.singleFileImdbFetched = false;
          _host.resetLocalCompletionState();

          // Update TV static overlay to show signal acquired
          if (title.isNotEmpty && _host.mounted) {
            _host.setState(() {
              _host.tvStaticMessage = '📺 SIGNAL ACQUIRED';
              _host.tvStaticSubtext = '▶ ${title.toUpperCase()}';
            });
          }

          // Use PikPak retry logic if this is a PikPak video
          final isPikPak =
              provider.toLowerCase() == 'pikpak' || pikpakFileId.isNotEmpty;
          if (isPikPak) {
            debugPrint(
              'Player: Detected PikPak video from Debrify TV, using retry logic',
            );
            // VpPikPakRetry.playPikPakVideoWithRetry will increment _pikPakRetryId to cancel previous retries
            await _host.playPikPakVideoWithRetry(
              url,
              overrideProvider: provider,
              overridePikPakFileId: pikpakFileId,
              isDebrifyTV: true,
            );
          } else {
            // Cancel any ongoing PikPak retry when switching to non-PikPak video
            _host.pikPakRetryId++;
            await _host.openMedia(
              mk.Media(url, httpHeaders: _host.activeHttpHeaders),
              play: true,
            );
          }
          _host.currentStreamUrl = url;
          // Disable auto-enabled embedded subtitles to prevent duplicates
          await _host.setSubtitleTrackWithDiagnostics(
            mk.SubtitleTrack.no(),
            source: 'debrify-tv-open-disable-auto',
          );
          // If advanced option is enabled, jump to a random timestamp for Debrify TV items
          if (_host.startFromRandom) {
            await _host.waitForVideoReady();
            final offset = _host.randomStartOffset(_host.duration);
            if (offset != null) {
              await _host.player.seek(offset);
            }
          } else if (_host.startAtPercent != null) {
            await _host.waitForVideoReady();
            final offset = _host.percentStartOffset(_host.duration);
            if (offset != null) {
              await _host.player.seek(offset);
            }
          }
          if (title.isNotEmpty) {
            _host.setState(() {
              _host.dynamicTitle = title;
            });
          }
          // Clear transition state when video is ready
          if (_host.mounted) {
            _host.setState(() {
              _host.isTransitioning = false;
            });
          }
          return;
        }
      } catch (e) {
        debugPrint('Player: MagicTV next failed: $e');
      }
    }

    // Clear transition state if no next episode found
    if (_host.mounted) {
      _host.setState(() {
        _host.isTransitioning = false;
      });
    }
  }

  /// Legacy fallback: pop with the next episode for the caller's Quick Play.
  Future<bool> handleSeriesNextEpisode() async {
    // Already popping to hand off the next episode — a second trigger (manual
    // Next racing end-of-video auto-advance) must not run again.
    if (_host.seriesNextDispatched) return true;
    if (_host.contentType != 'series' ||
        _host.contentImdbId == null ||
        _host.seriesSourceFetcher?.resolveAdjacentEpisode != null) {
      return false;
    }

    // Determine the CURRENT episode: prefer the series playlist (tracks actual
    // playback position within a season pack) over widget params (set at launch).
    int? currentSeason;
    int? currentEpisode;

    final seriesPlaylist = _host.seriesPlaylist;
    if (seriesPlaylist != null &&
        seriesPlaylist.isSeries &&
        _host.activePlaylist != null &&
        _host.currentIndex >= 0 &&
        _host.currentIndex < _host.activePlaylist!.length) {
      try {
        final current = seriesPlaylist.allEpisodes.firstWhere(
          (ep) => ep.originalIndex == _host.currentIndex,
        );
        currentSeason = current.seriesInfo.season;
        currentEpisode = current.seriesInfo.episode;
      } catch (_) {
        // firstWhere threw — no match, fall through to widget params
      }
    }

    // Fallback to widget params (single-file playback without a series playlist)
    currentSeason ??= _host.contentSeason;
    currentEpisode ??= _host.contentEpisode;

    if (currentSeason == null || currentEpisode == null) return false;

    debugPrint(
      'Player: Looking up next episode after S${currentSeason}E$currentEpisode',
    );
    final nextEp = await NextEpisodeService.findNextEpisode(
      _host.contentImdbId!,
      currentSeason,
      currentEpisode,
    );

    if (nextEp == null) {
      debugPrint(
        'Player: No next episode found (last episode or lookup failed)',
      );
      return false;
    }

    debugPrint(
      'Player: Found next episode S${nextEp.season}E${nextEp.episode}, popping for Quick Play',
    );
    // Re-check the guard right before popping. Because nothing awaits between
    // here and the pop, this set-and-pop is atomic on Dart's single thread, so
    // a concurrent call that already passed the top guard and is resuming from
    // its own await will see the flag set and return without a second pop.
    if (!_host.mounted || _host.seriesNextDispatched) return true;
    _host.seriesNextDispatched = true;
    final result = <String, dynamic>{
      'quickPlayNext': true,
      'imdbId': _host.contentImdbId,
      'season': nextEp.season,
      'episode': nextEp.episode,
      'title': _host.contentTitle ?? _host.title,
      'contentType': _host.contentType,
    };
    if (_host.iosPipSession?.isParked ?? false) {
      _host.iosPipSession!.close(result);
    } else {
      Navigator.of(_host.context).pop(result);
    }
    return true;
  }
}
