import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpIptvChannelSwitchHost {
  bool get activeMediaUserPaused;
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories});
  Future<void> applyIptvAudioPreference(int ticket);
  void cancelPendingIptvCatchup({bool hideFeedback = true});
  void clearBufferingIndicator();
  set currentChannelName(String? v);
  set currentChannelNumber(int? v);
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentIptvIndex(int v);
  int get currentSourceIndex;
  set currentSourceIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  bool get engineFlagOn;
  void hideIptvChannelSheet();
  void hideIptvZapBanner({bool immediate = false});
  void hideSourceSheet();
  String? get iptvChannelKey;
  IptvTuneDiagnostics get iptvDiag;
  set iptvErrorsMuted(bool v);
  IptvLiveRecovery get iptvLiveRecovery;
  ValueNotifier<String?> get iptvReconnectText;
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  bool get iptvStartOverLoading;
  set iptvStartOverLoading(bool v);
  set iptvStartOverTimelineRequested(bool v);
  int get iptvSwitchTicket;
  set iptvSwitchTicket(int v);
  bool get iptvZapPagingActive;
  bool get isIptvSeriesContext;
  set isTransitioning(bool v);
  set lastIptvErrorShown(DateTime? v);
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
  bool get pausedByLifecycle;
  mk.Player get player;
  void prepareIptvBannerData(IptvChannel channel);
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  void raiseIptvZapBanner();
  Future<void> recordIptvWatchForChannel(IptvChannel channel);
  Future<void> refreshEngineRecordingState();
  ResumeWriteGuard get resumeWriteGuard;
  bool get screenDisposed;
  void setIptvSources(
    String? channelKey,
    List<StremioIptvCandidate>? candidates, {
    int currentIndex = 0,
  });
  bool get sleepStopLatched;
  void startTransitionOverlay();
  Future<void> stopRecording({bool userInitiated = true});
  set transitionPhase(int v);
  set transitionPhase2Started(DateTime? v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set transitionStopTimer(Timer? v);
  Future<bool> tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
  });
  void tvAbandonScrub();
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  bool get mounted;
  void setState(VoidCallback fn);
  SleepTimerMode get sleepTimerMode;
}

class VpIptvChannelSwitch {
  VpIptvChannelSwitch(this._host);
  final VpIptvChannelSwitchHost _host;

  /// The machine may act only on a LIVE channel with playback wanted and
  /// nobody else in charge: sleep stops outrank reconnects, a backgrounded
  /// app must stay quiet (the resume path re-arms recovery itself).
  bool iptvRecoveryEligible() {
    if (!_host.mounted || _host.screenDisposed) return false;
    final channel = _host.currentIptvChannel;
    if (channel == null || !channel.isLive) return false;
    if (_host.sleepStopLatched) return false;
    if (_host.sleepTimerMode == SleepTimerMode.endOfItem) return false;
    if (_host.pausedByLifecycle) return false;
    // An explicit user pause (including the PiP pause action) means nobody
    // asked for playback — a pending retry must not restart the channel
    // (codex round 2, finding 3).
    if (_host.activeMediaUserPaused) return false;
    return true;
  }

  /// Re-open the current live channel with its full identity (URL + the
  /// channel's own headers — plan finding P7). A fresh open joins the live
  /// edge. Stremio channels re-run the whole switch so their candidate
  /// ladder stays the owner of which URL plays; [IptvLiveRecovery.expectRetune]
  /// keeps the recovery episode alive across that switch's tune-start.
  void performIptvLiveRetune(String source, int attempt) {
    final channel = _host.currentIptvChannel;
    if (channel == null || !channel.isLive) return;
    _host.cancelPendingIptvCatchup(hideFeedback: false);
    if (_host.iptvStartOverActive || _host.iptvStartOverLoading) {
      _host.setState(() {
        _host.iptvStartOverActive = false;
        _host.iptvStartOverLoading = false;
        _host.iptvStartOverTimelineRequested = false;
      });
    }
    _host.iptvDiag.onRecovery(source, 'retune', 'attempt=$attempt');
    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // expectRetune is consumed synchronously by the switch's entry (its
      // ticket + machine bookkeeping run before any await), so no real zap
      // can pick the flag up instead.
      _host.iptvLiveRecovery.expectRetune = true;
      unawaited(
        switchToIptvChannel(_host.currentIptvIndex, quietRecovery: true),
      );
      return;
    }
    // Direct reopen path. The ticket pins this retune to the channel the
    // machine saw: a real zap bumps it and the stale retune dissolves at
    // the checks below instead of stealing playback back (codex round 2's
    // blocker).
    final ticket = _host.iptvSwitchTicket;
    unawaited(() async {
      // mpv makes no promise about `stream-record` across an open() — a
      // running capture must be stopped first, exactly like every other
      // media replacement path (codex round 2, finding 6).
      await _host.stopRecording(userInitiated: false);
      if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
      _host.iptvDiag.onTuneStart(channel.name, channel.url, isLive: true);
      _host.iptvLiveRecovery.expectRetune = true;
      _host.iptvLiveRecovery.onTuneStarted();
      try {
        await _host.openMedia(
          mk.Media(channel.url, httpHeaders: channel.playbackHeaders),
          play: true,
          liveStream: true,
        );
      } catch (e) {
        debugPrint('Player: IPTV live retune failed to open: $e');
      }
    }());
  }

  Future<void> switchToIptvChannel(
    int index, {
    bool quietRecovery = false,
  }) async {
    final channels = _host.effectiveIptvChannels;
    if (channels == null || index < 0 || index >= channels.length) return;
    // Ticket FIRST, before any await — codex round 2's blocker: with the
    // ticket taken after the recording stop below, two overlapping switch
    // calls could resume from that await in either order and the OLDER
    // intent could take the newer ticket, hijacking playback back to the
    // channel the user just left.
    final ticket = ++_host.iptvSwitchTicket;
    // This switch owns the error gate now (a superseded ladder's state doesn't
    // survive). Muted until the new media is opened below; the burst debounce
    // resets too, so this channel can report its own failure.
    _host.iptvErrorsMuted = true;
    _host.lastIptvErrorShown = null;
    // One machine tune-start per SWITCH, not per Stremio candidate — the
    // candidate ladder below is this switch's own hunt. A machine-driven
    // stremio re-tune arrives here with expectRetune set and keeps its
    // episode; a real zap resets the machine and takes the pill with it.
    final wasRecoveryRetune = _host.iptvLiveRecovery.expectRetune;
    _host.iptvLiveRecovery.onTuneStarted();
    if (!wasRecoveryRetune) _host.iptvReconnectText.value = null;
    // A channel change ends the current recording (the stream identity flips).
    // Unconditional: it must also cancel a start still awaiting its storage
    // setup, which `_isRecording` would not report yet.
    await _host.stopRecording(userInitiated: false);
    if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
    _host.cancelPendingIptvCatchup();

    _host.hideIptvChannelSheet();

    final channel = channels[index];
    _host.clearBufferingIndicator();
    // The zap path never runs VpResumeRestore.maybeRestoreResume, so the previous channel's
    // resume guard (a VOD movie mid-resume) would otherwise stay armed and
    // suppress the incoming channel's saves. Same switch-boundary rule as
    // VpPlaylistLoad.loadPlaylistIndex.
    _host.resumeWriteGuard.clear();
    _host.setState(() {
      _host.iptvStartOverActive = false;
      _host.iptvStartOverLoading = false;
      _host.iptvStartOverTimelineRequested = false;
      // A quiet recovery re-tune is not a zap: no transition overlay, no
      // zap banner — the reconnect pill is the only narration (plan
      // invariant "retune ≠ zap"; codex round 2, finding 14).
      _host.isTransitioning = !quietRecovery;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
      _host.currentIptvIndex = index;
      _host.currentChannelNumber = channel.channelNumber ?? (index + 1);
      // The corner badge is painted from this pair; without the name it kept
      // showing the launch channel under the new channel's number.
      _host.currentChannelName = channel.name;
    });
    if (!quietRecovery) _host.startTransitionOverlay();
    // Identity paints from the channel itself, so it is correct before a
    // single byte of the new stream has arrived; the guide fills in behind it.
    // Zapping to on-demand retires the panel outright — it has no live
    // identity to present, and leaving it up would describe the wrong item.
    if (channel.isLive && !quietRecovery) {
      _host.prepareIptvBannerData(channel);
      _host.raiseIptvZapBanner();
      // The guide follows what is playing, so reopening it lands on the
      // category the current channel actually belongs to. A paged ring is the
      // exception: it already knows its own category from the response, which
      // a single channel's group can't always express — an "All"/uncategorized
      // window would keep narrowing the guide to whichever group it landed on.
      if (!_host.iptvZapPagingActive) _host.anchorIptvGuideCategory(channel);
    } else {
      _host.hideIptvZapBanner();
    }

    // Register the item we're switching TO in the IPTV watch history, exactly
    // as the native TV player does before every non-live start. Only the item
    // the user LAUNCHED used to be recorded, so an auto-advanced episode wrote
    // a resume position that no history row accounted for: the Continue
    // Watching shelf kept pointing at the launch episode, and a series-wide
    // removal (which finds episodes through the history) couldn't reach the
    // rest of them. Unawaited — the shelf can settle a frame late, a zap can't.
    if (!channel.isLive) unawaited(_host.recordIptvWatchForChannel(channel));

    try {
      await _host.player.pause();
    } catch (_) {}

    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // Retire the outgoing channel's source rows NOW — during the resolve
      // await below the sheet must not offer the previous channel's links
      // (picking one would abort this switch's ladder and play the old
      // channel under the new channel's identity).
      _host.setIptvSources(null, null);
      // Mirror the native path: the UI has already committed to the new
      // channel, so clear the outgoing stream now — a failed or empty
      // resolve must not leave the previous channel's frozen frame sitting
      // under the new channel's title/index.
      try {
        await _host.player.stop();
      } catch (_) {}
      // Stremio-addon channel: resolve its candidate URLs and walk them until
      // one produces playback — the same serial ladder the IPTV preview runs.
      // A zap is an explicit play intent, so a cached-empty resolve is
      // re-checked fresh instead of replaying a stale "nothing".
      final candidates = await StremioIptvService.instance.resolveCandidates(
        channel.url,
        refreshIfEmpty: true,
      );
      if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
      // The candidates double as the source sheet's rows for this channel.
      _host.setIptvSources(channel.url, candidates);
      var opened = false;
      try {
        for (var i = 0; i < candidates.length; i++) {
          if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
          final url = candidates[i].url;
          _host.iptvDiag.onTuneStart(channel.name, url, isLive: channel.isLive);
          _host.iptvDiag.note(
            'stremio candidate ${i + 1}/${candidates.length}',
          );
          final ok = await _host.tryOpenLiveStream(
            url,
            httpHeaders: channel.playbackHeaders,
          );
          // A newer switch superseded this ladder mid-probe: its success or
          // failure belongs to the other channel's playback now — don't
          // credit it here.
          if (ticket != _host.iptvSwitchTicket) return;
          if (ok) {
            StremioIptvService.instance.markWinner(channel.url, url);
            if (_host.mounted && _host.currentSourceIndex != i) {
              _host.setState(() => _host.currentSourceIndex = i);
            }
            opened = true;
            break;
          }
        }
      } finally {
        // Only this ladder's own probing is silenced; a newer switch owns the
        // flag from here (it sets it again on entry).
        if (ticket == _host.iptvSwitchTicket) _host.iptvErrorsMuted = false;
      }
      if (ticket != _host.iptvSwitchTicket) return;
      if (!opened) {
        // Dead channel — forget the stale candidates so a later attempt
        // re-resolves. Playback just stays down, like a dead M3U channel.
        StremioIptvService.instance.invalidate(channel.url);
        debugPrint('Player: no playable stream for ${channel.name}');
      }
    } else {
      // Plain M3U/Xtream channel: single link, no source sheet. Headers are
      // per-channel (the playlist declares them per entry), so they come from
      // the channel rather than widget.httpHeaders.
      _host.setIptvSources(null, null);
      try {
        _host.iptvDiag.onTuneStart(
          channel.name,
          channel.url,
          isLive: channel.isLive,
        );
        final media = mk.Media(
          channel.url,
          httpHeaders: channel.playbackHeaders,
        );
        // The outgoing stream is torn down (pause above); everything mpv
        // reports from here is this channel's, including a fast failure that
        // lands while open() is still awaiting.
        _host.iptvErrorsMuted = false;
        await _host.openMedia(media, play: true, liveStream: channel.isLive);
      } catch (e) {
        debugPrint('Player: IPTV channel switch failed: $e');
      }
    }

    if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;

    // Carry the audio choice onto the new episode (series memory). Fire and
    // forget: it waits for the new source's tracks then matches by language;
    // [ticket] is this switch's generation so a newer switch abandons it.
    if (_host.isIptvSeriesContext) {
      unawaited(_host.applyIptvAudioPreference(ticket));
    }

    // Directly trigger transition overlay cleanup sequence.
    // Unlike debrid channel switching (where _playSub listener handles
    // the transition phases after 'playing' fires), IPTV URLs are already
    // resolved so we skip phase 1 and go straight to the reveal phase.
    // This prevents the overlay from getting stuck if the playing event
    // doesn't fire reliably for HLS/live streams.
    _host.transitionStopTimer?.cancel();
    _host.transitionPhaseTimer?.cancel();
    _host.transitionPhase = 2;
    _host.transitionPhase2Started = DateTime.now();
    _host.setState(() {
      _host.isTransitioning = false;
    });
    _host.transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _host.rainbowController.stop();
      _host.transitionRunning = false;
      _host.rainbowActive = false;
      if (_host.mounted) _host.setState(() {});
    });

    // The NEW channel may itself already be recording (engine captures keep
    // running across zaps) — repaint the Record button from native truth.
    if (_host.engineFlagOn) unawaited(_host.refreshEngineRecordingState());
  }

  /// Manual pick from the source sheet while a Stremio IPTV channel plays:
  /// open the chosen link directly. No position seek, no subtitle
  /// bookkeeping, and no auto-advance on failure — the user chose this link
  /// deliberately, so a dead pick just leaves the channel down (they can
  /// pick another from the sheet).
  Future<void> switchToIptvSource(int index, String url) async {
    _host.hideSourceSheet();
    final key = _host.iptvChannelKey;
    final ticket = ++_host.iptvSwitchTicket;
    final previousIndex = _host.currentSourceIndex;
    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
      _host.currentSourceIndex = index;
    });
    _host.startTransitionOverlay();
    // A deliberate source pick is a fresh tune: any recovery episode (and
    // its pill) belonged to the link being abandoned.
    _host.iptvLiveRecovery.onTuneStarted();
    _host.iptvReconnectText.value = null;
    try {
      await _host.player.pause();
    } catch (_) {}
    final ok = await _host.tryOpenLiveStream(
      url,
      httpHeaders: _host.currentIptvChannel?.playbackHeaders,
    );
    if (!_host.mounted || ticket != _host.iptvSwitchTicket) return;
    if (ok) {
      if (key != null) {
        StremioIptvService.instance.markWinner(key, url);
      }
    } else {
      // Failed pick: restore the highlight — leaving it on the dead row
      // would both show a false PLAYING badge and block retrying it (the
      // sheet ignores selecting the "current" source).
      _host.setState(() => _host.currentSourceIndex = previousIndex);
    }
    // Same direct transition-overlay cleanup as switchToIptvChannel — the
    // 'playing' event is unreliable for HLS/live streams.
    _host.transitionStopTimer?.cancel();
    _host.transitionPhaseTimer?.cancel();
    _host.transitionPhase = 2;
    _host.transitionPhase2Started = DateTime.now();
    _host.setState(() {
      _host.isTransitioning = false;
    });
    _host.transitionStopTimer = Timer(const Duration(milliseconds: 1500), () {
      _host.rainbowController.stop();
      _host.transitionRunning = false;
      _host.rainbowActive = false;
      if (_host.mounted) _host.setState(() {});
    });
  }
}
