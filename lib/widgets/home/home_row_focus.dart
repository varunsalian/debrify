import 'package:flutter/widgets.dart';

/// Read the row shell's extent without including its animated card transform.
double? homeRowHeight(BuildContext? context, Key key) {
  double? height;
  context?.visitAncestorElements((element) {
    if (element.widget.key != key) return true;
    final box = element.findRenderObject();
    if (box is RenderBox && box.hasSize) height = box.size.height;
    return false;
  });
  return height;
}

/// Keep an existing row in the viewport when strictly additive results arrive
/// above it. Correct BEFORE the sliver lays out its new children: waiting for
/// a post-frame ensureVisible can already have disposed the focused row.
/// The caller must rebuild the list in the same update.
void preserveHomeInsertionAnchor({
  required ScrollController scroll,
  required List<String> previous,
  required List<String> next,
  required String anchor,
  required double Function(String id) extentOf,
}) {
  if (!scroll.hasClients ||
      !previous.contains(anchor) ||
      !next.contains(anchor) ||
      previous.toSet().length != previous.length ||
      next.toSet().length != next.length) {
    return;
  }
  final oldIds = previous.toSet();
  final retained = next.where(oldIds.contains).toList();
  if (retained.length != previous.length ||
      Iterable<int>.generate(
        previous.length,
      ).any((i) => retained[i] != previous[i])) {
    return;
  }
  var delta = 0.0;
  for (final id in next.takeWhile((id) => id != anchor)) {
    if (!oldIds.contains(id)) delta += extentOf(id);
  }
  if (!delta.isFinite || delta <= 0) return;
  final position = scroll.position;
  if (position is ScrollPositionWithSingleContext) position.goIdle();
  // jumpTo would start a ballistic clamp against the OLD content extent.
  // The forthcoming layout supplies the new extent and metrics notification.
  position.correctPixels(position.pixels + delta);
}

/// Reuses focus nodes by row/content identity across background Home refreshes.
List<List<FocusNode>> reconcileHomeRowFocus({
  required List<List<String>> previousIds,
  required List<List<FocusNode>> previousNodes,
  required List<List<String>> nextIds,
}) {
  final available = <String, List<FocusNode>>{};
  for (var r = 0; r < previousIds.length && r < previousNodes.length; r++) {
    for (
      var c = 0;
      c < previousIds[r].length && c < previousNodes[r].length;
      c++
    ) {
      available
          .putIfAbsent(previousIds[r][c], () => [])
          .add(previousNodes[r][c]);
    }
  }
  final next = [
    for (final row in nextIds)
      [
        for (final id in row)
          switch (available[id]) {
            final List<FocusNode> nodes when nodes.isNotEmpty => nodes.removeAt(
              0,
            ),
            _ => FocusNode(debugLabel: 'home_refreshed_card'),
          },
      ],
  ];
  final removed = previousNodes.expand((row) => row).toSet()
    ..removeAll(next.expand((row) => row));
  for (final node in removed) {
    node.dispose();
  }
  return next;
}
