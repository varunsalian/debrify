import 'package:flutter/material.dart';
import '../../../theme/app_theme_scope.dart';

// Shared with Atrium's row labels and scaled wall-height calculation.
const double homeStageRowLabelFontSize = 12.0;

/// Deck and Tonight's rail label — the same quiet caps as Atrium's rows, with the
/// stacked chevron pair that says UP/DOWN changes rails.
Widget buildHomeStageRowLabel({
  required BuildContext context,
  required String title,
}) {
  final app = AppThemeScope.of(context);
  return Row(
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
            fontSize: homeStageRowLabelFontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: app.fade(app.core.tx, 0.86),
          ),
        ),
      ),
    ],
  );
}
