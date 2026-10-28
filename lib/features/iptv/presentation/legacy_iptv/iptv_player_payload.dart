import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_membership_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/iptv_history_storage.dart';

typedef IptvPlayerPayloadDeps = ({
  IptvCatalogState catalogState,
  IptvMembershipState membershipState,
  IptvSettingsState settingsState,
  List<String> Function(String catalogKey, List<String> categories)
  withoutHidden,
});

class IptvPlayerPayload {
  final IptvPlayerPayloadDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvMembershipState _membershipState;
  final IptvSettingsState _settingsState;

  IptvPlayerPayload(this._deps)
    : _catalogState = _deps.catalogState,
      _membershipState = _deps.membershipState,
      _settingsState = _deps.settingsState;

  List<Map<String, dynamic>> playerSourcePayload() => [
    for (final playlist in _settingsState.playlists)
      // Sports has no channel catalog for the native guide to switch to.
      if (!playlist.isContinueWatching && !playlist.isSports)
        {
          'id': playlist.id,
          'name': playlist.name,
          // Favorites keeps its own flag even though it is now just the
          // built-in list: the native guide's ★ SAVED button resolves the
          // source by it, and expects exactly one.
          'isFavorites': playlist.isFavorites,
          'isContinue': playlist.isContinueWatching,
          'isXtream': playlist.isXtreamCodes,
          'isList': playlist.isCustomList,
          if (playlist.customListId != null) 'listId': playlist.customListId,
          if (playlist.connectionResourceId != null)
            'connectionResourceId': playlist.connectionResourceId,
          if (playlist.connectionResourceRevision != null)
            'connectionResourceRevision': playlist.connectionResourceRevision,
        },
  ];

  /// The user's lists, for the players' "add to list" picker. Shipped once
  /// per launch rather than as a field on every channel — the channel payload
  /// is already capped for size (see [kMaxPlayerChannels]).
  List<Map<String, dynamic>> playerListsPayload() => [
    for (final list in _membershipState.lists)
      {'id': list.id, 'name': list.name, 'isBuiltin': list.isBuiltin},
  ];

  String playerOriginPlaylistId(IptvChannel channel, IptvPlaylist source) {
    final seriesOrigin = channel.attributes['series_playlist_id'];
    if (seriesOrigin != null && seriesOrigin.isNotEmpty) {
      return seriesOrigin;
    }
    final listId = source.isFavorites
        ? IptvFavoritesStorage.iptvFavoritesListId
        : source.customListId;
    final shelfOrigin = (source.isFavorites || source.isCustomList)
        // Prefer the row's own origin (see [_kListOriginAttribute]); the map
        // is only a fallback for rows that predate it.
        ? (channel
                      .attributes[IptvMembershipState.kListOriginAttribute]
                      ?.isNotEmpty ??
                  false)
              ? channel.attributes[IptvMembershipState.kListOriginAttribute]
              : (listId == null
                    ? null
                    : _membershipState.favoritePlaylistIds[(
                        listId,
                        channel.url,
                      )])
        : source.isContinueWatching
        ? _membershipState.continuePlaylistIds[channel.url]
        : null;
    return shelfOrigin?.isNotEmpty == true ? shelfOrigin! : source.id;
  }

  IptvChannel playerChannelWithOrigin(
    IptvChannel channel,
    IptvPlaylist source,
  ) {
    return IptvChannel(
      channelNumber: channel.channelNumber,
      name: channel.name,
      url: channel.url,
      logoUrl: channel.logoUrl,
      group: channel.group,
      duration: channel.duration,
      contentType: channel.contentType,
      attributes: {
        ...channel.attributes,
        'source_playlist_id': playerOriginPlaylistId(channel, source),
      },
      httpHeaders: channel.httpHeaders,
    );
  }

  Future<List<Map<String, dynamic>>> playerChannelPayload(
    List<({IptvChannel channel, IptvPlaylist source})> entries,
  ) async {
    final favoriteUrls =
        await IptvFavoritesStorage.getIptvFavoriteChannelUrls();
    final resumePositions = await IptvHistoryStorage.getIptvResumePositions([
      for (final entry in entries)
        if (!entry.channel.isLive) entry.channel.url,
    ]);
    return [
      for (final entry in entries)
        {
          ...entry.channel.toJson(),
          'sourceId': playerOriginPlaylistId(entry.channel, entry.source),
          'sourceName': entry.source.name,
          'isFavorite': favoriteUrls.contains(entry.channel.url),
          if ((resumePositions[entry.channel.url] ?? 0) > 0)
            'resumePositionMs': resumePositions[entry.channel.url],
          if (entry.channel.attributes['series_id'] != null)
            'seriesId': entry.channel.attributes['series_id'],
          if (entry.channel.attributes['series_name'] != null)
            'seriesName': entry.channel.attributes['series_name'],
          if (int.tryParse(entry.channel.attributes['season'] ?? '') != null)
            'season': int.parse(entry.channel.attributes['season']!),
          if (int.tryParse(entry.channel.attributes['episode'] ?? '') != null)
            'episode': int.parse(entry.channel.attributes['episode']!),
          if (entry.channel.attributes['has_next_episode'] != null)
            'hasNextEpisode':
                entry.channel.attributes['has_next_episode'] == 'true',
          if (entry.channel.attributes['tv_archive'] != null)
            'tvArchive': entry.channel.attributes['tv_archive'],
          if (int.tryParse(
                entry.channel.attributes['tv_archive_duration'] ?? '',
              ) !=
              null)
            'tvArchiveDuration': int.parse(
              entry.channel.attributes['tv_archive_duration']!,
            ),
          if (entry.channel.attributes['series_playlist_id'] != null)
            'seriesPlaylistId': entry.channel.attributes['series_playlist_id'],
        },
    ];
  }

  /// The source's full category list for the in-player picker — ALL of the
  /// provider's categories, not just the handful present in the ~1500 channels
  /// sent to the player.
  ///
  /// Reuses [categories], which the view already maintains for its own chips
  /// (provider categories in order, else every distinct group) and refreshes on
  /// each catalog load — so the launch/browse path never re-runs a GROUP BY on
  /// the UI isolate. The snapshot/in-memory branches only cover the rare case
  /// where it hasn't been populated yet.
  List<String> fullCategoryList() {
    if (_catalogState.categories.isNotEmpty) return _catalogState.categories;
    final snap = _catalogState.dbSnapshot;
    if (snap != null) {
      // Same hidden-category filtering [_deriveCategories] applies, so the
      // in-player picker can't offer a category the page doesn't. groups()
      // is already filtered in SQL; the provider list is not.
      if (snap.categories.isNotEmpty) {
        return IptvCatalogDb.applyCategoryOrder(
          snap.catalogKey,
          _deps.withoutHidden(snap.catalogKey, snap.categories),
        );
      }
      return IptvCatalogDb.applyCategoryOrder(snap.catalogKey, [
        for (final group in snap.groups())
          if (group.name?.isNotEmpty == true) group.name!,
      ]);
    }
    return <String>{
      for (final channel in _catalogState.allChannels)
        if (channel.group?.isNotEmpty == true) channel.group!,
    }.toList()..sort();
  }
}
