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
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvCachedRealDebrid {
  final DebrifyTvDependencies _deps;
  DebrifyTvCachedRealDebrid(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watchWithCachedTorrents(
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

    final apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      MainPageBridge.notifyAutoLaunchFailed('No Real Debrid API key');
      _sections.feedback.showSnack(
        'Please add your Real Debrid API key in Settings first!',
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

    // Filter out RD-blocked torrents
    if (_owners.settings.rdSkipBlockedTorrents) {
      final beforeCount = torrentsToUse.length;
      torrentsToUse = torrentsToUse
          .where((t) => !isRdBlockedTorrent(t.name))
          .toList();
      if (beforeCount != torrentsToUse.length) {
        debugPrint(
          'DebrifyTV: RD-blocked filter on cached: $beforeCount → ${torrentsToUse.length} torrents',
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
        'DebrifyTV: Cached requestMagicNext() queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('DebrifyTV: Cached path trying RD link: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            if (!_sections.filters.rdLinkPassesSizeRules(unrestrict)) continue;
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint('DebrifyTV: Cached success (RD link) in ${elapsed}s');
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached RD link failed: $e');
            continue;
          }
        }

        if (item is Torrent) {
          debugPrint(
            'DebrifyTV: Cached trying torrent name="${item.name}" hash=${item.infohash}',
          );
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
            final elapsed = DateTime.now().difference(started).inSeconds;
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<String> rdLinks =
                (result['links'] as List<dynamic>? ?? const [])
                    .map((link) => link?.toString() ?? '')
                    .where((link) => link.isNotEmpty)
                    .toList();
            if (rdLinks.isEmpty) {
              continue;
            }

            final newLinks = rdLinks
                .where(
                  (link) => !_owners.session.seenRestrictedLinks.contains(link),
                )
                .toList();
            if (newLinks.isEmpty) {
              continue;
            }

            newLinks.shuffle(Random());
            // Walk THIS torrent's own links until one is playable. Bailing
            // after a single reject and re-queuing the torrent would pay
            // another add+info round trip just to reach a sibling file, so a
            // pack full of samples could burn one RD add per sample and play
            // nothing. Unrestrict calls are the cheap half — spend those.
            while (newLinks.isNotEmpty) {
              final selectedLink = newLinks.removeAt(0);
              _owners.session.seenRestrictedLinks.add(selectedLink);
              _owners.session.seenLinkWithTorrentId.add(
                '$torrentId|$selectedLink',
              );

              final unrestrict = await DebridService.unrestrictLink(
                apiKey,
                selectedLink,
              );
              if (!_sections.filters.rdLinkPassesSizeRules(unrestrict))
                continue;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl == null || videoUrl.isEmpty) continue;

              debugPrint(
                'DebrifyTV: Cached success: unrestricted in ${elapsed}s',
              );
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;

              if (newLinks.isNotEmpty) {
                _owners.session.queue.add(item);
              }

              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('DebrifyTV: Cached Debrid add failed: $e');
          }
        }
      }
      debugPrint('DebrifyTV: Cached queue exhausted.');
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
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerRealDebrid;
      unawaited(_sections.prefetch.startPrefetch());
      _sections.feedback.closeProgressDialog();

      if (await _sections.handoff.handOffToExternalPlayer(
        firstUrl,
        firstTitle,
      )) {
        return;
      }

      // Try to launch on Android TV first (for cached flow)
      final launchedOnTv = await _sections.handoff.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        channelName: channelName,
        channelId: channelId,
        channelNumber: channelNumber,
        channelDirectory: channelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint(
          'DebrifyTV: Cached flow - Real-Debrid playback started on Android TV',
        );
        // Prefetch will continue in background while TV player is active
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
      debugPrint('DebrifyTV: Cached watch flow finished.');
    }
  }
}
