import 'dart:async';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpIptvLiveSourcesHost {
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  set currentSourceIndex(int v);
  List<IptvChannel>? get effectiveIptvChannels;
  String? get iptvChannelKey;
  set iptvChannelKey(String? v);
  IptvTuneDiagnostics get iptvDiag;
  bool get iptvErrorsMuted;
  IptvLiveRecovery get iptvLiveRecovery;
  bool iptvRecoveryEligible();
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  set iptvStartOverTimelineRequested(bool v);
  DateTime? get lastIptvErrorShown;
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
  mk.Player get player;
  Future<String?> Function(Torrent)? get resolveStremioSourceOverride;
  set resolveStremioSourceOverride(Future<String?> Function(Torrent)? v);
  Future<void> stopRecording({bool userInitiated = true});
  List<Torrent>? get stremioSourcesOverride;
  set stremioSourcesOverride(List<Torrent>? v);
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  int? get iptvStartIndex;
  String get videoUrl;
}

class VpIptvLiveSources {
  VpIptvLiveSources(this._host);
  final VpIptvLiveSourcesHost _host;

  /// A plain IPTV channel's stream failed. Say so — the alternative (and the
  /// pre-existing behavior) is an indefinite black screen that reads as the
  /// whole IPTV section being broken.
  void onIptvStreamError(String error) {
    _host.iptvDiag.onError(error);
    if (!_host.mounted || _host.iptvErrorsMuted) return;
    final channels = _host.effectiveIptvChannels;
    if (channels == null) return;

    // mpv reports HTTP rejection on its error stream even when open()
    // completes normally. An archive failure must return to the live URL
    // before AUTH classification can bypass the recovery ladder.
    if (_host.iptvStartOverActive && _host.currentIptvChannel?.isLive == true) {
      if (_host.iptvRecoveryEligible()) {
        _host.setState(() {
          _host.iptvStartOverActive = false;
          _host.iptvStartOverTimelineRequested = false;
        });
        unawaited(
          _host.switchToIptvChannel(
            _host.currentIptvIndex,
            quietRecovery: true,
          ),
        );
      }
      return;
    }

    // Phase 2: a live channel's error goes to the recovery machine first —
    // the snackbar below is now the SURRENDER voice (via the machine's
    // onSurrender), not the first response. Non-live keeps the old
    // say-it-immediately behavior. Auth-class failures (mpv's error string
    // is all we have — best-effort match) skip the ladder entirely: a
    // 401/403/404 repeats deterministically, so say so NOW instead of
    // retrying for 75 seconds (mirror of the TV policy's AUTH class).
    final looksAuthError = RegExp(r'\b(401|403|404)\b').hasMatch(error);
    if (_host.currentIptvChannel?.isLive == true &&
        !looksAuthError &&
        _host.iptvLiveRecovery.onError()) {
      return;
    }

    final now = DateTime.now();
    final last = _host.lastIptvErrorShown;
    if (last != null && now.difference(last) < const Duration(seconds: 6)) {
      return;
    }
    _host.lastIptvErrorShown = now;

    final name =
        (_host.currentIptvIndex >= 0 &&
            _host.currentIptvIndex < channels.length)
        ? channels[_host.currentIptvIndex].name
        : 'This channel';
    debugPrint('Player: IPTV stream error on "$name": $error');
    ScaffoldMessenger.of(_host.context).showSnackBar(
      SnackBar(
        content: Text("$name didn't play — $error"),
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// Surface a Stremio IPTV channel's candidate links in the existing source
  /// sheet: the candidates become direct-URL [Torrent] rows via the override
  /// the sheet already honors. Null/empty clears the sheet (plain M3U
  /// channels have exactly one link — nothing to pick).
  void setIptvSources(
    String? channelKey,
    List<StremioIptvCandidate>? candidates, {
    int currentIndex = 0,
  }) {
    if (!_host.mounted) return;
    _host.iptvChannelKey = channelKey;
    if (channelKey == null || candidates == null || candidates.isEmpty) {
      if (_host.stremioSourcesOverride != null ||
          _host.resolveStremioSourceOverride != null) {
        _host.setState(() {
          _host.stremioSourcesOverride = null;
          _host.resolveStremioSourceOverride = null;
        });
      }
      return;
    }
    final sources = <Torrent>[
      for (var i = 0; i < candidates.length; i++)
        Torrent(
          rowid: i,
          // Same synthetic-hash convention _convertToTorrents uses for
          // direct-URL streams (stable per-URL dedupe key, not a real hash).
          infohash:
              'url:${candidates[i].url.hashCode.toRadixString(16).padLeft(40, '0')}',
          name: candidates[i].label,
          sizeBytes: 0,
          createdUnix: 0,
          seeders: 0,
          leechers: 0,
          completed: 0,
          scrapedDate: 0,
          source: 'stremio',
          streamType: StreamType.directUrl,
          directUrl: candidates[i].url,
          hasRealInfoHash: false,
        ),
    ];
    _host.setState(() {
      _host.stremioSourcesOverride = sources;
      _host.resolveStremioSourceOverride = (t) async => t.directUrl;
      _host.currentSourceIndex = currentIndex.clamp(0, sources.length - 1);
    });
  }

  /// The launch already resolved the initial channel's URL, but the source
  /// sheet wants the whole candidate list — fetch it (cache hit from the
  /// launch resolve) and populate the override for the starting channel.
  void initIptvStremioSources() {
    final channels = _host.effectiveIptvChannels;
    final idx = _host.iptvStartIndex ?? 0;
    if (channels == null || idx < 0 || idx >= channels.length) return;
    final channel = channels[idx];
    if (!StremioIptvService.isStremioChannelUrl(channel.url)) return;
    StremioIptvService.instance.resolveCandidates(channel.url).then((found) {
      if (!_host.mounted || found.isEmpty) return;
      // The user already zapped away (or a switch populated sources itself).
      if (_host.iptvChannelKey != null || _host.currentIptvIndex != idx) return;
      var current = found.indexWhere((c) => c.url == _host.videoUrl);
      if (current < 0) current = 0;
      setIptvSources(channel.url, found, currentIndex: current);
    });
  }

  /// Open [url] and wait until it demonstrably plays (a decoded video size or
  /// advancing position) or demonstrably fails (player error, open() throw,
  /// or the timeout — live streams can stall without ever erroring). Used by
  /// the Stremio channel ladder to decide whether to try the next candidate.
  Future<bool> tryOpenLiveStream(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
  }) async {
    // Every live media replacement ends the recording, not just a channel zap:
    // picking another row in the Sources sheet lands here via
    // VpIptvChannelSwitch.switchToIptvSource, and mpv makes no promise about `stream-record`
    // across an open() — it may quietly stop or overwrite the file while
    // `_isRecording` still claims it is running. Redundant (and harmless) on
    // the VpIptvChannelSwitch.switchToIptvChannel path, which already stopped before its ladder.
    await _host.stopRecording(userInitiated: false);

    final completer = Completer<bool>();
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    // Position/error events only count after open() returns — the stream can
    // still be draining the previous media's positions (or a dead outgoing
    // channel's queued error) before then. Genuine pre-open failures are
    // covered by the open() throw and the timeout.
    var openDone = false;
    final subs = <StreamSubscription>[
      _host.player.stream.error.listen((_) {
        if (openDone) finish(false);
      }),
      _host.player.stream.width.listen((w) {
        if (openDone && w != null && w > 0) finish(true);
      }),
      _host.player.stream.position.listen((p) {
        if (openDone && p > Duration.zero) finish(true);
      }),
    ];
    try {
      // Plan finding P7: candidate opens used to drop the channel's own
      // headers — the one open path that lost them. Carry them like every
      // other open does.
      await _host.openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        liveStream: true,
      );
      openDone = true;
    } catch (e) {
      debugPrint('Player: stremio candidate failed to open: $e');
      finish(false);
    }
    final ok = await completer.future.timeout(timeout, onTimeout: () => false);
    for (final s in subs) {
      unawaited(s.cancel());
    }
    return ok;
  }
}
