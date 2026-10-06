import 'dart:async';

import 'package:collection/collection.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/screens/catalog_item_detail_screen.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/stremio_tv/widgets/stremio_tv_local_catalogs_dialog.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StremioTvChannelActions {
  StremioTvChannelActions(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  void playChannelById(String channelId) {
    if (_owners.library.channels.isEmpty) {
      _sections.library.notifyStartupAutoLaunchFailed('Channels not loaded');
      return;
    }
    if (_owners.playback.startupAutoPlayActive &&
        !_owners.library.channels.any((channel) => channel.id == channelId)) {
      _sections.library.notifyStartupAutoLaunchFailed(
        'Startup channel not found',
      );
      return;
    }
    final channel = _owners.library.channels.firstWhere(
      (ch) => ch.id == channelId,
      orElse: () => _owners.library.channels.first,
    );
    _sections.play.playChannel(channel);
  }

  // ============================================================================
  // Channel Detail (cinematic "tune-in")
  // ============================================================================
  /// Tune in: opens the reused [CatalogItemDetailScreen] for the channel's
  /// now-playing item with a fast zoom/fade so selecting a channel feels
  /// like committing to it rather than a stock page push.
  Future<void> openChannelDetail(StremioTvChannel channel) async {
    if (_owners.playback.pushingChannelDetail) return;
    _owners.playback.pushingChannelDetail = true;
    try {
      await _sections.actions._pushChannelDetail(channel);
    } finally {
      _owners.playback.pushingChannelDetail = false;
    }
  }

  Future<void> _pushChannelDetail(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      // _ensureChannelItemsLoaded early-returns when a load is already in
      // flight (the Tuner kicks one off on focus), so the await above may
      // not have actually waited. Poll the in-flight load to settle before
      // deciding there's nothing to show — otherwise "View details" on a
      // still-tuning channel wrongly reports "No items available".
      var waitedMs = 0;
      while (_deps.mounted() &&
          !channel.hasItems &&
          _owners.library.loadingChannelIds.contains(channel.id) &&
          waitedMs < 8000) {
        await Future.delayed(const Duration(milliseconds: 120));
        waitedMs += 120;
      }
      if (!_deps.mounted()) return;
    }
    final nowPlaying = _owners.library.service.getNowPlaying(
      channel,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (nowPlaying == null) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }
    final screen = CatalogItemDetailScreen(
      item: nowPlaying.item,
      isTelevision: _deps.isTelevision(),
      onPlay: () => _sections.play.playChannel(channel),
      onBrowse: () => _sections.play.playChannel(channel),
      enablePrimarySourcesHold: false,
    );
    await Navigator.of(_deps.context()).push(
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => screen,
      ),
    );
  }

  // ============================================================================
  // Channel Guide
  // ============================================================================
  Future<void> showGuide(StremioTvChannel channel) async {
    if (!channel.hasItems) {
      await _sections.library.ensureChannelItemsLoaded(channel);
      if (!_deps.mounted()) return;
    }
    if (channel.items.isEmpty) {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(content: Text('No items available for this channel')),
        );
      }
      return;
    }

    final schedule = _owners.library.service.getSchedule(
      channel,
      count: 5,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (schedule.isEmpty || !_deps.mounted()) return;

    final tappedIndex = await StremioTvGuideSheet.show(
      _deps.context(),
      channel: channel,
      schedule: schedule,
    );

    if (tappedIndex != null && _deps.mounted()) {
      _sections.play.playChannel(channel);
    }
  }

  // ============================================================================
  // Favorites
  // ============================================================================
  Future<void> toggleFavorite(StremioTvChannel channel) async {
    final focusedChannelId = _sections.navigation.currentFocusedChannelId();
    final newState = !channel.isFavorite;
    await StremioTvStorage.setStremioTvChannelFavorited(channel.id, newState);
    if (!_deps.mounted()) return;
    final previousChannels = List<StremioTvChannel>.from(
      _owners.library.channels,
    );
    _deps.setState(() {
      channel.isFavorite = newState;
      _owners.library.channels = _sections.library.sortedChannels(
        _owners.library.channels,
      );
      _sections.navigation.reorderRowFocusNodes(
        previousChannels,
        _owners.library.channels,
      );
    });
    if (focusedChannelId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_deps.mounted()) return;
        final newIndex = _owners.library.channels.indexWhere(
          (ch) => ch.id == focusedChannelId,
        );
        if (newIndex >= 0 && newIndex < _owners.focus.rowFocusNodes.length) {
          _owners.focus.rowFocusNodes[newIndex].requestFocus();
        }
      });
    }
  }

  Future<void> copyLocalCatalogJson(StremioTvChannel channel) async {
    final payload = await LocalCatalogExporter.loadCatalog(
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (!_deps.mounted()) return;
    if (payload == null) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text('Local catalog could not be found'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: payload.json));
    if (!_deps.mounted()) return;
    ScaffoldMessenger.of(_deps.context()).showSnackBar(
      SnackBar(
        content: Text('Copied "${payload.name}" JSON to clipboard'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> editLocalCatalog(StremioTvChannel channel) async {
    final previousFocusedIndex = _owners.focus.focusedIndex;
    final previousFocusedChannelId = _sections.navigation
        .currentFocusedChannelId();
    final previousFilteredIndex = previousFocusedChannelId == null
        ? -1
        : _sections.navigation.filteredChannels.indexWhere(
            (ch) => ch.id == previousFocusedChannelId,
          );
    final changed = await StremioTvLocalCatalogEditorDialog.show(
      _deps.context(),
      catalogId: channel.catalog.id,
      catalogType: channel.type,
    );
    if (changed != true || !_deps.mounted()) return;

    await _sections.library.refresh();
    if (!_deps.mounted()) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted()) return;

      void focusChannelById(String channelId) {
        final channelIndex = _owners.library.channels.indexWhere(
          (ch) => ch.id == channelId,
        );
        if (channelIndex >= 0 &&
            channelIndex < _owners.focus.rowFocusNodes.length) {
          _owners.focus.rowFocusNodes[channelIndex].requestFocus();
          _deps.setState(() => _owners.focus.focusedIndex = channelIndex);
        }
      }

      final visibleChannels = _sections.navigation.filteredChannels;
      final visibleEditedChannel = visibleChannels.firstWhereOrNull(
        (ch) => ch.id == channel.id,
      );
      if (visibleEditedChannel != null) {
        focusChannelById(visibleEditedChannel.id);
        return;
      }

      final visiblePreviousChannel = previousFocusedChannelId == null
          ? null
          : visibleChannels.firstWhereOrNull(
              (ch) => ch.id == previousFocusedChannelId,
            );
      if (visiblePreviousChannel != null) {
        focusChannelById(visiblePreviousChannel.id);
        return;
      }

      if (visibleChannels.isNotEmpty) {
        final fallbackVisibleIndex = previousFilteredIndex >= 0
            ? previousFilteredIndex.clamp(0, visibleChannels.length - 1)
            : previousFocusedIndex.clamp(0, visibleChannels.length - 1);
        focusChannelById(visibleChannels[fallbackVisibleIndex].id);
        return;
      }

      _owners.focus.searchBtnFocusNode.requestFocus();
    });
  }
}
