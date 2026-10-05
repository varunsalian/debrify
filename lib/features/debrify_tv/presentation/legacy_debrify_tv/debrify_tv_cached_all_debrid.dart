import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvCachedAllDebrid {
  final DebrifyTvDependencies _deps;
  DebrifyTvCachedAllDebrid(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// AllDebrid channel playback. Mirrors the Real-Debrid cached flow
  /// (sequential add-and-probe, no cache-check API) but resolves each candidate
  /// through AllDebrid's `ready`-flag add (no polling) and lazily unlocks links
  /// on demand. The background prefetcher keeps upcoming items prepared.
  Future<void> watchAllDebridWithCachedTorrents(
    List<Torrent> cachedTorrents, {
    required bool applyNsfwFilter,
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

    _owners.session.launchedPlayer = false;
    await _sections.prefetch.stopPrefetch();
    _owners.prefetch.prefetchStopRequested = false;
    _owners.session.originalMaxCap = null;
    _owners.session.seenRestrictedLinks.clear();
    _owners.session.seenLinkWithTorrentId.clear();

    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      MainPageBridge.notifyAutoLaunchFailed('No AllDebrid API key');
      _sections.feedback.showSnack(
        'Please add your AllDebrid API key in Settings first!',
        color: Colors.orange,
      );
      return;
    }

    _sections.feedback.showCachedPlaybackDialog();

    // Apply NSFW filter to cached torrents if enabled
    List<Torrent> torrentsToUse = cachedTorrents;
    if (applyNsfwFilter) {
      final beforeCount = cachedTorrents.length;
      torrentsToUse = cachedTorrents.where((torrent) {
        if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
          debugPrint(
            'DebrifyTV: Filtered cached NSFW torrent: ${torrent.name}',
          );
          return false;
        }
        return true;
      }).toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: NSFW filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
        );
      }
    }

    _owners.session.queue
      ..clear()
      ..addAll(List<Torrent>.from(torrentsToUse)..shuffle(Random()));
    _owners.session.lastQueueSize = _owners.session.queue.length;
    _owners.session.lastSearchAt = DateTime.now();

    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint(
        'DebrifyTV/AD: requestMagicNext() queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        if (item is Map && item['type'] == 'ad_locked') {
          final String link = item['allDebridLink'] as String? ?? '';
          if (link.isEmpty) continue;
          try {
            final videoUrl = await AllDebridService.unlockLink(apiKey, link);
            if (videoUrl.isNotEmpty) {
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV/AD: Cached unlock failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
            'DebrifyTV/AD: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
          final prepared = await _sections.prefetch.resolveAllDebridLinks(
            item,
            apiKey,
          );
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            continue;
          }
          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);
          // AllDebrid returns every file at once: enqueue the remaining video
          // files (still locked) so siblings aren't lost if the head fails.
          for (final link in links) {
            _owners.session.queue.add({
              'type': 'ad_locked',
              'allDebridLink': link,
              'magnetId': prepared.magnetId,
              'displayName': item.name,
            });
          }
          try {
            final videoUrl = await AllDebridService.unlockLink(
              apiKey,
              headLink,
            );
            if (videoUrl.isNotEmpty) {
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV/AD: Cached add/unlock failed: $e');
            continue;
          }
        }
      }
      debugPrint('DebrifyTV/AD: Cached queue exhausted.');
      return null;
    }

    _deps.setState(() {
      _owners.session.status = 'Finding a playable stream...';
      _owners.session.isBusy = true;
    });

    try {
      final first = await requestMagicNext();
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (!_deps.mounted()) return;
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status =
              'No cached torrents played successfully. Try refreshing the channel.';
        });
        MainPageBridge.notifyAutoLaunchFailed('No cached streams available');
        _sections.feedback.showSnack(
          'No cached torrents played successfully. Try refreshing the channel.',
          color: Colors.orange,
        );
        return;
      }

      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!_deps.mounted()) return;
      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerAllDebrid;
      unawaited(_sections.prefetch.startPrefetch());
      _sections.feedback.closeProgressDialog();

      if (await _sections.handoff.handOffToExternalPlayer(
        firstUrl,
        firstTitle,
      )) {
        return;
      }

      // Try to launch on Android TV first (reuses the generic direct-URL
      // launcher; AllDebrid streams are ready URLs just like Real-Debrid's).
      final launchedOnTv = await _sections.handoff.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        debugPrint(
          'DebrifyTV: Cached flow - AllDebrid playback started on Android TV',
        );
        return;
      }

      // Hide auto-launch overlay before launching player
      MainPageBridge.notifyPlayerLaunching();

      // Fall back to Flutter video player
      await Navigator.of(_deps.context()).push(
        videoPlayerRoute(
          builder: (_) => VideoPlayerScreen(
            videoUrl: firstUrl,
            title: firstTitle,
            startFromRandom: _owners.settings.startRandom,
            randomStartMaxPercent: _owners.settings.randomStartPercent,
            hideSeekbar: _owners.settings.hideSeekbar,
            showChannelName: _owners.settings.showChannelName,
            channelName: channelName,
            channelNumber: channelNumber,
            showVideoTitle: _owners.settings.showVideoTitle,
            hideOptions: _owners.settings.hideOptions,
            requestMagicNext: requestMagicNext,
            requestNextChannel:
                _owners.library.channels.length > 1 &&
                    (_owners.settings.provider ==
                            DebrifyTvConstants.providerRealDebrid ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerTorbox ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPikPak ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerPremiumize ||
                        _owners.settings.provider ==
                            DebrifyTvConstants.providerAllDebrid)
                ? _sections.channelWatch.requestNextChannel
                : null,
            channelDirectory: channelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? _sections.channelWatch.requestChannelById
                : null,
          ),
        ),
      );
      await _sections.prefetch.stopPrefetch();
    } on NativePlayerSettingsUnavailable catch (error) {
      _sections.feedback.showNativeSettingsFailure(error);
    } finally {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.isBusy = false;
        _owners.session.status = '';
      });
      debugPrint('DebrifyTV: AllDebrid cached watch flow finished.');
    }
  }
}
