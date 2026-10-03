import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_focus_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:debrify/widgets/iptv/styles/iptv_style.dart';
import 'package:flutter/material.dart';

typedef IptvRowProjectionDeps = ({
  IptvCatalogState catalogState,
  IptvFocusState focusState,
  IptvSettingsState settingsState,
  bool Function() isTelevision,
});

class IptvRowProjection {
  final IptvRowProjectionDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvFocusState _focusState;
  final IptvSettingsState _settingsState;

  IptvRowProjection(this._deps)
    : _catalogState = _deps.catalogState,
      _focusState = _deps.focusState,
      _settingsState = _deps.settingsState;

  bool get spotlightRequestedForDevice =>
      _settingsState.iptvStyle == IptvStyle.spotlight &&
      (_deps.isTelevision() || IptvSettingsState.isDesktop);

  /// Whether the current view shows on-demand items, which are drawn as 2:3
  /// posters in taller rows. Derived from the selected view rather than by
  /// scanning the channels: the grid needs one answer for every tile, and
  /// scanning tens of thousands of rows per build to get it isn't free.
  ///
  /// M3U playlists keep the logo layout even for their VOD entries — their
  /// content type is a duration heuristic, so a mixed playlist has no single
  /// honest answer here.
  bool get showsPosterRows {
    final playlist = _settingsState.selectedPlaylist;
    if (playlist == null) return false;
    if (playlist.isContinueWatching) return true;
    if (playlist.isXtreamCodes) {
      return _catalogState.selectedContentType == 'vod' ||
          _catalogState.selectedContentType == 'series';
    }
    return false;
  }

  Map<String, int> get categoryCounts {
    // Counts come from one GROUP BY at present time — scanning the
    // facade here would page through the whole catalog.
    if (_catalogState.dbSnapshot != null) return _catalogState.dbGroupCounts;
    if (!identical(
          _catalogState.categoryCountsSource,
          _catalogState.allChannels,
        ) ||
        _catalogState.categoryCountsLength !=
            _catalogState.allChannels.length) {
      final counts = <String, int>{};
      for (final channel in _catalogState.allChannels) {
        final group = channel.group;
        if (group != null && group.isNotEmpty) {
          counts[group] = (counts[group] ?? 0) + 1;
        }
      }
      _catalogState.categoryCountsSource = _catalogState.allChannels;
      _catalogState.categoryCountsLength = _catalogState.allChannels.length;
      _catalogState.categoryCountsCache = counts;
    }
    return _catalogState.categoryCountsCache;
  }

  /// Whether the current list draws EPG rows (now/next inside each row).
  /// Poster lists never do; otherwise sampled from the first few channels —
  /// Xtream capability is homogeneous (URL parse), but XMLTV matching is
  /// per-channel, and a single unmatched channel at position 0 must not veto
  /// the whole list. Rows without data fall back gracefully; the grid needs
  /// one tile height for everything either way.
  bool get epgRowsActive {
    if (showsPosterRows) return false;
    final channels = _catalogState.filteredChannels;
    if (channels.isEmpty) return false;
    final sample = channels.length < 10 ? channels.length : 10;
    for (var i = 0; i < sample; i++) {
      if (IptvEpgService.isEpgCapable(channels[i])) return true;
    }
    return false;
  }

  void onRowDetached(IptvChannel channel) {
    _focusState.detachedRows.add(channel);
  }

  FocusNode focusNodeFor(IptvChannel channel) {
    // Being asked for the node means the row is being (re)built right now.
    _focusState.detachedRows.remove(channel);
    return _focusState.cardFocusNodes.putIfAbsent(
      channel,
      () => FocusNode(debugLabel: 'iptv-card-${channel.name}-${channel.url}'),
    );
  }

  /// Whether [channel]'s row is currently built (its node attached). Nodes
  /// with no map entry count as detached.
  bool rowAttached(IptvChannel channel) =>
      _focusState.cardFocusNodes.containsKey(channel) &&
      !_focusState.detachedRows.contains(channel);
}
