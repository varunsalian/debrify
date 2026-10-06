import 'dart:async';

import 'package:collection/collection.dart';
import 'package:debrify/features/stremio_tv/models/stremio_tv_playback_records.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_bindings.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_owners.dart';
import 'package:debrify/features/stremio_tv/presentation/legacy_stremio_tv/stremio_tv_sections.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_channel.dart';
import 'package:debrify/models/stremio_tv/stremio_tv_now_playing.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';

class StremioTvPlayerGuide {
  StremioTvPlayerGuide(this._deps);
  final StremioTvDependencies _deps;
  StremioTvOwners get _owners => _deps.owners;
  StremioTvSections get _sections => _deps.sections;

  void rememberPlaybackCursor(
    String channelId, {
    required int baseSlotStartMs,
    required int slotOffset,
  }) {
    _owners.playback.playbackCursors[channelId] = StremioTvPlaybackCursor(
      baseSlotStartMs: baseSlotStartMs,
      slotOffset: slotOffset,
    );
  }

  int _nextSlotOffsetFor(StremioTvChannel channel) {
    final current = _owners.library.service.getNowPlaying(
      channel,
      rotationMinutes: _sections.library.rotationFor(channel),
      salt: _owners.library.mixSalt,
    );
    if (current == null) return 1;

    final currentBaseMs = current.slotStart.millisecondsSinceEpoch;
    final cursor = _owners.playback.playbackCursors[channel.id];
    if (cursor == null || cursor.baseSlotStartMs != currentBaseMs) {
      return 1;
    }
    return cursor.slotOffset + 1;
  }

  Map<String, dynamic> guideDataFor(StremioTvNowPlaying playing) {
    return {
      'title': playing.item.name,
      'poster': playing.item.poster,
      'year': playing.item.year,
      'rating': playing.item.imdbRating,
      'type': playing.item.type,
      'slotEndMs': playing.slotEnd.millisecondsSinceEpoch,
      'progress': playing.progress,
    };
  }

  Map<String, dynamic> _playbackResultToMap(
    String channelId,
    StremioTvChannelPlaybackResult result,
  ) {
    return {
      'channelId': channelId,
      'url': result.url,
      'title': result.title,
      'contentType': result.contentType,
      'contentImdbId': result.contentImdbId,
      if (result.contentSeason != null) 'contentSeason': result.contentSeason,
      if (result.contentEpisode != null)
        'contentEpisode': result.contentEpisode,
      'startAtPercent': result.startAtPercent,
      'stremioSources': result.playableSources.map((t) => t.toJson()).toList(),
      'stremioCurrentSourceIndex': result.sourceIndex,
      'sourceResolver': result.sourceResolver,
      'nowPlaying': result.nowPlayingGuideData,
      if (result.nextUpGuideData != null) 'nextUp': result.nextUpGuideData,
    };
  }

  // ─── Source Resolution (no dialogs, returns URL) ────────────────────
  /// Creates a resolver closure that snapshots current state at creation time.
  Future<String?> Function(Torrent) createSourceResolver(
    StremioMeta item, {
    int? season,
    int? episode,
  }) {
    final debridProvider = _owners.settings.debridProvider;
    return (Torrent torrent) async {
      if (torrent.isDirectStream) {
        return torrent.directUrl;
      }
      if (torrent.streamType == StreamType.torrent) {
        return _sections.debrid.resolveTorrentUrl(
          torrent,
          item,
          debridProvider,
          season: season,
          episode: episode,
        );
      }
      return null;
    };
  }

  // ─── Stremio TV In-Player Guide ─────────────────────────────────────
  /// Build channel metadata list for the in-player guide.
  /// Includes inline now/next data for channels that already have items loaded.
  List<Map<String, dynamic>> buildGuideChannelMetadata() {
    return _owners.library.channels.map((ch) {
      final data = <String, dynamic>{
        'id': ch.id,
        'name': ch.displayName,
        'number': ch.channelNumber,
        'type': ch.type,
        'isFavorite': ch.isFavorite,
      };
      if (ch.hasItems) {
        final rotation = _sections.library.rotationFor(ch);
        final np = _owners.library.service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        final next = _owners.library.service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        if (np != null) {
          data['nowPlaying'] = {
            'title': np.item.name,
            'poster': np.item.poster,
            'year': np.item.year,
            'rating': np.item.imdbRating,
            'type': np.item.type,
            'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
            'progress': np.progress,
          };
        }
        if (next != null) {
          data['nextUp'] = {
            'title': next.item.name,
            'poster': next.item.poster,
            'year': next.item.year,
            'rating': next.item.imdbRating,
            'type': next.item.type,
          };
        }
      }
      return data;
    }).toList();
  }

  /// Creates a guide data provider closure for lazy-loading channel data.
  Future<Map<String, dynamic>?> Function(List<String>)
  createGuideDataProvider() {
    return (List<String> channelIds) async {
      final result = <String, dynamic>{};
      for (final id in channelIds) {
        final ch = _owners.library.channels.firstWhereOrNull((c) => c.id == id);
        if (ch == null) continue;
        if (!ch.hasItems) await _owners.library.service.loadChannelItems(ch);
        if (!ch.hasItems) continue;
        final rotation = _sections.library.rotationFor(ch);
        final np = _owners.library.service.getNowPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        final next = _owners.library.service.getNextPlaying(
          ch,
          rotationMinutes: rotation,
          salt: _owners.library.mixSalt,
        );
        result[id] = {
          if (np != null)
            'nowPlaying': {
              'title': np.item.name,
              'poster': np.item.poster,
              'year': np.item.year,
              'rating': np.item.imdbRating,
              'type': np.item.type,
              'slotEndMs': np.slotEnd.millisecondsSinceEpoch,
              'progress': np.progress,
            },
          if (next != null)
            'nextUp': {
              'title': next.item.name,
              'poster': next.item.poster,
              'year': next.item.year,
              'rating': next.item.imdbRating,
              'type': next.item.type,
            },
        };
      }
      return result;
    };
  }

  /// Creates a channel switch provider closure for the in-player guide.
  Future<Map<String, dynamic>?> Function(String) createChannelSwitchProvider() {
    return (String channelId) async {
      final ch = _owners.library.channels.firstWhereOrNull(
        (c) => c.id == channelId,
      );
      if (ch == null) return null;
      final result = await _sections.resolve.resolveChannelPlayback(ch);
      if (result == null) return null;
      _sections.guide.rememberPlaybackCursor(
        channelId,
        baseSlotStartMs: result.baseSlotStartMs,
        slotOffset: result.slotOffset,
      );
      return _sections.guide._playbackResultToMap(channelId, result);
    };
  }

  /// Creates a provider for the player Next button in Stremio TV mode.
  ///
  /// It advances one guide slot at a time and keeps a small per-channel cursor.
  /// An unavailable slot is reported to the player instead of silently skipping
  /// over another series and making the channel appear to contain one title.
  /// The failed slot is still remembered, so another explicit Next press moves
  /// on rather than retrying it forever.
  Future<Map<String, dynamic>?> Function(String) createNextProvider() {
    return (String channelId) async {
      final ch = _owners.library.channels.firstWhereOrNull(
        (c) => c.id == channelId,
      );
      if (ch == null) return null;

      final slotOffset = _sections.guide._nextSlotOffsetFor(ch);
      final result = await _sections.resolve.resolveChannelPlayback(
        ch,
        slotOffset: slotOffset,
      );
      if (result != null) {
        _sections.guide.rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: result.baseSlotStartMs,
          slotOffset: result.slotOffset,
        );
        return _sections.guide._playbackResultToMap(channelId, result);
      }

      debugPrint(
        'StremioTV next: slot offset $slotOffset unavailable; '
        'not skipping it silently.',
      );
      final current = _owners.library.service.getNowPlaying(
        ch,
        rotationMinutes: _sections.library.rotationFor(ch),
        salt: _owners.library.mixSalt,
      );
      if (current != null) {
        _sections.guide.rememberPlaybackCursor(
          channelId,
          baseSlotStartMs: current.slotStart.millisecondsSinceEpoch,
          slotOffset: slotOffset,
        );
      }
      return null;
    };
  }
}
