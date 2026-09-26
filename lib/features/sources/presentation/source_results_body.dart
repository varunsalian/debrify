import 'package:flutter/material.dart';

import 'source_results_pane.dart';
import 'source_status_widgets.dart';

/// Sources loading/status and list composition. Optional content is constructed
/// only in the results branch; actions and resources stay with the view.
Widget buildSourceResultsBody({
  required ColorScheme scheme,
  required bool loading,
  required String? error,
  required bool showProgress,
  required int visibleCount,
  required ValueGetter<bool> hasResults,
  required ScrollController scrollController,
  required bool isTelevision,
  required bool redesign,
  required VoidCallback onUserScroll,
  required IndexedWidgetBuilder itemBuilder,
  Widget? keywordField,
  ValueGetter<Widget>? titleBuilder,
  ValueGetter<Widget>? toolbarBuilder,
  ValueGetter<Widget>? pendingResultsBuilder,
}) => Column(
  children: [
    if (keywordField != null) keywordField,
    Expanded(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? SourceStatusMessage(
              color: scheme.onSurfaceVariant,
              text: 'Search failed.\n$error',
            )
          : Column(
              children: [
                if (titleBuilder != null) titleBuilder(),
                if (toolbarBuilder != null) toolbarBuilder(),
                if (showProgress) const SourceSearchProgress(),
                Expanded(
                  child: SourceResultsPane(
                    count: visibleCount,
                    controller: scrollController,
                    isTelevision: isTelevision,
                    redesign: redesign,
                    onUserScroll: onUserScroll,
                    emptyBuilder: (_) => SourceStatusMessage(
                      color: scheme.onSurfaceVariant,
                      text: !hasResults()
                          ? 'No sources found.'
                          : 'No matches for your filters.',
                    ),
                    pendingResults: pendingResultsBuilder?.call(),
                    itemBuilder: itemBuilder,
                  ),
                ),
              ],
            ),
    ),
  ],
);
