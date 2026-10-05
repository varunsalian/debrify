import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/cache_results.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/pikpak_tv_service.dart';
import 'package:debrify/services/storage/alldebrid_storage.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/storage/torbox_storage.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelSwitch {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelSwitch(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<Map<String, dynamic>?> switchToChannel(
    DebrifyTvChannel targetChannel, {
    int? fallbackIndex,
    String reason = 'direct',
  }) async {
    debugPrint(
      'DebrifyTV: _switchToChannel(${targetChannel.name}) reason=$reason',
    );

    final int computedIndex =
        fallbackIndex ??
        _owners.library.channels.indexWhere(
          (channel) => channel.id == targetChannel.id,
        );
    final int targetChannelNumber = targetChannel.channelNumber > 0
        ? targetChannel.channelNumber
        : (computedIndex >= 0 ? computedIndex + 1 : 0);

    final cacheEntry = await _sections.library.ensureCacheEntry(
      targetChannel.id,
    );
    if (cacheEntry == null) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" has no cache entry',
      );
      return null;
    }
    if (!cacheEntry.isReady) {
      debugPrint(
        'DebrifyTV: Channel "${targetChannel.name}" cache not ready. Error: ${cacheEntry.errorMessage}',
      );
      return null;
    }
    if (cacheEntry.torrents.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no torrents');
      return null;
    }

    debugPrint('DebrifyTV: Stopping old channel prefetcher...');
    await _sections.prefetch.stopPrefetch();
    debugPrint('DebrifyTV: Prefetcher stopped. Waiting for RD cooldown...');
    await Future.delayed(const Duration(seconds: 5));
    debugPrint('DebrifyTV: Cooldown complete. Proceeding with channel switch.');

    final previousChannelId = _owners.library.currentWatchingChannelId;
    if (previousChannelId != null) {
      _owners.library.channelCache.remove(previousChannelId);
      debugPrint(
        'DebrifyTV: Evicted cache entry for previous channel $previousChannelId',
      );
    }

    _owners.session.seenRestrictedLinks.clear();
    _owners.session.seenLinkWithTorrentId.clear();
    // New channel, new filter verdict — let it warn again if this one has
    // nothing at the requested quality/size.
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;
    debugPrint('DebrifyTV: Cleared prefetch state');

    final keywords = await _sections.library.getChannelKeywords(
      targetChannel.id,
    );
    if (keywords.isEmpty) {
      debugPrint('DebrifyTV: Channel "${targetChannel.name}" has no keywords');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(_sections.prefetch.startPrefetch());
      }
      return null;
    }

    final normalizedKeywords = _sections.library.normalizedKeywords(keywords);
    final playbackSelection = _sections.filters.selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );

    if (playbackSelection.isEmpty) {
      debugPrint('DebrifyTV: No torrents matched in selected channel');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(_sections.prefetch.startPrefetch());
      }
      return null;
    }

    final List<Torrent> allTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    if (allTorrents.isEmpty) {
      debugPrint('DebrifyTV: No playable torrents resolved for channel');
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
          _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        unawaited(_sections.prefetch.startPrefetch());
      }
      return null;
    }

    List<Torrent> filteredTorrents = allTorrents;
    if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
      final apiKey = await TorboxStorage.getTorboxApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        debugPrint('DebrifyTV: ❌ No Torbox API key configured');
        return null;
      }

      final List<Torrent> torboxCandidates = List<Torrent>.from(
        filteredTorrents,
      );
      torboxCandidates.shuffle(Random());

      int candidateCursor = 0;
      List<Torrent> cachedCandidates = <Torrent>[];
      try {
        while (candidateCursor < torboxCandidates.length &&
            cachedCandidates.isEmpty) {
          final TorboxCacheWindowResult window = await _sections.torbox
              .fetchTorboxCacheWindow(
                candidates: torboxCandidates,
                startIndex: candidateCursor,
                apiKey: apiKey,
              );
          candidateCursor = window.nextCursor;
          if (window.cachedTorrents.isNotEmpty) {
            cachedCandidates = window.cachedTorrents;
            break;
          }
          if (window.exhausted) {
            break;
          }
        }
      } catch (e) {
        debugPrint(
          'DebrifyTV: Torbox cache check failed during channel switch: $e',
        );
        return null;
      }

      if (cachedCandidates.isEmpty) {
        debugPrint(
          'DebrifyTV: Torbox channel has no cached torrents available',
        );
        return null;
      }

      filteredTorrents = cachedCandidates;
    }

    try {
      if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid) {
        debugPrint('DebrifyTV: Selected channel uses Real-Debrid provider');
        final apiKey = await RealDebridStorage.getApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Real-Debrid API key configured');
          return null;
        }

        if (_owners.settings.rdSkipBlockedTorrents) {
          filteredTorrents = filteredTorrents
              .where((t) => !isRdBlockedTorrent(t.name))
              .toList();
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];
          final magnetLink = 'magnet:?xt=urn:btih:${candidate.infohash}';

          Map<String, dynamic> selection;
          try {
            selection = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
          } catch (error) {
            debugPrint(
              'DebrifyTV: Real-Debrid rejected candidate ${candidate.infohash}: $error',
            );
            continue;
          }

          final rdLinks = (selection['links'] as List<dynamic>? ?? const [])
              .map((link) => link?.toString() ?? '')
              .where((link) => link.isNotEmpty)
              .toList();

          if (rdLinks.isEmpty) {
            debugPrint(
              'DebrifyTV: Real-Debrid returned no usable links for candidate ${candidate.infohash}',
            );
            continue;
          }

          final torrentId = selection['torrentId']?.toString() ?? '';
          List<String> newLinks = rdLinks
              .where(
                (link) => !_owners.session.seenRestrictedLinks.contains(link),
              )
              .toList();
          if (newLinks.isEmpty) {
            newLinks = List<String>.from(rdLinks);
          }
          newLinks.shuffle(Random());
          // Exhaust THIS candidate's links before moving on. Advancing to the
          // next candidate costs a whole add+info round trip, so a sample as
          // the first pick must not throw away a torrent that has a real
          // episode sitting right behind it.
          String? videoUrl;
          for (final selectedLink in newLinks) {
            _owners.session.seenRestrictedLinks.add(selectedLink);
            if (torrentId.isNotEmpty) {
              _owners.session.seenLinkWithTorrentId.add(
                '$torrentId|$selectedLink',
              );
            }

            Map<String, dynamic> unrestrict;
            try {
              unrestrict = await DebridService.unrestrictLink(
                apiKey,
                selectedLink,
              );
            } catch (error) {
              debugPrint(
                'DebrifyTV: Real-Debrid unrestrict failed for candidate ${candidate.infohash}: $error',
              );
              continue;
            }

            if (!_sections.filters.rdLinkPassesSizeRules(unrestrict)) continue;

            final String? resolved = unrestrict['download'] as String?;
            if (resolved == null || resolved.isEmpty) {
              debugPrint(
                'DebrifyTV: Real-Debrid unrestrict returned empty URL for candidate ${candidate.infohash}',
              );
              continue;
            }
            videoUrl = resolved;
            break;
          }

          if (videoUrl == null) continue;

          String title = candidate.name;
          final uri = Uri.tryParse(videoUrl);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final inferred = Uri.decodeComponent(uri.pathSegments.last);
            if (inferred.isNotEmpty) {
              title = inferred;
            }
          }

          if (_deps.mounted()) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            _deps.setState(() {
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          _owners.prefetch.activeApiKey = apiKey;
          _owners.prefetch.activeProvider =
              DebrifyTvConstants.providerRealDebrid;
          unawaited(_sections.prefetch.startPrefetch());
          debugPrint(
            'DebrifyTV: Started Real-Debrid prefetcher for new channel',
          );
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All Real-Debrid candidates failed for channel');
        return null;
      }

      if (_owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
        debugPrint('DebrifyTV: Selected channel uses AllDebrid provider');
        final apiKey = await AllDebridStorage.getAllDebridApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No AllDebrid API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await _sections.prefetch.resolveAllDebridLinks(
            candidate,
            apiKey,
          );
          if (prepared == null || prepared.lockedLinks.isEmpty) {
            // Not cached/ready or no usable video; try the next candidate.
            continue;
          }

          final links = List<String>.from(prepared.lockedLinks);
          final String headLink = links.removeAt(0);

          String videoUrl;
          try {
            videoUrl = await AllDebridService.unlockLink(apiKey, headLink);
          } catch (error) {
            debugPrint(
              'DebrifyTV: AllDebrid unlock failed for candidate ${candidate.infohash}: $error',
            );
            continue;
          }
          if (videoUrl.isEmpty) {
            continue;
          }

          String title = candidate.name;
          final uri = Uri.tryParse(videoUrl);
          if (uri != null && uri.pathSegments.isNotEmpty) {
            final inferred = Uri.decodeComponent(uri.pathSegments.last);
            if (inferred.isNotEmpty) {
              title = inferred;
            }
          }

          if (_deps.mounted()) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            _deps.setState(() {
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                // Remaining video files of this torrent first (already
                // resolved, still locked), then the other candidates.
                ..addAll(
                  links.map(
                    (link) => {
                      'type': 'ad_locked',
                      'allDebridLink': link,
                      'magnetId': prepared.magnetId,
                      'displayName': candidate.name,
                    },
                  ),
                )
                ..addAll(remaining);
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          _owners.prefetch.activeApiKey = apiKey;
          _owners.prefetch.activeProvider =
              DebrifyTvConstants.providerAllDebrid;
          unawaited(_sections.prefetch.startPrefetch());
          debugPrint('DebrifyTV: Started AllDebrid prefetcher for new channel');
          debugPrint('DebrifyTV: Successfully got stream from channel: $title');

          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': videoUrl,
            'firstTitle': title,
          };
        }

        debugPrint('DebrifyTV: All AllDebrid candidates failed for channel');
        return null;
      }

      if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
        final apiKey = await TorboxStorage.getTorboxApiKey();
        if (apiKey == null || apiKey.isEmpty) {
          debugPrint('DebrifyTV: ❌ No Torbox API key configured');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await _sections.torbox.prepareTorboxTorrent(
            candidate: candidate,
            apiKey: apiKey,
            log: (message) => debugPrint(message),
          );

          if (prepared == null || prepared.streamUrl.isEmpty) {
            debugPrint(
              'DebrifyTV: Torbox preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (_deps.mounted()) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            _deps.setState(() {
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
              if (prepared.hasMore) {
                _owners.session.queue.add(candidate);
              }
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: Torbox channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All Torbox candidates failed for channel');
        return null;
      }

      if (_owners.settings.provider == DebrifyTvConstants.providerPikPak) {
        final pikpakAvailable = await PikPakTvService.instance.isAvailable();
        if (!pikpakAvailable) {
          debugPrint('DebrifyTV: PikPak not authenticated');
          return null;
        }

        for (var index = 0; index < filteredTorrents.length; index++) {
          final candidate = filteredTorrents[index];

          final prepared = await _sections.cloud.preparePikPakTorrent(
            candidate: candidate,
            log: (message) => debugPrint('DebrifyTV/PikPak: $message'),
          );

          if (prepared == null) {
            debugPrint(
              'DebrifyTV: PikPak preparation failed for candidate ${candidate.infohash}',
            );
            continue;
          }

          if (_deps.mounted()) {
            final remaining = filteredTorrents.skip(index + 1).toList();
            _deps.setState(() {
              _owners.library.currentWatchingChannelId = targetChannel.id;
              _owners.session.queue
                ..clear()
                ..addAll(remaining);
              // Add back to queue if there are more files in this torrent
              if (prepared.hasMore) {
                _owners.session.queue.add(candidate);
              }
            });
            _owners.library.keywordsController.text = keywords.join(', ');
          }

          debugPrint(
            'DebrifyTV: PikPak channel switch ready with stream ${prepared.title}',
          );
          return {
            'channelId': targetChannel.id,
            'channelName': targetChannel.name,
            'channelNumber': targetChannelNumber,
            'firstUrl': prepared.streamUrl,
            'firstTitle': prepared.title,
          };
        }

        debugPrint('DebrifyTV: All PikPak candidates failed for channel');
        return null;
      }

      debugPrint(
        'DebrifyTV: Unsupported provider for channel switching: ${_owners.settings.provider}',
      );
      return null;
    } catch (e) {
      debugPrint('DebrifyTV: Error getting stream from channel: $e');
    }

    debugPrint('DebrifyTV: Channel switch failed');
    if (_owners.settings.provider == DebrifyTvConstants.providerRealDebrid ||
        _owners.settings.provider == DebrifyTvConstants.providerAllDebrid) {
      unawaited(_sections.prefetch.startPrefetch());
      debugPrint('DebrifyTV: Restarted prefetcher for current channel');
    }
    return null;
  }
}
