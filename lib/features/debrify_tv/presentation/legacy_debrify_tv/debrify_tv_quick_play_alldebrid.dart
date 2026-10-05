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
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvQuickPlayAllDebrid {
  final DebrifyTvDependencies _deps;
  DebrifyTvQuickPlayAllDebrid(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// AllDebrid Quick Play. Self-contained like [_watchWithPremiumize] for the
  /// search phase, but follows Real-Debrid's resolve model (sequential
  /// add-and-probe + background prefetcher) since AllDebrid has no cache-check
  /// API. Each candidate is added trusting the `ready` flag (no polling) and
  /// links are unlocked lazily on demand.
  Future<void> watchWithAllDebrid(
    List<String> keywords,
    void Function(String message) log,
  ) async {
    final integrationEnabled =
        await AllDebridStorage.getAllDebridIntegrationEnabled();
    if (!integrationEnabled) {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status =
            'Enable AllDebrid in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      _sections.feedback.showSnack(
        'Enable AllDebrid in Settings to use this provider.',
        color: Colors.orange,
      );
      return;
    }

    final apiKey = await AllDebridStorage.getAllDebridApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status =
            'Add your AllDebrid API key in Settings to use this provider.';
        _owners.session.isBusy = false;
      });
      _sections.feedback.showSnack(
        'Please add your AllDebrid API key in Settings first!',
        color: Colors.red,
      );
      return;
    }

    log('🌐 AllDebrid: searching for torrents...');
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
        if (_owners.session.watchCancelled) return;
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
            () => _owners.session.status = 'Finding a playable stream...',
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

      // Seed the queue with raw torrents — sequential add-and-probe, no cache
      // check (mirrors Real-Debrid). The prefetcher prepares the rest.
      _owners.session.queue
        ..clear()
        ..addAll(combinedList);
      _owners.session.lastQueueSize = _owners.session.queue.length;
      _owners.session.lastSearchAt = DateTime.now();
      _owners.session.seenRestrictedLinks.clear();
      _owners.session.seenLinkWithTorrentId.clear();

      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        if (_owners.session.watchCancelled) return null;
        debugPrint(
          'MagicTV/AD: requestMagicNext() queueSize=${_owners.session.queue.length}',
        );
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (item is Map && item['type'] == 'ad_locked') {
            final String link = item['allDebridLink'] as String? ?? '';
            if (link.isEmpty) continue;
            try {
              final videoUrl = await AllDebridService.unlockLink(apiKey, link);
              if (_owners.session.watchCancelled) return null;
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
              debugPrint('MagicTV/AD: unlock failed: $e');
              continue;
            }
          }

          if (item is Torrent) {
            final prepared = await _sections.prefetch.resolveAllDebridLinks(
              item,
              apiKey,
            );
            if (_owners.session.watchCancelled) return null;
            if (prepared == null || prepared.lockedLinks.isEmpty) {
              continue;
            }
            final links = List<String>.from(prepared.lockedLinks);
            final String headLink = links.removeAt(0);
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
              if (_owners.session.watchCancelled) return null;
              if (videoUrl.isNotEmpty) {
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('MagicTV/AD: add/unlock failed: $e');
              continue;
            }
          }
        }
        debugPrint('MagicTV/AD: requestMagicNext() queue exhausted.');
        return null;
      }

      final first = await requestMagicNext();
      if (_owners.session.watchCancelled) return;
      if (first == null) {
        _sections.feedback.closeProgressDialog();
        if (_deps.mounted() && !_owners.session.watchCancelled) {
          _deps.setState(() {
            _owners.session.status =
                'No playable AllDebrid streams found. Try different keywords.';
          });
          _sections.feedback.showSnack(
            'No playable AllDebrid streams found. Try different keywords.',
            color: Colors.red,
          );
        }
        return;
      }

      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      _sections.feedback.closeProgressDialog();
      if (!_deps.mounted()) return;

      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerAllDebrid;
      unawaited(_sections.prefetch.startPrefetch());

      if (await _sections.handoff.handOffToExternalPlayer(
        first['url'] ?? '',
        firstTitle,
      )) {
        return;
      }

      final launchedOnTv = await _sections.handoff.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
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
              title: firstTitle,
              startFromRandom: _owners.settings.quickStartRandom,
              randomStartMaxPercent: _owners.settings.quickRandomStartPercent,
              hideSeekbar: _owners.settings.quickHideSeekbar,
              showChannelName: _owners.settings.quickShowChannelName,
              channelName: null,
              channelNumber: null,
              showVideoTitle: _owners.settings.quickShowVideoTitle,
              hideOptions: _owners.settings.quickHideOptions,
              requestMagicNext: requestMagicNext,
              requestNextChannel:
                  _owners.library.channels.length > 1 &&
                      (_owners.settings.quickProvider ==
                              DebrifyTvConstants.providerRealDebrid ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerTorbox ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPikPak ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerPremiumize ||
                          _owners.settings.quickProvider ==
                              DebrifyTvConstants.providerAllDebrid)
                  ? _sections.channelWatch.requestNextChannel
                  : null,
            ),
          ),
        );
        await _sections.prefetch.stopPrefetch();
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
