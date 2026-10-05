import 'dart:async';
import 'dart:math';

import 'package:debrify/features/debrify_tv/models/debrify_tv_constants.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelWatch {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelWatch(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  /// [leadWith] (the Spotlight stage's play-one-title): that torrent plays
  /// FIRST, with the rest of the shuffled selection behind it. NEVER a
  /// single-element queue — the pick may not be cached at the provider, and
  /// a one-item queue has nothing to fall back to, which would make a
  /// deliberate choice fail exactly where Tune in would have succeeded.
  Future<void> watchChannel(
    DebrifyTvChannel channel, {
    CachedTorrent? leadWith,
  }) async {
    debugPrint('🎬 [WATCH] Starting for channel: ${channel.name}');
    _owners.session.qualityFallbackNotified = false;
    _owners.session.rdSizeRejections = 0;
    _owners.session.sizeFilterRelaxed = false;

    final keywords = await _sections.library.getChannelKeywords(channel.id);
    if (keywords.isEmpty) {
      debugPrint('❌ [WATCH] No keywords');
      MainPageBridge.notifyAutoLaunchFailed('Channel has no keywords');
      _sections.feedback.showSnack(
        'Channel has no keywords yet',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Keywords: ${keywords.length}');

    await _sections.settings.syncProviderAvailability();
    final bool providerReady = switch (_owners.settings.provider) {
      DebrifyTvConstants.providerTorbox => _owners.settings.torboxAvailable,
      DebrifyTvConstants.providerPikPak => _owners.settings.pikpakAvailable,
      DebrifyTvConstants.providerPremiumize =>
        _owners.settings.premiumizeAvailable,
      DebrifyTvConstants.providerAllDebrid =>
        _owners.settings.allDebridAvailable,
      _ => _owners.settings.rdAvailable,
    };
    if (!providerReady) {
      debugPrint('❌ [WATCH] Provider not ready: ${_owners.settings.provider}');
      MainPageBridge.notifyAutoLaunchFailed('Provider not configured');
      final providerName = _sections.settings.providerDisplay(
        _owners.settings.provider,
      );
      _sections.feedback.showSnack(
        'Enable $providerName in Settings to watch this channel',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Provider ready: ${_owners.settings.provider}');

    final cacheEntry = await _sections.library.ensureCacheEntry(channel.id);
    if (cacheEntry == null) {
      debugPrint('❌ [WATCH] Cache entry is null');
      MainPageBridge.notifyAutoLaunchFailed('Cache entry not found');
      _sections.feedback.showSnack(
        'Channel cache not found. Edit the channel to rebuild it.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache entry loaded, status: ${cacheEntry.status}');

    if (!cacheEntry.isReady) {
      debugPrint('❌ [WATCH] Cache not ready, status: ${cacheEntry.status}');
      MainPageBridge.notifyAutoLaunchFailed(
        'Cache not ready: ${cacheEntry.status}',
      );
      final message =
          cacheEntry.errorMessage ??
          'Channel cache failed to build. Try editing and saving again.';
      _sections.feedback.showSnack(message, color: Colors.orange);
      return;
    }

    if (cacheEntry.torrents.isEmpty) {
      debugPrint('❌ [WATCH] Cache has no torrents');
      MainPageBridge.notifyAutoLaunchFailed('Cache has no torrents');
      _sections.feedback.showSnack(
        'No torrents cached yet. Try editing the channel keywords.',
        color: Colors.orange,
      );
      return;
    }
    debugPrint('✅ [WATCH] Cache has ${cacheEntry.torrents.length} torrents');

    final previousKeywords = _owners.library.keywordsController.text;

    final int resolvedChannelNumber = _sections.library.resolveChannelNumber(
      channel,
    );

    _deps.setState(() {
      _owners.library.currentWatchingChannelId =
          channel.id; // Track for channel switching
    });
    _owners.library.keywordsController.text = keywords.join(', ');

    final normalizedKeywords = _sections.library.normalizedKeywords(keywords);
    final playbackSelection = _sections.filters.selectTorrentsForPlayback(
      cacheEntry,
      normalizedKeywords,
    );
    if (leadWith != null) {
      // The chosen title to the front; behaviour after it ends is unchanged.
      playbackSelection.removeWhere((t) => t.infohash == leadWith.infohash);
      playbackSelection.insert(0, leadWith);
      if (playbackSelection.length == 1 && cacheEntry.torrents.length > 1) {
        // The filter narrowed the selection to the pick alone while the pool
        // holds more: refill behind it from the wider pool (same cap the
        // selector uses), or an uncached pick would have nothing to fall
        // through to — the single-element queue the plan forbids.
        final rest =
            cacheEntry.torrents
                .where((t) => t.infohash != leadWith.infohash)
                .toList()
              ..shuffle(Random());
        playbackSelection.addAll(
          rest.take(DebrifyTvConstants.playbackTorrentThreshold),
        );
      }
    }
    final cachedTorrents = playbackSelection
        .map((cached) => cached.toTorrent())
        .toList();
    debugPrint(
      '✅ [WATCH] Selected ${cachedTorrents.length} torrents for playback',
    );

    if (_owners.settings.provider == DebrifyTvConstants.providerTorbox) {
      debugPrint('🎬 [WATCH] Launching Torbox flow...');
      await _sections.cachedTorbox.watchTorboxWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider == DebrifyTvConstants.providerPikPak) {
      debugPrint('🎬 [WATCH] Launching PikPak flow...');
      await _sections.cachedPikPak.watchPikPakWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider ==
        DebrifyTvConstants.providerPremiumize) {
      debugPrint('🎬 [WATCH] Launching Premiumize flow...');
      await _sections.cachedPremiumize.watchPremiumizeWithCachedTorrents(
        cachedTorrents,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else if (_owners.settings.provider ==
        DebrifyTvConstants.providerAllDebrid) {
      debugPrint('🎬 [WATCH] Launching AllDebrid flow...');
      await _sections.cachedAllDebrid.watchAllDebridWithCachedTorrents(
        cachedTorrents,
        applyNsfwFilter: channel.avoidNsfw || _owners.settings.viewerForcesNsfw,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    } else {
      debugPrint('🎬 [WATCH] Launching RealDebrid flow...');
      await _sections.cachedRealDebrid.watchWithCachedTorrents(
        cachedTorrents,
        applyNsfwFilter: channel.avoidNsfw || _owners.settings.viewerForcesNsfw,
        channelName: channel.name,
        channelId: channel.id,
        channelNumber: resolvedChannelNumber,
      );
    }

    if (!_deps.mounted()) {
      return;
    }

    _owners.library.keywordsController.text = previousKeywords;
  }

  /// Handle channel switching on Android TV - cycles to next channel with looping
  Future<Map<String, dynamic>?> requestNextChannel() async {
    debugPrint('DebrifyTV: _requestNextChannel() called');

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available');
      return null;
    }

    int currentIndex = -1;
    if (_owners.library.currentWatchingChannelId != null) {
      currentIndex = _owners.library.channels.indexWhere(
        (c) => c.id == _owners.library.currentWatchingChannelId,
      );
    }

    final int nextIndex = (currentIndex + 1) % _owners.library.channels.length;
    final DebrifyTvChannel targetChannel = _owners.library.channels[nextIndex];

    debugPrint(
      'DebrifyTV: Switching from channel ${currentIndex + 1} to ${nextIndex + 1} (${targetChannel.name})',
    );

    return _sections.channelSwitch.switchToChannel(
      targetChannel,
      fallbackIndex: nextIndex,
      reason: 'next',
    );
  }

  Future<Map<String, dynamic>?> requestChannelById(String channelId) async {
    debugPrint('DebrifyTV: _requestChannelById($channelId) called');

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTV: No channels available for direct selection');
      return null;
    }

    DebrifyTvChannel? targetChannel;
    int discoveredIndex = -1;
    for (var i = 0; i < _owners.library.channels.length; i++) {
      final channel = _owners.library.channels[i];
      if (channel.id == channelId) {
        targetChannel = channel;
        discoveredIndex = i;
        break;
      }
    }

    if (targetChannel == null) {
      debugPrint('DebrifyTV: Channel id $channelId not found');
      return null;
    }

    if (_owners.library.currentWatchingChannelId == targetChannel.id) {
      debugPrint(
        'DebrifyTV: Selected channel is already active; refreshing playback',
      );
    } else {
      debugPrint(
        'DebrifyTV: Switching directly to channel ${targetChannel.name}',
      );
    }

    return _sections.channelSwitch.switchToChannel(
      targetChannel,
      fallbackIndex: discoveredIndex >= 0 ? discoveredIndex : null,
      reason: 'direct',
    );
  }
}
