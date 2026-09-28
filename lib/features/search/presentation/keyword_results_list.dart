import 'package:flutter/material.dart';

import '../../../models/source_appearance.dart';
import '../../../models/torrent.dart';
import '../../../ui/core/source_metadata_labels.dart';
import '../../../utils/format_tag_detector.dart';
import '../../../ui/core/source_results_pane.dart';
import '../../../widgets/source_row.dart';
import '../models/keyword_results_state.dart';

/// Rows and local list navigation for the displayed Keyword snapshot. Route
/// actions own selection, playback and live-arrival acceptance; resources are borrowed.
class KeywordResultsList extends StatelessWidget {
  const KeywordResultsList({
    super.key,
    required this.state,
    required this.cache,
    required this.appearance,
    required this.isTelevision,
    required this.cinema,
    required this.scrollController,
    required this.focusNodes,
    required this.onFreeze,
    required this.onFocusAbove,
    required this.onCopy,
    required this.onActivate,
    required this.onLongPress,
    required this.emptyBuilder,
    this.pendingResults,
  });

  final WidgetBuilder emptyBuilder;
  final Widget? pendingResults;
  final KeywordResultsState state;
  final Map<String, List<String>> cache;
  final SourceAppearance appearance;
  final bool isTelevision, cinema;
  final ScrollController scrollController;
  final List<FocusNode> focusNodes;
  final VoidCallback onFreeze, onFocusAbove;
  final ValueChanged<Torrent> onCopy;
  final void Function(BuildContext, Torrent, int) onActivate;
  final void Function(Torrent, int) onLongPress;

  @override
  Widget build(BuildContext context) => SourceResultsPane(
    count: state.results.length,
    controller: scrollController,
    isTelevision: isTelevision,
    redesign: true,
    onUserScroll: onFreeze,
    emptyBuilder: emptyBuilder,
    pendingResults: pendingResults,
    itemBuilder: (context, i) {
      final t = state.results[i];
      final selectable = !t.isDirectStream && !t.isExternalStream;
      final isStream = !selectable;
      final labels = cache[t.infohash.toLowerCase()] ?? const [];
      final tags = isStream
          ? const <FormatTag>[]
          : FormatTagDetector.detect(t.name);
      return SourceRow(
        listIndex: i,
        key: ValueKey(
          '${t.infohash}_${state.selectionMode}_${state.selected.contains(t.infohash)}',
        ),
        title: t.displayTitle,
        addonText: appearance.text ? t.addonPresentation : null,
        addonName: appearance.logos ? t.addonDisplayName : null,
        addonLogo: t.addonLogo,
        titleMaxLines: 6,
        subtitle: _subtitle(t),
        focusNode: focusNodes[i],
        isTelevision: isTelevision,
        cinemaLayout: cinema,
        showPlayPill: isTelevision,
        formatTags: tags,
        badgeName: t.name,
        badgeDescription: t.badgeDescription,
        qualityTag: tags.isEmpty ? sourceQualityLabel(t) : null,
        cacheLabel: labels.isEmpty ? null : labels.join(' | '),
        streamBadge: t.isExternalStream
            ? 'External'
            : t.isDirectStream
            ? 'Direct'
            : null,
        isSelectionMode: state.selectionMode && selectable,
        isSelected: state.selected.contains(t.infohash),
        onCopy: state.selectionMode || t.copyLink == null
            ? null
            : () => onCopy(t),
        onTap: () => onActivate(context, t, i),
        onLongPress: state.selectionMode ? null : () => onLongPress(t, i),
        onNavigateUp: () {
          onFreeze();
          if (i > 0) {
            focusNodes[i - 1].requestFocus();
          } else {
            onFocusAbove();
          }
        },
        onNavigateDown: () {
          onFreeze();
          if (i < focusNodes.length - 1) {
            focusNodes[i + 1].requestFocus();
          }
        },
      );
    },
  );

  /// `size · ↑seeders · ↓leechers · SOURCE · date` meta line for a keyword
  /// row — same grammar as the Sources screen's rows (shared SourceRow look).
  static String _subtitle(Torrent t) {
    final parts = <String>[];
    final sourceLabel = t.addonDisplayName?.trim().isNotEmpty == true
        ? t.addonDisplayName!.trim()
        : t.source;
    if (t.isDirectStream || t.isExternalStream) {
      if (t.sizeBytes > 0) {
        parts.add(sourceSizeLabel(t.sizeBytes));
      }
      if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
      return parts.join(' · ');
    }
    if (t.sizeBytes > 0) parts.add(sourceSizeLabel(t.sizeBytes));
    if (t.seeders > 0) parts.add('↑ ${t.seeders}');
    if (t.leechers > 0) parts.add('↓ ${t.leechers}');
    if (sourceLabel.isNotEmpty) parts.add(sourceLabel.toUpperCase());
    final date = sourceDateLabel(t.createdUnix);
    if (date != null) parts.add(date);
    return parts.join(' · ');
  }
}
