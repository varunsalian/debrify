import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_preview_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_selection_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/services/stremio_iptv_service.dart';
import 'package:debrify/services/video_player_launcher.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvPlaybackDeps = ({
  IptvCatalogState catalogState,
  IptvPlayerState playerState,
  IptvPreviewState previewState,
  IptvSelectionState selectionState,
  IptvSettingsState settingsState,
  Future<void> Function(String? group) adoptStartupCategoryValue,
  BuildContext Function() context,
  String? Function() effectiveCategory,
  void Function() flushPreviewRearm,
  List<String> Function() fullCategoryList,
  bool Function() isTelevision,
  bool Function() mounted,
  String Function(String value) normalizedName,
  Future<void> Function(IptvChannel channel) openSeriesDetail,
  String? Function(IptvChannel channel) originPlaylistIdFor,
  IptvChannel Function(IptvChannel channel, IptvPlaylist source)
  playerChannelWithOrigin,
  List<Map<String, dynamic>> Function() playerListsPayload,
  List<Map<String, dynamic>> Function() playerSourcePayload,
  Future<Map<String, dynamic>?> Function(Map<String, dynamic> request)
  providePlayerIptvBrowse,
  Future<void> Function() refreshAfterPlayback,
});

class IptvPlayback {
  final IptvPlaybackDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvPlayerState _playerState;
  final IptvPreviewState _previewState;
  final IptvSelectionState _selectionState;
  final IptvSettingsState _settingsState;

  IptvPlayback(this._deps)
    : _catalogState = _deps.catalogState,
      _playerState = _deps.playerState,
      _previewState = _deps.previewState,
      _selectionState = _deps.selectionState,
      _settingsState = _deps.settingsState;

  String? get _effectiveCategory => _deps.effectiveCategory();

  Future<void> playChannel(
    IptvChannel channel, {
    bool Function()? shouldCancel,
  }) async {
    if (_playerState.launchingChannel) return;
    _playerState.launchingChannel = true;
    try {
      await playChannelInner(channel, shouldCancel: shouldCancel);
    } finally {
      _playerState.launchingChannel = false;
    }
  }

  /// Convert a catalog position into the facade's filtered index, then read the
  /// row back out of the live facade so it is a registered, resident instance.
  Future<IptvChannel?> residentDbRow(
    ({int position, IptvChannel channel}) entry,
    String url,
    String name,
    int? storedNumber,
  ) async {
    final channel = entry.channel;
    // Live-only, enforced on the resolved row rather than by filtering — see
    // the index contract below.
    if (!channel.isLive) return null;
    // A channel-number fallback must corroborate on NAME. Numbers are assigned
    // per load on virtual catalogs, so a shifted numbering is exactly the
    // condition that triggers this path — and "same group" is worthless
    // corroboration when hundreds of channels share "Sports".
    if (channel.url != url &&
        storedNumber != null &&
        _deps.normalizedName(channel.name) != _deps.normalizedName(name)) {
      return null;
    }

    await _deps.adoptStartupCategoryValue(channel.group);
    final snap = _catalogState.dbSnapshot;
    final list = _catalogState.filteredChannels;
    if (snap == null || list is! DbChannelList) return null;

    // The index MUST be counted under the facade's own filter set. DbChannelList
    // filters on group + search only — it has no `live` parameter — so counting
    // live-only rows here and indexing a facade holding live+VOD would land on
    // a different channel entirely.
    final index = snap.count(
      group: list.group,
      search: list.search,
      beforePosition: entry.position,
    );
    if (index < 0 || index >= list.length) return null;
    final row = list[index];
    // Verify against what resolution actually returned, not against the stored
    // blob: a successful number-fallback legitimately has a different URL, and
    // checking the stale value would reject every one of them.
    if (row.url != channel.url || row.name != channel.name) return null;
    return row;
  }

  /// [shouldCancel] is polled after the awaits below and immediately before the
  /// player is pushed. Checking only before `_playChannel` is not enough: this
  /// method still awaits a Stremio candidate resolve and a watch record, and a
  /// BACK landing in either window would otherwise still end in a player.
  Future<void> playChannelInner(
    IptvChannel channel, {
    bool Function()? shouldCancel,
  }) async {
    // Series entries aren't playable — their sentinel URL routes to the
    // merged series page, whose episode list does the actual playing.
    if (channel.contentType == 'series') {
      await _deps.openSeriesDetail(channel);
      return;
    }
    // Stremio channels have no stream URL yet — resolve the ladder now (the
    // preview's winner cache usually makes this instant) and launch on the
    // best candidate. The in-player guide still gets the full mixed list;
    // both players resolve further stremio-keyed channels on switch.
    var initialUrl = channel.url;
    if (StremioIptvService.isStremioChannelUrl(channel.url)) {
      // Explicit play intent: a cached "nothing playable" is re-checked
      // fresh, and an empty answer explains itself (addon down vs. no
      // streams) instead of a blanket "not playable".
      final candidates = await StremioIptvService.instance.resolveCandidates(
        channel.url,
        refreshIfEmpty: true,
      );
      if (!_deps.mounted()) return;
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          SnackBar(
            content: Text(
              StremioIptvService.instance.unplayableMessage(
                channel.url,
                channel.name,
              ),
            ),
          ),
        );
        return;
      }
      initialUrl = candidates.first.url;
      if (shouldCancel != null && shouldCancel()) return;
    }
    // Remember on-demand plays so the Continue-watching shelf can rebuild the
    // row later without re-fetching the panel. Recorded BEFORE the launch:
    // the player process can be killed outright on TV, and a shelf entry with
    // no saved position simply doesn't show up (the join drops it).
    //
    // Live channels are skipped — "62% through Sky Sports" is meaningless.
    if (!channel.isLive) {
      await IptvHistoryStorage.recordIptvWatch(
        channel.url,
        channelName: channel.name,
        logoUrl: channel.logoUrl,
        group: channel.group,
        playlistId: _deps.originPlaylistIdFor(channel),
        httpHeaders: channel.httpHeaders,
      );
    }

    // The in-player guide mirrors what the user was browsing: the current
    // category/search filter, not the whole playlist. (Also what keeps the
    // launch payload small when a filter is active.)
    // Sports has no catalog of its own: the matched channel plays alone, as
    // part of the playlist it came from.
    final selected = _settingsState.selectedPlaylist;
    final sportsOrigin = (selected?.isSports ?? false)
        ? _sportsOrigin(channel)
        : null;
    final playSource = sportsOrigin ?? selected;
    var channels = (selected?.isSports ?? false)
        ? <IptvChannel>[channel]
        : _catalogState.filteredChannels.contains(channel)
        ? _catalogState.filteredChannels
        : _catalogState.allChannels;
    var channelIndex = channels is DbChannelList
        // Identity lookup against resident pages — the tapped row is by
        // definition resident; a paged indexOf would walk the catalog.
        ? (channels.indexOfInstance(channel) ?? 0)
        : channels.indexOf(channel);
    if (channelIndex < 0) channelIndex = 0;
    if (channels is DbChannelList) {
      // Materialize exactly the launch window from SQL — the facade itself
      // must never be handed to the launcher (serializing it would page the
      // entire catalog).
      final source = channels;
      final total = source.length;
      final lo = total > IptvPlayerState.kMaxPlayerChannels
          ? (channelIndex - IptvPlayerState.kMaxPlayerChannels ~/ 2).clamp(
              0,
              total - IptvPlayerState.kMaxPlayerChannels,
            )
          : 0;
      channels = source.effectiveSnapshot.page(
        offset: lo,
        limit: IptvPlayerState.kMaxPlayerChannels,
        group: source.group,
        search: source.search,
      );
      if (channels.isEmpty) {
        // The pinned generation was swept between the row painting and OK
        // landing (a background revalidate finished in that window). With an
        // empty list, `clamp(0, -1)` throws ArgumentError in release — play
        // the tapped channel alone instead; the guide simply has one row
        // until the next open.
        channels = [channel];
      }
      channelIndex = (channelIndex - lo).clamp(0, channels.length - 1);
    } else if (channels.length > IptvPlayerState.kMaxPlayerChannels) {
      final lo = (channelIndex - IptvPlayerState.kMaxPlayerChannels ~/ 2).clamp(
        0,
        channels.length - IptvPlayerState.kMaxPlayerChannels,
      );
      channels = channels.sublist(lo, lo + IptvPlayerState.kMaxPlayerChannels);
      channelIndex -= lo;
    }
    final launchSource = selected;
    final playerChannels = launchSource == null
        ? channels
        : [
            for (final item in channels)
              _deps.playerChannelWithOrigin(item, launchSource),
          ];
    if (!_deps.mounted()) return;
    // Last gate before the player exists. Everything above may have taken
    // seconds (Stremio ladder, catalog page, watch record).
    if (shouldCancel != null && shouldCancel()) return;
    await VideoPlayerLauncher.push(
      _deps.context(),
      VideoPlayerLaunchArgs(
        videoUrl: initialUrl,
        title: channel.name,
        subtitle: channel.group ?? 'IPTV',
        channelName: channel.name,
        channelNumber: channel.channelNumber,
        showChannelName: channel.isLive,
        viewMode: PlaylistViewMode.sorted,
        iptvChannels: playerChannels,
        iptvStartIndex: channelIndex,
        iptvCategories: _deps.fullCategoryList(),
        iptvSourceId: playSource?.id,
        iptvSourceName: playSource?.name,
        iptvSelectedCategory: _effectiveCategory,
        iptvContentType: (selected?.isSports ?? false)
            ? 'live'
            : _settingsState.selectedPlaylist?.isXtreamCodes == true
            ? _catalogState.selectedContentType
            : (channel.isLive ? 'live' : 'vod'),
        iptvSources: _deps.playerSourcePayload(),
        iptvLists: _deps.playerListsPayload(),
        iptvBrowseProvider: _deps.providePlayerIptvBrowse,
        // Opening headers for the launch channel (later zaps read them off the
        // channel they switch to). Stremio-addon links are already-resolved CDN
        // URLs, so they keep the addon's own defaults.
        httpHeaders: StremioIptvService.isStremioChannelUrl(channel.url)
            ? null
            : channel.playbackHeaders,
      ),
    );
    // Re-arm the preview stage (see [_previewEpoch]) — but NOT yet. On TV,
    // push() returns the moment the native player activity STARTS, while this
    // activity is still resumed: remounting the stage now races the cover
    // (the fresh backdrop's dwell can open a stream UNDER the real player).
    // Park the re-arm; it completes on app resume (native path) or on the
    // next row focus (in-app fallback, whose route is awaited to the pop).
    // Desktop two-pane parks it too — push() can hand off to an EXTERNAL
    // player app and return while it's still playing, so the next hover
    // (a sign the user is back in the app) is the safe re-arm point.
    if (_deps.mounted() &&
        (_deps.isTelevision() || _selectionState.tvTwoPaneActive)) {
      _previewState.previewRearmPending = true;
    }
    // Off TV, push() is awaited to the pop — the position just written is
    // already on disk, so refresh now. On TV push() can return while the
    // native player is still starting, and rebuilding the list under a
    // launching player is the worst possible moment for it; the parked
    // re-arm below is the designated "we're back" hook and refreshes there.
    if (!_deps.isTelevision()) {
      if (_selectionState.touchTabletTwoPaneActive) {
        _deps.flushPreviewRearm();
      } else {
        await _deps.refreshAfterPlayback();
      }
    }
  }

  /// The saved playlist a Sports match was found in (carried on the channel
  /// as its list origin), or null when it is no longer configured.
  IptvPlaylist? _sportsOrigin(IptvChannel channel) {
    final id = channel.attributes[IptvMembershipState.kListOriginAttribute];
    for (final p in _settingsState.playlists) {
      if (p.id == id && !p.isVirtual) return p;
    }
    return null;
  }
}
