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
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvQuickPlayPremiumize {
  final DebrifyTvDependencies _deps;
  DebrifyTvQuickPlayPremiumize(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watchWithPremiumize(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    if (!integrationEnabled) {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status =
            'Enable Premiumize in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      _sections.feedback.showSnack(
        'Enable Premiumize in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status =
            'Add your Premiumize API key in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      _sections.feedback.showSnack(
        'Please add your Premiumize API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 Premiumize: searching for cached torrents...');
    final Map<String, Torrent> dedup = {};
    final engineStates = await _sections.engines.tvEngineSearchStates();
    final maxResultsOverrides = _sections.engines
        .quickPlayMaxResultsOverrides();

    try {
      final futures = keywords
          .map(
            (kw) => TorrentService.searchAllEngines(
              kw,
              engineStates: engineStates,
              maxResultsOverrides: maxResultsOverrides,
            ),
          )
          .toList();

      await for (final result in Stream.fromFutures(futures)) {
        final torrents =
            (result['torrents'] as List<Torrent>? ?? const <Torrent>[]);

        List<Torrent> torrentsToProcess = torrents;
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
          torrentsToProcess = torrents.where((t) {
            return !NsfwFilter.shouldFilter(t.category, t.name);
          }).toList();
        }

        for (final torrent in torrentsToProcess) {
          final normalizedHash = _sections.filters.normalizeInfohash(
            torrent.infohash,
          );
          if (normalizedHash.isEmpty) continue;
          dedup.putIfAbsent(normalizedHash, () => torrent);
        }

        if (dedup.isNotEmpty && _deps.mounted()) {
          _deps.setState(
            () => _owners.session.status = 'Checking Premiumize cache...',
          );
        }
      }

      final combinedList = _sections.filters.applyQualityFilterToTorrents(
        dedup.values.toList(),
        // Search is complete here — an empty match means this search really
        // has nothing at the requested quality, so degrade rather than fail.
        allowFallback: true,
      );
      if (combinedList.isEmpty) {
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted()) {
          _deps.setState(
            () => _owners.session.status =
                'No results found. Try different keywords.',
          );
          _sections.feedback.showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      if (_deps.mounted())
        _deps.setState(
          () => _owners.session.status = 'Checking Premiumize cache...',
        );

      int candidateCursor = 0;

      Future<bool> populateQueue() async {
        while (true) {
          if (candidateCursor >= combinedList.length) return false;
          final window = await _sections.cloud.fetchPremiumizeCacheWindow(
            candidates: combinedList,
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
            '✅ Found ${_owners.session.queue.length} cached Premiumize torrent(s)',
          );
          return true;
        }
      }

      bool seeded;
      try {
        seeded = await populateQueue();
      } catch (e) {
        log('❌ Premiumize cache check failed: $e');
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted()) {
          _deps.setState(
            () => _owners.session.status =
                'Premiumize cache check failed. Try again.',
          );
          _sections.feedback.showSnack(
            'Premiumize cache check failed: $e',
            color: Colors.red,
          );
        }
        return;
      }

      if (!seeded) {
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted()) {
          _deps.setState(
            () => _owners.session.status =
                'Premiumize has no cached results for these keywords.',
          );
          _sections.feedback.showSnack(
            'Premiumize has no cached results for these keywords.',
            color: Colors.orange,
          );
        }
        return;
      }

      Future<Map<String, String>?> requestPremiumizeNext() async {
        if (_owners.session.watchCancelled) return null;
        while (!_owners.session.watchCancelled) {
          if (_owners.session.queue.isEmpty) {
            bool replenished;
            try {
              replenished = await populateQueue();
            } catch (e) {
              log('❌ Premiumize cache check failed: $e');
              _sections.feedback.closeProgressDialog();
              if (_deps.mounted() && !_owners.session.watchCancelled) {
                _deps.setState(
                  () => _owners.session.status =
                      'Premiumize cache check failed. Try again.',
                );
                _sections.feedback.showSnack(
                  'Premiumize cache check failed: $e',
                  color: Colors.red,
                );
              }
              return null;
            }
            if (!replenished) break;
          }
          if (_owners.session.queue.isEmpty) break;

          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) break;
          if (item is! Torrent) continue;

          final result = await _sections.cloud.preparePremiumizeTorrent(
            candidate: item,
            apiKey: apiKey,
            log: log,
          );
          if (_owners.session.watchCancelled) return null;
          if (result != null) {
            if (result.hasMore && !_owners.session.watchCancelled)
              combinedList.add(item);
            if (_deps.mounted() && !_owners.session.watchCancelled) {
              _deps.setState(() {
                _owners.session.status = _owners.session.queue.isEmpty
                    ? ''
                    : 'Queue has ${_owners.session.queue.length} remaining';
              });
            }
            if (_owners.session.watchCancelled) return null;
            return {'url': result.streamUrl, 'title': result.title};
          }
        }
        if (_deps.mounted() && !_owners.session.watchCancelled) {
          _deps.setState(
            () => _owners.session.status = 'No more cached Premiumize streams.',
          );
        }
        return null;
      }

      final first = await requestPremiumizeNext();
      if (_owners.session.watchCancelled) return;
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted() && !_owners.session.watchCancelled) {
          _deps.setState(() {
            _owners.session.status =
                'No playable Premiumize streams found. Try different keywords.';
          });
          _sections.feedback.showSnack(
            'No playable Premiumize streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;

      if (await _sections.handoff.handOffToExternalPlayer(
        first['url'] ?? '',
        first['title'] ?? 'Debrify TV',
      )) {
        return;
      }

      final launchedOnTv = await _sections.handoff.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPremiumizeNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) return;
      if (launchedOnTv) return;

      if (!_owners.session.watchCancelled) {
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
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.showVideoTitle,
              hideOptions: _owners.settings.hideOptions,
              requestMagicNext: requestPremiumizeNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPremiumize)
                  ? _sections.channelWatch.requestNextChannel
                  : null,
            ),
          ),
        );
      }

      if (_deps.mounted() && !_owners.session.watchCancelled) {
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
      if (_deps.mounted()) _deps.setState(() => _owners.session.isBusy = false);
    }
  }
}
