import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/debrify_tv/dialogs/cached_loading_dialog.dart';
import 'package:debrify/screens/video_player/player_pip_route.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/android_tv_player_bridge.dart';
import 'package:debrify/services/debrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/nsfw_filter.dart';
import 'package:debrify/utils/rd_blocked_filter.dart';
import 'package:flutter/material.dart';

class DebrifyTvQuickPlay {
  final DebrifyTvDependencies _deps;
  DebrifyTvQuickPlay(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> watch() async {
    _owners.session.launchedPlayer = false;
    await _sections.prefetch.stopPrefetch();
    _owners.prefetch.prefetchStopRequested = false;
    _owners.session.watchCancelled = false;
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;
    _owners.session.originalMaxCap = null;
    void _log(String m) {
      final copy = List<String>.from(_owners.progress.progress.value)..add(m);
      _owners.progress.progress.value = copy;
      debugPrint('DebrifyTV: ' + m);
    }

    await _sections.settings.syncProviderAvailability();
    if (!_owners.settings.rdAvailable &&
        !_owners.settings.torboxAvailable &&
        !_owners.settings.pikpakAvailable &&
        !_owners.settings.premiumizeAvailable &&
        !_owners.settings.allDebridAvailable) {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.status =
              'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.';
        });
      }
      _sections.feedback.showSnack(
        'Connect Real Debrid, Torbox, Premiumize, AllDebrid, or PikPak in Settings to use Debrify TV.',
        color: Colors.orange,
      );
      return;
    }
    final text = _owners.library.keywordsController.text.trim();
    debugPrint('DebrifyTV: Watch started. Raw input="$text"');
    if (text.isEmpty) {
      _deps.setState(() {
        _owners.session.status =
            'Enter one or more keywords, separated by commas';
      });
      debugPrint('DebrifyTV: Aborting. No keywords provided.');
      return;
    }

    final keywords = _sections.library.parseKeywords(text);
    debugPrint(
      'DebrifyTV: Parsed ${keywords.length} keyword(s): ${keywords.join(' | ')}',
    );
    if (keywords.isEmpty) {
      _deps.setState(() {
        _owners.session.status = 'Enter valid keywords';
      });
      debugPrint(
        'DebrifyTV: Aborting. Parsed keywords became empty after trimming.',
      );
      return;
    }
    if (keywords.length > _owners.settings.quickPlayMaxKeywords) {
      _deps.setState(() {
        _owners.session.status =
            'Quick Play supports up to ${_owners.settings.quickPlayMaxKeywords} keywords. Create a channel for larger sets.';
      });
      _sections.feedback.showSnack(
        'Quick Play supports up to ${_owners.settings.quickPlayMaxKeywords} keywords. Create a channel for bigger combos.',
        color: Colors.orange,
      );
      debugPrint(
        'DebrifyTV: Aborting. Too many keywords for Quick Play (${keywords.length}).',
      );
      return;
    }

    _deps.setState(() {
      _owners.session.isBusy = true;
      _owners.session.status = 'Searching...';
      _owners.session.queue.clear();
    });

    // show non-dismissible loading modal
    _owners.progress.progress.value = [];
    _owners.progress.progressOpen = true;
    final providerLabel =
        _owners.settings.quickProvider == DebrifyTvConstants.providerTorbox
        ? 'Torbox'
        : _owners.settings.quickProvider == DebrifyTvConstants.providerPikPak
        ? 'PikPak'
        : _owners.settings.quickProvider ==
              DebrifyTvConstants.providerPremiumize
        ? 'Premiumize'
        : _owners.settings.quickProvider == DebrifyTvConstants.providerAllDebrid
        ? 'AllDebrid'
        : 'Real Debrid';
    // ignore: unawaited_futures
    showDialog(
      context: _deps.context(),
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (ctx) {
        _owners.progress.progressSheetContext = ctx;
        return CachedLoadingDialog(
          eyebrow: 'Quick play · $providerLabel',
          title: 'Searching for something to play',
          subtitle:
              'Debrify is searching your keywords, applying filters, and checking $providerLabel.',
          onCancel: () =>
              _sections.feedback.cancelActiveWatch(dialogContext: ctx),
        );
      },
    ).whenComplete(() {
      _owners.progress.progressOpen = false;
      _owners.progress.progressSheetContext = null;
    });

    if (_owners.settings.quickProvider == DebrifyTvConstants.providerTorbox) {
      await _sections.quickTorbox.watchWithTorbox(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider == DebrifyTvConstants.providerPikPak) {
      await _sections.quickPikPak.watchWithPikPak(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider ==
        DebrifyTvConstants.providerPremiumize) {
      await _sections.quickPremiumize.watchWithPremiumize(keywords, _log);
      return;
    }

    if (_owners.settings.quickProvider ==
        DebrifyTvConstants.providerAllDebrid) {
      await _sections.quickAllDebrid.watchWithAllDebrid(keywords, _log);
      return;
    }

    // Silent approach - no progress logging needed

    try {
      // Require RD API key early so we can prefetch as soon as results arrive
      final String? apiKeyEarlyRaw = await RealDebridStorage.getApiKey();
      if (apiKeyEarlyRaw == null || apiKeyEarlyRaw.isEmpty) {
        if (!_deps.mounted()) return;
        _log('❌ Real Debrid API key not found - please add it in Settings');
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text(
              'Please add your Real Debrid API key in Settings first!',
            ),
          ),
        );
        debugPrint('DebrifyTV: Missing Real Debrid API key.');
        return;
      }
      final String apiKeyEarly = apiKeyEarlyRaw;

      // Helper to infer a filename-like title from a URL
      String _inferTitleFromUrl(String url) {
        final uri = Uri.tryParse(url);
        final last = (uri != null && uri.pathSegments.isNotEmpty)
            ? uri.pathSegments.last
            : url;
        return Uri.decodeComponent(last);
      }

      String firstTitle = 'Debrify TV';

      Future<Map<String, String>?> requestMagicNext() async {
        if (_owners.session.watchCancelled) {
          return null;
        }
        debugPrint(
          'DebrifyTV: requestMagicNext() called. queueSize=${_owners.session.queue.length}',
        );
        while (_owners.session.queue.isNotEmpty &&
            !_owners.session.watchCancelled) {
          final item = _owners.session.queue.removeAt(0);
          if (_owners.session.watchCancelled) {
            break;
          }
          // Case 1: RD-restricted entry (append-only items)
          if (item is Map && item['type'] == 'rd_restricted') {
            final String link = item['restrictedLink'] as String? ?? '';
            final String rdTid = item['torrentId'] as String? ?? '';
            debugPrint(
              'DebrifyTV: Trying RD link from queue: torrentId=$rdTid',
            );
            if (link.isEmpty) continue;
            try {
              final started = DateTime.now();
              final unrestrict = await DebridService.unrestrictLink(
                apiKeyEarly,
                link,
              );
              if (_owners.session.watchCancelled) {
                return null;
              }
              if (!_sections.filters.rdLinkPassesSizeRules(unrestrict))
                continue;
              final elapsed = DateTime.now().difference(started).inSeconds;
              final videoUrl = unrestrict['download'] as String?;
              if (videoUrl != null && videoUrl.isNotEmpty) {
                debugPrint(
                  'DebrifyTV: Success (RD link). Unrestricted in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final display = (item['displayName'] as String?)?.trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (display ?? 'Debrify TV');
                firstTitle = chosenTitle;
                if (_owners.session.watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint('DebrifyTV: RD link failed to unrestrict: $e');
              continue;
            }
          }

          // Case 2: Torrent entry
          if (item is Torrent) {
            debugPrint(
              'DebrifyTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
            );
            final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
            try {
              final started = DateTime.now();
              final result = await DebridService.addTorrentToDebridPreferVideos(
                apiKeyEarly,
                magnetLink,
              );
              if (_owners.session.watchCancelled) {
                return null;
              }
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
                    (link) =>
                        !_owners.session.seenRestrictedLinks.contains(link),
                  )
                  .toList();
              if (newLinks.isEmpty) {
                continue;
              }

              newLinks.shuffle(Random());
              // Walk THIS torrent's own links until one is playable, rather
              // than re-queuing the torrent after a single reject — that would
              // cost another add+info round trip per sibling file (see the
              // cached-channel flow for the same reasoning).
              while (newLinks.isNotEmpty && !_owners.session.watchCancelled) {
                final selectedLink = newLinks.removeAt(0);
                _owners.session.seenRestrictedLinks.add(selectedLink);
                _owners.session.seenLinkWithTorrentId.add(
                  '$torrentId|$selectedLink',
                );

                final unrestrict = await DebridService.unrestrictLink(
                  apiKeyEarly,
                  selectedLink,
                );
                if (_owners.session.watchCancelled) {
                  return null;
                }
                if (!_sections.filters.rdLinkPassesSizeRules(unrestrict))
                  continue;
                final videoUrl = unrestrict['download'] as String?;
                if (videoUrl == null || videoUrl.isEmpty) continue;

                debugPrint(
                  'DebrifyTV: Success. Got unrestricted URL in ${elapsed}s',
                );
                final inferred = _inferTitleFromUrl(videoUrl).trim();
                final chosenTitle = inferred.isNotEmpty
                    ? inferred
                    : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
                firstTitle = chosenTitle;

                if (!_owners.session.watchCancelled && newLinks.isNotEmpty) {
                  _owners.session.queue.add(item);
                }

                if (_owners.session.watchCancelled) {
                  return null;
                }
                return {'url': videoUrl, 'title': chosenTitle};
              }
            } catch (e) {
              debugPrint(
                'DebrifyTV: Debrid add failed for ${item.infohash}: $e',
              );
            }
          }
        }
        debugPrint('DebrifyTV: requestMagicNext() queue exhausted.');
        return null;
      }

      final Map<String, Torrent> dedupByInfohash = {};
      final engineStates = await _sections.engines.tvEngineSearchStates();
      final maxResultsOverrides = _sections.engines
          .quickPlayMaxResultsOverrides();

      // Launch limited batches of per-keyword searches so we don't overwhelm
      List<String> pendingKeywords = List<String>.from(keywords);
      while (pendingKeywords.isNotEmpty && !_owners.session.watchCancelled) {
        final batch = pendingKeywords
            .take(_owners.settings.channelBatchSize)
            .toList();
        pendingKeywords = pendingKeywords.skip(batch.length).toList();

        final futures = batch.map((kw) {
          debugPrint('DebrifyTV: Searching engines for "$kw"...');
          return TorrentService.searchAllEngines(
            kw,
            engineStates: engineStates,
            maxResultsOverrides: maxResultsOverrides,
          );
        }).toList();

        await for (final result in Stream.fromFutures(futures)) {
          if (_owners.session.watchCancelled) {
            break;
          }
          final List<Torrent> torrents =
              (result['torrents'] as List<Torrent>?) ?? <Torrent>[];
          final engineCounts =
              (result['engineCounts'] as Map<String, int>?) ?? const {};
          final Map<String, String> engineErrors = {};
          final rawErrors = result['engineErrors'];
          if (rawErrors is Map) {
            rawErrors.forEach((key, value) {
              engineErrors[key.toString()] = value?.toString() ?? '';
            });
          }
          if (engineErrors.isNotEmpty) {
            engineErrors.forEach((engine, message) {
              debugPrint('DebrifyTV: Search engine "$engine" failed: $message');
            });
          }
          debugPrint(
            'DebrifyTV: Partial results received: total=${torrents.length}, engineCounts=$engineCounts',
          );

          // Apply NSFW filter if enabled
          List<Torrent> torrentsToProcess = torrents;
          if (_owners.settings.quickAvoidNsfw ||
              _owners.settings.viewerForcesNsfw) {
            final beforeCount = torrents.length;
            torrentsToProcess = torrents.where((torrent) {
              if (NsfwFilter.shouldFilter(torrent.category, torrent.name)) {
                debugPrint('DebrifyTV: Filtered NSFW torrent: ${torrent.name}');
                return false;
              }
              return true;
            }).toList();
            if (beforeCount != torrentsToProcess.length) {
              debugPrint(
                'DebrifyTV: NSFW filter: $beforeCount → ${torrentsToProcess.length} torrents',
              );
            }
          }

          // Filter out RD-blocked torrents
          if (_owners.settings.rdSkipBlockedTorrents) {
            torrentsToProcess = torrentsToProcess
                .where((t) => !isRdBlockedTorrent(t.name))
                .toList();
          }

          int added = 0;
          for (final t in torrentsToProcess) {
            if (!dedupByInfohash.containsKey(t.infohash)) {
              dedupByInfohash[t.infohash] = t;
              added++;
            }
          }
          if (added > 0) {
            if (_owners.session.watchCancelled) {
              break;
            }
            final combined = _sections.filters.applyQualityFilterToTorrents(
              dedupByInfohash.values.toList(),
            );
            combined.shuffle(Random());
            _owners.session.queue
              ..clear()
              ..addAll(combined);
            _owners.session.lastQueueSize = _owners.session.queue.length;
            _owners.session.lastSearchAt = DateTime.now();
            // Silent approach - no progress logging needed
            if (_deps.mounted() && !_owners.session.watchCancelled) {
              _deps.setState(() {
                _owners.session.status = 'Preparing your content...';
              });
            }

            // Do not start prefetch until player launches

            // Try to launch player as soon as a playable stream is available
            if (!_owners.session.launchedPlayer &&
                !_owners.session.watchCancelled) {
              final first = await requestMagicNext();
              if (_owners.session.watchCancelled) {
                break;
              }
              if (first != null &&
                  _deps.mounted() &&
                  !_owners.session.launchedPlayer &&
                  !_owners.session.watchCancelled) {
                _owners.session.launchedPlayer = true;
                final firstUrl = first['url'] ?? '';
                final firstTitleResolved =
                    (first['title'] ?? firstTitle).trim().isNotEmpty
                    ? (first['title'] ?? firstTitle)
                    : firstTitle;
                if (!_owners.session.watchCancelled &&
                    _owners.progress.progressOpen &&
                    _owners.progress.progressSheetContext != null) {
                  Navigator.of(_owners.progress.progressSheetContext!).pop();
                }
                debugPrint(
                  'DebrifyTV: Launching player early. Remaining queue=${_owners.session.queue.length}',
                );

                // Start background prefetch only while player is active
                if (!_owners.session.watchCancelled) {
                  _owners.prefetch.activeApiKey = apiKeyEarly;
                  _owners.prefetch.activeProvider =
                      DebrifyTvConstants.providerRealDebrid;
                  unawaited(_sections.prefetch.startPrefetch());

                  final String? activeChannelId =
                      _owners.library.currentWatchingChannelId;
                  final int? activeChannelNumber;
                  if (activeChannelId != null) {
                    final int idx = _owners.library.channels.indexWhere(
                      (c) => c.id == activeChannelId,
                    );
                    if (idx >= 0) {
                      final int resolvedNumber = _sections.library
                          .resolveChannelNumber(_owners.library.channels[idx]);
                      activeChannelNumber = resolvedNumber > 0
                          ? resolvedNumber
                          : null;
                    } else {
                      activeChannelNumber = null;
                    }
                  } else {
                    activeChannelNumber = null;
                  }
                  final List<Map<String, dynamic>>? activeChannelDirectory =
                      _owners.library.channels.isNotEmpty
                      ? _sections.library.androidTvChannelMetadata(
                          activeChannelId: activeChannelId,
                        )
                      : null;

                  // External player set as the default: hand this one title
                  // over and stop the search — nothing rotates past it.
                  if (await _sections.handoff.handOffToExternalPlayer(
                    firstUrl,
                    firstTitleResolved,
                  )) {
                    break; // Exit the search loop
                  }

                  // Try to launch on Android TV first (early launch path)
                  final launchedOnTv = await _sections.handoff
                      .launchRealDebridOnAndroidTv(
                        firstStream: first,
                        requestNext: requestMagicNext,
                        showChannelNameOverride:
                            _owners.settings.quickShowChannelName,
                        channelId: activeChannelId,
                        channelNumber: activeChannelNumber,
                        channelDirectory: activeChannelDirectory,
                      );

                  if (launchedOnTv) {
                    // Successfully launched on Android TV
                    debugPrint(
                      'DebrifyTV: Early launch - Real-Debrid playback started on Android TV',
                    );
                    // Prefetch will continue in background while TV player is active
                    break; // Exit the search loop
                  }

                  // Hide auto-launch overlay before launching player
                  MainPageBridge.notifyPlayerLaunching();

                  // Fall back to Flutter video player
                  await Navigator.of(_deps.context()).push(
                    videoPlayerRoute(
                      builder: (_) => VideoPlayerScreen(
                        videoUrl: firstUrl,
                        title: firstTitleResolved,
                        startFromRandom: _owners.settings.quickStartRandom,
                        randomStartMaxPercent:
                            _owners.settings.quickRandomStartPercent,
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
                                        DebrifyTvConstants.providerPremiumize)
                            ? _sections.channelWatch.requestNextChannel
                            : null,
                        channelDirectory: activeChannelDirectory,
                        requestChannelById: _owners.library.channels.length > 1
                            ? _sections.channelWatch.requestChannelById
                            : null,
                      ),
                    ),
                  );

                  // Stop prefetch when player exits
                  await _sections.prefetch.stopPrefetch();
                }
              }
            }
          }
        }
        if (_owners.session.watchCancelled) {
          break;
        }
      }
      // Final queue snapshot (if we didn't launch early)
      if (!_owners.session.launchedPlayer) {
        // The per-batch rebuilds above filter strictly, so an empty queue here
        // means nothing in the whole search matched the quality filter. This
        // is the point where that's genuinely known — degrade to unfiltered
        // rather than reporting "no results" for a search that found plenty.
        if (_owners.session.queue.isEmpty &&
            _owners.settings.tvFilters.hasQuality &&
            dedupByInfohash.isNotEmpty &&
            !_owners.session.watchCancelled) {
          _sections.filters.notifyQualityFallback();
          final fallback = dedupByInfohash.values.toList()..shuffle(Random());
          _owners.session.queue
            ..clear()
            ..addAll(fallback);
        }
        debugPrint(
          'DebrifyTV: Queue prepared. size=${_owners.session.queue.length}',
        );
        _owners.session.lastQueueSize = _owners.session.queue.length;
        _owners.session.lastSearchAt = DateTime.now();
      }
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status = 'Search failed: $e';
      });
      debugPrint('DebrifyTV: Search failed: $e');
      if (e is NativePlayerSettingsUnavailable) {
        _sections.feedback.showNativeSettingsFailure(e);
        return;
      }
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
        });
      }
    }

    if (_owners.session.watchCancelled) {
      debugPrint('DebrifyTV: Watch was cancelled before completion.');
      return;
    }

    if (!_deps.mounted()) return;
    if (_owners.session.queue.isEmpty) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status = 'No results found';
      });
      debugPrint('DebrifyTV: No results found after combining.');
      _log('❌ No results found - trying different search strategies');

      // Close popup and show user-friendly message
      if (_owners.progress.progressOpen &&
          _owners.progress.progressSheetContext != null) {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
        _owners.progress.progressOpen = false;
        _owners.progress.progressSheetContext = null;
      }

      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = 'No results found. Try different keywords.';
        });
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text(
              'No results found. Try different keywords or check your internet connection.',
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // If we already launched the player early, we're done here
    if (_owners.session.launchedPlayer) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _owners.session.status = '';
      });
      return;
    }

    // Helper to infer a filename-like title from a URL
    String _inferTitleFromUrl(String url) {
      final uri = Uri.tryParse(url);
      final last = (uri != null && uri.pathSegments.isNotEmpty)
          ? uri.pathSegments.last
          : url;
      return Uri.decodeComponent(last);
    }

    // Build a provider for "next" requests that reuses the same queue and keywords
    final apiKey = await RealDebridStorage.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (!_deps.mounted()) return;
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add your Real Debrid API key in Settings first!',
          ),
        ),
      );
      debugPrint('MagicTV: Missing Real Debrid API key.');
      return;
    }

    String firstTitle = 'Debrify TV';

    Future<Map<String, String>?> requestMagicNext() async {
      debugPrint(
        'MagicTV: requestMagicNext() called. queueSize=${_owners.session.queue.length}',
      );
      while (_owners.session.queue.isNotEmpty) {
        final item = _owners.session.queue.removeAt(0);
        // Case 1: RD-restricted entry (append-only items)
        if (item is Map && item['type'] == 'rd_restricted') {
          final String link = item['restrictedLink'] as String? ?? '';
          final String rdTid = item['torrentId'] as String? ?? '';
          debugPrint('MagicTV: Trying RD link from queue: torrentId=$rdTid');
          if (link.isEmpty) continue;
          try {
            final started = DateTime.now();
            final unrestrict = await DebridService.unrestrictLink(apiKey, link);
            if (!_sections.filters.rdLinkPassesSizeRules(unrestrict)) continue;
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = unrestrict['download'] as String?;
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'MagicTV: Success (RD link). Unrestricted in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to any stored displayName
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final display = (item['displayName'] as String?)?.trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (display ?? 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: RD link failed to unrestrict: $e');
            continue;
          }
        }

        // Case 2: Torrent entry
        if (item is Torrent) {
          debugPrint(
            'MagicTV: Trying torrent: name="${item.name}", hash=${item.infohash}, size=${item.sizeBytes}, seeders=${item.seeders}',
          );
          final magnetLink = 'magnet:?xt=urn:btih:${item.infohash}';
          try {
            final started = DateTime.now();
            final result = await DebridService.addTorrentToDebridPreferVideos(
              apiKey,
              magnetLink,
            );
            final elapsed = DateTime.now().difference(started).inSeconds;
            final videoUrl = result['downloadLink'] as String?;
            // Append other RD-restricted links from this torrent to the END of the queue
            final String torrentId = result['torrentId'] as String? ?? '';
            final List<dynamic> rdLinks =
                (result['links'] as List<dynamic>? ?? const []);
            if (rdLinks.isNotEmpty) {
              // We assume we used rdLinks[0] to play; enqueue remaining
              for (int i = 1; i < rdLinks.length; i++) {
                final String link = rdLinks[i]?.toString() ?? '';
                if (link.isEmpty) continue;
                final String combined = '$torrentId|$link';
                if (_owners.session.seenRestrictedLinks.contains(link) ||
                    _owners.session.seenLinkWithTorrentId.contains(combined)) {
                  continue;
                }
                _owners.session.seenRestrictedLinks.add(link);
                _owners.session.seenLinkWithTorrentId.add(combined);
                _owners.session.queue.add({
                  'type': 'rd_restricted',
                  'restrictedLink': link,
                  'torrentId': torrentId,
                  'displayName': item.name,
                });
              }
              if (rdLinks.length > 1) {
                debugPrint(
                  'MagicTV: Enqueued ${rdLinks.length - 1} additional RD links to tail. New queueSize=${_owners.session.queue.length}',
                );
              }
            }
            if (videoUrl != null && videoUrl.isNotEmpty) {
              debugPrint(
                'MagicTV: Success. Got unrestricted URL in ${elapsed}s',
              );
              // Prefer filename inferred from URL; fallback to torrent name
              final inferred = _inferTitleFromUrl(videoUrl).trim();
              final chosenTitle = inferred.isNotEmpty
                  ? inferred
                  : (item.name.trim().isNotEmpty ? item.name : 'Debrify TV');
              firstTitle = chosenTitle;
              return {'url': videoUrl, 'title': chosenTitle};
            }
          } catch (e) {
            debugPrint('MagicTV: Debrid add failed for ${item.infohash}: $e');
          }
        }
      }
      debugPrint('MagicTV: requestMagicNext() queue exhausted.');
      return null;
    }

    _deps.setState(() {
      _owners.session.status = 'Finding a playable stream...';
      _owners.session.isBusy = true;
    });
    _log('🎬 Selecting the best quality stream for you');

    try {
      final first = await requestMagicNext();
      if (first == null) {
        // Close popup and show user-friendly message
        if (_owners.progress.progressOpen &&
            _owners.progress.progressSheetContext != null) {
          Navigator.of(_owners.progress.progressSheetContext!).pop();
          _owners.progress.progressOpen = false;
          _owners.progress.progressSheetContext = null;
        }

        if (_deps.mounted()) {
          _deps.setState(() {
            _owners.session.isBusy = false;
            _owners.session.status =
                'No playable torrents found. Try different keywords.';
          });
          MainPageBridge.notifyAutoLaunchFailed('No playable streams found');
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            const SnackBar(
              content: Text(
                'No playable streams found. Try different keywords or check your internet connection.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
        debugPrint('MagicTV: No playable stream found.');
        return;
      }
      final firstUrl = first['url'] ?? '';
      firstTitle = (first['title'] ?? firstTitle).trim().isNotEmpty
          ? (first['title'] ?? firstTitle)
          : firstTitle;

      if (!_deps.mounted()) return;
      debugPrint(
        'MagicTV: Launching player. Remaining queue=${_owners.session.queue.length}',
      );

      // Start background prefetch while player is active
      _owners.prefetch.activeApiKey = apiKey;
      _owners.prefetch.activeProvider = DebrifyTvConstants.providerRealDebrid;
      unawaited(_sections.prefetch.startPrefetch());

      if (_owners.progress.progressOpen &&
          _owners.progress.progressSheetContext != null) {
        Navigator.of(_owners.progress.progressSheetContext!).pop();
      }

      final String? activeChannelId = _owners.library.currentWatchingChannelId;
      final int? activeChannelNumber;
      if (activeChannelId != null) {
        final int idx = _owners.library.channels.indexWhere(
          (c) => c.id == activeChannelId,
        );
        if (idx >= 0) {
          final int resolvedNumber = _sections.library.resolveChannelNumber(
            _owners.library.channels[idx],
          );
          activeChannelNumber = resolvedNumber > 0 ? resolvedNumber : null;
        } else {
          activeChannelNumber = null;
        }
      } else {
        activeChannelNumber = null;
      }
      final List<Map<String, dynamic>>? quickChannelDirectory =
          _owners.library.channels.isNotEmpty
          ? _sections.library.androidTvChannelMetadata(
              activeChannelId: activeChannelId,
            )
          : null;

      if (await _sections.handoff.handOffToExternalPlayer(
        firstUrl,
        firstTitle,
      )) {
        return;
      }

      // Try to launch on Android TV first
      final launchedOnTv = await _sections.handoff.launchRealDebridOnAndroidTv(
        firstStream: first,
        requestNext: requestMagicNext,
        showChannelNameOverride: _owners.settings.quickShowChannelName,
        channelId: activeChannelId,
        channelNumber: activeChannelNumber,
        channelDirectory: quickChannelDirectory,
      );

      if (launchedOnTv) {
        // Successfully launched on Android TV
        debugPrint('MagicTV: Real-Debrid playback started on Android TV');
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
                            DebrifyTvConstants.providerPikPak)
                ? _sections.channelWatch.requestNextChannel
                : null,
            channelDirectory: quickChannelDirectory,
            requestChannelById: _owners.library.channels.length > 1
                ? _sections.channelWatch.requestChannelById
                : null,
          ),
        ),
      );
      // Stop prefetch when player exits
      await _sections.prefetch.stopPrefetch();
    } on NativePlayerSettingsUnavailable catch (error) {
      _sections.feedback.showNativeSettingsFailure(error);
    } finally {
      if (_deps.mounted()) {
        _deps.setState(() {
          _owners.session.isBusy = false;
          _owners.session.status = '';
        });
        debugPrint('MagicTV: Watch flow finished.');
      }
    }
  }
}
