import 'dart:async';
import 'package:debrify/features/video_player/models/iptv_catchup_request_gate.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/iptv_live_recovery.dart';
import 'package:debrify/screens/video_player/services/iptv_tune_diagnostics.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpIptvGuideCatchupHost {
  ValueNotifier<bool> get controlsVisible;
  IptvChannel? get currentIptvChannel;
  int get currentIptvIndex;
  Duration get duration;
  List<IptvChannel>? get effectiveIptvChannels;
  void hideIptvZapBanner({bool immediate = false});
  set iptvChannelsOverride(List<IptvChannel>? v);
  IptvTuneDiagnostics get iptvDiag;
  int get iptvGuideContextGeneration;
  set iptvGuideContextGeneration(int v);
  IptvGuideContext? get iptvGuideContextOverride;
  set iptvGuideContextOverride(IptvGuideContext? v);
  IptvLiveRecovery get iptvLiveRecovery;
  bool iptvRecoveryEligible();
  bool get iptvStartOverActive;
  set iptvStartOverActive(bool v);
  bool get iptvStartOverLoading;
  set iptvStartOverLoading(bool v);
  bool get iptvStartOverTimelineRequested;
  set iptvStartOverTimelineRequested(bool v);
  int get iptvSwitchTicket;
  EpgNowNext? get iptvZapEpg;
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
  Future<void> reanchorIptvRingToCategory(
    IptvChannel channel, {
    required int switchTicket,
  });
  void resetIptvZapPaging();
  void scheduleAutoHide();
  set showIptvChannelSheet(bool v);
  Future<void> stopRecording({bool userInitiated = true});
  Future<void> switchToIptvChannel(int index, {bool quietRecovery = false});
  FocusNode get tvProgressFocus;
  bool get mounted;
  BuildContext get context;
  void setState(VoidCallback fn);
  String? get iptvSourceId;
  List<String>? get iptvCategories;
  String? get iptvContentType;
  String? get iptvSourceName;
}

class VpIptvGuideCatchup {
  VpIptvGuideCatchup(this._host);
  final VpIptvGuideCatchupHost _host;

  final IptvCatchupRequestGate iptvCatchupRequests = IptvCatchupRequestGate();

  bool get iptvStartOverTimelineVisible =>
      _host.iptvStartOverActive &&
      _host.iptvStartOverTimelineRequested &&
      _host.duration > Duration.zero;

  void toggleIptvStartOverTimeline() {
    if (!_host.iptvStartOverActive) return;
    if (_host.duration <= Duration.zero) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(content: Text('Timeline is still loading')),
      );
      return;
    }
    final reveal = !_host.iptvStartOverTimelineRequested;
    _host.setState(() => _host.iptvStartOverTimelineRequested = reveal);
    if (reveal && PlatformUtil.isTelevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_host.mounted && iptvStartOverTimelineVisible) {
          _host.tvProgressFocus.requestFocus();
        }
      });
    }
    _host.scheduleAutoHide();
  }

  bool get canStartOverCurrentIptv {
    final channel = _host.currentIptvChannel;
    final programme = _host.iptvZapEpg?.now;
    return channel != null &&
        channel.isLive &&
        programme != null &&
        programme.airsAt(DateTime.now()) &&
        IptvEpgService.isStartOverAvailable(channel, programme);
  }

  VoidCallback? get iptvLiveEdgeAction =>
      _host.iptvStartOverActive || canStartOverCurrentIptv
      ? () => unawaited(toggleIptvStartOver())
      : null;

  Future<void> toggleIptvStartOver() async {
    if (_host.iptvStartOverLoading) return;
    if (_host.iptvStartOverActive) {
      _host.setState(() {
        _host.iptvStartOverActive = false;
        _host.iptvStartOverTimelineRequested = false;
      });
      await _host.switchToIptvChannel(_host.currentIptvIndex);
      return;
    }

    final channel = _host.currentIptvChannel;
    final programme = _host.iptvZapEpg?.now;
    if (channel == null ||
        programme == null ||
        !programme.airsAt(DateTime.now()) ||
        !IptvEpgService.isStartOverAvailable(channel, programme)) {
      return;
    }

    await startIptvProgrammeFromBeginning(channel, programme);
  }

  Future<void> startIptvProgrammeFromBeginning(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    final requestTicket = beginIptvCatchupRequest();
    final switchTicket = _host.iptvSwitchTicket;
    _host.setState(() => _host.iptvStartOverLoading = true);
    String? url;
    try {
      url = await IptvEpgService.instance.catchupUrl(channel.url, programme);
    } catch (error) {
      debugPrint('Player: IPTV start-over lookup failed: $error');
    }
    if (!isCurrentIptvCatchupRequest(requestTicket) ||
        switchTicket != _host.iptvSwitchTicket ||
        _host.currentIptvChannel?.url != channel.url) {
      return;
    }
    if (url == null) {
      iptvCatchupRequests.complete(requestTicket);
      _host.setState(() => _host.iptvStartOverLoading = false);
      if (!_host.mounted) return;
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(content: Text('Start over is not available')),
      );
      return;
    }

    await _host.stopRecording(userInitiated: false);
    if (!isCurrentIptvCatchupRequest(requestTicket) ||
        switchTicket != _host.iptvSwitchTicket ||
        _host.currentIptvChannel?.url != channel.url) {
      return;
    }
    _host.iptvDiag.onTuneStart(channel.name, url, isLive: true);
    _host.iptvLiveRecovery.onTuneStarted();
    try {
      await _host.openMedia(
        mk.Media(url, httpHeaders: channel.playbackHeaders),
        play: true,
        liveStream: true,
        beforeOpen: () {
          if (!isCurrentIptvCatchupRequest(requestTicket) ||
              switchTicket != _host.iptvSwitchTicket ||
              _host.currentIptvChannel?.url != channel.url) {
            return false;
          }
          iptvCatchupRequests.complete(requestTicket);
          _host.setState(() {
            _host.iptvStartOverLoading = false;
            _host.iptvStartOverActive = true;
            _host.iptvStartOverTimelineRequested = false;
          });
          return true;
        },
      );
    } catch (error) {
      debugPrint('Player: IPTV start-over failed to open: $error');
      if (!_host.mounted || switchTicket != _host.iptvSwitchTicket) return;
      if (!_host.iptvStartOverActive &&
          !isCurrentIptvCatchupRequest(requestTicket)) {
        return;
      }
      cancelPendingIptvCatchup(hideFeedback: false);
      if (_host.iptvRecoveryEligible()) {
        _host.setState(() {
          _host.iptvStartOverActive = false;
          _host.iptvStartOverTimelineRequested = false;
        });
        await _host.switchToIptvChannel(
          _host.currentIptvIndex,
          quietRecovery: true,
        );
      }
    }
  }

  void persistIptvGuideContext(IptvGuideContext context) {
    if (!_host.mounted) return;
    _host.iptvGuideContextGeneration++;
    _host.setState(() => _host.iptvGuideContextOverride = context);
  }

  /// Make the guide's selected category follow the playing channel.
  ///
  /// The native player re-anchors its browsing context to the playing
  /// channel's group on every tune and every pick. Here the category only
  /// ever moved when the user chose one, so after zapping — or after picking
  /// a channel from a different category — reopening the guide showed a
  /// category that no longer contained what was on screen.
  void anchorIptvGuideCategory(IptvChannel channel, {Object? categories}) {
    if (!_host.mounted || !channel.isLive) return;
    final group = channel.group?.trim();
    applyIptvGuideCategory(
      (group == null || group.isEmpty) ? null : group,
      categories is List ? categories.whereType<String>().toList() : null,
    );
  }

  /// Point the guide at [category] verbatim, without inferring it from a
  /// channel. A zap that crossed a category boundary knows the category it
  /// landed in from the response — including the null the "All"/uncategorized
  /// wrap lands on, which no single channel's group can express.
  ///
  /// Deliberately does NOT bump [_iptvGuideContextGeneration]: that counter
  /// means "the user browsed", and an in-flight zap prefetch reading it must
  /// not be invalidated by the zap's own bookkeeping.
  void applyIptvGuideCategory(String? category, List<String>? categories) {
    if (!_host.mounted) return;
    final current = _host.iptvGuideContextOverride;
    final nextCategories =
        categories ??
        (current?.categories ?? _host.iptvCategories ?? const <String>[]);
    if (current != null &&
        current.selectedCategory == category &&
        listEquals(nextCategories, current.categories)) {
      return;
    }
    _host.setState(() {
      _host.iptvGuideContextOverride = IptvGuideContext(
        categories: nextCategories,
        sourceId: current?.sourceId ?? _host.iptvSourceId,
        // Same fallback the sheet applies to a nameless source.
        sourceName: current?.sourceName ?? _host.iptvSourceName ?? 'IPTV',
        selectedCategory: category,
        contentType: current?.contentType ?? _host.iptvContentType ?? 'live',
      );
    });
  }

  void cancelPendingIptvCatchup({bool hideFeedback = true}) {
    final canceled = iptvCatchupRequests.cancel();
    if (_host.iptvStartOverLoading && _host.mounted) {
      _host.setState(() => _host.iptvStartOverLoading = false);
    }
    if (canceled && hideFeedback && _host.mounted) {
      ScaffoldMessenger.maybeOf(_host.context)?.hideCurrentSnackBar();
    }
  }

  int beginIptvCatchupRequest() {
    cancelPendingIptvCatchup();
    return iptvCatchupRequests.begin();
  }

  bool isCurrentIptvCatchupRequest(int ticket) =>
      _host.mounted && iptvCatchupRequests.isCurrent(ticket);

  /// Show IPTV channel sheet overlay
  void showIptvChannelSheetOverlay() {
    final channels = _host.effectiveIptvChannels;
    if (channels == null || channels.isEmpty) return;
    _host.hideIptvZapBanner();
    _host.setState(() {
      _host.showIptvChannelSheet = true;
      _host.controlsVisible.value = false;
    });
  }

  /// Hide IPTV channel sheet overlay
  void hideIptvChannelSheet() {
    cancelPendingIptvCatchup();
    _host.setState(() {
      _host.showIptvChannelSheet = false;
    });
  }

  /// A full-catalog guide result is not necessarily part of the launch
  /// window. Adopt the result set before tuning so every player read uses the
  /// selected channel's real index and metadata.
  Future<void> switchToIptvGuideChannel(
    List<IptvChannel> channels,
    int index,
  ) async {
    if (index < 0 || index >= channels.length) return;
    cancelPendingIptvCatchup();
    final channel = channels[index];
    // Adopt the visible list first so playback starts immediately; the
    // re-anchor below then replaces it with the channel's own category.
    // A browse result is not a page of any category, so the zap window's
    // coordinates stop describing the ring until the re-anchor lands.
    _host.resetIptvZapPaging();
    _host.iptvChannelsOverride = List<IptvChannel>.from(channels);
    // Take this tune's generation from the call itself. VpIptvChannelSwitch.switchToIptvChannel
    // bumps the ticket synchronously before its first await, and it returns
    // normally when a newer tune supersedes it — so reading the ticket AFTER
    // the await would read the newer tune's value and defeat every staleness
    // check downstream.
    final switchFuture = _host.switchToIptvChannel(index);
    final switchTicket = _host.iptvSwitchTicket;
    await switchFuture;
    if (!_host.mounted || switchTicket != _host.iptvSwitchTicket) return;
    unawaited(
      _host.reanchorIptvRingToCategory(channel, switchTicket: switchTicket),
    );
  }

  /// Turn an archived EPG programme into a finite, seekable IPTV item in the
  /// current player. The normal IPTV switching path remains responsible for
  /// headers, transition feedback, tracks, and resume identity.
  Future<void> playIptvCatchup(
    IptvChannel channel,
    EpgProgramme programme,
  ) async {
    if (programme.airsAt(DateTime.now())) {
      final channels = _host.effectiveIptvChannels;
      final index = channels?.indexWhere(
        (candidate) => candidate.url == channel.url,
      );
      if (index != null && index >= 0 && index != _host.currentIptvIndex) {
        await _host.switchToIptvChannel(index);
      }
      final current = _host.currentIptvChannel;
      if (current != null && current.url == channel.url) {
        await startIptvProgrammeFromBeginning(current, programme);
      }
      return;
    }
    final requestTicket = beginIptvCatchupRequest();
    final messenger = ScaffoldMessenger.of(_host.context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Preparing replay of "${programme.title}"…'),
        duration: const Duration(seconds: 30),
      ),
    );
    String? url;
    try {
      url = await IptvEpgService.instance.catchupUrl(channel.url, programme);
    } catch (error) {
      debugPrint('Player: IPTV replay lookup failed: $error');
    }
    if (!isCurrentIptvCatchupRequest(requestTicket)) return;
    if (url == null) {
      iptvCatchupRequests.complete(requestTicket);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Replay is not available')),
      );
      return;
    }

    final sourceId =
        channel.attributes['source_playlist_id'] ??
        _host.iptvGuideContextOverride?.sourceId ??
        _host.iptvSourceId;
    final replay = IptvChannel(
      name: programme.title,
      url: url,
      logoUrl: channel.logoUrl,
      group: channel.name,
      contentType: 'vod',
      httpHeaders: channel.httpHeaders,
      attributes: {if (sourceId != null) 'source_playlist_id': sourceId},
    );
    await IptvHistoryStorage.recordIptvWatch(
      replay.url,
      channelName: replay.name,
      logoUrl: replay.logoUrl,
      group: replay.group,
      playlistId: sourceId,
      httpHeaders: replay.httpHeaders,
    );
    if (!isCurrentIptvCatchupRequest(requestTicket)) return;
    iptvCatchupRequests.complete(requestTicket);
    messenger.hideCurrentSnackBar();
    // A replay is a single on-demand item, not a page of any category.
    _host.resetIptvZapPaging();
    _host.iptvChannelsOverride = [replay];
    await _host.switchToIptvChannel(0);
  }
}
