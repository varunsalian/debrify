import 'dart:async';

import 'package:debrify/models/torrent.dart';

/// Result from resolving a channel to a playable stream (no UI).
class StremioTvChannelPlaybackResult {
  final String url;
  final String title;
  final String contentType;
  final String? contentImdbId;
  final int? contentSeason;
  final int? contentEpisode;
  final double? startAtPercent;
  final List<Torrent> playableSources;
  final int sourceIndex;
  final Future<String?> Function(Torrent) sourceResolver;
  final Map<String, dynamic> nowPlayingGuideData;
  final Map<String, dynamic>? nextUpGuideData;
  final int baseSlotStartMs;
  final int slotOffset;

  const StremioTvChannelPlaybackResult({
    required this.url,
    required this.title,
    required this.contentType,
    this.contentImdbId,
    this.contentSeason,
    this.contentEpisode,
    this.startAtPercent,
    required this.playableSources,
    required this.sourceIndex,
    required this.sourceResolver,
    required this.nowPlayingGuideData,
    this.nextUpGuideData,
    required this.baseSlotStartMs,
    required this.slotOffset,
  });
}

class StremioTvResolvedSourceChoice {
  final String url;
  final int sourceIndex;

  const StremioTvResolvedSourceChoice({
    required this.url,
    required this.sourceIndex,
  });
}

class StremioTvPlaybackCursor {
  final int baseSlotStartMs;
  final int slotOffset;

  const StremioTvPlaybackCursor({
    required this.baseSlotStartMs,
    required this.slotOffset,
  });
}
