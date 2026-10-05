import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/pikpak_tv_service.dart';
import 'package:flutter/material.dart';

class DebrifyTvCachedPikPak {
  final DebrifyTvDependencies _deps;
  DebrifyTvCachedPikPak(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watchPikPakWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    String? channelName,
    String? channelId,
    int? channelNumber,
  }) async {
    if (cachedTorrents.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No cached torrents');
      _sections.feedback.showSnack(
        'Cached channel has no torrents yet. Please wait a moment.',
        color: Colors.orange,
      );
      return;
    }

    final List<Map<String, dynamic>>? channelDirectory =
        _owners.library.channels.isNotEmpty
        ? _sections.library.androidTvChannelMetadata(
            activeChannelId:
                channelId ?? _owners.library.currentWatchingChannelId,
          )
        : null;

    void log(String message) {
      debugPrint('DebrifyTV/PikPak: $message');
    }

    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      _sections.feedback.showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _sections.feedback.showCachedPlaybackDialog();

    _owners.session.pikpakCandidatePool = List<Torrent>.from(cachedTorrents);
    _owners.session.pikpakCandidatePool!.shuffle(Random());

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.session.status = 'Preparing PikPak stream...';
        _owners.session.isBusy = true;
        _owners.session.queue
          ..clear()
          ..addAll(_owners.session.pikpakCandidatePool!);
      });
    }

    Future<Map<String, String>?> requestPikPakNext() async {
      if (_owners.session.watchCancelled) return null;

      while (_owners.session.queue.isNotEmpty &&
          !_owners.session.watchCancelled) {
        final next = _owners.session.queue.removeAt(0);
        if (_owners.session.watchCancelled) break;

        if (next is! Torrent) {
          continue;
        }

        final prepared = await _sections.cloud.preparePikPakTorrent(
          candidate: next,
          log: log,
        );

        if (_owners.session.watchCancelled) return null;

        if (prepared == null) {
          continue;
        }

        if (prepared.hasMore) {
          _owners.session.queue.add(next);
        }

        return {
          'url': prepared.streamUrl,
          'title': prepared.title,
          'provider': 'pikpak',
        };
      }
      return null;
    }

    try {
      final first = await requestPikPakNext();
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (!_deps.mounted()) return;
        _deps.setState(() {
          _owners.session.status =
              'No playable PikPak streams found. Try refreshing.';
          _owners.session.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
        _sections.feedback.showSnack(
          'No PikPak streams are playable. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      if (!_deps.mounted()) return;
      _sections.feedback.closeProgressDialog();

      if (await _sections.handoff.handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      // Try Android TV native player first
      final launchedOnTv = await _sections.handoff.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) {
        return;
      }

      // Fall back to Flutter video player (MediaKit)
      MainPageBridge.notifyPlayerLaunching();

      await Navigator.of(_deps.context()).push(
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: first['url'] ?? '',
            title: first['title'] ?? 'Debrify TV',
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestPikPakNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize)
                ? _sections.channelWatch.requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? _sections.channelWatch.requestChannelById
                : null,
          ),
        ),
      );
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.status = _owners.session.queue.isEmpty
              ? ''
              : 'Queue has ${_owners.session.queue.length} remaining';
        });
      }
    } on NativePlayerSettingsUnavailable catch (error) {
      _sections.feedback.showNativeSettingsFailure(error);
    } finally {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.isBusy = false;
      });
    }
  }
}
