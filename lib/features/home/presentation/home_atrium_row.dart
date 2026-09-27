import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../theme/app_theme_scope.dart';
import 'home_stage_row_label.dart' show homeStageRowLabelFontSize;

/// Atrium's quiet label and lazy horizontal strip. The caller owns navigation,
/// per-kind cell sizing, actions and borrowed focus nodes in its indexed builder.
Widget buildHomeAtriumRow({
  required BuildContext context,
  required String title,
  required bool androidTv,
  required double labelGap,
  required double rowHeight,
  required String railKey,
  required int itemCount,
  required IndexedWidgetBuilder itemBuilder,
}) {
  final app = AppThemeScope.of(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: homeStageRowLabelFontSize,
          // Match the reserved wall-label extent on Android TV. tvOS keeps
          // its existing typography and opening behavior.
          height: androidTv ? 1.35 : null,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
          color: app.fade(app.core.tx, 0.86),
          shadows: const [Shadow(color: Color(0x99000000), blurRadius: 6)],
        ),
      ),
      SizedBox(height: labelGap),
      SizedBox(
        height: rowHeight,
        child: ListView.builder(
          // Keyed by rail identity, never its current index.
          key: ValueKey('atrium-rail-$railKey'),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.hardEdge,
          scrollCacheExtent: const ScrollCacheExtent.pixels(400),
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        ),
      ),
    ],
  );
}
