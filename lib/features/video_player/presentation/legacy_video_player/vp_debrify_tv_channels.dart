import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/models/channel_entry.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpDebrifyTvChannelsHost {
  Map<String, String>? get activeHttpHeaders;
  List<ChannelEntry> get channelEntries;
  set channelEntries(List<ChannelEntry> v);
  ValueNotifier<bool> get controlsVisible;
  String? get currentChannelId;
  set currentChannelId(String? v);
  set currentChannelName(String? v);
  set currentChannelNumber(int? v);
  set currentStreamUrl(String? v);
  Duration get duration;
  set dynamicTitle(String v);
  set isTransitioning(bool v);
  int get pikPakRetryId;
  set pikPakRetryId(int v);
  mk.Player get player;
  set showChannelGuide(bool v);
  set singleFileImdbFetched(bool v);
  set singleFileImdbId(String? v);
  int get tvScrubGeneration;
  set tvScrubGeneration(int v);
  set tvStaticMessage(String v);
  set tvStaticSubtext(String v);
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
  Future<void> waitForVideoReady();
  Duration? randomStartOffset(Duration total);
  Duration? percentStartOffset(Duration total);
  void raiseDebrifyBanner();
  bool get mounted;
  void setState(VoidCallback fn);
  List<Map<String, dynamic>>? get channelDirectory;
  Future<Map<String, dynamic>?> Function(String)? get requestChannelById;
  Future<Map<String, dynamic>?> Function()? get requestNextChannel;
  bool get startFromRandom;
  double? get startAtPercent;
  void hideIptvZapBanner({bool immediate = false});
  Future<bool> setSubtitleTrackWithDiagnostics(
    mk.SubtitleTrack track, {
    required String source,
    bool Function()? isCurrent,
  });
}

class VpDebrifyTvChannels {
  VpDebrifyTvChannels(this._host);
  final VpDebrifyTvChannelsHost _host;

  /// Parse channel directory from widget params into ChannelEntry list
  void parseChannelDirectory() {
    final directory = _host.channelDirectory;
    if (directory == null || directory.isEmpty) {
      _host.channelEntries = [];
      return;
    }

    _host.channelEntries = directory.asMap().entries.map((e) {
      final entry = ChannelEntry.fromMap(e.value, order: e.key);
      // Check if this is the current channel
      if (entry.isCurrent && _host.currentChannelId == null) {
        _host.currentChannelId = entry.id;
        if (entry.number != null) _host.currentChannelNumber = entry.number;
      }
      return entry;
    }).toList();
  }

  /// Show channel guide overlay
  void showChannelGuideOverlay() {
    if (_host.channelEntries.isEmpty) {
      debugPrint('Player: No channels available for guide');
      return;
    }
    _host.hideIptvZapBanner();
    _host.setState(() {
      _host.showChannelGuide = true;
      _host.controlsVisible.value = false;
    });
  }

  /// Hide channel guide overlay
  void hideChannelGuideOverlay() {
    _host.setState(() {
      _host.showChannelGuide = false;
    });
  }

  /// Switch to a specific channel by ID (from channel guide)
  Future<void> goToChannelById(ChannelEntry channel) async {
    hideChannelGuideOverlay();

    final request = _host.requestChannelById;
    if (request == null) {
      debugPrint('Player: requestChannelById not provided');
      return;
    }

    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
      _host.currentChannelId = channel.id;
      _host.currentChannelName = channel.name;
      if (channel.number != null) {
        _host.currentChannelNumber = channel.number;
      }
    });
    _host.startTransitionOverlay();

    try {
      await _host.player.pause();
    } catch (_) {}

    Map<String, dynamic>? payload;
    try {
      payload = await request(channel.id);
    } catch (e) {
      debugPrint('Player: Channel switch by ID failed: $e');
    }

    if (!_host.mounted) return;

    if (payload == null) {
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

    final dynamic rawUrl = payload['firstUrl'] ?? payload['url'];
    final dynamic rawTitle = payload['firstTitle'] ?? payload['title'];
    final String nextUrl = rawUrl is String ? rawUrl : '';
    final String nextTitle = rawTitle is String ? rawTitle : '';

    // Update channel metadata from payload if provided
    final String? payloadChannelName = payload['channelName'] is String
        ? (payload['channelName'] as String)
        : null;
    final String? payloadChannelId = payload['channelId'] is String
        ? (payload['channelId'] as String)
        : null;
    final dynamic channelNumberRaw = payload['channelNumber'];
    int? payloadChannelNumber;
    if (channelNumberRaw is int) {
      payloadChannelNumber = channelNumberRaw;
    } else if (channelNumberRaw is String) {
      payloadChannelNumber = int.tryParse(channelNumberRaw);
    }

    _host.setState(() {
      if (payloadChannelId != null) _host.currentChannelId = payloadChannelId;
      if (payloadChannelName != null && payloadChannelName.trim().isNotEmpty) {
        _host.currentChannelName = payloadChannelName;
      }
      if (payloadChannelNumber != null) {
        _host.currentChannelNumber = payloadChannelNumber;
      }
    });

    _host.raiseDebrifyBanner();

    if (nextUrl.isEmpty) {
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL HAS NO STREAMS';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

    if (nextTitle.isNotEmpty) {
      _host.setState(() {
        _host.tvStaticMessage = '📺 SIGNAL ACQUIRED';
        _host.tvStaticSubtext = '▶ ${nextTitle.toUpperCase()}';
      });
    }

    // Clear subtitle and IMDB state when switching channels
    _host.resetSubtitleState();
    _host.singleFileImdbId = null;
    _host.singleFileImdbFetched = false;

    try {
      _host.pikPakRetryId++;
      await _host.openMedia(
        mk.Media(nextUrl, httpHeaders: _host.activeHttpHeaders),
        play: true,
      );
      _host.currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _host.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'channel-switch-disable-auto',
      );
    } catch (e) {
      debugPrint('Player: Failed to open channel stream: $e');
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

    if (_host.mounted) {
      _host.setState(() {
        _host.isTransitioning = false;
        if (nextTitle.isNotEmpty) {
          _host.dynamicTitle = nextTitle;
        }
      });
    }
  }

  /// Switch to the next Debrify TV channel (MediaKit fallback)
  Future<void> goToNextChannel() async {
    final request = _host.requestNextChannel;
    if (request == null) {
      return;
    }

    _host.clearBufferingIndicator();
    _host.setState(() {
      _host.isTransitioning = true;
      _host.tvScrubGeneration++;
      _host.tvAbandonScrub();
    });
    _host.startTransitionOverlay();

    try {
      await _host.player.pause();
    } catch (_) {}

    Map<String, dynamic>? payload;
    try {
      payload = await request();
    } catch (e) {
      debugPrint('Player: Next channel request failed: $e');
    }

    if (!_host.mounted) {
      return;
    }

    if (payload == null) {
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

    final dynamic rawUrl = payload['firstUrl'] ?? payload['url'];
    final dynamic rawTitle = payload['firstTitle'] ?? payload['title'];
    final String nextUrl = rawUrl is String ? rawUrl : '';
    final String nextTitle = rawTitle is String ? rawTitle : '';

    final String? channelName = payload['channelName'] is String
        ? (payload['channelName'] as String)
        : null;
    final String? channelId = payload['channelId'] is String
        ? (payload['channelId'] as String)
        : null;
    final dynamic channelNumberRaw = payload['channelNumber'];
    int? channelNumber;
    if (channelNumberRaw is int) {
      channelNumber = channelNumberRaw;
    } else if (channelNumberRaw is String) {
      channelNumber = int.tryParse(channelNumberRaw);
    }

    if ((channelName != null && channelName.trim().isNotEmpty) ||
        channelNumber != null ||
        channelId != null) {
      _host.setState(() {
        if (channelId != null) {
          _host.currentChannelId = channelId;
        }
        if (channelName != null && channelName.trim().isNotEmpty) {
          _host.currentChannelName = channelName;
        }
        if (channelNumber != null) {
          _host.currentChannelNumber = channelNumber;
        }
      });
      _host.raiseDebrifyBanner();
    }

    if (nextUrl.isEmpty) {
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL HAS NO STREAMS';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

    if (nextTitle.isNotEmpty) {
      _host.setState(() {
        _host.tvStaticMessage = '📺 SIGNAL ACQUIRED';
        _host.tvStaticSubtext = '▶ ${nextTitle.toUpperCase()}';
      });
    }

    // Clear subtitle and IMDB state when switching channels
    _host.resetSubtitleState();
    _host.singleFileImdbId = null;
    _host.singleFileImdbFetched = false;

    try {
      // Cancel any ongoing PikPak retry when switching channels
      _host.pikPakRetryId++;
      await _host.openMedia(
        mk.Media(nextUrl, httpHeaders: _host.activeHttpHeaders),
        play: true,
      );
      _host.currentStreamUrl = nextUrl;
      // Disable auto-enabled embedded subtitles to prevent duplicates
      await _host.setSubtitleTrackWithDiagnostics(
        mk.SubtitleTrack.no(),
        source: 'next-channel-disable-auto',
      );
    } catch (e) {
      debugPrint('Player: Failed to open next channel stream: $e');
      _host.setState(() {
        _host.tvStaticMessage = '⚠ CHANNEL SWITCH FAILED';
        _host.tvStaticSubtext = '';
        _host.isTransitioning = false;
      });
      return;
    }

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

    if (_host.mounted) {
      _host.setState(() {
        if (nextTitle.isNotEmpty) {
          _host.dynamicTitle = nextTitle;
        }
        _host.isTransitioning = false;
      });
    }
  }
}
