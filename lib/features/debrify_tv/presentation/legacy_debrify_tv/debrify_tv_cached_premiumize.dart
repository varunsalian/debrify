import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/cache_results.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:flutter/material.dart';

class DebrifyTvCachedPremiumize {
  final DebrifyTvDependencies _deps;
  DebrifyTvCachedPremiumize(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watchPremiumizeWithCachedTorrents(
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

    void log(String message) => debugPrint('DebrifyTV/PM: $message');

    final integrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      _sections.feedback.showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      MainPageBridge.notifyAutoLaunchFailed('No Premiumize API key');
      _sections.feedback.showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _sections.feedback.showCachedPlaybackDialog();

    final List<Torrent> candidatePool = List<Torrent>.from(cachedTorrents);
    candidatePool.shuffle(Random());

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.session.status = 'Checking Premiumize cache...';
        _owners.session.isBusy = true;
      });
    }

    int candidateCursor = 0;

    Future<bool> populateQueue() async {
      while (true) {
        if (candidateCursor >= candidatePool.length) return false;
        final TorboxCacheWindowResult window = await _sections.cloud
            .fetchPremiumizeCacheWindow(
              candidates: candidatePool,
              startIndex: candidateCursor,
              apiKey: apiKey,
            );
        candidateCursor = window.nextCursor;
        if (window.cachedTorrents.isEmpty) {
          if (window.exhausted) return false;
          continue;
        }
        _owners.session.queue
          ..clear()
          ..addAll(window.cachedTorrents);
        _owners.session.lastQueueSize = _owners.session.queue.length;
        _owners.session.lastSearchAt = DateTime.now();
        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.status = _owners.session.queue.isEmpty
                ? ''
                : 'Queue has ${_owners.session.queue.length} remaining';
          });
        }
        log(
          '✅ Cached Premiumize batch ready with ${_owners.session.queue.length} item(s)',
        );
        return true;
      }
    }

    bool seeded;
    try {
      seeded = await populateQueue();
    } catch (e) {
      _sections.feedback.closeProgressDialog();
      _sections.feedback.showSnack(
        'Premiumize cache check failed: $e',
        color: Colors.orange,
      );
      if (_deps.mounted()) _deps.setState(() => _owners.session.isBusy = false);
      return;
    }

    if (!seeded) {
      _sections.feedback.closeProgressDialog();
      _sections.feedback.showSnack(
        'No cached torrents found on Premiumize. Please refresh the channel.',
        color: Colors.orange,
      );
      if (_deps.mounted()) _deps.setState(() => _owners.session.isBusy = false);
      return;
    }

    Future<Map<String, String>?> requestPremiumizeNext() async {
      while (true) {
        if (_owners.session.queue.isEmpty) {
          bool replenished;
          try {
            replenished = await populateQueue();
          } catch (e) {
            _sections.feedback.closeProgressDialog();
            _sections.feedback.showSnack(
              'Premiumize cache check failed: $e',
              color: Colors.orange,
            );
            if (_deps.mounted())
              _deps.setState(() => _owners.session.isBusy = false);
            return null;
          }
          if (!replenished) break;
        }
        if (_owners.session.queue.isEmpty) break;

        final next = _owners.session.queue.removeAt(0);
        if (next is! Torrent) continue;

        final prepared = await _sections.cloud.preparePremiumizeTorrent(
          candidate: next,
          apiKey: apiKey,
          log: log,
        );
        if (prepared == null) continue;
        if (prepared.hasMore) candidatePool.add(next);
        return {'url': prepared.streamUrl, 'title': prepared.title};
      }
      return null;
    }

    try {
      final first = await requestPremiumizeNext();
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (!_deps.mounted()) return;
        _deps.setState(() {
          _owners.session.status =
              'No playable Premiumize streams found. Try refreshing.';
          _owners.session.isBusy = false;
        });
        MainPageBridge.notifyAutoLaunchFailed(
          'No cached Premiumize streams available',
        );
        _sections.feedback.showSnack(
          'No cached Premiumize streams are playable. Try refreshing the channel.',
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

      final launchedOnTv = await _sections.handoff.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );
      if (launchedOnTv) return;

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
            requestMagicNext: requestPremiumizeNext,
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
      _deps.setState(() => _owners.session.isBusy = false);
    }
  }
}
