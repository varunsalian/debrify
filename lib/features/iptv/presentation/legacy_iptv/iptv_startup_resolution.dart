import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/storage/startup_iptv_storage.dart';
import 'package:flutter/material.dart';

typedef IptvStartupResolutionDeps = ({
  IptvCatalogState catalogState,
  IptvSettingsState settingsState,
  void Function() applyFilters,
  void Function(IptvPlaylist? playlist, {bool focusContent}) onPlaylistChanged,
  Future<IptvChannel?> Function(
    ({int position, IptvChannel channel}) entry,
    String url,
    String name,
    int? storedNumber,
  )
  residentDbRow,
  StateSetter setState,
  IptvPlaylist? Function(Map<String, dynamic> payload) startupPlaylistFor,
});

class IptvStartupResolution {
  final IptvStartupResolutionDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvSettingsState _settingsState;

  IptvStartupResolution(this._deps)
    : _catalogState = _deps.catalogState,
      _settingsState = _deps.settingsState;

  /// Locate the stored channel and return the *resident* row instance.
  ///
  /// Never returns a self-materialized [IptvChannel]: `_playChannelInner` looks
  /// the row up by IDENTITY (`DbChannelList` is backed by a `HashMap.identity`),
  /// so a foreign instance fails `contains`, falls through to `allChannels`,
  /// resolves to null, and gets clamped to index 0 — silently launching the
  /// first channel in the catalog.
  Future<IptvChannel?> resolveStartupRow(
    Map<String, dynamic> payload,
    bool Function() cancelled,
  ) async {
    // Bootstrap case: nothing has ever been watched, so there is no stored
    // channel to look up. Start on whatever the page already landed on — their
    // default provider, else Favourites when they have any (see
    // `_loadSettings`). Deliberately NOT resolved as a stored identity:
    // there is nothing to match, and no user expectation to get wrong.
    if (payload[StartupIptvStorage.startupIptvFirstAvailable] == true) {
      return resolveFirstAvailableRow(cancelled);
    }

    final url = payload['url'] as String;
    final name = payload['name'] as String;
    final channelNumber = (payload['channelNumber'] as num?)?.toInt();

    // 1. The target's own provider, resolved BEFORE anything is looked up — a
    //    lookup against the landing playlist's catalog would answer about the
    //    wrong provider entirely.
    final target = _deps.startupPlaylistFor(payload);
    if (target == null) return null;
    if (_settingsState.selectedPlaylist?.id != target.id) {
      _deps.onPlaylistChanged(target);
    }

    final deadline = DateTime.now().add(IptvPlayerState.startupResolveDeadline);

    // 2. Do not read the catalog until the OUTGOING one is gone. `_loadPlaylist`
    //    sets its in-flight ticket synchronously, but `_loadPlaylistInner`
    //    clears `_allChannels`/`_dbSnapshot` only after its first awaits — so
    //    for a window the previous provider's rows are still sitting there, and
    //    matching against them would resolve a channel from the wrong account.
    var ready = false;
    while (!ready && !cancelled() && DateTime.now().isBefore(deadline)) {
      if (_catalogState.inFlightLoadTicket == null) {
        ready = true; // load finished (or a cached catalog was already present)
      } else if (_catalogState.allChannels.isEmpty &&
          _catalogState.dbSnapshot == null) {
        ready = true; // cleared — anything arriving now belongs to the target
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }

    // 3. Wait for that provider's catalog. Stremio shelves arrive
    //    progressively, so this waits for the row to APPEAR, not merely for a
    //    load to finish.
    while (!cancelled() && DateTime.now().isBefore(deadline)) {
      // A load for a DIFFERENT playlist means something (a user action, an
      // addon refresh) moved on from under us — the attempt is void.
      if (_settingsState.selectedPlaylist?.id != target.id) return null;
      final snap = _catalogState.dbSnapshot;
      if (snap != null) {
        final entry =
            snap.entryForUrl(url: url, name: name) ??
            (channelNumber != null
                ? snap.entryForChannelNumber(channelNumber)
                : null);
        if (entry != null) {
          return _deps.residentDbRow(entry, url, name, channelNumber);
        }
      } else if (_catalogState.allChannels.isNotEmpty) {
        final match = materializedStartupMatch(url, name, channelNumber);
        if (match != null) return adoptStartupCategory(match);
        // A finished load that still doesn't hold the channel is a real miss;
        // an in-flight one may still deliver it.
        if (_catalogState.inFlightLoadTicket == null) return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  /// First live row of whatever the page is currently showing.
  ///
  /// Rows come straight off `filteredChannels`, so they are the facade's own
  /// resident instances — the identity `_playChannelInner` needs — and no
  /// category is adopted, because the landing view is exactly what we want.
  ///
  /// The walk is capped: a VOD-heavy catalog could otherwise page thousands of
  /// rows looking for a live one, and if the first few hundred hold none, the
  /// honest answer is "nothing to start on" rather than a long stall.
  Future<IptvChannel?> resolveFirstAvailableRow(
    bool Function() cancelled,
  ) async {
    final deadline = DateTime.now().add(IptvPlayerState.startupResolveDeadline);
    while (!cancelled() && DateTime.now().isBefore(deadline)) {
      final channels = _catalogState.filteredChannels;
      if (channels.isNotEmpty) {
        final limit = channels.length < 300 ? channels.length : 300;
        for (var i = 0; i < limit; i++) {
          final channel = channels[i];
          if (channel.isLive) return channel;
        }
        // A finished load with no live row in reach is a real answer; an
        // in-flight one (progressive Stremio) may still deliver.
        if (_catalogState.inFlightLoadTicket == null) return null;
      } else if (_catalogState.inFlightLoadTicket == null &&
          _settingsState.settingsLoaded) {
        return null;
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return null;
  }

  IptvChannel? materializedStartupMatch(
    String url,
    String name,
    int? storedNumber,
  ) {
    for (final channel in _catalogState.allChannels) {
      if (channel.url == url && channel.name == name && channel.isLive) {
        return channel;
      }
    }
    if (storedNumber == null) return null;
    for (final channel in _catalogState.allChannels) {
      if (channel.channelNumber == storedNumber &&
          channel.isLive &&
          normalizedName(channel.name) == normalizedName(name)) {
        return channel;
      }
    }
    return null;
  }

  /// Materialized lists hand back the very instance the filtered list holds, so
  /// identity already lines up — only the category needs adopting.
  Future<IptvChannel?> adoptStartupCategory(IptvChannel channel) async {
    await adoptStartupCategoryValue(channel.group);
    return _catalogState.filteredChannels.contains(channel) ? channel : null;
  }

  /// Make the target's own group the active category. Without this the landing
  /// category can simply exclude the target, and no amount of correct counting
  /// inside it will ever materialize the row.
  Future<void> adoptStartupCategoryValue(String? group) async {
    if (_catalogState.selectedCategory != group) {
      _deps.setState(() => _catalogState.selectedCategory = group);
      _deps.applyFilters();
      // Let the new facade/filtered list settle before it is indexed.
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  static String normalizedName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
