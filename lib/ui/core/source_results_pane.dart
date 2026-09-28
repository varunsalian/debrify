import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../widgets/source_list_scroll_anchor.dart';

/// Lazy results and parked-arrival overlay. The view owns rows, actions and focus.
class SourceResultsPane extends StatelessWidget {
  const SourceResultsPane({
    super.key,
    required this.count,
    required this.controller,
    required this.isTelevision,
    required this.redesign,
    required this.itemBuilder,
    required this.emptyBuilder,
    required this.onUserScroll,
    this.pendingResults,
  });

  final int count;

  /// Borrowed; this pane does not create or dispose the controller.
  final ScrollController controller;
  final bool isTelevision;
  final bool redesign;
  final IndexedWidgetBuilder itemBuilder;
  final WidgetBuilder emptyBuilder;
  final VoidCallback onUserScroll;
  final Widget? pendingResults;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: count == 0
            ? emptyBuilder(context)
            : NotificationListener<ScrollNotification>(
                // Programmatic ensureVisible must not freeze live arrivals.
                onNotification: (notification) {
                  if (notification is ScrollStartNotification &&
                      notification.dragDetails != null) {
                    onUserScroll();
                  }
                  return false;
                },
                child: SourceListScrollAnchor(
                  child: ListView.builder(
                    controller: controller,
                    // Reserve focus expansion room above the first TV row:
                    // negative scroll extent cannot reveal that overflow.
                    padding: EdgeInsets.symmetric(
                      vertical: isTelevision ? 24 : 8,
                      horizontal: redesign ? 10 : 0,
                    ),
                    scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
                    itemCount: count,
                    itemBuilder: itemBuilder,
                  ),
                ),
              ),
      ),
      // Arrivals stay parked until adopted, even if no rows currently match.
      if (pendingResults != null)
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(child: pendingResults),
        ),
    ],
  );
}
