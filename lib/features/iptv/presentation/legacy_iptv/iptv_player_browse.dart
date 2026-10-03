import 'dart:async';

import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_catalog_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_player_state.dart';
import 'package:debrify/features/iptv/presentation/legacy_iptv/iptv_settings_state.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/xtream_codes_service.dart';
import 'package:debrify/utils/iptv_player_paging.dart';
import 'package:flutter/material.dart';

typedef IptvPlayerBrowseDeps = ({
  IptvCatalogState catalogState,
  IptvPlayerState playerState,
  IptvSettingsState settingsState,
  List<String> Function() fullCategoryList,
  Future<void> Function(IptvPlaylist playlist, {bool userRequested})
  loadPlaylist,
  bool Function() mounted,
  Future<List<Map<String, dynamic>>> Function(
    List<({IptvChannel channel, IptvPlaylist source})> entries,
  )
  playerChannelPayload,
  List<Map<String, dynamic>> Function() playerSourcePayload,
  StateSetter setState,
});

class IptvPlayerBrowse {
  final IptvPlayerBrowseDeps _deps;
  final IptvCatalogState _catalogState;
  final IptvPlayerState _playerState;
  final IptvSettingsState _settingsState;

  IptvPlayerBrowse(this._deps)
    : _catalogState = _deps.catalogState,
      _playerState = _deps.playerState,
      _settingsState = _deps.settingsState;

  Future<Map<String, dynamic>?> providePlayerIptvBrowse(
    Map<String, dynamic> request,
  ) async {
    if (!_deps.mounted()) return null;
    final action = request['action'] as String? ?? 'browse';
    final query = (request['query'] as String? ?? '').trim();

    final sourceId =
        request['sourceId'] as String? ?? _settingsState.selectedPlaylist?.id;
    IptvPlaylist? source;
    for (final playlist in _settingsState.playlists) {
      if (playlist.id == sourceId) {
        source = playlist;
        break;
      }
    }
    source ??= _settingsState.selectedPlaylist;
    if (source == null) return null;

    if (action == 'seriesEpisodes') {
      var episodeSource = source;
      final seriesUrl = request['channelUrl'] as String? ?? '';
      String? sentinelOriginId;
      String? sentinelSeriesId;
      if (seriesUrl.startsWith('xtream-series://')) {
        final path = seriesUrl.substring('xtream-series://'.length);
        final slash = path.indexOf('/');
        if (slash > 0) {
          sentinelOriginId = path.substring(0, slash);
          sentinelSeriesId = path.substring(slash + 1);
        } else {
          sentinelSeriesId = path;
        }
      }
      if (!episodeSource.isXtreamCodes && sentinelOriginId != null) {
        for (final playlist in _settingsState.playlists) {
          if (playlist.id == sentinelOriginId && playlist.isXtreamCodes) {
            episodeSource = playlist;
            break;
          }
        }
      }
      if (!episodeSource.isXtreamCodes) return null;
      if (episodeSource != _settingsState.selectedPlaylist ||
          _catalogState.selectedContentType != 'series') {
        _deps.setState(() {
          _settingsState.selectedPlaylist = episodeSource;
          _catalogState.selectedCategory = null;
          _catalogState.selectedContentType = 'series';
        });
        await _deps.loadPlaylist(episodeSource);
        if (!_deps.mounted()) return null;
      }
      IptvChannel? series;
      for (final channel in _catalogState.allChannels) {
        if (channel.url == seriesUrl ||
            (sentinelSeriesId != null &&
                channel.attributes['series_id'] == sentinelSeriesId)) {
          series = channel;
          break;
        }
      }
      final seriesId =
          series?.attributes['series_id'] ?? sentinelSeriesId ?? '';
      if (seriesId.isEmpty) return null;
      series ??= IptvChannel(
        name: (request['title'] as String?)?.trim().isNotEmpty == true
            ? (request['title'] as String).trim()
            : 'Series',
        url: seriesUrl,
        contentType: 'series',
        attributes: {
          'series_id': seriesId,
          'series_playlist_id': episodeSource.id,
        },
      );
      final info = await XtreamCodesService.instance.fetchSeriesInfo(
        episodeSource.serverUrl!,
        episodeSource.username ?? '',
        episodeSource.password ?? '',
        seriesId,
        connectionResourceId: episodeSource.connectionResourceId,
        connectionResourceRevision: episodeSource.connectionResourceRevision,
      );
      if (!_deps.mounted() || info == null) return null;
      final episodes = [
        for (var index = 0; index < info.episodes.length; index++)
          IptvChannel(
            name:
                '${series.name} · S${info.episodes[index].season.toString().padLeft(2, '0')}'
                'E${info.episodes[index].episode.toString().padLeft(2, '0')}'
                '${info.episodes[index].title.trim().isEmpty ? '' : ' · ${info.episodes[index].title.trim()}'}',
            url: info.episodes[index].url,
            logoUrl: info.episodes[index].thumbnailUrl?.isNotEmpty == true
                ? info.episodes[index].thumbnailUrl
                : series.logoUrl,
            group: series.name,
            contentType: 'vod',
            attributes: {
              'series_id': seriesId,
              'series_playlist_id': episodeSource.id,
              'series_name': series.name,
              'season': info.episodes[index].season.toString(),
              'episode': info.episodes[index].episode.toString(),
              'has_next_episode': info.episodes
                  .skip(index + 1)
                  .any((episode) => episode.season != 0)
                  .toString(),
            },
          ),
      ];
      _playerState.playerSeriesEpisodes = episodes;
      _playerState.playerSeriesEpisodeSourceId = episodeSource.id;
      _playerState.playerSeriesTitle = series.name;
      return {
        'sourceId': episodeSource.id,
        'sourceName': episodeSource.name,
        'contentType': 'episodes',
        'title': series.name,
        'categories': const <String>[],
        'sources': _deps.playerSourcePayload(),
        'channels': await _deps.playerChannelPayload([
          for (final episode in episodes)
            (channel: episode, source: episodeSource),
        ]),
      };
    }

    final requestedType =
        request['contentType'] as String? ??
        (source.isXtreamCodes ? _catalogState.selectedContentType : 'live');
    if (requestedType == 'episodes') {
      final cached = source.id == _playerState.playerSeriesEpisodeSourceId
          ? _playerState.playerSeriesEpisodes
          : const <IptvChannel>[];
      final terms = query.toLowerCase().split(RegExp(r'\s+'));
      final episodes = cached
          .where(
            (channel) =>
                query.isEmpty || terms.every(channel.searchKey.contains),
          )
          .take(IptvPlayerState.kMaxPlayerChannels)
          .toList();
      return {
        'sourceId': source.id,
        'sourceName': source.name,
        'contentType': 'episodes',
        'title': _playerState.playerSeriesTitle ?? 'Episodes',
        'categories': const <String>[],
        'sources': _deps.playerSourcePayload(),
        'channels': await _deps.playerChannelPayload([
          for (final episode in episodes) (channel: episode, source: source),
        ]),
      };
    }
    final needsLoad =
        source != _settingsState.selectedPlaylist ||
        (source.isXtreamCodes &&
            requestedType != _catalogState.selectedContentType);
    if (needsLoad) {
      _deps.setState(() {
        _settingsState.selectedPlaylist = source;
        _catalogState.selectedCategory = null;
        if (source!.isXtreamCodes &&
            const {'live', 'vod', 'series'}.contains(requestedType)) {
          _catalogState.selectedContentType = requestedType;
        }
      });
      await _deps.loadPlaylist(source);
      if (!_deps.mounted()) return null;
    }

    final category = (request['category'] as String?)?.trim();
    var effectiveCategory =
        category == null || category.isEmpty || category == 'All'
        ? null
        : category;
    final jumpNumber = action == 'channelNumber'
        ? (request['channelNumber'] as num?)?.toInt()
        : null;
    final isJump = jumpNumber != null && jumpNumber > 0;
    final isZapPage = action == 'zapPage';
    final isPagedRequest = isZapPage || isJump;
    final requestedLimit = (request['limit'] as num?)?.toInt();
    final pageLimit = isPagedRequest
        ? (requestedLimit ?? IptvPlayerState.kPlayerZapPageSize).clamp(
            1,
            IptvPlayerState.kMaxPlayerChannels,
          )
        : IptvPlayerState.kMaxPlayerChannels;
    var pageOffset = isPagedRequest
        ? ((request['offset'] as num?)?.toInt() ?? 0).clamp(0, 1 << 30)
        : 0;
    final anchorUrl = (request['anchorUrl'] as String?)?.trim();
    final anchorName = (request['anchorName'] as String?)?.trim();
    final fromEnd = request['fromEnd'] == true;
    List<IptvChannel> channels;
    var totalChannels = 0;
    int? anchorIndex;
    final snap = _catalogState.dbSnapshot;
    if (snap != null) {
      final live = source.isXtreamCodes
          ? null
          : switch (requestedType) {
              'live' => true,
              'vod' => false,
              _ => null,
            };
      final jumpEntry = isJump ? snap.entryForChannelNumber(jumpNumber) : null;
      if (isJump && jumpEntry == null) {
        return {
          'sourceId': source.id,
          'sourceName': source.name,
          'contentType': requestedType,
          'channelNotFound': true,
        };
      }
      if (jumpEntry != null) effectiveCategory = jumpEntry.channel.group;
      totalChannels = snap.count(group: effectiveCategory, live: live);
      if (jumpEntry != null) {
        anchorIndex = snap.count(
          group: effectiveCategory,
          live: live,
          beforePosition: jumpEntry.position,
        );
      } else if (isZapPage &&
          anchorUrl != null &&
          anchorUrl.isNotEmpty &&
          anchorName != null &&
          anchorName.isNotEmpty) {
        final catalogPosition = snap.positionOf(
          url: anchorUrl,
          name: anchorName,
          group: effectiveCategory,
          live: live,
        );
        if (catalogPosition != null) {
          anchorIndex = snap.count(
            group: effectiveCategory,
            live: live,
            beforePosition: catalogPosition,
          );
        }
      }
      if (isPagedRequest) {
        pageOffset = iptvPlayerZapPageOffset(
          total: totalChannels,
          limit: pageLimit,
          requestedOffset: pageOffset,
          anchorIndex: anchorIndex,
          fromEnd: fromEnd,
        );
      }
      channels = snap.page(
        offset: pageOffset,
        limit: pageLimit,
        group: effectiveCategory,
        search: isPagedRequest || query.isEmpty ? null : query,
        live: live,
      );
    } else {
      Iterable<IptvChannel> filtered = _catalogState.allChannels;
      IptvChannel? jumpChannel;
      if (isJump) {
        for (final channel in _catalogState.allChannels) {
          if (channel.channelNumber == jumpNumber && channel.isLive) {
            jumpChannel = channel;
            break;
          }
        }
        if (jumpChannel == null) {
          return {
            'sourceId': source.id,
            'sourceName': source.name,
            'contentType': requestedType,
            'channelNotFound': true,
          };
        }
        effectiveCategory = jumpChannel.group;
      }
      // A list shelf is a curated mix — whatever the user put in it — so it
      // is never narrowed by the requested content type. Without this a list
      // holding movies would come back EMPTY in the player's guide: these
      // sources aren't Xtream, so requestedType falls back to 'live' above
      // and would filter out every on-demand row the user chose to save.
      if (!source.isXtreamCodes &&
          !source.isContinueWatching &&
          !source.isFavorites &&
          !source.isCustomList) {
        filtered = switch (requestedType) {
          'live' => filtered.where((channel) => channel.isLive),
          'vod' => filtered.where(
            (channel) => !channel.isLive && channel.contentType != 'series',
          ),
          'series' => filtered.where(
            (channel) => channel.contentType == 'series',
          ),
          _ => filtered,
        };
      }
      if (effectiveCategory != null) {
        filtered = filtered.where(
          (channel) => channel.group == effectiveCategory,
        );
      }
      if (query.isNotEmpty) {
        final terms = query.toLowerCase().split(RegExp(r'\s+'));
        filtered = filtered.where(
          (channel) => terms.every(channel.searchKey.contains),
        );
      }
      if (isPagedRequest) {
        // Legacy/in-memory catalogs are already materialized. Compute the
        // filtered ordinal once so native can request a small window centered
        // on a channel selected from search.
        final materialized = filtered.toList(growable: false);
        totalChannels = materialized.length;
        if (jumpChannel != null) {
          anchorIndex = materialized.indexWhere(
            (channel) => channel.channelNumber == jumpNumber,
          );
          if (anchorIndex == -1) anchorIndex = null;
        } else if (anchorUrl != null && anchorUrl.isNotEmpty) {
          anchorIndex = materialized.indexWhere(
            (channel) =>
                channel.url == anchorUrl &&
                (anchorName == null ||
                    anchorName.isEmpty ||
                    channel.name == anchorName),
          );
          if (anchorIndex == -1) anchorIndex = null;
        }
        pageOffset = iptvPlayerZapPageOffset(
          total: totalChannels,
          limit: pageLimit,
          requestedOffset: pageOffset,
          anchorIndex: anchorIndex,
          fromEnd: fromEnd,
        );
        channels = materialized
            .skip(pageOffset)
            .take(pageLimit)
            .toList(growable: false);
      } else {
        channels = filtered.take(IptvPlayerState.kMaxPlayerChannels).toList();
        totalChannels = channels.length;
      }
    }

    final categories = _deps.fullCategoryList();
    return {
      'sourceId': source.id,
      'sourceName': source.name,
      'contentType': requestedType,
      'selectedCategory': effectiveCategory,
      'categories': categories,
      if (isPagedRequest) 'pageOffset': pageOffset,
      if (isPagedRequest) 'totalChannels': totalChannels,
      if (isPagedRequest && anchorIndex != null) 'anchorIndex': anchorIndex,
      if (isJump) 'targetChannelNumber': jumpNumber,
      'sources': _deps.playerSourcePayload(),
      'channels': await _deps.playerChannelPayload([
        for (final channel in channels) (channel: channel, source: source),
      ]),
    };
  }
}
