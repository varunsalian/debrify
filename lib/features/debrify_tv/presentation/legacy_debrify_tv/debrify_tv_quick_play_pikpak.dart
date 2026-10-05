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
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvQuickPlayPikPak {
  final DebrifyTvDependencies _deps;
  DebrifyTvQuickPlayPikPak(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watchWithPikPak(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final pikpakAvailable = await PikPakTvService.instance.isAvailable();
    if (!pikpakAvailable) {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status = 'Please login to PikPak in Settings first!';
        _owners.session.isBusy = false;
      });
      _sections.feedback.showSnack(
        'Please login to PikPak in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    log('🌐 PikPak: searching for torrents...');
    final Map<String, Torrent> dedup = <String, Torrent>{};
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
        final Map<String, String> engineErrors = {};
        final rawErrors = result['engineErrors'];
        if (rawErrors is Map) {
          rawErrors.forEach((key, value) {
            engineErrors[key.toString()] = value?.toString() ?? '';
          });
        }
        if (engineErrors.isNotEmpty) {
          engineErrors.forEach((engine, message) {
            debugPrint('PikPak: Search engine "$engine" failed: $message');
          });
        }

        // Apply NSFW filter if enabled
        List<Torrent> torrentsToProcess = torrents;
        if (_owners.settings.quickAvoidNsfw ||
            _owners.settings.viewerForcesNsfw) {
          final beforeCount = torrents.length;
          torrentsToProcess = torrents.where((torrent) {
            if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
              debugPrint('PikPak: Filtered NSFW torrent: ${torrent.name}');
              return false;
            }
            return true;
          }).toList();
          if (beforeCount != torrentsToProcess.length) {
            debugPrint(
              'PikPak: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
            );
          }
        }

        int added = 0;
        for (final torrent in torrentsToProcess) {
          final normalizedHash = _sections.filters.normalizeInfohash(
            torrent.infohash,
          );
          if (normalizedHash.isEmpty) continue;
          if (!dedup.containsKey(normalizedHash)) {
            dedup[normalizedHash] = torrent;
            added++;
          }
        }
        if (added > 0) {
          final combined = _sections.filters.applyQualityFilterToTorrents(
            dedup.values.toList(),
          );
          combined.shuffle(Random());
          _owners.session.queue
            ..clear()
            ..addAll(combined);
          _owners.session.lastQueueSize = _owners.session.queue.length;
          _owners.session.lastSearchAt = DateTime.now();
          if (_deps.mounted()) {
            _deps.setState(() {
              _owners.session.status = 'Preparing PikPak stream...';
            });
          }
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
          _deps.setState(() {
            _owners.session.status =
                'No results found. Try different keywords.';
          });
          _sections.feedback.showSnack(
            'No results found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      combinedList.shuffle(Random());
      _owners.session.queue
        ..clear()
        ..addAll(combinedList);
      _owners.session.lastQueueSize = _owners.session.queue.length;
      _owners.session.lastSearchAt = DateTime.now();

      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.status = 'Preparing PikPak stream...';
        });
      }

      Future<Map<String, String>?> requestPikPakNext() async {
        if (_owners.session.watchCancelled) {
          return null;
        }
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) {
            break;
          }
          if (item is! Torrent) {
            continue;
          }

          log('Trying torrent: ${item.name}');
          final prepared = await _sections.cloud.preparePikPakTorrent(
            candidate: item,
            log: (msg) => debugPrint('DebrifyTV/PikPak: $msg'),
          );

          if (_owners.session.watchCancelled) {
            return null;
          }

          if (prepared == null) {
            log('Torrent not ready, trying next...');
            continue;
          }

          // Add back to queue if there are more files in this torrent
          if (prepared.hasMore) {
            _owners.session.queue.add(item);
            log(
              'Multi-file torrent: added back to queue (${_owners.session.queue.length} remaining)',
            );
          }

          if (_deps.mounted() && !_owners.session.watchCancelled) {
            _deps.setState(() {
              _owners.session.status = _owners.session.queue.isEmpty
                  ? ''
                  : 'Queue has ${_owners.session.queue.length} remaining';
            });
          }

          return {
            'url': prepared.streamUrl,
            'title': prepared.title,
            'provider': 'pikpak',
            'pikpakFileId': '',
          };
        }
        if (_deps.mounted() && !_owners.session.watchCancelled) {
          _deps.setState(() {
            _owners.session.status = 'No more PikPak streams available.';
          });
        }
        return null;
      }

      final first = await requestPikPakNext();
      if (_owners.session.watchCancelled) {
        return;
      }
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted() && !_owners.session.watchCancelled) {
          _deps.setState(() {
            _owners.session.status =
                'No playable PikPak streams found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No PikPak streams available');
          _sections.feedback.showSnack(
            'No playable PikPak streams found. Try different keywords.',
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

      // Try Android TV native player first
      final launchedOnTv = await _sections.handoff.launchPikPakOnAndroidTv(
        firstStream: first,
        requestNext: requestPikPakNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelName: null,
        channelId: null,
        channelNumber: null,
        channelDirectory: null,
      );
      if (_owners.session.watchCancelled) {
        return;
      }
      if (launchedOnTv) {
        return;
      }

      if (!_owners.session.watchCancelled) {
        // Hide auto-launch overlay before launching player
        MainPageBridge.notifyPlayerLaunching();

        await Navigator.of(_deps.context()).push(
          videoPlayerRoute(
            builder: (_) => VideoPlayerScreen(
              videoUrl: first['url'] ?? '',
              title: first['title'] ?? 'Debrify TV',
              startFromRandom: _owners.settings.quickStartRandom,
              randomStartMaxPercent: _owners.settings.quickRandomStartPercent,
              hideSeekbar: _owners.settings.quickHideSeekbar,
              showChannelName: _owners.settings.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.quickShowVideoTitle,
              hideOptions: _owners.settings.quickHideOptions,
              requestMagicNext: requestPikPakNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak)
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
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
    }
  }
}
