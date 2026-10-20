import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';

abstract interface class VpPlaybackEndedHost {
  set activeMediaShouldPlay(bool v);
  List<PlaylistEntry>? get activePlaylist;
  bool get continuousShuffleEnabled;
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  bool get hasIptvNext;
  bool get hasStremioTvNext;
  IptvLiveRecovery get iptvLiveRecovery;
  set isAutoAdvancing(bool v);
  set sleepStopLatched(bool v);
  bool get validationGateActive;
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
  Future<void> goToNextEpisode();
  Future<bool> fetchNextEpisodeInPlayer({bool autoAdvance = false});
  Future<bool> handleSeriesNextEpisode();
  Future<Map<String, String>?> Function()? get requestMagicNext;
  void observeServerWatch({bool completed = false});
  void stopTraktHeartbeat();
  void traktScrobble(String action);
  void stopSimklHeartbeat();
  void simklScrobble(String action);
  void mdblistStop({bool complete = false});
  Future<void> markCurrentEpisodeAsFinished();
  Future<void> markCurrentMovieAsFinished();
  SleepTimerMode get sleepTimerMode;
  void cancelSleepTimer();
  void showSleepTimerToast(String message);
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  Future<bool> goToNextStremioTvSlot({bool resumeCurrentOnFailure = true});
}

class VpPlaybackEnded {
  VpPlaybackEnded(this._host);
  final VpPlaybackEndedHost _host;

  Future<void> onPlaybackEnded() async {
    // A manually selected replacement is not playback until its validation
    // gate commits it. In particular, a short provider error video can emit
    // `completed`; never let that become a watched/scrobble event.
    if (_host.validationGateActive) return;
    _host.observeServerWatch(completed: true);
    // LIVE IPTV: an ended live stream is a dropped connection, not a
    // finished item — the origin closed on us (mpv's keep-open parks on the
    // last frame, which is the "fake pause" from the Discord report). The
    // recovery machine re-tunes to the live edge; nothing below this line
    // (scrobble stop, mark-as-finished, episode advance) may interpret a
    // live EOF as "watched to the end" — so live returns here even when the
    // machine declines (backgrounded, sleep-stopped).
    final endedLiveChannel = _host.currentIptvChannel;
    if (endedLiveChannel != null && endedLiveChannel.isLive) {
      _host.iptvLiveRecovery.onEnded();
      return;
    }

    // Scrobble stop to Trakt when movie finishes
    _host.stopTraktHeartbeat();
    _host.traktScrobble('stop');
    _host.stopSimklHeartbeat();
    _host.simklScrobble('stop');
    _host.mdblistStop(complete: true);

    // Mark the current episode as finished if it's a series
    await _host.markCurrentEpisodeAsFinished();
    // A locally tracked movie may finish before the next periodic position
    // save; make EOF a completion too (tracker sessions keep their existing
    // scrobble-only path above).
    await _host.markCurrentMovieAsFinished();

    // "Stop at the end of this episode": suppress every advance below and let
    // the screen sleep. Playback has already finished, so there is nothing
    // left to pause.
    if (_host.sleepTimerMode == SleepTimerMode.endOfItem) {
      _host.cancelSleepTimer();
      _host.sleepStopLatched = true;
      _host.activeMediaShouldPlay = false;
      _host.showSleepTimerToast('Sleep timer — stopping here');
      return;
    }

    // IPTV episode list (series/VOD): advance to the next episode in the
    // season, mirroring the Next button. Checked first because IPTV episodes
    // carry no playlist / magic-next, so the branches below would otherwise
    // leave the player parked on the final frame with a next episode available.
    if (_host.hasIptvNext) {
      await _host.switchToIptvChannel(_host.currentIptvIndex + 1);
      return;
    }

    // Playlist auto-advance keeps priority over guide-based Stremio TV next.
    if (_host.continuousShuffleEnabled) {
      if (await _host.playShowShuffle(autoAdvance: true)) return;
      final shuffleIndex = _host.pickShuffleIndex();
      if (shuffleIndex != null) {
        _host.isAutoAdvancing = true;
        await _host.loadPlaylistIndex(shuffleIndex, autoplay: true);
        return;
      }
    }

    final nextIndex = _host.findNextEpisodeIndex();
    if (nextIndex != -1) {
      _host.isAutoAdvancing = true;
      await _host.loadPlaylistIndex(nextIndex, autoplay: true);
      return;
    }

    if (_host.hasStremioTvNext) {
      final handled = await _host.goToNextStremioTvSlot(
        resumeCurrentOnFailure: false,
      );
      if (handled) return;
      debugPrint(
        'Player: Stremio TV auto-next unavailable; leaving playback ended.',
      );
      return;
    }

    // Debrify TV (no playlist): auto-advance using provider if available
    if ((_host.activePlaylist == null || _host.activePlaylist!.isEmpty) &&
        _host.requestMagicNext != null) {
      await _host.goToNextEpisode();
      return;
    }

    // Match manual Next for direct links and exhausted packs: keep the player
    // alive while resolving the following episode.
    if (await _host.fetchNextEpisodeInPlayer(autoAdvance: true)) return;

    if (_host.activePlaylist == null || _host.activePlaylist!.isEmpty) {
      // No playlist — try series next episode
      await _host.handleSeriesNextEpisode();
      return;
    }

    // End of playlist — try series next episode
    await _host.handleSeriesNextEpisode();
  }
}
