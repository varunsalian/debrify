import 'dart:async';

import 'package:collection/collection.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_bindings.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_owners.dart';
import 'package:debrify/features/debrify_tv/presentation/legacy_debrify_tv/debrify_tv_sections.dart';
import 'package:debrify/models/debrify_tv/channel.dart';
import 'package:debrify/models/debrify_tv/channel_stats.dart';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_repository.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DebrifyTvChannelLibrary {
  final DebrifyTvDependencies _deps;
  DebrifyTvChannelLibrary(this._deps);
  DebrifyTvOwners get _owners => _deps.owners;
  DebrifyTvSections get _sections => _deps.sections;

  Future<void> loadChannels() async {
    final records = await DebrifyTvRepository.instance.fetchAllChannels();
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _owners.library.channels = records
          .map(DebrifyTvChannel.fromRecord)
          .toList(growable: false);
    });
    // Every path that reloads channels (create, edit, delete-all, ZIP/YAML/
    // community imports) has fresh pools too, so the rail's pips ride along
    // here rather than each call site remembering to refresh them.
    if (_owners.library.debrifyTvStyle == 'spotlight') {
      await _sections.stage.loadSpotlightRailHealth();
    }
  }

  void handleSyncedDebrifyTvLibraryChanged() {
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _owners.library.channelCache.clear();
      _owners.stage.spotlightStats.clear();
      _owners.stage.spotlightRailHealth = const <String, DebrifyTvRailHealth>{};
    });
    unawaited(_sections.library.loadChannels());
  }

  Future<void> loadFavoriteChannels() async {
    final favoriteIds = await DebrifyTvStorage.getDebrifyTvFavoriteChannelIds();
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _owners.library.favoriteChannelIds = favoriteIds;
    });
  }

  Future<void> toggleChannelFavorite(DebrifyTvChannel channel) async {
    final isFavorited = _owners.library.favoriteChannelIds.contains(channel.id);
    final newState = !isFavorited;

    await DebrifyTvStorage.setDebrifyTvChannelFavorited(channel.id, newState);

    if (!_deps.mounted()) return;
    _deps.setState(() {
      if (newState) {
        _owners.library.favoriteChannelIds = {
          ..._owners.library.favoriteChannelIds,
          channel.id,
        };
      } else {
        _owners.library.favoriteChannelIds = _owners.library.favoriteChannelIds
            .where((id) => id != channel.id)
            .toSet();
      }
    });
  }

  /// Watch a channel by ID (called from external sources like home screen)
  Future<void> watchChannelById(String channelId) async {
    final channel = _owners.library.channels.firstWhereOrNull(
      (c) => c.id == channelId,
    );
    if (channel != null) {
      _sections.legacy.watchChannel(channel);
    } else {
      debugPrint('DebrifyTVScreen: Channel with ID $channelId not found');
    }
  }

  /// Check for pending auto-play channel from home screen
  Future<void> checkPendingAutoPlay() async {
    final channelId = MainPageBridge.getAndClearDebrifyTvChannelToAutoPlay();
    if (channelId == null) return;

    // Wait for channels to load
    int attempts = 0;
    const maxAttempts = 50; // 5 seconds max wait
    while (_owners.library.channels.isEmpty && attempts < maxAttempts) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
      if (!_deps.mounted()) return;
    }

    if (_owners.library.channels.isEmpty) {
      debugPrint('DebrifyTVScreen: Channels not loaded for auto-play');
      return;
    }

    _sections.library.watchChannelById(channelId);
  }

  Future<void> deleteChannel(String id) async {
    _deps.setState(() {
      _owners.library.channels = _owners.library.channels
          .where((c) => c.id != id)
          .toList();
    });
    await DebrifyTvRepository.instance.deleteChannel(id);
    _deps.setState(() {
      _owners.library.channelCache.remove(id);
      _owners.stage.spotlightStats.remove(id);
      _owners.stage.spotlightRailHealth = Map.of(
        _owners.stage.spotlightRailHealth,
      )..remove(id);
      // The layout's staged-channel repair fires onChannelFocused for its
      // replacement; a dangling id here would make that look like a no-move.
      if (_owners.stage.spotlightFocusedId == id)
        _owners.stage.spotlightFocusedId = null;
    });
  }

  List<String> parseKeywords(String input) {
    return input
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  List<String> normalizedKeywords(List<String> keywords) {
    final seen = <String>{};
    final normalized = <String>[];
    for (final keyword in keywords) {
      final value = keyword.trim().toLowerCase();
      if (value.isEmpty || seen.contains(value)) {
        continue;
      }
      seen.add(value);
      normalized.add(value);
    }
    return normalized;
  }

  Future<DebrifyTvChannelCacheEntry?> ensureCacheEntry(String channelId) async {
    final cached = _owners.library.channelCache[channelId];
    if (cached != null) {
      return cached;
    }
    final fetched = await DebrifyTvCacheService.getEntry(channelId);
    if (fetched != null) {
      _owners.library.channelCache[channelId] = fetched;
    }
    return fetched;
  }

  Future<List<String>> getChannelKeywords(String channelId) async {
    final index = _owners.library.channels.indexWhere((c) => c.id == channelId);
    if (index == -1) {
      return const <String>[];
    }
    final existing = _owners.library.channels[index];
    if (existing.keywords.isNotEmpty) {
      return existing.keywords;
    }
    final fetched = await DebrifyTvRepository.instance.fetchChannelKeywords(
      channelId,
    );
    if (!_deps.mounted()) {
      return fetched;
    }
    final updated = existing.copyWith(keywords: fetched);
    _deps.setState(() {
      final next = List<DebrifyTvChannel>.from(_owners.library.channels);
      next[index] = updated;
      _owners.library.channels = next;
    });
    return fetched;
  }

  String resolveUniqueChannelName(
    String baseName,
    Set<String> usedLowerCaseNames,
  ) {
    final String trimmed = baseName.trim().isEmpty
        ? 'Imported Channel'
        : baseName.trim();
    String candidate = trimmed;
    int suffix = 2;
    while (usedLowerCaseNames.contains(candidate.toLowerCase())) {
      candidate = '$trimmed ($suffix)';
      suffix++;
    }
    return candidate;
  }

  int resolveChannelNumber(DebrifyTvChannel channel) {
    if (channel.channelNumber > 0) {
      return channel.channelNumber;
    }
    final int index = _owners.library.channels.indexWhere(
      (element) => element.id == channel.id,
    );
    if (index >= 0) {
      return index + 1;
    }
    final int fallback = _owners.library.channels.indexOf(channel);
    return fallback >= 0 ? fallback + 1 : 0;
  }

  List<Map<String, dynamic>> androidTvChannelMetadata({
    String? activeChannelId,
  }) {
    if (_owners.library.channels.isEmpty) {
      return const <Map<String, dynamic>>[];
    }
    final String? highlightId =
        activeChannelId ?? _owners.library.currentWatchingChannelId;
    final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
    for (var i = 0; i < _owners.library.channels.length; i++) {
      final channel = _owners.library.channels[i];
      payload.add({
        'id': channel.id,
        'name': channel.name,
        'channelNumber': channel.channelNumber > 0
            ? channel.channelNumber
            : i + 1,
        'isCurrent': highlightId != null && channel.id == highlightId,
      });
    }
    return payload;
  }
}
