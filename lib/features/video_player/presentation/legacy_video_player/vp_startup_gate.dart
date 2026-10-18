import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpStartupGateHost {
  int get currentSourceIndex;
  int get decoderProbeGeneration;
  Duration get duration;
  List<Torrent>? get effectiveSources;
  bool get isPlaying;
  mk.Player get player;
  int get playerInstanceGeneration;
  int get resumeVerifyEpoch;
  bool get screenDisposed;
  bool get startupGateActive;
  set startupGateActive(bool v);
  String get startupGateMessage;
  set startupGateMessage(String v);
  set startupGateOverlayHidden(bool v);
  DeferredStartupSeek get stremioTvStartupSeek;
  ChannelStartupWatch? get stremioTvStartupWatch;
  set stremioTvStartupWatch(ChannelStartupWatch? v);
  bool get validationGateActive;
  BuildContext get context;
  bool canFallbackExplicitRenderer({
    required int instanceGeneration,
    required int mediaGeneration,
  });
  void setState(VoidCallback fn);
  bool get mounted;
  Future<void> Function()? get onStartupSourcesExhausted;
  String? get traktLastScrobbleAction;
  bool get simklScrobbleEnabled;
  set simklLastScrobbleAction(String? v);
  void traktScrobble(String action);
  void startTraktHeartbeat();
  void startSimklHeartbeat();
  void updateMdblistPosition();
  void mdblistPlay();
}

class VpStartupGate {
  VpStartupGate(this._host);
  final VpStartupGateHost _host;

  void resumeTrackingAfterValidationGate() {
    if (!_host.mounted || _host.validationGateActive) return;
    _host.updateMdblistPosition();
    if (!_host.isPlaying || _host.duration <= Duration.zero) return;
    _host.traktScrobble('start');
    if (_host.traktLastScrobbleAction == 'start') _host.startTraktHeartbeat();
    if (_host.simklScrobbleEnabled) {
      // Simkl uses a local playing marker and pause-based checkpoints; sending
      // its remote "start" would erase the resumable playback entry.
      _host.simklLastScrobbleAction = 'start';
      _host.startSimklHeartbeat();
    }
    _host.mdblistPlay();
  }

  void watchStremioTvStartup(String url) {
    _host.stremioTvStartupWatch?.dispose();
    final epoch = _host.resumeVerifyEpoch;
    final instance = _host.playerInstanceGeneration;
    final mediaGeneration = _host.decoderProbeGeneration;
    final sources = _host.effectiveSources;
    final source =
        sources != null &&
            _host.currentSourceIndex >= 0 &&
            _host.currentSourceIndex < sources.length
        ? sources[_host.currentSourceIndex]
        : null;
    final sourceName = [
      source?.source,
      source?.addonDisplayName,
      source?.name,
    ].whereType<String>().join(' ');
    final isAioStreams = StartupStreamPolicy.isAioStreams(
      addonId: source?.stremioAddonId,
      sourceName: sourceName,
      url: url,
    );
    bool isCurrent() =>
        _host.mounted &&
        !_host.screenDisposed &&
        epoch == _host.resumeVerifyEpoch &&
        instance == _host.playerInstanceGeneration;
    _host.stremioTvStartupWatch = ChannelStartupWatch(
      errors: _host.player.stream.error,
      widths: _host.player.stream.width,
      positions: _host.player.stream.position,
      durations: _host.player.stream.duration,
      completed: _host.player.stream.completed,
      addonId: source?.stremioAddonId,
      sourceName: sourceName,
      url: url,
      isCurrent: isCurrent,
      onReady: () {
        if (isCurrent() && isAioStreams) {
          resumeTrackingAfterValidationGate();
        }
      },
      // Do not depend on which error-stream subscription runs first. The
      // renderer listener owns recoverable output errors; the new backend
      // installs its own watch and can still report an unrecoverable failure.
      shouldDeferError: (error) =>
          AndroidRendererStartupFallback.isRendererFailure(error) &&
          _host.canFallbackExplicitRenderer(
            instanceGeneration: instance,
            mediaGeneration: mediaGeneration,
          ),
      onFailure: () {
        _host.stremioTvStartupSeek.cancel();
        unawaited(reportStartupFailure(isCurrent: isCurrent));
      },
    );
  }

  Future<void> reportStartupFailure({bool Function()? isCurrent}) async {
    bool current() =>
        _host.mounted && !_host.screenDisposed && (isCurrent?.call() ?? true);
    if (!current()) return;
    final canRecover = _host.onStartupSourcesExhausted != null;
    ScaffoldMessenger.of(_host.context).showSnackBar(
      SnackBar(
        content: Text(
          canRecover
              ? 'Saved source failed. Looking for another source…'
              : 'No playable source could be started.',
        ),
      ),
    );
    // A covering dialog may leave later. Only close this player route, and
    // abandon the failure if the viewer has since selected different media.
    final playerRoute = ModalRoute.of(_host.context);
    await Future<void>.delayed(Duration(milliseconds: canRecover ? 250 : 900));
    while (current() && playerRoute?.isActive == true) {
      if (playerRoute?.isCurrent == true) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_host.mounted || !current() || playerRoute?.isCurrent != true) return;
    if (canRecover) {
      Navigator.of(
        _host.context,
      ).pop(<String, dynamic>{'startupSourcesExhausted': true});
    } else {
      Navigator.of(_host.context).maybePop();
    }
  }

  void setStartupGateActive(bool active) {
    if (_host.startupGateActive == active) return;
    _host.startupGateActive = active;
    if (!active) _host.startupGateOverlayHidden = false;
    if (_host.mounted) _host.setState(() {});
  }

  void setStartupGateMessage(String message) {
    if (_host.startupGateMessage == message) return;
    _host.startupGateMessage = message;
    if (_host.mounted && _host.startupGateActive) _host.setState(() {});
  }
}
