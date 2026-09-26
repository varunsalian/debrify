import 'package:flutter/material.dart';

import '../../../models/torrent.dart';
import '../../../ui/core/source_metadata_labels.dart';
import '../../../utils/format_tag_detector.dart';
import '../../../widgets/source_row.dart';
import '../models/source_presentation_settings.dart';

/// Composes the detail/picker row without owning its actions or focus node.
/// Returning the row directly preserves its position in the existing widget tree.
SourceRow buildSourceResultRow({
  required Torrent torrent,
  required int listIndex,
  required bool cinemaLayout,
  required bool keywordMode,
  required SourcePresentationSettings settings,
  required bool isCurrentSource,
  required bool isCachedEpisode,
  required FocusNode focusNode,
  required bool isTelevision,
  required bool bindMode,
  required String? cacheLabel,
  required VoidCallback? onCopy,
  required VoidCallback onTap,
  required VoidCallback onLongPress,
  required VoidCallback onNavigateUp,
  required VoidCallback onNavigateDown,
}) {
  final isStream = torrent.isDirectStream || torrent.isExternalStream;
  final tags = (keywordMode || isStream)
      ? const <FormatTag>[]
      : FormatTagDetector.detect(torrent.name);
  return SourceRow(
    isCurrentSource: isCurrentSource,
    notice: isCachedEpisode
        ? 'Last played source · Not returned by the latest search. Using its cached link.'
        : null,
    listIndex: listIndex,
    cinemaLayout: cinemaLayout,
    title: torrent.displayTitle,
    addonText: settings.useAddonText ? torrent.addonPresentation : null,
    addonName: settings.showAddonLogos ? torrent.addonDisplayName : null,
    addonLogo: torrent.addonLogo,
    titleMaxLines: 6,
    subtitle: sourceRowSubtitle(torrent),
    focusNode: focusNode,
    isTelevision: isTelevision,
    showPlayPill: !bindMode && isTelevision,
    formatTags: tags,
    badgeName: torrent.name,
    badgeDescription: torrent.badgeDescription,
    qualityTag: tags.isEmpty ? sourceQualityLabel(torrent) : null,
    cacheLabel: cacheLabel,
    coverageBadge: keywordMode ? null : sourceCoverageLabel(torrent),
    streamBadge: torrent.isExternalStream
        ? 'External'
        : torrent.isDirectStream
        ? 'Direct'
        : null,
    onCopy: onCopy,
    onTap: onTap,
    onLongPress: onLongPress,
    onNavigateUp: onNavigateUp,
    onNavigateDown: onNavigateDown,
  );
}
