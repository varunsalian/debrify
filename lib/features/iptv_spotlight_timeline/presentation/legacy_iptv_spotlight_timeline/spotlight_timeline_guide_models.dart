import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

enum SpotlightTimelineCursorLane { identity, retry, programme }

enum SpotlightTimelineGuideStatus { loading, ready, error }

@immutable
class SpotlightTimelineGuideSnapshot {
  final SpotlightTimelineGuideStatus status;
  final int contextVersion;
  final List<EpgProgramme> programmes;

  const SpotlightTimelineGuideSnapshot.loading(this.contextVersion)
    : status = SpotlightTimelineGuideStatus.loading,
      programmes = const [];

  const SpotlightTimelineGuideSnapshot.ready(
    this.contextVersion,
    this.programmes,
  ) : status = SpotlightTimelineGuideStatus.ready;

  const SpotlightTimelineGuideSnapshot.error(this.contextVersion)
    : status = SpotlightTimelineGuideStatus.error,
      programmes = const [];
}

@immutable
class SpotlightTimelineLoadToken {
  final int generation;
  final SpotlightTimelineEntryKey entryKey;
  final int contextVersion;
  final int sourceIndex;
  final IptvChannel channel;

  const SpotlightTimelineLoadToken({
    required this.generation,
    required this.entryKey,
    required this.contextVersion,
    required this.sourceIndex,
    required this.channel,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpotlightTimelineLoadToken &&
          generation == other.generation &&
          entryKey == other.entryKey &&
          contextVersion == other.contextVersion &&
          sourceIndex == other.sourceIndex &&
          identical(channel, other.channel);

  @override
  int get hashCode => Object.hash(
    generation,
    entryKey,
    contextVersion,
    sourceIndex,
    identityHashCode(channel),
  );
}
