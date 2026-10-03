import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';
import 'package:debrify/widgets/iptv/db_channel_list.dart';
import 'package:flutter/material.dart';

typedef IptvVirtualResultsDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  void Function() applyFilters,
  void Function() consumeContentFocusRequest,
  void Function() endLoadStatus,
  bool Function() mounted,
  StateSetter setState,
});

class IptvVirtualResults {
  final IptvVirtualResultsDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;

  IptvVirtualResults(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState;

  /// A page of Stremio channels landed while the catalog walk is still
  /// running. Batches are cumulative snapshots, so skipped intermediate ones
  /// lose nothing — throttle the repaints and let the next batch (or the
  /// final result) true everything up.
  void applyProgressiveBatch(
    int ticket,
    List<IptvChannel> channels,
    List<String> categories,
  ) {
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    final now = DateTime.now();
    final last = _catalogState.lastProgressiveApply;
    final firstBatch = !_catalogState.isLoadingMore;
    if (!firstBatch &&
        last != null &&
        now.difference(last) < const Duration(milliseconds: 300)) {
      return;
    }
    final wasFirstBatch = firstBatch;
    _catalogState.lastProgressiveApply = now;
    _deps.endLoadStatus();
    _deps.setState(() {
      _catalogState.isLoading =
          false; // first batch swaps the spinner for real rows
      _catalogState.isLoadingMore = true;
      _catalogState.allChannels = channels;
      _catalogState.categories = categories;
    });
    _deps.applyFilters();
    // A Stremio source picked from the rail: hand focus to the content pane
    // once its first batch of rows is on screen (later batches keep focus).
    if (wasFirstBatch) _deps.consumeContentFocusRequest();
  }

  /// Look up saved positions for the loaded list. Live channels can't have
  /// one, so a playlist with no on-demand items skips the read entirely —
  /// that's the overwhelmingly common case (a live-TV panel).
  Future<void> loadProgress(int ticket, List<IptvChannel> channels) async {
    // Bars load per faulted page (_loadPageProgress); a full-list
    // refresh (post-playback) re-reads just the RESIDENT pages — the rows
    // that can be on screen.
    if (_catalogState.dbSnapshot != null) {
      final all = _catalogState.allChannels;
      final filtered = _catalogState.filteredChannels;
      final resident = <IptvChannel>[
        if (all is DbChannelList) ...all.residentChannels(),
        if (filtered is DbChannelList) ...filtered.residentChannels(),
      ];
      final urls = <String>{
        for (final channel in resident)
          if (!channel.isLive && channel.contentType != 'series') channel.url,
      };
      if (urls.isEmpty) return;
      final progress = await IptvHistoryStorage.getIptvProgressForUrls(urls);
      if (!_deps.mounted() ||
          ticket != _catalogState.loadTicket ||
          progress.isEmpty) {
        return;
      }
      _deps.setState(
        () => _membershipState.progressByUrl = {
          ..._membershipState.progressByUrl,
          ...progress,
        },
      );
      return;
    }

    final onDemand = [
      for (final channel in channels)
        // Series rows carry a sentinel (non-stream) URL — no position can
        // exist for it; their per-episode progress lives on the detail page.
        if (!channel.isLive && channel.contentType != 'series') channel.url,
    ];
    if (onDemand.isEmpty) {
      if (_membershipState.progressByUrl.isNotEmpty &&
          _deps.mounted() &&
          ticket == _catalogState.loadTicket) {
        _deps.setState(() => _membershipState.progressByUrl = {});
      }
      return;
    }

    final progress = await IptvHistoryStorage.getIptvProgressForUrls(onDemand);
    if (!_deps.mounted() || ticket != _catalogState.loadTicket) return;
    _deps.setState(() => _membershipState.progressByUrl = progress);
  }

  /// Build the virtual "Continue watching" playlist. Like Favorites, the rows
  /// are replayed from metadata captured at play time rather than re-fetched,
  /// so they survive a provider that has since renumbered or expired.
  Future<IptvParseResult> buildContinueResult() async {
    final items = await IptvHistoryStorage.getIptvContinueWatching();
    _membershipState.continuePlaylistIds = {};
    final channels = <IptvChannel>[];
    // A series' episodes collapse to ONE row: items are most-recent-first, so
    // the first entry per (provider, series) wins and the rest are folded in.
    // Non-series items (movies/catchup) keep one row each, exactly as before.
    final seenSeries = <String>{};
    for (final item in items) {
      final seriesId = (item['seriesId'] as String?) ?? '';
      final originId = (item['playlistId'] as String?) ?? '';
      if (seriesId.isNotEmpty) {
        final groupKey = '$originId::$seriesId';
        if (!seenSeries.add(groupKey)) continue; // already have this series
        // A series sentinel URL, so a tap routes into the merged series page
        // (which resumes at the true next-up from the players' saved
        // positions) rather than playing one episode standalone. The origin
        // provider id is baked into the URL: Xtream series ids are per-provider
        // small integers, so two providers routinely share one — a plain
        // `xtream-series://<id>` would collide in the url-keyed row/focus/
        // origin bookkeeping and open the wrong show.
        final sentinelUrl = 'xtream-series://$originId/$seriesId';
        _membershipState.continuePlaylistIds[sentinelUrl] = originId;
        final seriesName = (item['seriesName'] as String?)?.isNotEmpty == true
            ? item['seriesName'] as String
            : ((item['group'] as String?)?.isNotEmpty == true
                  ? item['group'] as String
                  : 'Unknown series');
        channels.add(
          IptvChannel(
            name: seriesName,
            url: sentinelUrl,
            logoUrl: (item['logoUrl'] as String?)?.isNotEmpty == true
                ? item['logoUrl'] as String
                : null,
            group: seriesName,
            contentType: 'series',
            attributes: {
              'series_id': seriesId,
              if (originId.isNotEmpty) 'series_playlist_id': originId,
            },
          ),
        );
        continue;
      }
      // Defensive cast, matching every other field in this loop: this is
      // decoded storage JSON, and one malformed entry (null/missing url)
      // must skip that row, not TypeError the whole shelf's build.
      final itemUrl = item['url'] as String?;
      if (itemUrl == null || itemUrl.isEmpty) continue;
      _membershipState.continuePlaylistIds[itemUrl] = originId;
      channels.add(
        IptvChannel(
          name: (item['name'] as String?)?.isNotEmpty == true
              ? item['name'] as String
              : 'Unknown',
          url: itemUrl,
          logoUrl: (item['logoUrl'] as String?)?.isNotEmpty == true
              ? item['logoUrl'] as String
              : null,
          group: (item['group'] as String?)?.isNotEmpty == true
              ? item['group'] as String
              : null,
          // Always on-demand — live channels are never recorded — so the row
          // draws a poster and the "LIVE" dot stays off.
          contentType: 'vod',
          httpHeaders: IptvFavoritesStorage.iptvFavoriteHeaders(item),
        ),
      );
    }
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()..sort();
    // Already ordered most-recently-watched first; leave it alone.
    return IptvParseResult(channels: channels, categories: categories);
  }

  /// Build a virtual list shelf (Favorites or a user list) from the stored
  /// membership. Metadata was captured when the channel was added, so no
  /// fetch is needed; Stremio-keyed URLs still resolve on focus/play exactly
  /// like anywhere else.
  Future<IptvParseResult> buildListResult(String listId) async {
    final stored = await IptvFavoritesStorage.getIptvListChannels(listId);
    final channels = stored.entries.map((entry) {
      final meta = entry.value;
      final name = (meta['name'] as String?) ?? '';
      final logoUrl = (meta['logoUrl'] as String?) ?? '';
      final group = (meta['group'] as String?) ?? '';
      return IptvChannel(
        channelNumber: (meta['channelNumber'] as num?)?.toInt(),
        name: name.isEmpty ? 'Unknown Channel' : name,
        url: entry.key,
        logoUrl: logoUrl.isEmpty ? null : logoUrl,
        group: group.isEmpty ? null : group,
        // Rows added before these were stored (and every row migrated
        // from the pre-v5 favorites table) fall back to live, which is
        // how they presented then; the reconcile pass backfills them the
        // first time their provider is opened.
        duration: (meta['duration'] as num?)?.toInt() ?? -1,
        contentType: meta['contentType'] as String?,
        attributes: {
          if ((meta['playlistId'] as String?)?.isNotEmpty ?? false)
            IptvMembershipState.kListOriginAttribute:
                meta['playlistId'] as String,
        },
        httpHeaders: IptvFavoritesStorage.iptvFavoriteHeaders(meta),
      );
    }).toList();
    final categories = <String>{
      for (final channel in channels)
        if (channel.group != null) channel.group!,
    }.toList()..sort();
    return IptvParseResult(channels: channels, categories: categories);
  }
}
