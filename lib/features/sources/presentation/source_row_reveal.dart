import 'package:flutter/widgets.dart';

/// Walk a lazy viewport until its selected row mounts, then align that row.
/// The view owns nodes/controllers and guards each frame against stale work.
Future<void> revealSourceRow({
  required int index,
  required ScrollController controller,
  required List<FocusNode> Function() readNodes,
  required bool Function() canContinue,
  required String? Function() cancellationReason,
  required ValueChanged<FocusNode> onRowMounted,
  required bool Function() focusRequested,
  required void Function(String, Map<String, Object?>) onEvent,
}) async {
  while (canContinue()) {
    await WidgetsBinding.instance.endOfFrame;
    final reason = cancellationReason();
    if (reason != null) {
      onEvent('reveal_skipped', {'reason': reason});
      return;
    }
    final nodes = readNodes();
    final rowContext = nodes[index].context;
    if (rowContext != null && rowContext.mounted) {
      onRowMounted(nodes[index]);
      await Scrollable.ensureVisible(rowContext, alignment: 0.3);
      onEvent('reveal_complete', {'focus_requested': focusRequested()});
      return;
    }
    if (!controller.hasClients) {
      onEvent('reveal_skipped', {'reason': 'scroll_not_attached'});
      return;
    }
    final position = controller.position;
    final attached = <int>[
      for (var i = 0; i < nodes.length; i++)
        if (nodes[i].context != null) i,
    ];
    final backwards = attached.isNotEmpty && index < attached.first;
    final next =
        (position.pixels + (backwards ? -1 : 1) * position.viewportDimension)
            .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (next == position.pixels) {
      onEvent('reveal_skipped', {
        'reason': 'scroll_boundary_before_row_mounted',
      });
      return;
    }
    position.jumpTo(next);
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}
