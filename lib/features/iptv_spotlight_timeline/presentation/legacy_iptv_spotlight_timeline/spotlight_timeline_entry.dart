import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/iptv_epg_service.dart';
import 'package:flutter/material.dart';

/// Loads the schedule for one visible live channel.
///
/// Callers can wire this directly to
/// `IptvEpgService.instance.schedule(channel.url)`. Keeping the loader outside
/// this widget also lets a mixed-source list restore the correct guide context
/// before asking for a channel's programmes.
typedef SpotlightScheduleLoader =
    Future<List<EpgProgramme>> Function(IptvChannel channel);

typedef SpotlightChannelActivate = void Function(SpotlightTimelineEntry entry);

typedef SpotlightProgrammeActivate =
    void Function(SpotlightTimelineEntry entry, EpgProgramme programme);

/// The stable identity of an item in a flattened or virtual IPTV source.
///
/// A channel URL is deliberately absent: providers can repeat URLs and a
/// favorites/custom-list row can contain entries from several sources. The
/// source projection generation and row ordinal make those rows collision-free.
/// A filter or sort replacement must supply a new generation.
@immutable
class SpotlightTimelineEntryKey {
  final String sourceId;
  final int loadGeneration;
  final int sourceOrdinal;

  const SpotlightTimelineEntryKey({
    required this.sourceId,
    required this.loadGeneration,
    required this.sourceOrdinal,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpotlightTimelineEntryKey &&
          sourceId == other.sourceId &&
          loadGeneration == other.loadGeneration &&
          sourceOrdinal == other.sourceOrdinal;

  @override
  int get hashCode => Object.hash(sourceId, loadGeneration, sourceOrdinal);

  @override
  String toString() => '$sourceId/$loadGeneration/$sourceOrdinal';
}

/// A channel plus the source identity needed to reject recycled-row results.
@immutable
class SpotlightTimelineEntry {
  final String sourceId;
  final int loadGeneration;
  final int sourceOrdinal;
  final IptvChannel channel;

  const SpotlightTimelineEntry({
    required this.sourceId,
    required this.loadGeneration,
    required this.sourceOrdinal,
    required this.channel,
  });

  SpotlightTimelineEntryKey get entryKey => SpotlightTimelineEntryKey(
    sourceId: sourceId,
    loadGeneration: loadGeneration,
    sourceOrdinal: sourceOrdinal,
  );
}

/// The widget's single logical cursor, exposed for a surrounding preview pane.
@immutable
class SpotlightTimelineSelection {
  final SpotlightTimelineEntry entry;
  final EpgProgramme? programme;
  final bool fromPointer;

  const SpotlightTimelineSelection({
    required this.entry,
    this.programme,
    this.fromPointer = false,
  });
}
