import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpStremioTvChannelsHost {
  ValueNotifier<bool> get controlsVisible;
  set currentSourceIndex(int v);
  set currentStreamUrl(String? v);
  String? get currentStremioTvChannelId;
  set currentStremioTvChannelId(String? v);
  set currentStremioTvContentEpisode(int? v);
  set currentStremioTvContentImdbId(String? v);
  set currentStremioTvContentSeason(int? v);
  set currentStremioTvContentTitle(String? v);
  set currentStremioTvContentType(String? v);
  String get dynamicTitle;
  set dynamicTitle(String v);
  List<Map<String, dynamic>>? get effectiveStremioTvChannels;
  bool get hasStremioTvGuide;
  set isTransitioning(bool v);
  int get pikPakRetryId;
  set pikPakRetryId(int v);
  mk.Player get player;
  set rainbowActive(bool v);
  AnimationController get rainbowController;
  set resolveStremioSourceOverride(Future<String?> Function(Torrent)? v);
  set showStremioTvGuide(bool v);
  bool get showStremioTvNextLoading;
  set showStremioTvNextLoading(bool v);
  set singleFileImdbFetched(bool v);
  set singleFileImdbId(String? v);
  set stremioSourcesOverride(List<Torrent>? v);
  set stremioTvChannelsOverride(List<Map<String, dynamic>>? v);
  set transitionPhase(int v);
  set transitionPhase2Started(DateTime? v);
  Timer? get transitionPhaseTimer;
  set transitionRunning(bool v);
  Timer? get transitionStopTimer;
  set transitionStopTimer(Timer? v);
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  void tvAbandonScrub();
  void clearBufferingIndicator();
  void startTransitionOverlay();
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
  bool get mounted;
  void setState(VoidCallback fn);
  String? get stremioTvCurrentChannelId;
  Future<Map<String, dynamic>?> Function(String)? get stremioTvNextProvider;
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
  void resetLocalCompletionState();
}

class VpStremioTvChannels {
  VpStremioTvChannels(this._host);
  final VpStremioTvChannelsHost _host;

  // ─── Stremio TV Guide ─────────────────────────────────────────────

  String? findInitialStremioTvChannelId() {
    // Use explicitly provided current channel ID
    if (_host.stremioTvCurrentChannelId != null) {
      return _host.stremioTvCurrentChannelId;
    }
    return null;
  }

  void showStremioTvGuideOverlay() {
    if (!_host.hasStremioTvGuide) return;
    _host.setState(() {
      _host.showStremioTvGuide = true;
      _host.controlsVisible.value = false;
    });
  }

  void hideStremioTvGuide() {
    _host.setState(() {
      _host.showStremioTvGuide = false;
    });
  }

  void setStremioTvNextLoading(bool loading) {
    if (!_host.mounted || _host.showStremioTvNextLoading == loading) return;
    _host.setState(() {
      _host.showStremioTvNextLoading = loading;
    });
  }

  void applyStremioTvGuidePlaybackData(
    String channelId, {
    Map<String, dynamic>? nowPlaying,
    Map<String, dynamic>? nextUp,
  }) {
    final current = _host.effectiveStremioTvChannels;
    if (current == null || current.isEmpty) return;

    _host.stremioTvChannelsOverride = current
        .map((entry) {
          final copy = Map<String, dynamic>.from(entry);
          if (copy['id'] == channelId) {
            if (nowPlaying != null) {
              copy['nowPlaying'] = Map<String, dynamic>.from(nowPlaying);
            }
            if (nextUp != null) {
              copy['nextUp'] = Map<String, dynamic>.from(nextUp);
            }
          }
          return copy;
        })
        .toList(growable: false);
  }

  List<Torrent>? parseStremioTvSources(dynamic rawSources) {
    if (rawSources is! List) return null;
    return rawSources
        .map(
          (s) =>
              s is Map ? Torrent.fromJson(Map<String, dynamic>.from(s)) : null,
        )
        .whereType<Torrent>()
        .toList();
  }

  Future<void> switchToStremioTvChannel(
    String channelId,
    String url,
    String title, {
    String? contentImdbId,
    String? contentType,
    int? contentSeason,
    int? contentEpisode,
    Map<String, dynamic>? nowPlaying,
    Map<String, dynamic>? nextUp,
    double? startAtPercent,
    List<Torrent>? newSources,
    int? newSourceIndex,
    Future<String?> Function(Torrent)? sourceResolver,
  }) async {
    hideStremioTvGuide();
    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
      _host.currentStremioTvChannelId = channelId;
      _host.dynamicTitle = title;
      _host.currentStremioTvContentImdbId = contentImdbId;
      _host.currentStremioTvContentType = contentType;
      _host.currentStremioTvContentSeason = contentSeason;
      _host.currentStremioTvContentEpisode = contentEpisode;
      _host.currentStremioTvContentTitle = title;
      applyStremioTvGuidePlaybackData(
        channelId,
        nowPlaying: nowPlaying,
        nextUp: nextUp,
      );
      if (newSources != null) {
        _host.stremioSourcesOverride = newSources;
        _host.currentSourceIndex = newSourceIndex ?? 0;
      }
      if (sourceResolver != null) {
        _host.resolveStremioSourceOverride = sourceResolver;
      }
    });
    _host.startTransitionOverlay();

    try {
      await _host.player.pause();
    } catch (_) {}

    _host.resetSubtitleState();
    _host.singleFileImdbId = null;
    _host.singleFileImdbFetched = false;
    _host.resetLocalCompletionState();

    try {
      _host.pikPakRetryId++;
      await _host.openMedia(mk.Media(url), play: true);
      _host.currentStreamUrl = url;
      await _host.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'stremio-tv-switch-disable-auto',
      );
      if (startAtPercent != null && startAtPercent > 0) {
        // Apply start position once duration is known
        _host.player.stream.duration.firstWhere((d) => d > Duration.zero).then((
          d,
        ) {
          if (_host.mounted) {
            final seekTo = Duration(
              milliseconds: (d.inMilliseconds * startAtPercent).round(),
            );
            _host.player.seek(seekTo);
          }
        });
      }
    } catch (e) {
      debugPrint('Player: Stremio TV channel switch failed: $e');
    }

    if (!_host.mounted) return;

    // End transition
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

  Future<bool> goToNextStremioTvSlot({
    bool resumeCurrentOnFailure = true,
  }) async {
    final requestNext = _host.stremioTvNextProvider;
    final channelId = _host.currentStremioTvChannelId;
    if (requestNext == null || channelId == null || channelId.isEmpty) {
      return false;
    }
    if (_host.showStremioTvNextLoading) {
      return true;
    }

    Map<String, dynamic>? result;
    setStremioTvNextLoading(true);
    try {
      result = await requestNext(channelId);
    } catch (e) {
      debugPrint('Player: Stremio TV next failed: $e');
    }

    if (!_host.mounted) return true;
    setStremioTvNextLoading(false);

    if (result == null) {
      _host.setState(() => _host.isTransitioning = false);
      if (!resumeCurrentOnFailure) return false;
      try {
        await _host.player.play();
      } catch (_) {}
      return true;
    }

    final url = result['url'] as String?;
    final title = result['title'] as String? ?? _host.dynamicTitle;
    if (url == null || url.isEmpty) {
      _host.setState(() => _host.isTransitioning = false);
      if (!resumeCurrentOnFailure) return false;
      try {
        await _host.player.play();
      } catch (_) {}
      return true;
    }

    final newSources = parseStremioTvSources(result['stremioSources']);
    final sourceResolver =
        result['sourceResolver'] as Future<String?> Function(Torrent)?;

    await switchToStremioTvChannel(
      result['channelId'] as String? ?? channelId,
      url,
      title,
      contentImdbId: result['contentImdbId'] as String?,
      contentType: result['contentType'] as String?,
      contentSeason: (result['contentSeason'] as num?)?.toInt(),
      contentEpisode: (result['contentEpisode'] as num?)?.toInt(),
      nowPlaying: result['nowPlaying'] is Map
          ? Map<String, dynamic>.from(result['nowPlaying'] as Map)
          : null,
      nextUp: result['nextUp'] is Map
          ? Map<String, dynamic>.from(result['nextUp'] as Map)
          : null,
      startAtPercent: (result['startAtPercent'] as num?)?.toDouble(),
      newSources: newSources,
      newSourceIndex: (result['stremioCurrentSourceIndex'] as num?)?.toInt(),
      sourceResolver: sourceResolver,
    );
    return true;
  }
}
