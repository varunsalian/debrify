import 'dart:math' show max;
import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';
import 'home_canvas_tabs.dart' show homeCanvasChevronColumnHeight;

// The label and the identity block that must stay clear of it share these
// typography metrics. Promenade uses the same chevron floor as Canvas tabs.
const double _kPromLabelFontSize = 12.0;

/// Height of Promenade's centred label row at the current text scale (the
/// chevron column is the floor, as with Canvas tabs).
double homeStageRailLabelHeight(BuildContext context) => max(
  homeCanvasChevronColumnHeight,
  MediaQuery.textScalerOf(context).scale(_kPromLabelFontSize) * 1.35,
);

/// Shared rail label: centered in Promenade, end-aligned in Mosaic. The
/// stacked chevron pair is the same
/// affordance Canvas's tabs carry, and for the same reason: UP/DOWN is what
/// changes rails, and nothing else on this screen says so.
Widget buildHomeStageRailLabel({
  required BuildContext context,
  required String title,
  required int railIndex,
  required int railCount,
  MainAxisAlignment align = MainAxisAlignment.center,
}) {
  final app = AppThemeScope.of(context);
  return Row(
    mainAxisAlignment: align,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.keyboard_arrow_up_rounded,
            size: 13,
            color: app.fade(app.core.tx, 0.45),
          ),
          Transform.translate(
            offset: const Offset(0, -5),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: app.fade(app.core.tx, 0.45),
            ),
          ),
        ],
      ),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          title.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: _kPromLabelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
            color: app.fade(app.core.tx, 0.82),
          ),
        ),
      ),
      if (railCount > 1) ...[
        const SizedBox(width: 14),
        // Flexible as well as the title: on a narrow header (Mosaic shares
        // its row with the identity) a rigid counter is what tips the Row
        // into an overflow.
        Flexible(
          child: Text(
            '${railIndex + 1}/$railCount',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: _kPromLabelFontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: app.fade(app.core.tx, 0.32),
            ),
          ),
        ),
      ],
    ],
  );
}
