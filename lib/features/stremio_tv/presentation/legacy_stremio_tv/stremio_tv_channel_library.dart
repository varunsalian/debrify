import 'dart:async';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';

import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';

import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';

import 'package:debrify/services/main_page_bridge.dart';

import 'package:flutter/material.dart';

class StremioTvChannelLibrary {
  StremioTvChannelLibrary(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  /// Get the rotation duration for a channel based on its content type.
  int rotationFor(StremioTvChannel channel) => channel.type == 'series'
      ? _owners.settings.seriesRotationMinutes
      : _owners.settings.rotationMinutes;

  Future<void> discoverAndLoad() async {
    _deps.setState(() => _owners.library.loading = true);

    final channels = await _owners.library.service.discoverChannels();

    // Set up focus nodes
    for (final node in _owners.focus.rowFocusNodes) {
      node.dispose();
    }
    _owners.focus.rowFocusNodes.clear();
    for (int i = 0; i < channels.length; i++) {
      _owners.focus.rowFocusNodes.add(FocusNode(debugLabel: 'stremioTvRow$i'));
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.library.channels = _sections.library.sortedChannels(channels);
        _owners.library.loading = false;
      });
    }

    // Handle pending auto-play (eagerly load the target channel first)
    if (_owners.playback.pendingChannelId != null && _deps.mounted()) {
      final id = _owners.playback.pendingChannelId!;
      _owners.playback.pendingChannelId = null;
      _owners.playback.startupAutoPlayActive = true;
      await _sections.library._ensureChannelLoaded(id);
      if (_deps.mounted()) _sections.actions.playChannelById(id);
    }
  }

  void notifyStartupAutoLaunchFailed(String reason) {
    if (!_owners.playback.startupAutoPlayActive) return;
    _owners.playback.startupAutoPlayActive = false;
    MainPageBridge.notifyAutoLaunchFailed(reason);
  }

  void notifyStartupPlayerLaunching() {
    if (!_owners.playback.startupAutoPlayActive) return;
    _owners.playback.startupAutoPlayActive = false;
    MainPageBridge.notifyPlayerLaunching();
  }

  Future<void> refresh() async {
    if (_owners.library.refreshing) return;
    _deps.setState(() => _owners.library.refreshing = true);

    await _sections.settings.loadSettings();
    final channels = await _owners.library.service.discoverChannels();

    // Clear loading tracker and invalidate cache so channels refetch
    _owners.library.loadingChannelIds.clear();
    for (final ch in channels) {
      ch.lastFetched = null;
    }

    // Reset focus nodes
    for (final node in _owners.focus.rowFocusNodes) {
      node.dispose();
    }
    _owners.focus.rowFocusNodes.clear();
    for (int i = 0; i < channels.length; i++) {
      _owners.focus.rowFocusNodes.add(FocusNode(debugLabel: 'stremioTvRow$i'));
    }

    if (_deps.mounted()) {
      _deps.setState(() {
        _owners.library.channels = _sections.library.sortedChannels(channels);
        _owners.library.refreshing = false;
      });
    } else {
      _owners.library.refreshing = false;
    }
  }

  List<StremioTvChannel> sortedChannels(List<StremioTvChannel> channels) {
    final favorites = channels.where((ch) => ch.isFavorite).toList();
    final rest = channels.where((ch) => !ch.isFavorite).toList();
    favorites.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));
    rest.sort((a, b) => a.channelNumber.compareTo(b.channelNumber));
    return [...favorites, ...rest];
  }

  // ============================================================================
  // Lazy Loading
  // ============================================================================
  /// Lazy-load items for a single channel by ID.
  Future<void> _ensureChannelLoaded(String channelId) async {
    final idx = _owners.library.channels.indexWhere((ch) => ch.id == channelId);
    if (idx == -1) return;
    await _sections.library.ensureChannelItemsLoaded(
      _owners.library.channels[idx],
    );
  }

  /// Lazy-load items for a single channel.
  /// Prevents duplicate concurrent fetches via [_loadingChannelIds].
  /// Removes the channel from the list if it loads with zero items.
  Future<void> ensureChannelItemsLoaded(StremioTvChannel channel) async {
    if (channel.isLocal) return;
    if (channel.hasItems && !channel.isCacheStale) return;
    if (_owners.library.loadingChannelIds.contains(channel.id)) return;

    _owners.library.loadingChannelIds.add(channel.id);

    try {
      await _owners.library.service.loadChannelItems(channel);
    } catch (_) {
      // Mark as fetched so we don't retry every frame
      channel.lastFetched = DateTime.now();
    } finally {
      _owners.library.loadingChannelIds.remove(channel.id);
    }

    if (!_deps.mounted()) return;

    // Remove channels that loaded with no usable items
    if (channel.items.isEmpty && channel.lastFetched != null) {
      _deps.setState(() {
        final idx = _owners.library.channels.indexWhere(
          (ch) => ch.id == channel.id,
        );
        if (idx == -1) return;

        // Rescue focus before disposing the node
        final removingFocused =
            idx < _owners.focus.rowFocusNodes.length &&
            _owners.focus.rowFocusNodes[idx].hasFocus;
        if (removingFocused) {
          if (idx > 0 && idx - 1 < _owners.focus.rowFocusNodes.length) {
            _owners.focus.rowFocusNodes[idx - 1].requestFocus();
          } else if (idx + 1 < _owners.focus.rowFocusNodes.length) {
            _owners.focus.rowFocusNodes[idx + 1].requestFocus();
          } else {
            _owners.focus.searchFocusNode.requestFocus();
          }
        }

        _owners.library.channels.removeAt(idx);
        if (idx < _owners.focus.rowFocusNodes.length) {
          _owners.focus.rowFocusNodes[idx].dispose();
          _owners.focus.rowFocusNodes.removeAt(idx);
        }

        // Keep _focusedIndex in sync
        if (removingFocused) {
          _owners.focus.focusedIndex = idx > 0 ? idx - 1 : 0;
        } else if (_owners.focus.focusedIndex > idx) {
          _owners.focus.focusedIndex--;
        }
      });
    } else {
      // Items landed for an existing channel: rebuild just the tuner (via its
      // ValueListenableBuilder), not the whole screen — a full setState here
      // fired once per completing fetch and stuttered mid-surf navigation.
      _owners.library.contentRevision.value++;
    }
  }
}
